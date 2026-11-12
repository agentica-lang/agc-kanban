import Db from "pkg/db/db"
import Boards from "../src/kanban/boards"
import Cards from "../src/kanban/cards"
import Claims from "../src/kanban/claims"
import Database from "../src/kanban/repo/database"
import Transitions from "../src/kanban/transitions"

def test_claim_guards_and_leases() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-claims-test-#{System.pid()}"
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
  blocked = try Cards.create(pool, input.with(title: "Blocked", depends_on: [card.id]))
  done = try Cards.create(pool, input.with(title: "Done", column: some("Done")))
  before = try state(pool)
  try Test.eq(Claims.claim(pool, 0, "agent", 0), error("INVALID:id"))
  try Test.eq(Claims.claim(pool, 999, "agent", 0), error("NOT_FOUND:card"))
  try Test.eq(Claims.claim(pool, card.id, "bad agent", 0), error("INVALID:agent"))
  try Test.eq(Claims.claim(pool, card.id, "agent", -1), error("INVALID:lease"))
  try Test.eq(Claims.claim(pool, blocked.id, "agent", 0), error("BLOCKED:#{card.id}"))
  try Test.eq(Claims.claim(pool, done.id, "agent", 0), error("DONE:card"))
  try Test.eq(try state(pool), before)
  claimed = try Claims.claim(pool, card.id, "agent", 1)
  try Test.eq(claimed.claimed_by, some("agent"))
  try Test.assert(claimed.lease_until.some?, "lease is missing")
  held = try state(pool)
  try Test.eq(Claims.claim(pool, card.id, "other", 1), error("CLAIMED:agent"))
  try Test.eq(try state(pool), held)
  renewed = try Claims.claim(pool, card.id, "agent", 1)
  try Test.assert(renewed.lease_until.unwrap! >= claimed.lease_until.unwrap!, "lease was not renewed")
  try expire(pool, card.id)
  taken = try Claims.claim(pool, card.id, "other", 0)
  try Test.eq(taken.claimed_by, some("other"))
  try Test.eq(taken.lease_until, none)
  next = Claims.Next(board: "project", column: none, label: none, actor: "next-agent", lease_minutes: 0)
  unchanged = try state(pool)
  try Test.eq(Claims.claim_next(pool, next.with(board: "")), error("INVALID:board"))
  try Test.eq(Claims.claim_next(pool, next.with(board: "missing")), error("NOT_FOUND:board"))
  try Test.eq(Claims.claim_next(pool, next.with(actor: "bad agent")), error("INVALID:agent"))
  try Test.eq(Claims.claim_next(pool, next.with(lease_minutes: -1)), error("INVALID:lease"))
  try Test.eq(Claims.claim_next(pool, next), error("NO_READY_CARD:board"))
  try Test.eq(try state(pool), unchanged)
  low = try Cards.create(pool, input.with(title: "Low", priority: 4, labels: ["api"]))
  high = try Cards.create(pool, input.with(title: "High", priority: 0, labels: ["api"]))
  selected = try Claims.claim_next(pool, next.with(label: some("api")))
  try Test.eq(selected.id, high.id)
  selected_low = try Claims.claim_next(pool, next.with(label: some("api"), actor: "another"))
  try Test.eq(selected_low.id, low.id)
  Database.close(pool)
  try Path.remove("#{dir}/kanban.sqlite3")
  Path.remove(dir)
end

def state(pool: Database.Pool) -> Result[List[Db.Row]]
  Database.with_connection(pool) do |conn|
    Db.query(
      conn,
      "select id, claimed_by, version, (select count(*) from events) as event_count from cards order by id",
      [],
    )
  end
end

def expire(pool: Database.Pool, id: Int) -> Result[Void]
  Database.with_connection(pool) do |conn|
    _ = try Db.execute(conn, "update cards set lease_until = 1 where id = ?", [Db.Value.Int(id)])
    ok()
  end
end

def test_finish_validates_and_preserves_cards_on_error() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-finish-test-#{System.pid()}"
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
  _ = try Claims.claim(pool, card.id, "agent", 0)
  action = Transitions.Action(id: card.id, actor: "agent", force: false)
  before = try state(pool)
  try Test.eq(Transitions.finish(pool, action.with(id: 0)), error("INVALID:id"))
  try Test.eq(Transitions.finish(pool, action.with(id: 999)), error("NOT_FOUND:card"))
  try Test.eq(Transitions.finish(pool, action.with(actor: "bad agent")), error("INVALID:agent"))
  try Test.eq(Transitions.finish(pool, action.with(actor: "other")), error("NOT_CLAIMER:card"))
  try Test.eq(try state(pool), before)
  done = try Transitions.finish(pool, action)
  try Test.eq(done.done, true)
  try Test.eq(done.claimed_by, none)
  try Test.assert(done.done_at.some?, "done time missing")
  Database.close(pool)
  try Path.remove("#{dir}/kanban.sqlite3")
  Path.remove(dir)
end
