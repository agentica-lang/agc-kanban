import Bond from "pkg/bond/bond"

def main() -> Void
  app = (
    Bond.app()
    |> Bond.get("/api/health", &health)
    |> Bond.get("/api/auth-check", &invalid)
  )

  server = Bond.start(app, "127.0.0.1", 0).unwrap!
  puts(Bond.local_port(server).to_s)
  IO.flush()
  Bond.wait(server).unwrap!
end

def health(conn: Bond.Conn) -> Result[Bond.Conn]
  ok(Bond.json(conn, 200, JSON.parse("{\"ok\":true,\"version\":\"0.1.0\"}").unwrap!))
end

def invalid(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "not authenticated"))
