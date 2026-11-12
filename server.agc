import Bond from "pkg/bond/bond"
import App from "src/kanban_web/app"
import Database from "src/kanban/repo/database"

def main() -> Void
  key = System.env("KANBAN_API_KEY").unwrap_or("")
  if key.length < 32
    IO.warn("KANBAN_API_KEY must be at least 32 characters")
    System.exit(1)
  end

  host = System.env("KANBAN_HOST").unwrap_or("127.0.0.1")
  port = System.env("KANBAN_PORT").unwrap_or("4580").to_i()
  if not port.ok?
    IO.warn("invalid KANBAN_PORT")
    System.exit(1)
  end

  lease = System.env("KANBAN_LEASE_MINUTES").unwrap_or("0").to_i()
  if not lease.ok? or lease.unwrap! < 0 or lease.unwrap! > 1000000000
    IO.warn("invalid KANBAN_LEASE_MINUTES")
    System.exit(1)
  end

  data_dir = System.env("KANBAN_DATA_DIR").unwrap_or("./data")
  pool = Database.open(data_dir, 1000)
  if not pool.ok?
    IO.warn("kanban: #{pool.message}")
    System.exit(1)
  end

  assets = System.env("KANBAN_ASSETS_DIR").unwrap_or("public/assets")
  # Behind HTTPS the browser keeps a Secure cookie only over HTTPS, so it stays off by default (plain HTTP).
  secure_cookie = System.env("KANBAN_COOKIE_SECURE").unwrap_or("0") == "1"
  result = Bond.run(App.build(key, some(pool.unwrap!), lease.unwrap!, assets, secure_cookie), host, port.unwrap!)
  Database.close(pool.unwrap!)
  if not result.ok?
    IO.warn(result.message)
    System.exit(1)
  end
end
