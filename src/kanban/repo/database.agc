import Db from "pkg/db/db"
import DbPool from "pkg/db/db_pool"
import Migrate from "pkg/db/migrate"
import Migrations from "migrations"

export type Pool = DbPool.Pool

export def open(dir: String) -> Result[Pool]
  try prepare_dir(dir)
  url = "sqlite:#{dir}/kanban.sqlite3"
  conn = try Db.open(url)
  applied = Migrate.up(conn, Migrations.all())
  Db.close(conn)
  try applied
  DbPool.start(DbPool.Options(url: url, size: 0, checkout_ms: 3000))
end

export def close(pool: Pool) -> Void
  DbPool.close(pool, 1000)
end

export def with_connection[R](pool: Pool, body: Fn[Db.Connection, Result[R]]) -> Result[R] = DbPool.with(pool, body)

export def busy?(message: String) -> Bool
  DbPool.timeout?(message) or message.include?("pool error: queue full") or message.include?("sqlite error 5:")
end

def prepare_dir(dir: String) -> Result[Void]
  found = File.stat(dir)
  if found.ok?
    return ok() if found.unwrap!.kind == "directory"
    return error("data path is not a directory")
  end

  return error(found.message) if found.message != "filesystem: path does not exist"

  Dir.mkdir_private(dir)
end
