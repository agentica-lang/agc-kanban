import Db from "pkg/db/db"
import Regex from "std/regex"
import Boards from "boards"
import Database from "repo/database"

export struct Add
  board: String
  name: String
  position: Optional[Int]
  done: Bool
  wip_limit: Optional[Int]
  actor: String
end

export def add(pool: Database.Pool, input: Add) -> Result[Boards.Column]
  return error("INVALID:board") if input.board.empty?
  return error("INVALID:name") if input.name.strip.empty?
  return error("INVALID:position") if input.position.some? and input.position.unwrap! < 0
  return error("INVALID:wip_limit") if input.wip_limit.some? and input.wip_limit.unwrap! <= 0
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| insert(tx, input) end end
end

def insert(conn: Db.Connection, input: Add) -> Result[Boards.Column]
  boards = try Db.query(
    conn,
    "select id from boards where slug = ? or cast(id as text) = ? order by case when slug = ? then 0 else 1 end limit 1",
    [Db.Value.Text(input.board), Db.Value.Text(input.board), Db.Value.Text(input.board)],
  )

  return error("NOT_FOUND:board") if boards.empty?

  board_id = int_of(boards[0], "id")
  rows = try Db.query(
    conn,
    "select id, name from columns where board_id = ? order by position",
    [Db.Value.Int(board_id)],
  )

  return error("CONFLICT:name") if rows.any? do |row| text_of(row, "name") == input.name end

  position = input.position.unwrap_or(rows.size)
  return error("INVALID:position") if position > rows.size

  now = Time.now_ms()
  _ = try Db.execute(conn, "update columns set position = -position - 1 where board_id = ?", [Db.Value.Int(board_id)])
  for index in 0...rows.size
    next_position = index
    if index >= position
      next_position = index + 1
    end

    _ = try Db.execute(
      conn,
      "update columns set position = ? where id = ?",
      [Db.Value.Int(next_position), Db.Value.Int(int_of(rows[index], "id"))],
    )
  end

  if input.done
    _ = try Db.execute(
      conn,
      "update cards set done_at = null, updated_at = ?, version = version + 1 where board_id = ? and column_id in (select id from columns where board_id = ? and done = 1)",
      [Db.Value.Int(now), Db.Value.Int(board_id), Db.Value.Int(board_id)],
    )

    _ = try Db.execute(conn, "update columns set done = 0 where board_id = ? and done = 1", [Db.Value.Int(board_id)])
  end

  done = 0
  if input.done
    done = 1
  end

  wip = case input.wip_limit
    some(value) -> Db.Value.Int(value)
    none -> Db.Value.Null
  end

  _ = try Db.execute(
    conn,
    "insert into columns (board_id, name, position, done, wip_limit, created_at) values (?, ?, ?, ?, ?, ?)",
    [
      Db.Value.Int(board_id),
      Db.Value.Text(input.name),
      Db.Value.Int(position),
      Db.Value.Int(done),
      wip,
      Db.Value.Int(now),
    ],
  )

  created = try Db.query(
    conn,
    "select id from columns where board_id = ? and position = ?",
    [Db.Value.Int(board_id), Db.Value.Int(position)],
  )

  column = Boards.Column(
    id: int_of(created[0], "id"),
    name: input.name,
    position: position,
    done: input.done,
    wip_limit: input.wip_limit,
  )

  _ = try Db.execute(
    conn,
    "update boards set updated_at = ? where id = ?",
    [Db.Value.Int(now), Db.Value.Int(board_id)],
  )

  _ = try Db.execute(
    conn,
    "insert into events (board_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?)",
    [
      Db.Value.Int(board_id),
      Db.Value.Text("column.added"),
      Db.Value.Text(input.actor),
      Db.Value.Text(JSON.encode(JSON.from(column))),
      Db.Value.Int(now),
    ],
  )

  ok(column)
end

def int_of(row: Db.Row, key: String) -> Int
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
