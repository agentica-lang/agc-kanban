import Db from "pkg/db/db"
import Regex from "std/regex"
import Cards from "cards"
import Database from "repo/database"

struct Destination
  column_id: Int
  position: Int
end

export def claim(pool: Database.Pool, id: Int, actor: String, lease_minutes: Int) -> Result[Cards.Card]
  return error("INVALID:id") if id <= 0
  return error("INVALID:agent") if not Regex.match?(actor, /^[A-Za-z0-9._@\/-]{1,64}$/)
  return error("INVALID:lease") if lease_minutes < 0 or lease_minutes > 1000000000

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| acquire(tx, id, actor, lease_minutes) end end
end

def acquire(conn: Db.Connection, id: Int, actor: String, lease_minutes: Int) -> Result[Cards.Card]
  now = Time.now_ms()
  card = try Cards.load_at(conn, id, now)
  target = try destination(conn, card)
  lease: Db.Value = Db.Value.Null
  if lease_minutes > 0
    lease = Db.Value.Int(now + lease_minutes * 60000)
  end

  changed = try Db.execute(
    conn,
    "update cards set claimed_by = ?, claimed_at = ?, lease_until = ?, updated_at = ?, version = version + 1, column_id = ?, position = ? where id = ? and archived_at is null and column_id not in (select id from columns where done = 1) and (claimed_by is null or claimed_by = ? or lease_until <= ?) and not exists (select 1 from card_deps d join cards dep on dep.id = d.depends_on_id join columns col on col.id = dep.column_id where d.card_id = cards.id and col.done = 0)",
    [
      Db.Value.Text(actor),
      Db.Value.Int(now),
      lease,
      Db.Value.Int(now),
      Db.Value.Int(target.column_id),
      Db.Value.Int(target.position),
      Db.Value.Int(id),
      Db.Value.Text(actor),
      Db.Value.Int(now),
    ],
  )

  return diagnose(conn, card, actor, now) if changed == 0

  if target.column_id != card.column_id
    _ = try Db.execute(
      conn,
      "update cards set position = position - 1, version = version + 1, updated_at = ? where column_id = ? and position > ? and archived_at is null",
      [Db.Value.Int(now), Db.Value.Int(card.column_id), Db.Value.Int(card.position)],
    )
  end

  updated = try Cards.load_at(conn, id, now)
  board = try Db.query(conn, "select board_id from cards where id = ?", [Db.Value.Int(id)])
  _ = try Db.execute(
    conn,
    "insert into events (board_id, card_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?, ?)",
    [
      Db.Value.Int(number(board[0], "board_id")),
      Db.Value.Int(id),
      Db.Value.Text("card.claimed"),
      Db.Value.Text(actor),
      Db.Value.Text(JSON.encode(JSON.from(updated))),
      Db.Value.Int(now),
    ],
  )

  ok(updated)
end

def destination(conn: Db.Connection, card: Cards.Card) -> Result[Destination]
  source = try Db.query(conn, "select board_id, position from columns where id = ?", [Db.Value.Int(card.column_id)])
  board_id = number(source[0], "board_id")
  first = try Db.query(
    conn,
    "select id from columns where board_id = ? order by position limit 1",
    [Db.Value.Int(board_id)],
  )

  if number(first[0], "id") != card.column_id
    return ok(Destination(column_id: card.column_id, position: card.position))
  end

  targets = try Db.query(
    conn,
    "select id from columns where board_id = ? and done = 0 and id != ? order by position limit 1",
    [Db.Value.Int(board_id), Db.Value.Int(card.column_id)],
  )

  return ok(Destination(column_id: card.column_id, position: card.position)) if targets.empty?

  target_id = number(targets[0], "id")
  positions = try Db.query(
    conn,
    "select coalesce(max(position) + 1, 0) as next from cards where column_id = ? and archived_at is null",
    [Db.Value.Int(target_id)],
  )

  ok(Destination(column_id: target_id, position: number(positions[0], "next")))
end

def diagnose(conn: Db.Connection, card: Cards.Card, actor: String, now: Int) -> Result[Cards.Card]
  return error("DONE:card") if card.done
  active = card.claimed_by.some? and (not card.lease_until.some? or card.lease_until.unwrap! > now)
  return error("CLAIMED:#{card.claimed_by.unwrap!}") if active and card.claimed_by.unwrap! != actor

  blocked = try Db.query(
    conn,
    "select dep.id from card_deps d join cards dep on dep.id = d.depends_on_id join columns col on col.id = dep.column_id where d.card_id = ? and col.done = 0 order by dep.id",
    [Db.Value.Int(card.id)],
  )

  ids = blocked.map do |row| number(row, "id").to_s end
  return error("BLOCKED:#{ids.join(",")}") if not ids.empty?

  error("CONFLICT:claim")
end

def number(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end
