import Bond from "pkg/bond/bond"
import Failure from "failure"
import Regex from "std/regex"
import Database from "../kanban/repo/database"
import Users from "../kanban/users"

## The signing key of the session cookie, derived from the API key: one secret, and a new API key signs everyone out.
def session_secret(key: String) -> String = OpenSSL.HMAC.sha256_hexdigest(key.bytes, SESSION_LABEL.bytes)

## The API key given in the `apikey` header is the right one.
def key_matches?(given: String, key: String) -> Bool = OpenSSL.HMAC.secure_compare(given.bytes, key.bytes)

## The name of the session cookie. Over HTTPS it takes the `__Host-` prefix: a browser then refuses a cookie of that
## name from a sibling subdomain, and one that is not Secure.
def cookie_name(secure: Bool) -> String
  return "__Host-kanban_session" if secure

  "kanban_session"
end

## A new session id: 256 random bits from the CSPRNG, as hex.
def new_session_id() -> String = OpenSSL.Random.hex(SESSION_ID_BYTES)

## The connection carries a signed cookie with the id of a session that is stored and has not ended.
def signed_in?(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Bool = session_key(conn, pool).some?

## The key of that session (the hash of its id, which the store keeps), or none when the connection has none.
def session_key(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Optional[String]
  token = Bond.get_session(conn, SESSION_ID).unwrap_or("")
  return none if token.empty? or not pool.some?

  key = Users.token_hash(token)
  found = Users.session_user(pool.unwrap!, key, Time.now_ms())
  return some(key) if found.ok? and found.unwrap!.some?

  none
end

## The connection with a fresh cookie that holds `session_id` (nothing of an earlier session is kept). The caller
## stores the session before: `Users.open_session` or `Users.register`.
def with_session(conn: Bond.Conn, session_id: String) -> Bond.Conn
  Bond.set_session(Bond.clear_session(conn), SESSION_ID, session_id)
end

## Ends the session of the connection, in the store and in the cookie.
def sign_out(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Bond.Conn
  token = Bond.get_session(conn, SESSION_ID).unwrap_or("")
  if pool.some? and not token.empty?
    _ = Users.close_session(pool.unwrap!, Users.token_hash(token))
  end

  Bond.clear_session(conn)
end

def authorize(conn: Bond.Conn, key: String, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(conn) if public?(conn.path)
  return ok(page_access(conn, pool)) if not conn.path.start_with?("/api/")

  # The session reads the API, edits the color of a label (the handler refuses a rename) and archives and unarchives
  # (the handler refuses force); every other write needs the key. A write needs the agent name, a header that a page
  # of another site cannot send, so these writes cannot be forged across sites.
  read = conn.method == "GET" or conn.method == "HEAD"
  return ok(conn) if read and signed_in?(conn, pool)

  given = Bond.request_header(conn, "apikey").unwrap_or("")
  keyed = key_matches?(given, key)
  session_edit = not keyed and signed_in?(conn, pool) and session_path?(conn)
  return ok(Failure.reject(conn, 401, "UNAUTHORIZED", "unauthorized")) if not keyed and not session_edit

  if not read
    agent = Bond.request_header(conn, "X-Kanban-Agent").unwrap_or("")
    if not Regex.match?(agent, /^[A-Za-z0-9._@\/-]{1,64}$/)
      return ok(Failure.reject(conn, 400, "INVALID", "invalid agent", some("X-Kanban-Agent")))
    end
  end

  return ok(Bond.assign(conn, SESSION_WRITE, true)) if session_edit

  ok(conn)
end

## The request is a write of the web session, not of the key: a handler decides what that may change.
def session_write?(conn: Bond.Conn) -> Bool = Bond.assigned?(conn, SESSION_WRITE)

private

SESSION_ID = "sid"
SESSION_ID_BYTES = 32
SESSION_LABEL = "kanban session v2"
SESSION_WRITE = "session_write"

# Public by name, never by prefix (but the assets folder): a page added later must opt in explicitly. `/cable` checks
# the session itself, in `connect`, as a redirect on the handshake would make the client retry in a loop.
def public?(path: String) -> Bool
  path == "/api/health" or path == "/login" or path == "/register" or path == "/cable" or path.start_with?("/assets/")
end

def session_path?(conn: Bond.Conn) -> Bool
  return Regex.match?(conn.path, /^\/api\/labels\/[0-9]+$/) if conn.method == "PATCH"
  return false if conn.method != "POST"

  (
    Regex.match?(conn.path, /^\/api\/cards\/[0-9]+\/(archive|unarchive)$/) or
    Regex.match?(conn.path, /^\/api\/boards\/[a-z0-9-]+\/archive-done$/)
  )
end

def page_access(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Bond.Conn
  return conn if signed_in?(conn, pool)

  Bond.redirect(conn, "/login")
end
