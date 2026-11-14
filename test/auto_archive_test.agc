import Db from "pkg/db/db"
import AutoArchive from "../src/kanban/auto_archive"
import Boards from "../src/kanban/boards"
import Cards from "../src/kanban/cards"
import Database from "../src/kanban/repo/database"

DAY = 86400000

# The sweep archives the old done cards of the boards that turned it on, under its own name, and leaves the others.
def test_sweep_archives_only_boards_with_the_setting() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-auto-archive-test-#{System.pid()}"
  pool = try Database.open(dir)
  _ = try Boards.create(pool, "On", "on", "agent", ["Todo", "Done"])
  _ = try Boards.create(pool, "Off", "off", "agent", ["Todo", "Done"])
  input = Cards.Create(
    board: "on",
    title: "Old",
    body: "",
    column: some("Done"),
    labels: [],
    priority: 2,
    depends_on: [],
    actor: "agent",
  )

  on = try Cards.create(pool, input)
  off = try Cards.create(pool, input.with(board: "off"))
  done_at = on.done_at.unwrap!
  try Test.eq(
    AutoArchive.set(pool, AutoArchive.Setting(board: "on", days: some(0), actor: "agent")),
    error("INVALID:days"),
  )

  setting = AutoArchive.Setting(board: "on", days: some(2), actor: "agent")
  board = try AutoArchive.set(pool, setting)
  try Test.eq(board.auto_archive_days, some(2))
  try Test.eq(try AutoArchive.sweep(pool, done_at + 2 * DAY - 1), 0)
  try Test.eq(try AutoArchive.sweep(pool, done_at + 5 * DAY), 1)
  try Test.eq((try Cards.show(pool, on.id)).card.archived_at.some?, true)
  try Test.eq((try Cards.show(pool, off.id)).card.archived_at, none)
  try Test.eq(try AutoArchive.sweep(pool, done_at + 6 * DAY), 0)
  _ = try AutoArchive.set(pool, setting.with(days: none))
  actors = try actors_of(pool)
  Database.close(pool)
  try Path.remove("#{dir}/kanban.sqlite3")
  try Path.remove(dir)
  Test.eq(actors, ["auto-archive", "auto-archive"])
end

def actors_of(pool: Database.Pool) -> Result[List[String]]
  Database.with_connection(pool) do |conn|
    rows = try Db.query(conn, "select actor from events where actor = 'auto-archive' order by id", [])
    ok(
      rows.map do |row|
        case row.get("actor", Db.Value.Null)
          Db.Value.Text(value) -> value
          _ -> ""
        end
      end,
    )
  end
end
