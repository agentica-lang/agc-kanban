import Db from "pkg/db/db"
import Boards from "../src/kanban/boards"
import Cards from "../src/kanban/cards"
import Columns from "../src/kanban/columns"
import Database from "../src/kanban/repo/database"

def test_add_validates_inputs_without_changes() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-columns-test-#{System.pid()}"
  pool = try Database.open(dir)
  _ = try Boards.create(pool, "Existing", "existing", "agent", ["Todo", "Done"])
  input = Columns.Add(board: "existing", name: "Review", position: none, done: false, wip_limit: none, actor: "agent")
  before = try state(pool)
  try Test.eq(Columns.add(pool, input.with(board: "")), error("INVALID:board"))
  try Test.eq(Columns.add(pool, input.with(board: "missing")), error("NOT_FOUND:board"))
  try Test.eq(Columns.add(pool, input.with(name: "")), error("INVALID:name"))
  try Test.eq(Columns.add(pool, input.with(name: "Todo")), error("CONFLICT:name"))
  try Test.eq(Columns.add(pool, input.with(position: some(-1))), error("INVALID:position"))
  try Test.eq(Columns.add(pool, input.with(position: some(3))), error("INVALID:position"))
  try Test.eq(Columns.add(pool, input.with(wip_limit: some(0))), error("INVALID:wip_limit"))
  try Test.eq(Columns.add(pool, input.with(actor: "bad agent")), error("INVALID:agent"))
  after = try state(pool)
  try Test.eq(after, before)
  column = try Columns.add(pool, input.with(position: some(1), done: true))
  try Test.eq(column.position, 1)
  try Test.eq(column.done, true)
  rows = try columns(pool)
  try Test.eq(
    rows.map do |row| row.get("position", Db.Value.Null) end,
    [Db.Value.Int(0), Db.Value.Int(1), Db.Value.Int(2)],
  )

  try Test.eq(
    rows.map do |row| row.get("done", Db.Value.Null) end,
    [Db.Value.Int(0), Db.Value.Int(1), Db.Value.Int(0)],
  )

  Database.close(pool)
  try Path.remove("#{dir}/kanban.sqlite3")
  Path.remove(dir)
end

def columns(pool: Database.Pool) -> Result[List[Db.Row]]
  Database.with_connection(pool) do |conn|
    Db.query(conn, "select id, name, position, done, wip_limit from columns order by position", [])
  end
end

def state(pool: Database.Pool) -> Result[List[Db.Row]]
  Database.with_connection(pool) do |conn|
    Db.query(
      conn,
      "select id, name, position, done, wip_limit, (select count(*) from events) as event_count from columns order by position",
      [],
    )
  end
end

def test_update_and_remove_preserve_invariants() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-columns-update-test-#{System.pid()}"
  pool = try Database.open(dir)
  _ = try Boards.create(pool, "Project", "project", "agent", ["Todo", "Doing", "Review", "Done"])
  ids = try column_ids(pool)
  update = Columns.Update(id: ids[0], name: none, position: none, done: none, wip_limit: none, actor: "agent")
  before = try state(pool)
  try Test.eq(Columns.update(pool, update.with(id: 0)), error("INVALID:id"))
  try Test.eq(Columns.update(pool, update.with(id: 999)), error("NOT_FOUND:column"))
  try Test.eq(Columns.update(pool, update.with(name: some(" "))), error("INVALID:name"))
  try Test.eq(Columns.update(pool, update.with(name: some("Doing"))), error("CONFLICT:name"))
  try Test.eq(Columns.update(pool, update.with(position: some(4))), error("INVALID:position"))
  try Test.eq(Columns.update(pool, update.with(wip_limit: some(0))), error("INVALID:wip_limit"))
  try Test.eq(Columns.update(pool, update.with(actor: "bad agent")), error("INVALID:agent"))
  try Test.eq(Columns.update(pool, update.with(id: ids[3], done: some(false))), error("CONFLICT:done_column"))
  try Test.eq(Columns.remove(pool, Columns.Remove(id: ids[3], actor: "agent")), error("CONFLICT:done_column"))
  try Test.eq(Columns.remove(pool, Columns.Remove(id: 999, actor: "agent")), error("NOT_FOUND:column"))
  after = try state(pool)
  try Test.eq(after, before)

  renamed = try Columns.update(pool, update.with(name: some("Backlog"), position: some(2), wip_limit: some(3)))
  try Test.eq(renamed.name, "Backlog")
  try Test.eq(renamed.position, 2)
  try Test.eq(renamed.wip_limit, some(3))
  try Test.eq(try names(pool), ["Doing", "Review", "Backlog", "Done"])
  moved = try Columns.update(pool, update.with(id: ids[3], position: some(0)))
  try Test.eq(moved.position, 0)
  try Test.eq(try names(pool), ["Done", "Doing", "Review", "Backlog"])
  card = try Cards.create(
    pool,
    Cards.Create(
      board: "project",
      title: "First",
      body: "",
      column: some("Done"),
      labels: [],
      priority: 2,
      depends_on: [],
      actor: "agent",
    ),
  )

  marked = try Columns.update(pool, update.with(id: ids[2], done: some(true)))
  try Test.eq(marked.done, true)
  rows = try columns(pool)
  try Test.eq(
    rows.map do |row| row.get("done", Db.Value.Null) end,
    [Db.Value.Int(0), Db.Value.Int(0), Db.Value.Int(1), Db.Value.Int(0)],
  )

  reopened = try Cards.show(pool, card.id)
  try Test.eq(reopened.card.done, false)
  try Test.eq(reopened.card.done_at, none)
  try Test.eq((try kinds(pool)).include?("card.updated"), true)
  try Test.eq(Columns.remove(pool, Columns.Remove(id: ids[2], actor: "agent")), error("CONFLICT:done_column"))
  try Test.eq(Columns.remove(pool, Columns.Remove(id: ids[3], actor: "agent")), error("CONFLICT:column_not_empty"))
  try Columns.remove(pool, Columns.Remove(id: ids[1], actor: "agent"))
  remaining = try columns(pool)
  try Test.eq(remaining.size, 3)
  try Test.eq(try event_count(pool), 7)

  Database.close(pool)
  try Path.remove("#{dir}/kanban.sqlite3")
  Path.remove(dir)
end

def names(pool: Database.Pool) -> Result[List[String]]
  Database.with_connection(pool) do |conn|
    rows = try Db.query(conn, "select name from columns order by position", [])
    ok(
      rows.map do |row|
        case row.get("name", Db.Value.Null)
          Db.Value.Text(value) -> value
          _ -> ""
        end
      end,
    )
  end
end

def column_ids(pool: Database.Pool) -> Result[List[Int]]
  Database.with_connection(pool) do |conn|
    rows = try Db.query(conn, "select id from columns order by position", [])
    ok(rows.map do |row| number(row, "id") end)
  end
end

def event_count(pool: Database.Pool) -> Result[Int]
  Database.with_connection(pool) do |conn|
    rows = try Db.query(conn, "select count(*) as n from events", [])
    ok(number(rows[0], "n"))
  end
end

def number(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end

def kinds(pool: Database.Pool) -> Result[List[String]]
  Database.with_connection(pool) do |conn|
    rows = try Db.query(conn, "select kind from events order by id", [])
    ok(
      rows.map do |row|
        case row.get("kind", Db.Value.Null)
          Db.Value.Text(value) -> value
          _ -> ""
        end
      end,
    )
  end
end
