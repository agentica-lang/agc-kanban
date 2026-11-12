import Bond from "pkg/bond/bond"

def main() -> Void
  app = Bond.get(Bond.app(), "/api/health", &health)
  server = Bond.start(app, "127.0.0.1", 0).unwrap!
  puts(Bond.local_port(server).to_s)
  IO.flush()
  Bond.wait(server).unwrap!
end

def health(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "not kanban"))
