import Db from "pkg/db/db"
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

# Gives each name that the board has not seen a color: one of the palette that no label of the board wears yet, any
# of it when all are taken.
def ensure(conn: Db.Connection, board_id: Int, names: List[String], now: Int) -> Result[Void]
  rows = try Db.query(conn, "select name, color from labels where board_id = ?", [Db.Value.Int(board_id)])
  known = rows.map do |row| text_of(row, "name") end
  used = rows.map do |row| text_of(row, "color") end
  for name in names
    next if known.include?(name) or name.strip.empty?

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
