import Bond from "pkg/bond/bond"
import Failure from "failure"
import Regex from "std/regex"

## The signing key of the session cookie, derived from the API key: one secret, and a new API key signs everyone out.
def session_secret(key: String) -> String = OpenSSL.HMAC.sha256_hexdigest(key.bytes, SESSION_LABEL.bytes)

## The API key given on the login form is the right one.
def key_matches?(given: String, key: String) -> Bool = OpenSSL.HMAC.secure_compare(given.bytes, key.bytes)

## The connection carries a signed session that `sign_in` made.
def signed_in?(conn: Bond.Conn) -> Bool = Bond.get_session(conn, SESSION_USER).unwrap_or("") == OWNER

## The connection with a fresh session of the owner (nothing of an earlier session is kept).
def sign_in(conn: Bond.Conn) -> Bond.Conn = Bond.set_session(Bond.clear_session(conn), SESSION_USER, OWNER)

def authorize(conn: Bond.Conn, key: String) -> Result[Bond.Conn]
  return ok(conn) if public?(conn.path)
  return ok(page_access(conn)) if not conn.path.start_with?("/api/")

  # The session reads the API and edits the color of a label (the handler refuses a rename); every other write needs
  # the key. A write needs the agent name,
  # a header that a page of another site cannot send, so a label edit cannot be forged across sites.
  read = conn.method == "GET" or conn.method == "HEAD"
  return ok(conn) if read and signed_in?(conn)

  given = Bond.request_header(conn, "apikey").unwrap_or("")
  keyed = key_matches?(given, key)
  session_edit = not keyed and signed_in?(conn) and label_edit?(conn)
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

SESSION_USER = "user"
OWNER = "owner"
SESSION_LABEL = "kanban session v1"
SESSION_WRITE = "session_write"

# Public by name, never by prefix (but the assets folder): a page added later must opt in explicitly. `/cable` checks
# the session itself, in `connect`, as a redirect on the handshake would make the client retry in a loop.
def public?(path: String) -> Bool
  path == "/api/health" or path == "/login" or path == "/cable" or path.start_with?("/assets/")
end

def label_edit?(conn: Bond.Conn) -> Bool
  conn.method == "PATCH" and Regex.match?(conn.path, /^\/api\/labels\/[0-9]+$/)
end

def page_access(conn: Bond.Conn) -> Bond.Conn
  return conn if signed_in?(conn)

  Bond.redirect(conn, "/login")
end
