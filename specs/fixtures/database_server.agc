import Bond from "pkg/bond/bond"
import Database from "../../src/kanban/repo/database"
import App from "../../src/kanban_web/app"

def main() -> Void
  dir = System.env("KANBAN_DATA_DIR").unwrap!
  pool = Database.open(dir).unwrap!
  server = Bond.start(App.build("01234567890123456789012345678901", some(pool)), "127.0.0.1", 0).unwrap!
  puts(Bond.local_port(server).to_s)
  IO.flush()
  _ = IO.gets()
  Bond.stop(server)
  Database.close(pool)
end
