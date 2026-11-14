import Db from "pkg/db/db"
import Regex from "std/regex"
import Database from "repo/database"

PALETTE = [
  "#d73a4a",
  "#0075ca",
  "#7057ff",
  "#008672",
  "#e99695",
  "#fbca04",
  "#0e8a16",
  "#d876e3",
  "#1d76db",
  "#b60205",
  "#c5def5",
  "#bfd4f2",
]

struct Label
  id: Int
  name: String
  color: String
end

struct Update
  id: Int
  name: Optional[String]
  color: Optional[String]
  actor: String
end

def list(pool: Database.Pool, board: String) -> Result[List[Label]]
  return error("INVALID:board") if board.empty?

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| list_board(tx, board) end end
end

def list_by_board_id(conn: Db.Connection, board_id: Int) -> Result[List[Label]]
  rows = try Db.query(
    conn,
    "select id, name, color from labels where board_id = ? order by name",
    [Db.Value.Int(board_id)],
  )

  ok(rows.map do |row| label(row) end)
end

def update(pool: Database.Pool, input: Update) -> Result[Label]
  return error("INVALID:id") if input.id <= 0
  return error("INVALID:label") if not input.name.some? and not input.color.some?
  return error("INVALID:name") if input.name.some? and input.name.unwrap!.strip.empty?
  return error("INVALID:color") if input.color.some? and not valid_color?(input.color.unwrap!)
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| update_open(tx, input) end end
end

# Gives each name that the board has not seen a color: one of the palette that no label of the board wears yet, any
# of it when all are taken.
def ensure(conn: Db.Connection, board_id: Int, names: List[String], now: Int) -> Result[Void]
  rows = try Db.query(conn, "select name, color from labels where board_id = ?", [Db.Value.Int(board_id)])
  known = rows.map do |row| text_of(row, "name") end
  used = rows.map do |row| text_of(row, "color") end
  for name in names
    next if known.include?(name)

    color = pick(used)
    _ = try Db.execute(
      conn,
      "insert into labels (board_id, name, color, created_at) values (?, ?, ?, ?)",
      [Db.Value.Int(board_id), Db.Value.Text(name), Db.Value.Text(color), Db.Value.Int(now)],
    )

    known = known.push(name)
    used = used.push(color)
  end

  ok()
end

private

# The data of a label.updated event: the label as it is now and the name it had.
struct Changed
  id: Int
  name: String
  color: String
  previous_name: String
end

def valid_color?(color: String) -> Bool = Regex.match?(color, /^#[0-9A-Fa-f]{6}$/)

def pick(used: List[String]) -> String
  fresh = PALETTE.select do |color| not used.include?(color) end
  choices = PALETTE
  if not fresh.empty?
    choices = fresh
  end

  choices[Random.int(0, choices.size - 1)]
end

def list_board(conn: Db.Connection, reference: String) -> Result[List[Label]]
  found = try Db.query(
    conn,
    "select id from boards where slug = ? or cast(id as text) = ? order by case when slug = ? then 0 else 1 end limit 1",
    [Db.Value.Text(reference), Db.Value.Text(reference), Db.Value.Text(reference)],
  )

  return error("NOT_FOUND:board") if found.empty?

  list_by_board_id(conn, number_of(found[0], "id"))
end

def update_open(conn: Db.Connection, input: Update) -> Result[Label]
  rows = try Db.query(conn, "select id, board_id, name, color from labels where id = ?", [Db.Value.Int(input.id)])

  return error("NOT_FOUND:label") if rows.empty?

  current = label(rows[0])
  board_id = number_of(rows[0], "board_id")
  name = input.name.unwrap_or(current.name)
  color = input.color.unwrap_or(current.color).downcase
  return ok(current) if name == current.name and color == current.color

  if name != current.name
    taken = try Db.query(
      conn,
      "select id from labels where board_id = ? and name = ?",
      [Db.Value.Int(board_id), Db.Value.Text(name)],
    )

    return error("CONFLICT:name") if not taken.empty?
  end

  now = Time.now_ms()
  _ = try Db.execute(
    conn,
    "update labels set name = ?, color = ? where id = ?",
    [Db.Value.Text(name), Db.Value.Text(color), Db.Value.Int(input.id)],
  )

  if name != current.name
    try rename_on_cards(conn, board_id, current.name, name, now)
  end

  updated = Label(id: input.id, name: name, color: color)
  _ = try Db.execute(
    conn,
    "insert into events (board_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?)",
    [
      Db.Value.Int(board_id),
      Db.Value.Text("label.updated"),
      Db.Value.Text(input.actor),
      Db.Value.Text(
        JSON.encode(JSON.from(Changed(id: input.id, name: name, color: color, previous_name: current.name))),
      ),
      Db.Value.Int(now),
    ],
  )

  ok(updated)
end

def rename_on_cards(conn: Db.Connection, board_id: Int, old_name: String, new_name: String, now: Int) -> Result[Void]
  rows = try Db.query(
    conn,
    "select c.id, c.labels from cards c where c.board_id = ? and exists (select 1 from json_each(c.labels) j where j.value = ?)",
    [Db.Value.Int(board_id), Db.Value.Text(old_name)],
  )

  for row in rows
    names = try JSON.decode(text_of(row, "labels"), List[String])
    renamed = names.map { |name| swapped(name, old_name, new_name) }.uniq
    _ = try Db.execute(
      conn,
      "update cards set labels = ?, updated_at = ?, version = version + 1 where id = ?",
      [Db.Value.Text(JSON.encode(JSON.from(renamed))), Db.Value.Int(now), Db.Value.Int(number_of(row, "id"))],
    )
  end

  ok()
end

def swapped(name: String, old_name: String, new_name: String) -> String
  return new_name if name == old_name

  name
end

def label(row: Db.Row) -> Label
  Label(id: number_of(row, "id"), name: text_of(row, "name"), color: text_of(row, "color"))
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
