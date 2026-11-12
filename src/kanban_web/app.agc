import Bond from "pkg/bond/bond"

export def build(key: String) -> Bond.App
  (
    Bond.app()
    |> Bond.get("/api/health", &health)
    |> Bond.get("/api/auth-check") do |conn| auth_check(conn, key) end
  )
end

def health(conn: Bond.Conn) -> Result[Bond.Conn]
  ok(Bond.json(conn, 200, JSON.parse("{\"ok\":true,\"version\":\"0.1.0\"}").unwrap!))
end

def auth_check(conn: Bond.Conn, key: String) -> Result[Bond.Conn]
  given = Bond.request_header(conn, "apikey").unwrap_or("")
  if OpenSSL.HMAC.secure_compare(given.bytes, key.bytes)
    ok(Bond.json(conn, 200, JSON.parse("{\"ok\":true}").unwrap!))
  else
    ok(
      Bond.json(conn, 401, JSON.parse("{\"error\":{\"code\":\"UNAUTHORIZED\",\"message\":\"unauthorized\"}}").unwrap!),
    )
  end
end
