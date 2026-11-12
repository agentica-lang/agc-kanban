import Bond from "pkg/bond/bond"

def main() -> Void
  counts: ATS[String, Int] = ATS.new()
  always = System.env("BUSY_ALWAYS").unwrap_or("0") == "1"
  app = (
    Bond.app()
    |> Bond.get("/api/health") do |conn| health(conn, counts, always) end
    |> Bond.get("/api/auth-check", &auth)
  )

  server = Bond.start(app, "127.0.0.1", 0).unwrap!
  puts(Bond.local_port(server).to_s)
  IO.flush()
  Bond.wait(server).unwrap!
end

def health(conn: Bond.Conn, counts: ATS[String, Int], always: Bool) -> Result[Bond.Conn]
  count = counts.add("health", 1)
  if always or count <= 3
    ok(Bond.json(conn, 503, JSON.parse("{\"error\":{\"code\":\"BUSY\",\"message\":\"busy\"}}").unwrap!))
  else
    ok(Bond.json(conn, 200, JSON.parse("{\"ok\":true,\"version\":\"0.1.0\"}").unwrap!))
  end
end

def auth(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.json(conn, 200, JSON.parse("{\"ok\":true}").unwrap!))
