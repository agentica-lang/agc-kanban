import Db from "pkg/db/db"
import Regex from "std/regex"
import Database from "repo/database"

struct Column
  id: Int
  name: String
  position: Int
  done: Bool
  wip_limit: Optional[Int]
end

struct BoardSummary
  id: Int
  slug: String
  name: String
  created_at: Int
  updated_at: Int
end

struct Board
  id: Int
  slug: String
  name: String
  created_at: Int
  updated_at: Int
  # None: the done cards stay until somebody archives them. Some(n): the server archives the ones done n days ago.
  auto_archive_days: Optional[Int]
  columns: List[Column]
end

def create(pool: Database.Pool, name: String, slug: String, actor: String, names: List[String]) -> Result[Board]
  return error("INVALID:name") if name.strip.empty?
  return error("INVALID:slug") if not Regex.match?(slug, /^[a-z0-9-]{1,40}$/)
  return error("INVALID:agent") if not Regex.match?(actor, /^[A-Za-z0-9._@\/-]{1,64}$/)

  return error("INVALID:columns") if names.empty?
  for column_name in names
    return error("INVALID:columns") if column_name.strip.empty?
    duplicates = names.select do |other| other == column_name end
    return error("INVALID:columns") if duplicates.size > 1
  end

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| insert(tx, name, slug, actor, names) end end
end

def list(pool: Database.Pool) -> Result[List[BoardSummary]]
  Database.with_connection(pool) do |conn|
    rows = try Db.query(conn, "select id, slug, name, created_at, updated_at from boards order by id", [])
    ok(rows.map do |row| summary(row) end)
  end
end

def get_open(conn: Db.Connection, reference: String) -> Result[Board]
  return error("INVALID:board") if reference.empty?

  rows = try Db.query(
    conn,
    "select id, slug, name, created_at, updated_at, auto_archive_days from boards where slug = ? or cast(id as text) = ? order by case when slug = ? then 0 else 1 end limit 1",
    [Db.Value.Text(reference), Db.Value.Text(reference), Db.Value.Text(reference)],
  )

  return error("NOT_FOUND:board") if rows.empty?

  id = int_of(rows[0], "id")
  found = try Db.query(
    conn,
    "select id, name, position, done, wip_limit from columns where board_id = ? order by position",
    [Db.Value.Int(id)],
  )

  columns = found.map do |row| read_column(row) end
  ok(board(rows[0], columns))
end

private

def insert(conn: Db.Connection, name: String, slug: String, actor: String, names: List[String]) -> Result[Board]
  exists = try Db.query(conn, "select id from boards where slug = ?", [Db.Value.Text(slug)])
  return error("CONFLICT:slug") if not exists.empty?

  now = Time.now_ms()
  _ = try Db.execute(
    conn,
    "insert into boards (slug, name, created_at, updated_at) values (?, ?, ?, ?)",
    [Db.Value.Text(slug), Db.Value.Text(name), Db.Value.Int(now), Db.Value.Int(now)],
  )

  rows = try Db.query(
    conn,
    "select id, slug, name, created_at, updated_at from boards where slug = ?",
    [Db.Value.Text(slug)],
  )

  id = int_of(rows[0], "id")
  columns = try insert_columns(conn, id, now, names)
  data = JSON.encode(JSON.from({"name": name, "slug": slug}))
  _ = try Db.execute(
    conn,
    "insert into events (board_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?)",
    [Db.Value.Int(id), Db.Value.Text("board.created"), Db.Value.Text(actor), Db.Value.Text(data), Db.Value.Int(now)],
  )

  ok(board(rows[0], columns))
end

def insert_columns(conn: Db.Connection, id: Int, now: Int, names: List[String]) -> Result[List[Column]]
  for position in 0...names.size
    done = 0
    if position == names.size - 1
      done = 1
    end

    _ = try Db.execute(
      conn,
      "insert into columns (board_id, name, position, done, created_at) values (?, ?, ?, ?, ?)",
      [
        Db.Value.Int(id),
        Db.Value.Text(names[position]),
        Db.Value.Int(position),
        Db.Value.Int(done),
        Db.Value.Int(now),
      ],
    )
  end

  rows = try Db.query(
    conn,
    "select id, name, position, done from columns where board_id = ? order by position",
    [Db.Value.Int(id)],
  )

  ok(
    rows.map do |row|
      Column(
        id: int_of(row, "id"),
        name: text_of(row, "name"),
        position: int_of(row, "position"),
        done: int_of(row, "done") == 1,
        wip_limit: none,
      )
    end,
  )
end

def board(row: Db.Row, columns: List[Column]) -> Board
  Board(
    id: int_of(row, "id"),
    slug: text_of(row, "slug"),
    name: text_of(row, "name"),
    created_at: int_of(row, "created_at"),
    updated_at: int_of(row, "updated_at"),
    auto_archive_days: optional_int(row, "auto_archive_days"),
    columns: columns,
  )
end

def int_of(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end

def optional_int(row: Db.Row, key: String) -> Optional[Int]
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> some(value)
    _ -> none
  end
end

def text_of(row: Db.Row, key: String) -> String
  case row.get(key, Db.Value.Null)
    Db.Value.Text(value) -> value
    _ -> ""
  end
end

def summary(row: Db.Row) -> BoardSummary
  BoardSummary(
    id: int_of(row, "id"),
    slug: text_of(row, "slug"),
    name: text_of(row, "name"),
    created_at: int_of(row, "created_at"),
    updated_at: int_of(row, "updated_at"),
  )
end

def read_column(row: Db.Row) -> Column
  wip = case row.get("wip_limit", Db.Value.Null)
    Db.Value.Int(value) -> some(value)
    _ -> none
  end

  Column(
    id: int_of(row, "id"),
    name: text_of(row, "name"),
    position: int_of(row, "position"),
    done: int_of(row, "done") == 1,
    wip_limit: wip,
  )
end
