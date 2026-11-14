import Db from "pkg/db/db"
import Boards from "../src/kanban/boards"
import Cards from "../src/kanban/cards"
import Database from "../src/kanban/repo/database"
import Transitions from "../src/kanban/transitions"

DAY = 86400000

# The clock is an input: a card done at `done` is old enough from `done + days * DAY` on, and a bad request
# writes nothing.
def test_archive_done_follows_the_clock_given() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-archives-test-#{System.pid()}"
  pool = try Database.open(dir)
  _ = try Boards.create(pool, "Project", "project", "agent", ["Todo", "Done"])
  input = Cards.Create(
    board: "project",
    title: "Old",
    body: "",
    column: some("Done"),
    labels: [],
    priority: 2,
    depends_on: [],
    actor: "agent",
  )

  old = try Cards.create(pool, input)
  open = try Cards.create(pool, input.with(title: "Open", column: none))
  done_at = old.done_at.unwrap!
  sweep = Transitions.ArchiveDone(board: "project", days: 3, actor: "agent", now: done_at + 3 * DAY - 1)
  try Test.eq(Transitions.archive_done(pool, sweep.with(days: -1)), error("INVALID:days"))
  try Test.eq(Transitions.archive_done(pool, sweep.with(board: "missing")), error("NOT_FOUND:board"))
  try Test.eq(try events(pool), 0)
  early = try Transitions.archive_done(pool, sweep)
  try Test.eq(early.archived, 0)
  try Test.eq(try events(pool), 0)
  on_time = try Transitions.archive_done(pool, sweep.with(now: done_at + 3 * DAY))
  try Test.eq(on_time.cards, [old.id])
  try Test.eq(try events(pool), 2)
  again = try Transitions.archive_done(pool, sweep.with(now: done_at + 30 * DAY))
  try Test.eq(again.archived, 0)
  try Test.eq((try Cards.show(pool, open.id)).card.archived_at, none)
  Database.close(pool)
  try Path.remove("#{dir}/kanban.sqlite3")
  Path.remove(dir)
end

def events(pool: Database.Pool) -> Result[Int]
  Database.with_connection(pool) do |conn|
    rows = try Db.query(conn, "select count(*) as n from events where kind like '%archived'", [])
    case rows[0].get("n", Db.Value.Null)
      Db.Value.Int(value) -> ok(value)
      _ -> ok(-1)
    end
  end
end
