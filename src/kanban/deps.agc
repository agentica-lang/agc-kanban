import Db from "pkg/db/db"
import Regex from "std/regex"
import Cards from "cards"
import Database from "repo/database"

export struct Change
  card_id: Int
  depends_on: Int
  actor: String
  lease_minutes: Int
  force: Bool = false
end

export def add(pool: Database.Pool, input: Change) -> Result[Cards.Card]
  try validate(input)
  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| change(tx, input, true) end end
end

export def remove(pool: Database.Pool, input: Change) -> Result[Cards.Card]
  try validate(input)
  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| change(tx, input, false) end end
end

def validate(input: Change) -> Result[Void]
  return error("INVALID:id") if input.card_id <= 0
  return error("INVALID:depends_on") if input.depends_on <= 0
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)
  return error("INVALID:lease") if input.lease_minutes < 0 or input.lease_minutes > 1000000000

  ok()
end

def change(conn: Db.Connection, input: Change, adding: Bool) -> Result[Cards.Card]
  now = Time.now_ms()
  card = try Cards.load_at(conn, input.card_id, now)
  if adding
    # The dependency must exist.
    _ = try Cards.load_at(conn, input.depends_on, now)
  end

  active = card.claimed_by.some? and (not card.lease_until.some? or card.lease_until.unwrap! > now)
  if active and card.claimed_by.unwrap! != input.actor and not input.force
    return error("CLAIMED:#{card.claimed_by.unwrap!}")
  end

  existing = try Db.query(
    conn,
    "select 1 as present from card_deps where card_id = ? and depends_on_id = ?",
    [Db.Value.Int(input.card_id), Db.Value.Int(input.depends_on)],
  )

  if adding
    return error("CYCLE:dependency") if input.card_id == input.depends_on
    return error("CONFLICT:dependency") if not existing.empty?
    cycle = try Db.query(
      conn,
      "with recursive reaches(id) as (select ? union select d.depends_on_id from card_deps d join reaches r on d.card_id = r.id) select 1 as present from reaches where id = ? limit 1",
      [Db.Value.Int(input.depends_on), Db.Value.Int(input.card_id)],
    )

    return error("CYCLE:dependency") if not cycle.empty?

    _ = try Db.execute(
      conn,
      "insert into card_deps (card_id, depends_on_id, created_at) values (?, ?, ?)",
      [Db.Value.Int(input.card_id), Db.Value.Int(input.depends_on), Db.Value.Int(now)],
    )
  else
    return error("NOT_FOUND:dependency") if existing.empty?

    _ = try Db.execute(
      conn,
      "delete from card_deps where card_id = ? and depends_on_id = ?",
      [Db.Value.Int(input.card_id), Db.Value.Int(input.depends_on)],
    )
  end

  claim: Db.Value = nullable_text(card.claimed_by)
  claimed_at: Db.Value = nullable_int(card.claimed_at)
  lease: Db.Value = nullable_int(card.lease_until)
  if card.claimed_by.some? and not active
    # A lapsed claim is free: drop it, as every write does. A live claim stays: the card is blocked in its column.
    claim = Db.Value.Null
    claimed_at = Db.Value.Null
    lease = Db.Value.Null
  end

  if active and card.claimed_by.unwrap! == input.actor
    lease = Db.Value.Null
    if input.lease_minutes > 0
      lease = Db.Value.Int(now + input.lease_minutes * 60000)
    end
  end

  _ = try Db.execute(
    conn,
    "update cards set updated_at = ?, version = version + 1, claimed_by = ?, claimed_at = ?, lease_until = ? where id = ?",
    [Db.Value.Int(now), claim, claimed_at, lease, Db.Value.Int(input.card_id)],
  )

  updated = try Cards.load_at(conn, input.card_id, now)
  board = try Db.query(conn, "select board_id from cards where id = ?", [Db.Value.Int(input.card_id)])
  kind = "dep.removed"
  if adding
    kind = "dep.added"
  end

  _ = try Db.execute(
    conn,
    "insert into events (board_id, card_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?, ?)",
    [
      Db.Value.Int(number(board[0], "board_id")),
      Db.Value.Int(input.card_id),
      Db.Value.Text(kind),
      Db.Value.Text(input.actor),
      Db.Value.Text(JSON.encode(JSON.from(updated))),
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

def nullable_text(value: Optional[String]) -> Db.Value
  case value
    none -> Db.Value.Null
    some(text) -> Db.Value.Text(text)
  end
end

def nullable_int(value: Optional[Int]) -> Db.Value
  case value
    none -> Db.Value.Null
    some(number) -> Db.Value.Int(number)
  end
end
