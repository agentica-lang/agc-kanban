import Db from "pkg/db/db"
import Regex from "std/regex"
import Boards from "boards"
import Cards from "cards"
import Database from "repo/database"

struct Action
  id: Int
  actor: String
  force: Bool
end

struct Move
  id: Int
  actor: String
  force: Bool
  column: String
  position: Optional[Int]
  lease_minutes: Int
end

struct ArchiveDone
  board: String
  days: Int
  actor: String
  now: Int
end

struct ArchivedDone
  archived: Int
  days: Int
  cards: List[Int]
end

struct Release
  id: Int
  actor: String
  force: Bool
  column: Optional[String]
end

def finish(pool: Database.Pool, input: Action) -> Result[Cards.Card]
  return error("INVALID:id") if input.id <= 0
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| finish_open(tx, input) end end
end

## Hides a card from the board and the lists: it stays in the database and the journal, and `show` still reads it. It
## follows the rules of the other writes: a card that somebody else holds needs `force`. Archiving an archived card
## changes nothing and writes no event. The claim is dropped, so an archived card holds nothing.
def archive(pool: Database.Pool, input: Action) -> Result[Cards.Card]
  return error("INVALID:id") if input.id <= 0
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| archive_open(tx, input, Time.now_ms()) end end
end

## Puts an archived card back: on top of a done column, at the end of any other. Unarchiving a card that is not
## archived changes nothing and writes no event. `force` is not read: an archived card holds no claim.
def unarchive(pool: Database.Pool, input: Action) -> Result[Cards.Card]
  return error("INVALID:id") if input.id <= 0
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| unarchive_open(tx, input) end end
end

## Archives the cards of a done column that were done `days` days or more before `now`, in one transaction: a
## `card.archived` event per card and, when there is any, one `board.done_archived` event for the board. A card that
## is not in a done column, or that somebody holds, is never touched.
def archive_done(pool: Database.Pool, input: ArchiveDone) -> Result[ArchivedDone]
  return error("INVALID:board") if input.board.empty?
  return error("INVALID:days") if input.days < 0 or input.days > DAYS_MAX
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| archive_done_open(tx, input) end end
end

def move(pool: Database.Pool, input: Move) -> Result[Cards.Card]
  return error("INVALID:id") if input.id <= 0
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)
  return error("INVALID:column") if input.column.empty?
  return error("INVALID:position") if input.position.some? and input.position.unwrap! < 0
  return error("INVALID:lease") if input.lease_minutes < 0 or input.lease_minutes > 1000000000

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| move_open(tx, input, false) end end
end

def release(pool: Database.Pool, input: Release) -> Result[Cards.Card]
  return error("INVALID:id") if input.id <= 0
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)
  return error("INVALID:column") if input.column.some? and input.column.unwrap!.empty?

  move = Move(
    id: input.id,
    actor: input.actor,
    force: input.force,
    column: input.column.unwrap_or(""),
    position: none,
    lease_minutes: 0,
  )

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| move_open(tx, move, true) end end
end

private

DAY_MS = 86400000
DAYS_MAX = 36500

# The column a card left, so the feed can say "from Doing to Review". Events written before it have no `from`.
struct Source
  id: Int
  name: String
end

# The data of the card.moved, card.released and card.done events: the card after the change and where it was before.
struct EventData
  card: Cards.Card
  from: Source
  forced: Bool
end

# The data of the board.done_archived event.
struct SweepData
  count: Int
  days: Int
  cards: List[Int]
end

def finish_open(conn: Db.Connection, input: Action) -> Result[Cards.Card]
  now = Time.now_ms()
  card = try Cards.load_at(conn, input.id, now)
  return error("DONE:card") if card.done

  active = card.claimed_by.some? and (not card.lease_until.some? or card.lease_until.unwrap! > now)
  return error("NOT_CLAIMER:card") if not input.force and (not active or card.claimed_by.unwrap! != input.actor)
  try refuse_blocked(conn, card.id, input.force)

  rows = try Db.query(
    conn,
    "select c.board_id, col.id as done_id from cards c join columns col on col.board_id = c.board_id and col.done = 1 where c.id = ?",
    [Db.Value.Int(input.id)],
  )

  return error("CONFLICT:done_column") if rows.empty?

  board_id = number(rows[0], "board_id")
  target = number(rows[0], "done_id")
  # The newest finished card goes on top: make room at position 0 before the card
  # joins the column, so the shift never touches it and positions stay 0..n-1.
  _ = try Db.execute(
    conn,
    "update cards set position = position + 1, version = version + 1, updated_at = ? where column_id = ? and archived_at is null",
    [Db.Value.Int(now), Db.Value.Int(target)],
  )

  position = 0
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
  data = EventData(card: updated, from: Source(id: card.column_id, name: card.column), forced: input.force)
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

def archive_open(conn: Db.Connection, input: Action, now: Int) -> Result[Cards.Card]
  card = try Cards.load_any_at(conn, input.id, now)
  return ok(card) if card.archived_at.some?

  active = card.claimed_by.some? and (not card.lease_until.some? or card.lease_until.unwrap! > now)
  if active and card.claimed_by.unwrap! != input.actor and not input.force
    return error("CLAIMED:#{card.claimed_by.unwrap!}")
  end

  _ = try Db.execute(
    conn,
    "update cards set archived_at = ?, claimed_by = null, claimed_at = null, lease_until = null, updated_at = ?, version = version + 1 where id = ?",
    [Db.Value.Int(now), Db.Value.Int(now), Db.Value.Int(input.id)],
  )

  # The cards below it move up, so the positions of the column stay 0..n-1 without it.
  _ = try Db.execute(
    conn,
    "update cards set position = position - 1, version = version + 1, updated_at = ? where column_id = ? and position > ? and archived_at is null",
    [Db.Value.Int(now), Db.Value.Int(card.column_id), Db.Value.Int(card.position)],
  )

  updated = try Cards.load_any_at(conn, input.id, now)
  board = try Db.query(conn, "select board_id from cards where id = ?", [Db.Value.Int(input.id)])
  data = EventData(card: updated, from: Source(id: card.column_id, name: card.column), forced: input.force)
  _ = try Db.execute(
    conn,
    "insert into events (board_id, card_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?, ?)",
    [
      Db.Value.Int(number(board[0], "board_id")),
      Db.Value.Int(input.id),
      Db.Value.Text("card.archived"),
      Db.Value.Text(input.actor),
      Db.Value.Text(JSON.encode(JSON.from(data))),
      Db.Value.Int(now),
    ],
  )

  ok(updated)
end

def archive_done_open(conn: Db.Connection, input: ArchiveDone) -> Result[ArchivedDone]
  board = try Boards.get_open(conn, input.board)
  rows = try Db.query(
    conn,
    "select c.id from cards c join columns col on col.id = c.column_id where c.board_id = ? and c.archived_at is null and col.done = 1 and c.done_at is not null and c.done_at <= ? and (c.claimed_by is null or c.lease_until <= ?) order by c.id",
    [Db.Value.Int(board.id), Db.Value.Int(input.now - input.days * DAY_MS), Db.Value.Int(input.now)],
  )

  ids = rows.map do |row| number(row, "id") end
  action = Action(id: 0, actor: input.actor, force: false)
  for id in ids
    _ = try archive_open(conn, action.with(id: id), input.now)
  end

  if not ids.empty?
    data = SweepData(count: ids.size, days: input.days, cards: ids)
    _ = try Db.execute(
      conn,
      "insert into events (board_id, card_id, kind, actor, data, created_at) values (?, null, ?, ?, ?, ?)",
      [
        Db.Value.Int(board.id),
        Db.Value.Text("board.done_archived"),
        Db.Value.Text(input.actor),
        Db.Value.Text(JSON.encode(JSON.from(data))),
        Db.Value.Int(input.now),
      ],
    )
  end

  ok(ArchivedDone(archived: ids.size, days: input.days, cards: ids))
end

def unarchive_open(conn: Db.Connection, input: Action) -> Result[Cards.Card]
  now = Time.now_ms()
  card = try Cards.load_any_at(conn, input.id, now)
  return ok(card) if not card.archived_at.some?

  rows = try Db.query(
    conn,
    "select board_id, (select coalesce(max(position) + 1, 0) from cards where column_id = ? and archived_at is null) as next from cards where id = ?",
    [Db.Value.Int(card.column_id), Db.Value.Int(input.id)],
  )

  # Like `finish`, a card that comes back into a done column goes on top, any other column appends.
  done_at: Db.Value = Db.Value.Null
  position = number(rows[0], "next")
  if card.done
    done_at = Db.Value.Int(card.done_at.unwrap_or(now))
    position = 0
    _ = try Db.execute(
      conn,
      "update cards set position = position + 1, version = version + 1, updated_at = ? where column_id = ? and archived_at is null",
      [Db.Value.Int(now), Db.Value.Int(card.column_id)],
    )
  end

  _ = try Db.execute(
    conn,
    "update cards set archived_at = null, position = ?, done_at = ?, updated_at = ?, version = version + 1 where id = ?",
    [Db.Value.Int(position), done_at, Db.Value.Int(now), Db.Value.Int(input.id)],
  )

  updated = try Cards.load_at(conn, input.id, now)
  data = EventData(card: updated, from: Source(id: card.column_id, name: card.column), forced: false)
  _ = try Db.execute(
    conn,
    "insert into events (board_id, card_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?, ?)",
    [
      Db.Value.Int(number(rows[0], "board_id")),
      Db.Value.Int(input.id),
      Db.Value.Text("card.unarchived"),
      Db.Value.Text(input.actor),
      Db.Value.Text(JSON.encode(JSON.from(data))),
      Db.Value.Int(now),
    ],
  )

  ok(updated)
end

# A card with an open dependency cannot be closed (`done`, or a move into a done column) unless forced, with the
# same `force` that skips CLAIMED and NOT_CLAIMER. Every other move stays free, so a blocked card can sit in Doing
# or Review.
def refuse_blocked(conn: Db.Connection, id: Int, force: Bool) -> Result[Void]
  return ok() if force

  ids = try Cards.open_blockers(conn, id)
  return error("BLOCKED:#{ids.map { |blocker| blocker.to_s }.join(",")}") if not ids.empty?

  ok()
end

def number(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end

def move_open(conn: Db.Connection, input: Move, release: Bool) -> Result[Cards.Card]
  now = Time.now_ms()
  card = try Cards.load_at(conn, input.id, now)
  active = card.claimed_by.some? and (not card.lease_until.some? or card.lease_until.unwrap! > now)
  if release and not input.force and (not active or card.claimed_by.unwrap! != input.actor)
    return error("NOT_CLAIMER:card")
  end

  if not release and not input.force and active and card.claimed_by.unwrap! != input.actor
    return error("CLAIMED:#{card.claimed_by.unwrap!}")
  end

  source = try Db.query(conn, "select board_id from cards where id = ?", [Db.Value.Int(input.id)])
  board_id = number(source[0], "board_id")
  target = card.column_id
  target_done = card.done
  if not input.column.empty?
    rows = try Db.query(
      conn,
      "select id, done from columns where board_id = ? and (name = ? or cast(id as text) = ?) order by case when name = ? then 0 else 1 end limit 1",
      [Db.Value.Int(board_id), Db.Value.Text(input.column), Db.Value.Text(input.column), Db.Value.Text(input.column)],
    )

    return error("NOT_FOUND:column") if rows.empty?

    target = number(rows[0], "id")
    target_done = number(rows[0], "done") == 1
  end

  if target_done and not card.done
    try refuse_blocked(conn, card.id, input.force)
  end

  count = try Db.query(
    conn,
    "select count(*) as n from cards where column_id = ? and id != ? and archived_at is null",
    [Db.Value.Int(target), Db.Value.Int(input.id)],
  )

  # Into the done column a card goes on top, like finish; any other column appends.
  fallback = number(count[0], "n")
  if target_done
    fallback = 0
  end

  desired = input.position.unwrap_or(fallback)
  if release and input.column.empty?
    desired = card.position
  end

  return error("INVALID:position") if desired > number(count[0], "n")

  try reorder(conn, card, target, desired, now)
  claim: Db.Value = nullable_text(card.claimed_by)
  claimed_at: Db.Value = nullable_int(card.claimed_at)
  lease: Db.Value = nullable_int(card.lease_until)
  done_at: Db.Value = Db.Value.Null
  if target_done
    done_at = Db.Value.Int(card.done_at.unwrap_or(now))
  end

  if release or target_done
    claim = Db.Value.Null
    claimed_at = Db.Value.Null
    lease = Db.Value.Null
  elsif active and card.claimed_by.unwrap! == input.actor
    lease = Db.Value.Null
    if input.lease_minutes > 0
      lease = Db.Value.Int(now + input.lease_minutes * 60000)
    end
  end

  _ = try Db.execute(
    conn,
    "update cards set column_id = ?, position = ?, claimed_by = ?, claimed_at = ?, lease_until = ?, done_at = ?, updated_at = ?, version = version + 1 where id = ?",
    [
      Db.Value.Int(target),
      Db.Value.Int(desired),
      claim,
      claimed_at,
      lease,
      done_at,
      Db.Value.Int(now),
      Db.Value.Int(input.id),
    ],
  )

  updated = try Cards.load_at(conn, input.id, now)
  kind = "card.moved"
  if release
    kind = "card.released"
  end

  data = EventData(card: updated, from: Source(id: card.column_id, name: card.column), forced: input.force)
  _ = try Db.execute(
    conn,
    "insert into events (board_id, card_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?, ?)",
    [
      Db.Value.Int(board_id),
      Db.Value.Int(input.id),
      Db.Value.Text(kind),
      Db.Value.Text(input.actor),
      Db.Value.Text(JSON.encode(JSON.from(data))),
      Db.Value.Int(now),
    ],
  )

  ok(updated)
end

def reorder(conn: Db.Connection, card: Cards.Card, target: Int, desired: Int, now: Int) -> Result[Void]
  if target == card.column_id
    if desired > card.position
      _ = try Db.execute(
        conn,
        "update cards set position = position - 1, updated_at = ?, version = version + 1 where column_id = ? and position > ? and position <= ? and archived_at is null",
        [Db.Value.Int(now), Db.Value.Int(target), Db.Value.Int(card.position), Db.Value.Int(desired)],
      )
    elsif desired < card.position
      _ = try Db.execute(
        conn,
        "update cards set position = position + 1, updated_at = ?, version = version + 1 where column_id = ? and position >= ? and position < ? and archived_at is null",
        [Db.Value.Int(now), Db.Value.Int(target), Db.Value.Int(desired), Db.Value.Int(card.position)],
      )
    end
  else
    _ = try Db.execute(
      conn,
      "update cards set position = position - 1, updated_at = ?, version = version + 1 where column_id = ? and position > ? and archived_at is null",
      [Db.Value.Int(now), Db.Value.Int(card.column_id), Db.Value.Int(card.position)],
    )

    _ = try Db.execute(
      conn,
      "update cards set position = position + 1, updated_at = ?, version = version + 1 where column_id = ? and position >= ? and archived_at is null",
      [Db.Value.Int(now), Db.Value.Int(target), Db.Value.Int(desired)],
    )
  end

  ok()
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
