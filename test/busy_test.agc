import Db from "pkg/db/db"
import DbPool from "pkg/db/db_pool"
import Sqlite from "pkg/db/sqlite"
import Database from "../src/kanban/repo/database"

def test_busy_messages_are_recognized() -> Result[Void]
  try Test.eq(Database.busy?("sqlite error 5: database is locked"), true)
  try Test.eq(Database.busy?("pool error: checkout timed out after 50 ms"), true)
  try Test.eq(Database.busy?("pool error: lease timed out after 50 ms"), true)
  try Test.eq(Database.busy?("pool error: queue full"), true)
  try Test.eq(Database.busy?("NOT_FOUND:card"), false)
  try Test.eq(Database.busy?("INVALID:title"), false)
  ok()
end

def test_lock_and_pool_timeouts_are_busy() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-busy-test-#{System.pid()}"
  pool = try Database.open(dir)
  try Test.eq(Database.busy?(try lock_message(dir)), true)
  try Test.eq(Database.busy?(try pool_message(dir)), true)
  Database.close(pool)
  try Path.remove("#{dir}/kanban.sqlite3")
  Path.remove(dir)
end

def lock_message(dir: String) -> Result[String]
  url = "sqlite:#{dir}/kanban.sqlite3?busy_timeout=50"
  holder = try Db.open(url, [Sqlite.driver()])
  _ = try Db.execute(holder, "begin immediate", [])
  other = try Db.open(url, [Sqlite.driver()])
  failed = Db.execute(other, "insert into boards (slug, name, created_at, updated_at) values ('x', 'X', 1, 1)", [])

  Db.close(other)
  _ = try Db.execute(holder, "rollback", [])
  Db.close(holder)
  return ok("unexpected lock success") if failed.ok?

  ok(failed.message)
end

def pool_message(dir: String) -> Result[String]
  url = "sqlite:#{dir}/kanban.sqlite3"
  small = try DbPool.start(DbPool.Options(url: url, drivers: [Sqlite.driver()], size: 1, checkout_ms: 50))
  inside = DbPool.with(small) do |_conn| DbPool.with(small) do |_second| ok("second connection") end end

  DbPool.close(small, 1000)
  return ok("no timeout") if inside.ok?

  ok(inside.message)
end
