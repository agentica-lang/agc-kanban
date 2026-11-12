import Bond from "pkg/bond/bond"
import Failure from "failure"
import Regex from "std/regex"

export def authorize(conn: Bond.Conn, key: String) -> Result[Bond.Conn]
  # Public by name, never by prefix: a page added later must opt in explicitly.
  return ok(conn) if conn.path == "/api/health"

  given = Bond.request_header(conn, "apikey").unwrap_or("")
  if not OpenSSL.HMAC.secure_compare(given.bytes, key.bytes)
    return ok(Failure.reject(conn, 401, "UNAUTHORIZED", "unauthorized"))
  end

  if conn.method != "GET" and conn.method != "HEAD"
    agent = Bond.request_header(conn, "X-Kanban-Agent").unwrap_or("")
    if not Regex.match?(agent, /^[A-Za-z0-9._@\/-]{1,64}$/)
      return ok(Failure.reject(conn, 400, "INVALID", "invalid agent", some("X-Kanban-Agent")))
    end
  end

  ok(conn)
end
