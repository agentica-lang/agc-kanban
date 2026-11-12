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

export struct Update
  id: Int
  name: Optional[String]
  position: Optional[Int]
  done: Optional[Bool]
  wip_limit: Optional[Int]
  actor: String
end

export struct Remove
  id: Int
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

export def update(pool: Database.Pool, input: Update) -> Result[Boards.Column]
  return error("INVALID:id") if input.id <= 0
  return error("INVALID:name") if input.name.some? and input.name.unwrap!.strip.empty?
  return error("INVALID:position") if input.position.some? and input.position.unwrap! < 0
  return error("INVALID:wip_limit") if input.wip_limit.some? and input.wip_limit.unwrap! <= 0
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| update_open(tx, input) end end
end

export def remove(pool: Database.Pool, input: Remove) -> Result[Void]
  return error("INVALID:id") if input.id <= 0
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| remove_open(tx, input) end end
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

def update_open(conn: Db.Connection, input: Update) -> Result[Boards.Column]
  rows = try Db.query(
    conn,
    "select id, board_id, name, position, done, wip_limit from columns where id = ?",
    [Db.Value.Int(input.id)],
  )

  return error("NOT_FOUND:column") if rows.empty?

  board_id = int_of(rows[0], "board_id")
  current = read_column(rows[0])
  name = input.name.unwrap_or(current.name)
  position = input.position.unwrap_or(current.position)
  done = input.done.unwrap_or(current.done)
  return error("CONFLICT:done_column") if current.done and not done

  if name != current.name
    taken = try Db.query(
      conn,
      "select id from columns where board_id = ? and name = ? and id != ?",
      [Db.Value.Int(board_id), Db.Value.Text(name), Db.Value.Int(input.id)],
    )

    return error("CONFLICT:name") if not taken.empty?
  end

  ordered = try Db.query(conn, "select id from columns where board_id = ? order by position", [Db.Value.Int(board_id)])

  return error("INVALID:position") if position >= ordered.size
  now = Time.now_ms()
  if position != current.position
    try reorder(conn, board_id, ordered, input.id, position)
  end

  if done and not current.done
    _ = try Db.execute(
      conn,
      "update cards set done_at = null, updated_at = ?, version = version + 1 where column_id in (select id from columns where board_id = ? and done = 1)",
      [Db.Value.Int(now), Db.Value.Int(board_id)],
    )

    _ = try Db.execute(
      conn,
      "update cards set done_at = ?, claimed_by = null, claimed_at = null, lease_until = null, updated_at = ?, version = version + 1 where column_id = ? and done_at is null",
      [Db.Value.Int(now), Db.Value.Int(now), Db.Value.Int(input.id)],
    )

    _ = try Db.execute(conn, "update columns set done = 0 where board_id = ? and done = 1", [Db.Value.Int(board_id)])
  end

  wip = nullable(input.wip_limit)
  if input.wip_limit.none?
    wip = nullable(current.wip_limit)
  end

  _ = try Db.execute(
    conn,
    "update columns set name = ?, position = ?, done = ?, wip_limit = ? where id = ?",
    [Db.Value.Text(name), Db.Value.Int(position), Db.Value.Int(bool_int(done)), wip, Db.Value.Int(input.id)],
  )

  _ = try Db.execute(
    conn,
    "update boards set updated_at = ? where id = ?",
    [Db.Value.Int(now), Db.Value.Int(board_id)],
  )

  updated = try reload(conn, input.id)
  _ = try Db.execute(
    conn,
    "insert into events (board_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?)",
    [
      Db.Value.Int(board_id),
      Db.Value.Text("column.updated"),
      Db.Value.Text(input.actor),
      Db.Value.Text(JSON.encode(JSON.from(updated))),
      Db.Value.Int(now),
    ],
  )

  ok(updated)
end

def remove_open(conn: Db.Connection, input: Remove) -> Result[Void]
  rows = try Db.query(
    conn,
    "select id, board_id, name, position, done from columns where id = ?",
    [Db.Value.Int(input.id)],
  )

  return error("NOT_FOUND:column") if rows.empty?
  return error("CONFLICT:done_column") if int_of(rows[0], "done") == 1

  board_id = int_of(rows[0], "board_id")
  cards = try Db.query(conn, "select count(*) as n from cards where column_id = ?", [Db.Value.Int(input.id)])

  return error("CONFLICT:column_not_empty") if int_of(cards[0], "n") > 0

  now = Time.now_ms()
  _ = try Db.execute(conn, "delete from columns where id = ?", [Db.Value.Int(input.id)])
  remaining = try Db.query(
    conn,
    "select id from columns where board_id = ? order by position",
    [Db.Value.Int(board_id)],
  )

  _ = try Db.execute(conn, "update columns set position = -position - 1 where board_id = ?", [Db.Value.Int(board_id)])

  for index in 0...remaining.size
    _ = try Db.execute(
      conn,
      "update columns set position = ? where id = ?",
      [Db.Value.Int(index), Db.Value.Int(int_of(remaining[index], "id"))],
    )
  end

  _ = try Db.execute(
    conn,
    "update boards set updated_at = ? where id = ?",
    [Db.Value.Int(now), Db.Value.Int(board_id)],
  )

  data = JSON.encode(JSON.object({"id": JSON.from(input.id), "name": JSON.from(text_of(rows[0], "name"))}))
  _ = try Db.execute(
    conn,
    "insert into events (board_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?)",
    [
      Db.Value.Int(board_id),
      Db.Value.Text("column.removed"),
      Db.Value.Text(input.actor),
      Db.Value.Text(data),
      Db.Value.Int(now),
    ],
  )

  ok()
end

def reorder(conn: Db.Connection, board_id: Int, ordered: List[Db.Row], id: Int, position: Int) -> Result[Void]
  others = ordered.map do |row| int_of(row, "id") end.select do |current| current != id end
  wanted: List[Int] = []
  for index in 0...ordered.size
    if index == position
      wanted = wanted.push(id)
    end

    if index < others.size
      wanted = wanted.push(others[index])
    end
  end

  _ = try Db.execute(conn, "update columns set position = -position - 1 where board_id = ?", [Db.Value.Int(board_id)])

  for index in 0...wanted.size
    _ = try Db.execute(
      conn,
      "update columns set position = ? where id = ?",
      [Db.Value.Int(index), Db.Value.Int(wanted[index])],
    )
  end

  ok()
end

def reload(conn: Db.Connection, id: Int) -> Result[Boards.Column]
  rows = try Db.query(conn, "select id, name, position, done, wip_limit from columns where id = ?", [Db.Value.Int(id)])

  ok(read_column(rows[0]))
end

def read_column(row: Db.Row) -> Boards.Column
  wip = case row.get("wip_limit", Db.Value.Null)
    Db.Value.Int(value) -> some(value)
    _ -> none
  end

  Boards.Column(
    id: int_of(row, "id"),
    name: text_of(row, "name"),
    position: int_of(row, "position"),
    done: int_of(row, "done") == 1,
    wip_limit: wip,
  )
end

def nullable(value: Optional[Int]) -> Db.Value
  case value
    none -> Db.Value.Null
    some(number) -> Db.Value.Int(number)
  end
end

def bool_int(flag: Bool) -> Int
  return 1 if flag

  0
end
