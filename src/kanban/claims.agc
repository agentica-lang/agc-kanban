import Db from "pkg/db/db"
import Regex from "std/regex"
import Cards from "cards"
import Database from "repo/database"

export struct Next
  board: String
  column: Optional[String]
  label: Optional[String]
  actor: String
  lease_minutes: Int
end

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

export def claim_next(pool: Database.Pool, input: Next) -> Result[Cards.Card]
  return error("INVALID:board") if input.board.empty?
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)
  return error("INVALID:lease") if input.lease_minutes < 0 or input.lease_minutes > 1000000000

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| next_open(tx, input) end end
end

def next_open(conn: Db.Connection, input: Next) -> Result[Cards.Card]
  boards = try Db.query(
    conn,
    "select id from boards where slug = ? or cast(id as text) = ? order by case when slug = ? then 0 else 1 end limit 1",
    [Db.Value.Text(input.board), Db.Value.Text(input.board), Db.Value.Text(input.board)],
  )

  return error("NOT_FOUND:board") if boards.empty?

  column = text_value(input.column)
  label = text_value(input.label)
  now = Time.now_ms()
  candidates = try Db.query(
    conn,
    "select c.id from cards c join columns col on col.id = c.column_id where c.board_id = ? and c.archived_at is null and col.done = 0 and (c.claimed_by is null or c.lease_until <= ?) and not exists (select 1 from card_deps d join cards dep on dep.id = d.depends_on_id join columns dc on dc.id = dep.column_id where d.card_id = c.id and dc.done = 0) and (? is null or col.name = ? or cast(col.id as text) = ?) and (? is null or exists (select 1 from json_each(c.labels) j where j.value = ?)) order by c.priority, col.position, c.position, c.id limit 8",
    [Db.Value.Int(number(boards[0], "id")), Db.Value.Int(now), column, column, column, label, label],
  )

  return error("NO_READY_CARD:board") if candidates.empty?

  for row in candidates
    claimed = acquire(conn, number(row, "id"), input.actor, input.lease_minutes)
    return claimed if claimed.ok?
  end

  error("NO_READY_CARD:board")
end

def text_value(value: Optional[String]) -> Db.Value
  case value
    none -> Db.Value.Null
    some(text) -> Db.Value.Text(text)
  end
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
    "update cards set claimed_by = ?, claimed_at = ?, lease_until = ?, updated_at = ?, version = version + 1, column_id = ?, position = ? where id = ? and archived_at is null and column_id not in (select id from columns where done = 1) and (claimed_by is null or claimed_by = ? or lease_until <= ?) and (not exists (select 1 from card_deps d join cards dep on dep.id = d.depends_on_id join columns col on col.id = dep.column_id where d.card_id = cards.id and col.done = 0) or (claimed_by = ? and (lease_until is null or lease_until > ?)))",
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

  ids = try Cards.open_blockers(conn, card.id)
  return error("BLOCKED:#{ids.map do |id| id.to_s end.join(",")}") if not ids.empty?

  error("CONFLICT:claim")
end

def number(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end
