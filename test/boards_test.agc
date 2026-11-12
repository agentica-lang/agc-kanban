import Db from "pkg/db/db"
import Boards from "../src/kanban/boards"
import Database from "../src/kanban/repo/database"

def test_invalid_board_does_not_change_existing_data() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-boards-test-#{System.pid()}"
  pool = try Database.open(dir)
  created = try Boards.create(pool, "Existing", "existing", "agent", ["Todo", "Done"])
  try Test.eq(created.columns.map do |column| column.done end, [false, true])
  before = try Boards.list(pool)
  events_before = try event_count(pool)
  try Test.eq(Boards.create(pool, "Other", "existing", "agent", ["Todo"]), error("CONFLICT:slug"))
  try Test.eq(Boards.create(pool, "", "other", "agent", ["Todo"]), error("INVALID:name"))
  try Test.eq(Boards.create(pool, "Other", "bad slug", "agent", ["Todo"]), error("INVALID:slug"))
  try Test.eq(Boards.create(pool, "Other", "other", "bad agent", ["Todo"]), error("INVALID:agent"))
  try Test.eq(Boards.create(pool, "Other", "other", "agent", []), error("INVALID:columns"))
  try Test.eq(Boards.create(pool, "Other", "other", "agent", [""]), error("INVALID:columns"))
  try Test.eq(Boards.create(pool, "Other", "other", "agent", ["Todo", "Todo"]), error("INVALID:columns"))
  after = Boards.list(pool)
  events_after = try event_count(pool)
  try Test.eq(events_after, events_before)
  Database.close(pool)
  reopened = try Database.open(dir)
  persisted = Boards.list(reopened)
  Database.close(reopened)
  try Test.eq(persisted, ok(before))
  try Path.remove("#{dir}/kanban.sqlite3")
  try Path.remove(dir)
  Test.eq(after, ok(before))
end

def event_count(pool: Database.Pool) -> Result[Int]
  Database.with_connection(pool) do |conn|
    rows = try Db.query(conn, "select count(*) as n from events", [])
    case rows[0].get("n", Db.Value.Null)
      Db.Value.Int(value) -> ok(value)
      _ -> error("invalid event count")
    end
  end
end
