import Db from "pkg/db/db"
import Boards from "../src/kanban/boards"
import Cards from "../src/kanban/cards"
import Claims from "../src/kanban/claims"
import Database from "../src/kanban/repo/database"

def test_create_validates_inputs_without_changes() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-cards-test-#{System.pid()}"
  pool = try Database.open(dir)
  _ = try Boards.create(pool, "Project", "project", "agent", ["Todo", "Done"])
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

  first = try Cards.create(pool, input)
  before = try snapshot(pool)
  try Test.eq(Cards.create(pool, input.with(board: "")), error("INVALID:board"))
  try Test.eq(Cards.create(pool, input.with(board: "missing")), error("NOT_FOUND:board"))
  try Test.eq(Cards.create(pool, input.with(title: "")), error("INVALID:title"))
  try Test.eq(Cards.create(pool, input.with(priority: -1)), error("INVALID:priority"))
  try Test.eq(Cards.create(pool, input.with(priority: 5)), error("INVALID:priority"))
  try Test.eq(Cards.create(pool, input.with(actor: "bad agent")), error("INVALID:agent"))
  try Test.eq(Cards.create(pool, input.with(labels: [""])), error("INVALID:labels"))
  try Test.eq(Cards.create(pool, input.with(depends_on: [0])), error("INVALID:depends_on"))
  try Test.eq(Cards.create(pool, input.with(depends_on: [first.id, first.id])), error("INVALID:depends_on"))
  try Test.eq(Cards.create(pool, input.with(depends_on: [999])), error("NOT_FOUND:depends_on"))
  try Test.eq(Cards.create(pool, input.with(column: some("missing"))), error("NOT_FOUND:column"))
  after = try snapshot(pool)
  try Test.eq(after, before)
  detail = try Cards.show(pool, first.id)
  try Test.eq(detail.card, first)
  blocked = try Cards.create(pool, input.with(title: "Second", labels: ["api"], depends_on: [first.id]))
  try Test.eq(blocked.ready, false)
  try Test.eq(blocked.depends_on, [first.id])
  updated = try Cards.show(pool, first.id)
  try Test.eq(updated.card.blocks, [blocked.id])
  filters = Cards.Filters(column: none, ready: none, claimed_by: none, label: none, done: none)
  all = try Cards.list(pool, "project", filters)
  try Test.eq(all.map do |card| card.id end, [first.id, blocked.id])
  ready = try Cards.list(pool, "project", filters.with(ready: some(true)))
  try Test.eq(ready.map do |card| card.id end, [first.id])
  labeled = try Cards.list(pool, "project", filters.with(label: some("api")))
  try Test.eq(labeled.map do |card| card.id end, [blocked.id])
  Database.close(pool)
  try Path.remove("#{dir}/kanban.sqlite3")
  Path.remove(dir)
end

def snapshot(pool: Database.Pool) -> Result[List[Db.Row]]
  Database.with_connection(pool) do |conn|
    Db.query(conn, "select id, title, (select count(*) from events) as event_count from cards order by id", [])
  end
end

def test_update_guards_and_lease_renewal() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-cards-update-test-#{System.pid()}"
  pool = try Database.open(dir)
  _ = try Boards.create(pool, "Project", "project", "agent", ["Todo", "Done"])
  card = try Cards.create(
    pool,
    Cards.Create(
      board: "project",
      title: "First",
      body: "",
      column: none,
      labels: [],
      priority: 2,
      depends_on: [],
      actor: "agent",
    ),
  )

  update = Cards.Update(
    id: card.id,
    title: none,
    body: none,
    labels: none,
    priority: none,
    branch: none,
    worktree: none,
    actor: "agent-1",
    force: false,
    lease_minutes: 30,
  )

  before = try snapshot(pool)
  try Test.eq(Cards.update(pool, update.with(id: 0)), error("INVALID:id"))
  try Test.eq(Cards.update(pool, update.with(id: 999)), error("NOT_FOUND:card"))
  try Test.eq(Cards.update(pool, update.with(title: some(" "))), error("INVALID:title"))
  try Test.eq(Cards.update(pool, update.with(priority: some(5))), error("INVALID:priority"))
  try Test.eq(Cards.update(pool, update.with(actor: "bad agent")), error("INVALID:agent"))
  try Test.eq(Cards.update(pool, update.with(labels: some([""]))), error("INVALID:labels"))
  try Test.eq(Cards.update(pool, update.with(lease_minutes: -1)), error("INVALID:lease"))
  try Test.eq(try snapshot(pool), before)

  _ = try Claims.claim(pool, card.id, "agent-1", 30)
  try Test.eq(Cards.update(pool, update.with(actor: "agent-2")), error("CLAIMED:agent-1"))
  renewed = try Cards.update(pool, update.with(title: some("Renamed"), labels: some(["api"]), priority: some(0)))
  try Test.eq(renewed.title, "Renamed")
  try Test.eq(renewed.labels, ["api"])
  try Test.eq(renewed.priority, 0)
  try Test.eq(renewed.lease_until.some?, true)
  forced = try Cards.update(pool, update.with(actor: "agent-2", force: true, title: some("Forced")))
  try Test.eq(forced.title, "Forced")
  try expire(pool, card.id)
  free = try Cards.update(pool, update.with(actor: "agent-3", title: some("Free")))
  try Test.eq(free.title, "Free")
  try Test.eq(try event_count(pool), 6)

  Database.close(pool)
  try Path.remove("#{dir}/kanban.sqlite3")
  Path.remove(dir)
end

def expire(pool: Database.Pool, id: Int) -> Result[Void]
  Database.with_connection(pool) do |conn|
    _ = try Db.execute(conn, "update cards set lease_until = 1 where id = ?", [Db.Value.Int(id)])
    ok()
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
