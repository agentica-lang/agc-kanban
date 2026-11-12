import Bond from "pkg/bond/bond"

export def health(conn: Bond.Conn) -> Result[Bond.Conn]
  ok(Bond.json(conn, 200, JSON.parse("{\"ok\":true,\"version\":\"0.1.0\"}").unwrap!))
end

export def auth_check(conn: Bond.Conn) -> Result[Bond.Conn]
  ok(Bond.json(conn, 200, JSON.parse("{\"ok\":true}").unwrap!))
end
