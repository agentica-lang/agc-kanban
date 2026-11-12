import Db from "pkg/db/db"
import Boards from "../src/kanban/boards"
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
