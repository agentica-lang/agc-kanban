import Db from "pkg/db/db"
import DbPool from "pkg/db/db_pool"
import Migrate from "pkg/db/migrate"
import Migrations from "migrations"

type Pool = DbPool.Pool

def open(dir: String, busy_timeout: Int = 0) -> Result[Pool]
  try prepare_dir(dir)
  url = "sqlite:#{dir}/kanban.sqlite3"
  if busy_timeout > 0
    url = "#{url}?busy_timeout=#{busy_timeout}"
  end

  conn = try Db.open(url)
  applied = Migrate.up(conn, Migrations.all())
  Db.close(conn)
  try applied
  DbPool.start(DbPool.Options(url: url, size: 0, checkout_ms: 3000))
end

def close(pool: Pool) -> Void
  DbPool.close(pool, 1000)
end

def with_connection[R](pool: Pool, body: Fn[Db.Connection, Result[R]]) -> Result[R] = DbPool.with(pool, body)

def busy?(message: String) -> Bool
  return true if DbPool.timeout?(message)
  return true if message.include?("pool error: queue full")
  return true if message.include?("pool error: closed")

  message.include?("sqlite error 5:")
end

private

def prepare_dir(dir: String) -> Result[Void]
  found = File.stat(dir)
  if found.ok?
    return ok() if found.unwrap!.kind == "directory"
    return error("data path is not a directory")
  end

  return error(found.message) if found.message != "filesystem: path does not exist"

  Dir.mkdir_private(dir)
end
