import Db from "pkg/db/db"
import Boards from "../src/kanban/boards"
import Cards from "../src/kanban/cards"
import Claims from "../src/kanban/claims"
import Deps from "../src/kanban/deps"
import Database from "../src/kanban/repo/database"

struct State
  cards: List[Db.Row]
  deps: List[Db.Row]
end

def test_dependency_writes_validate_and_preserve_data() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-deps-test-#{System.pid()}"
  pool = try Database.open(dir)
  _ = try Boards.create(pool, "Project", "project", "agent", ["Todo", "Doing", "Done"])
  create = Cards.Create(
    board: "project",
    title: "One",
    body: "",
    column: none,
    labels: [],
    priority: 2,
    depends_on: [],
    actor: "agent",
  )

  first = try Cards.create(pool, create)
  second = try Cards.create(pool, create.with(title: "Two"))
  third = try Cards.create(pool, create.with(title: "Three"))
  edge = Deps.Change(card_id: second.id, depends_on: first.id, actor: "agent", lease_minutes: 1)
  _ = try Deps.add(pool, edge)
  _ = try Claims.claim(pool, first.id, "agent", 1)
  before = try state(pool)
  try Test.eq(Deps.add(pool, edge.with(card_id: 0)), error("INVALID:id"))
  try Test.eq(Deps.remove(pool, edge.with(card_id: 0)), error("INVALID:id"))
  try Test.eq(Deps.add(pool, edge.with(depends_on: 0)), error("INVALID:depends_on"))
  try Test.eq(Deps.remove(pool, edge.with(depends_on: 0)), error("INVALID:depends_on"))
  try Test.eq(Deps.add(pool, edge.with(actor: "bad agent")), error("INVALID:agent"))
  try Test.eq(Deps.remove(pool, edge.with(actor: "bad agent")), error("INVALID:agent"))
  try Test.eq(Deps.add(pool, edge.with(lease_minutes: -1)), error("INVALID:lease"))
  try Test.eq(Deps.remove(pool, edge.with(lease_minutes: -1)), error("INVALID:lease"))
  try Test.eq(Deps.add(pool, edge.with(card_id: 999)), error("NOT_FOUND:card"))
  try Test.eq(Deps.remove(pool, edge.with(depends_on: 999)), error("NOT_FOUND:dependency"))
  try Test.eq(Deps.add(pool, edge), error("CONFLICT:dependency"))
  try Test.eq(Deps.add(pool, edge.with(card_id: first.id, depends_on: first.id)), error("CYCLE:dependency"))
  try Test.eq(Deps.add(pool, edge.with(card_id: first.id, depends_on: second.id)), error("CYCLE:dependency"))
  try Test.eq(
    Deps.add(pool, edge.with(card_id: first.id, depends_on: third.id, actor: "other")),
    error("CLAIMED:agent"),
  )

  try Test.eq(Deps.remove(pool, edge.with(depends_on: third.id)), error("NOT_FOUND:dependency"))
  try Test.eq(try state(pool), before)
  held = try Deps.add(pool, edge.with(card_id: first.id, depends_on: third.id))
  try Test.eq(held.claimed_by, some("agent"))
  try Test.eq(held.depends_on, [third.id])
  try Test.eq(held.ready, false)
  _ = try Deps.remove(pool, edge.with(card_id: first.id, depends_on: third.id))
  removed = try Deps.remove(pool, edge)
  try Test.eq(removed.ready, true)
  try Test.eq(removed.depends_on, [])
  _ = try Claims.claim(pool, first.id, "agent", 1)
  try expire(pool, first.id)
  adopted = try Deps.add(pool, edge.with(card_id: first.id, depends_on: third.id, actor: "other"))
  try Test.eq(adopted.claimed_by, none)
  try Test.eq(adopted.claimed_at, none)
  try Test.eq(adopted.ready, false)
  Database.close(pool)
  try Path.remove("#{dir}/kanban.sqlite3")
  Path.remove(dir)
end

def state(pool: Database.Pool) -> Result[State]
  Database.with_connection(pool) do |conn|
    cards = try Db.query(
      conn,
      "select id, version, lease_until, (select count(*) from events) as event_count from cards order by id",
      [],
    )

    deps = try Db.query(conn, "select card_id, depends_on_id from card_deps order by card_id, depends_on_id", [])
    ok(State(cards: cards, deps: deps))
  end
end

def expire(pool: Database.Pool, id: Int) -> Result[Void]
  Database.with_connection(pool) do |conn|
    _ = try Db.execute(conn, "update cards set lease_until = 1 where id = ?", [Db.Value.Int(id)])
    ok()
  end
end
