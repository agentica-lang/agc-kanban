import Db from "pkg/db/db"
import Boards from "../src/kanban/boards"
import Cards from "../src/kanban/cards"
import Claims from "../src/kanban/claims"
import Comments from "../src/kanban/comments"
import Database from "../src/kanban/repo/database"

def test_only_the_holder_renews_the_lease() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-comments-test-#{System.pid()}"
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

  add = Comments.Add(card_id: card.id, body: "Please add tests", actor: "agent-2", lease_minutes: 30)
  before = try snapshot(pool)
  try Test.eq(Comments.add(pool, add.with(card_id: 0)), error("INVALID:id"))
  try Test.eq(Comments.add(pool, add.with(card_id: 999)), error("NOT_FOUND:card"))
  try Test.eq(Comments.add(pool, add.with(body: " ")), error("INVALID:body"))
  try Test.eq(Comments.add(pool, add.with(actor: "bad agent")), error("INVALID:agent"))
  try Test.eq(Comments.add(pool, add.with(lease_minutes: -1)), error("INVALID:lease"))
  try Test.eq(try snapshot(pool), before)

  _ = try Claims.claim(pool, card.id, "agent-1", 30)
  now = Time.now_ms()
  try set_lease(pool, card.id, now + 60000)
  _ = try Comments.add(pool, add)
  try Test.eq(try lease(pool, card.id), now + 60000)
  _ = try Comments.add(pool, add.with(actor: "agent-1"))
  try Test.eq(try lease(pool, card.id) > now + 60000, true)
  detail = try Cards.show(pool, card.id)
  try Test.eq(detail.comments.size, 2)
  try Test.eq(detail.comments[0].author, "agent-2")
  try Test.eq(detail.comments[1].author, "agent-1")
  try Test.eq(detail.card.claimed_by, some("agent-1"))
  try Test.eq(try event_count(pool), 5)

  Database.close(pool)
  try Path.remove("#{dir}/kanban.sqlite3")
  Path.remove(dir)
end

def lease(pool: Database.Pool, id: Int) -> Result[Int]
  Database.with_connection(pool) do |conn|
    rows = try Db.query(conn, "select lease_until from cards where id = ?", [Db.Value.Int(id)])
    ok(number(rows[0], "lease_until"))
  end
end

def set_lease(pool: Database.Pool, id: Int, until: Int) -> Result[Void]
  Database.with_connection(pool) do |conn|
    _ = try Db.execute(conn, "update cards set lease_until = ? where id = ?", [Db.Value.Int(until), Db.Value.Int(id)])
    ok()
  end
end

def event_count(pool: Database.Pool) -> Result[Int]
  Database.with_connection(pool) do |conn|
    rows = try Db.query(conn, "select count(*) as n from events", [])
    ok(number(rows[0], "n"))
  end
end

def snapshot(pool: Database.Pool) -> Result[List[Db.Row]]
  Database.with_connection(pool) do |conn|
    Db.query(
      conn,
      "select (select count(*) from comments) as comments, (select count(*) from events) as events, (select count(*) from cards) as cards",
      [],
    )
  end
end

def number(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end
