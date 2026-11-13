import Db from "pkg/db/db"
import Regex from "std/regex"
import Cards from "cards"
import Database from "repo/database"

struct Add
  card_id: Int
  body: String
  actor: String
  lease_minutes: Int
end

def add(pool: Database.Pool, input: Add) -> Result[Cards.Comment]
  return error("INVALID:id") if input.card_id <= 0
  return error("INVALID:body") if input.body.strip.empty?
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)
  return error("INVALID:lease") if input.lease_minutes < 0 or input.lease_minutes > 1000000000

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| add_open(tx, input) end end
end

private

def add_open(conn: Db.Connection, input: Add) -> Result[Cards.Comment]
  now = Time.now_ms()
  card = try Cards.load_at(conn, input.card_id, now)
  _ = try Db.execute(
    conn,
    "insert into comments (card_id, author, body, created_at) values (?, ?, ?, ?)",
    [Db.Value.Int(input.card_id), Db.Value.Text(input.actor), Db.Value.Text(input.body), Db.Value.Int(now)],
  )

  inserted = try Db.query(conn, "select last_insert_rowid() as id", [])
  comment = Cards.Comment(
    id: number(inserted[0], "id"),
    card_id: input.card_id,
    author: input.actor,
    body: input.body,
    created_at: now,
  )

  try renew(conn, card, input.actor, input.lease_minutes, now)
  board = try Db.query(conn, "select board_id from cards where id = ?", [Db.Value.Int(input.card_id)])
  _ = try Db.execute(
    conn,
    "insert into events (board_id, card_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?, ?)",
    [
      Db.Value.Int(number(board[0], "board_id")),
      Db.Value.Int(input.card_id),
      Db.Value.Text("comment.added"),
      Db.Value.Text(input.actor),
      Db.Value.Text(JSON.encode(JSON.from(comment))),
      Db.Value.Int(now),
    ],
  )

  ok(comment)
end

# Only the holder renews, and only a lease that is still running: an expired claim stays free.
def renew(conn: Db.Connection, card: Cards.Card, actor: String, lease_minutes: Int, now: Int) -> Result[Void]
  return ok() if lease_minutes == 0
  return ok() if card.lease_until.none?
  holder = card.claimed_by
  return ok() if holder.none? or holder.unwrap! != actor
  return ok() if card.lease_until.unwrap! <= now

  _ = try Db.execute(
    conn,
    "update cards set lease_until = ?, updated_at = ?, version = version + 1 where id = ?",
    [Db.Value.Int(now + lease_minutes * 60000), Db.Value.Int(now), Db.Value.Int(card.id)],
  )

  ok()
end

def number(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end
