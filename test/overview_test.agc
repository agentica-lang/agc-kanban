import Boards from "../src/kanban/boards"
import Cards from "../src/kanban/cards"
import Claims from "../src/kanban/claims"
import Database from "../src/kanban/repo/database"
import Overview from "../src/kanban/overview"

# The home page counts a claim as an active agent only while its lease holds.
def test_overview_counts_active_claims_only() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-overview-test-#{System.pid()}"
  pool = try Database.open(dir)
  _ = try Boards.create(pool, "Project", "project", "agent", ["Todo", "Doing", "Done"])
  input = Cards.Create(
    board: "project",
    title: "First",
    body: "",
    column: none,
    labels: [],
    priority: 2,
    depends_on: [],
    actor: "agent",
  )

  card = try Cards.create(pool, input)
  _ = try Cards.create(pool, input.with(title: "Waits", depends_on: [card.id]))
  _ = try Cards.create(pool, input.with(title: "Finished", column: some("Done")))
  _ = try Claims.claim(pool, card.id, "worker", 5)
  now = Time.now_ms()
  active = try Overview.list(pool, now)
  try Test.eq(active.size, 1)
  try Test.eq(active[0].agents, ["worker"])
  try Test.eq(active[0].blocked, 1)
  try Test.eq(active[0].columns.map(->(column) { column.cards }), [1, 1, 1])
  later = try Overview.list(pool, now + 10 * 60000)
  try Test.eq(later[0].agents, [])
  Database.close(pool)
  try Path.remove("#{dir}/kanban.sqlite3")
  Path.remove(dir)
end
