import Db from "pkg/db/db"
import Regex from "std/regex"
import Cards from "cards"
import Database from "repo/database"

export struct Action
  id: Int
  actor: String
  force: Bool
end

struct EventData
  card: Cards.Card
  forced: Bool
end

export def finish(pool: Database.Pool, input: Action) -> Result[Cards.Card]
  return error("INVALID:id") if input.id <= 0
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| finish_open(tx, input) end end
end

def finish_open(conn: Db.Connection, input: Action) -> Result[Cards.Card]
  now = Time.now_ms()
  card = try Cards.load_at(conn, input.id, now)
  active = card.claimed_by.some? and (not card.lease_until.some? or card.lease_until.unwrap! > now)
  return error("NOT_CLAIMER:card") if not input.force and (not active or card.claimed_by.unwrap! != input.actor)

  rows = try Db.query(
    conn,
    "select c.board_id, col.id as done_id from cards c join columns col on col.board_id = c.board_id and col.done = 1 where c.id = ?",
    [Db.Value.Int(input.id)],
  )

  return error("CONFLICT:done_column") if rows.empty?

  board_id = number(rows[0], "board_id")
  target = number(rows[0], "done_id")
  positions = try Db.query(
    conn,
    "select coalesce(max(position) + 1, 0) as next from cards where column_id = ? and archived_at is null",
    [Db.Value.Int(target)],
  )

  position = number(positions[0], "next")
  _ = try Db.execute(
    conn,
    "update cards set column_id = ?, position = ?, claimed_by = null, claimed_at = null, lease_until = null, done_at = ?, updated_at = ?, version = version + 1 where id = ?",
    [Db.Value.Int(target), Db.Value.Int(position), Db.Value.Int(now), Db.Value.Int(now), Db.Value.Int(input.id)],
  )

  _ = try Db.execute(
    conn,
    "update cards set position = position - 1, version = version + 1, updated_at = ? where column_id = ? and position > ? and archived_at is null",
    [Db.Value.Int(now), Db.Value.Int(card.column_id), Db.Value.Int(card.position)],
  )

  updated = try Cards.load_at(conn, input.id, now)
  data = EventData(card: updated, forced: input.force)
  _ = try Db.execute(
    conn,
    "insert into events (board_id, card_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?, ?)",
    [
      Db.Value.Int(board_id),
      Db.Value.Int(input.id),
      Db.Value.Text("card.done"),
      Db.Value.Text(input.actor),
      Db.Value.Text(JSON.encode(JSON.from(data))),
      Db.Value.Int(now),
    ],
  )

  ok(updated)
end

def number(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end
