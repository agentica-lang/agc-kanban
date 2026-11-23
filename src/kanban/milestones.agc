import Db from "pkg/db/db"
import Regex from "std/regex"
import Database from "repo/database"
import Labels from "labels"

# A milestone is a label that the board flagged (its id is the label id). The cards stay as they are: a card is in a
# milestone by carrying the label. A card counts as closed when its column is done, archived or not (so the auto
# archive does not lower the percent), and as open when it is not archived and not done. An archived card that was not
# done counts in neither.
struct Milestone
  id: Int
  name: String
  color: String
  description: String
  due_on: Optional[String]
  state: String
  closed_at: Optional[Int]
  open: Int
  closed: Int
  percent: Int
  overdue: Bool
end

struct Create
  board: String
  name: String
  description: String
  due_on: Optional[String]
  actor: String
end

# An empty `due_on` clears the date; none leaves it as it is.
struct Update
  id: Int
  description: Optional[String]
  due_on: Optional[String]
  state: Optional[String]
  actor: String
end

struct Remove
  id: Int
  actor: String
end

def today() -> String = Time.at_us(Time.now_ms() * 1000).unwrap!.strftime("%Y-%m-%d")

## `state` is "open", "closed" or "all". Open ones come first, the soonest due date first and the ones without a date
## last; closed ones come after, the newest first.
def list(pool: Database.Pool, board: String, state: String, today: String) -> Result[List[Milestone]]
  return error("INVALID:board") if board.empty?
  return error("INVALID:state") if not ["open", "closed", "all"].include?(state)

  Database.with_connection(pool) do |conn|
    Db.transaction(conn) do |tx|
      id = try board_id(tx, board)
      list_by_board_id(tx, id, state, today)
    end
  end
end

def list_by_board_id(conn: Db.Connection, board_id: Int, state: String, today: String) -> Result[List[Milestone]]
  rows = try Db.query(
    conn,
    "#{SELECT} where l.board_id = ? and (? = 'all' or (? = 'open') = (m.closed_at is null)) #{ORDER}",
    [Db.Value.Text(today), Db.Value.Int(board_id), Db.Value.Text(state), Db.Value.Text(state)],
  )

  ok(rows.map do |row| milestone(row) end)
end

def create(pool: Database.Pool, input: Create) -> Result[Milestone]
  return error("INVALID:name") if input.name.strip.empty?
  return error("INVALID:due_on") if input.due_on.some? and not valid_date?(input.due_on.unwrap!)
  return error("INVALID:agent") if not valid_agent?(input.actor)

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| create_open(tx, input) end end
end

def update(pool: Database.Pool, input: Update) -> Result[Milestone]
  return error("INVALID:id") if input.id <= 0
  return error("INVALID:milestone") if not input.description.some? and not input.due_on.some? and not input.state.some?
  return error("INVALID:due_on") if input.due_on.some? and not blank_or_date?(input.due_on.unwrap!)
  return error("INVALID:state") if input.state.some? and not ["open", "closed"].include?(input.state.unwrap!)
  return error("INVALID:agent") if not valid_agent?(input.actor)

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| update_open(tx, input) end end
end

def remove(pool: Database.Pool, input: Remove) -> Result[Void]
  return error("INVALID:id") if input.id <= 0
  return error("INVALID:agent") if not valid_agent?(input.actor)

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| remove_open(tx, input) end end
end

private

SELECT = (
  "select l.id, l.name, l.color, m.description, m.due_on, m.closed_at, coalesce(m.due_on < ?, 0) as late, (select count(*) from cards c join columns col on col.id = c.column_id where c.board_id = l.board_id and col.done = 1 and exists (select 1 from json_each(c.labels) j where j.value = l.name)) as closed, (select count(*) from cards c join columns col on col.id = c.column_id where c.board_id = l.board_id and col.done = 0 and c.archived_at is null and exists (select 1 from json_each(c.labels) j where j.value = l.name)) as open from milestones m join labels l on l.id = m.label_id"
)

ORDER = (
  "order by m.closed_at is not null, case when m.closed_at is null then m.due_on is null else 0 end, case when m.closed_at is null then m.due_on end, m.closed_at desc, l.name"
)

def valid_agent?(actor: String) -> Bool = Regex.match?(actor, /^[A-Za-z0-9._@\/-]{1,64}$/)

def blank_or_date?(value: String) -> Bool = value.empty? or valid_date?(value)

def valid_date?(value: String) -> Bool = Regex.match?(value, /^\d{4}-\d{2}-\d{2}$/)

# SQLite moves 2026-02-30 to March, so the date counts when it comes back unchanged.
def real_date?(conn: Db.Connection, value: String) -> Result[Bool]
  rows = try Db.query(conn, "select date(?) as d", [Db.Value.Text(value)])
  ok(text_of(rows[0], "d") == value)
end

def board_id(conn: Db.Connection, reference: String) -> Result[Int]
  found = try Db.query(
    conn,
    "select id from boards where slug = ? or cast(id as text) = ? order by case when slug = ? then 0 else 1 end limit 1",
    [Db.Value.Text(reference), Db.Value.Text(reference), Db.Value.Text(reference)],
  )

  return error("NOT_FOUND:board") if found.empty?

  ok(number_of(found[0], "id"))
end

def create_open(conn: Db.Connection, input: Create) -> Result[Milestone]
  if input.due_on.some?
    real = try real_date?(conn, input.due_on.unwrap!)
    return error("INVALID:due_on") if not real
  end

  board = try board_id(conn, input.board)
  now = Time.now_ms()
  try Labels.ensure(conn, board, [input.name], now)
  rows = try Db.query(
    conn,
    "select id from labels where board_id = ? and name = ?",
    [Db.Value.Int(board), Db.Value.Text(input.name)],
  )

  id = number_of(rows[0], "id")
  known = try Db.query(conn, "select label_id from milestones where label_id = ?", [Db.Value.Int(id)])
  return error("CONFLICT:name") if not known.empty?

  _ = try Db.execute(
    conn,
    "insert into milestones (label_id, description, due_on, created_at) values (?, ?, ?, ?)",
    [Db.Value.Int(id), Db.Value.Text(input.description), nullable(input.due_on), Db.Value.Int(now)],
  )

  announce(conn, board, id, input.actor, now)
end

def update_open(conn: Db.Connection, input: Update) -> Result[Milestone]
  rows = try Db.query(
    conn,
    "select l.board_id, m.description, m.due_on, m.closed_at from milestones m join labels l on l.id = m.label_id where m.label_id = ?",
    [Db.Value.Int(input.id)],
  )

  return error("NOT_FOUND:milestone") if rows.empty?

  due = input.due_on.unwrap_or("")
  if not due.empty?
    real = try real_date?(conn, due)
    return error("INVALID:due_on") if not real
  end

  now = Time.now_ms()
  description = input.description.unwrap_or(text_of(rows[0], "description"))
  due_on = optional_text(rows[0], "due_on")
  if input.due_on.some?
    due_on = none
    if not due.empty?
      due_on = some(due)
    end
  end

  closed_at = optional_int(rows[0], "closed_at")
  if input.state.some?
    if input.state.unwrap! == "open"
      closed_at = none
    elsif not closed_at.some?
      closed_at = some(now)
    end
  end

  _ = try Db.execute(
    conn,
    "update milestones set description = ?, due_on = ?, closed_at = ? where label_id = ?",
    [Db.Value.Text(description), nullable(due_on), nullable_int(closed_at), Db.Value.Int(input.id)],
  )

  announce(conn, number_of(rows[0], "board_id"), input.id, input.actor, now)
end

def remove_open(conn: Db.Connection, input: Remove) -> Result[Void]
  rows = try Db.query(
    conn,
    "select l.board_id, l.name from milestones m join labels l on l.id = m.label_id where m.label_id = ?",
    [Db.Value.Int(input.id)],
  )

  return error("NOT_FOUND:milestone") if rows.empty?

  _ = try Db.execute(conn, "delete from milestones where label_id = ?", [Db.Value.Int(input.id)])
  data = JSON.encode(JSON.from({"id": JSON.from(input.id), "name": JSON.from(text_of(rows[0], "name"))}))
  insert_event(conn, number_of(rows[0], "board_id"), "milestone.removed", input.actor, data, Time.now_ms())
end

# The milestone as it is now, and its `milestone.updated` event.
def announce(conn: Db.Connection, board: Int, id: Int, actor: String, now: Int) -> Result[Milestone]
  rows = try Db.query(conn, "#{SELECT} where m.label_id = ?", [Db.Value.Text(today()), Db.Value.Int(id)])
  current = milestone(rows[0])
  try insert_event(conn, board, "milestone.updated", actor, JSON.encode(JSON.from(current)), now)
  ok(current)
end

def insert_event(conn: Db.Connection, board: Int, kind: String, actor: String, data: String, now: Int) -> Result[Void]
  _ = try Db.execute(
    conn,
    "insert into events (board_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?)",
    [Db.Value.Int(board), Db.Value.Text(kind), Db.Value.Text(actor), Db.Value.Text(data), Db.Value.Int(now)],
  )

  ok()
end

def milestone(row: Db.Row) -> Milestone
  open = number_of(row, "open")
  closed = number_of(row, "closed")
  total = open + closed
  percent = 0
  if total > 0
    percent = (closed * 100) / total
  end

  due_on = optional_text(row, "due_on")
  closed_at = optional_int(row, "closed_at")
  state = "open"
  if closed_at.some?
    state = "closed"
  end

  Milestone(
    id: number_of(row, "id"),
    name: text_of(row, "name"),
    color: text_of(row, "color"),
    description: text_of(row, "description"),
    due_on: due_on,
    state: state,
    closed_at: closed_at,
    open: open,
    closed: closed,
    percent: percent,
    overdue: number_of(row, "late") == 1 and not closed_at.some? and open > 0,
  )
end

def optional_text(row: Db.Row, key: String) -> Optional[String]
  case row.get(key, Db.Value.Null)
    Db.Value.Text(value) -> some(value)
    _ -> none
  end
end

def optional_int(row: Db.Row, key: String) -> Optional[Int]
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> some(value)
    _ -> none
  end
end

def nullable(value: Optional[String]) -> Db.Value
  return Db.Value.Text(value.unwrap!) if value.some?

  Db.Value.Null
end

def nullable_int(value: Optional[Int]) -> Db.Value
  return Db.Value.Int(value.unwrap!) if value.some?

  Db.Value.Null
end

def number_of(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end

def text_of(row: Db.Row, key: String) -> String
  case row.get(key, Db.Value.Null)
    Db.Value.Text(value) -> value
    _ -> ""
  end
end
