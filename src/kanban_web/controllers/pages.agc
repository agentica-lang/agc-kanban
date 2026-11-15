import Bond from "pkg/bond/bond"
import Regex from "std/regex"
import Auth from "../auth"
import Limiter from "../limiter"
import Passwords from "../../kanban/passwords"
import Users from "../../kanban/users"
import Boards from "../../kanban/boards"
import Database from "../../kanban/repo/database"
import Overview from "../../kanban/overview"
import Views from "../views"

def root(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.redirect(conn, "/boards"))

## The sign-in page; while no user exists it is the form that creates the first one.
def login_form(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Bond.redirect(conn, "/boards")) if Auth.signed_in?(conn, pool)

  ok(entry(conn, pool, 200, [], ""))
end

## Signs in with a username and a password. An unknown user and a wrong password get the same answer, and the same
## work, so the answer does not tell which usernames exist. Too many tries of one username or one address get 429.
def login(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(unavailable(conn)) if not pool.some?

  name = Users.normalize(Bond.form(conn, "username").unwrap_or(""))
  password = Bond.form(conn, "password").unwrap_or("")
  now = Time.now_ms()
  if (
    not Limiter.attempt("user:#{name}", USER_ATTEMPTS, now) or
    not Limiter.attempt(address_key(conn), ADDRESS_ATTEMPTS, now)
  )
    return ok(too_many(conn, now))
  end

  found = Users.find(pool.unwrap!, name)
  return ok(unavailable(conn)) if not found.ok?

  if not password_matches?(found.unwrap!, password)
    return ok(entry(conn, pool, 401, ["Invalid username or password."], name))
  end

  session_id = Auth.new_session_id()
  opened = Users.open_session(pool.unwrap!, found.unwrap!.unwrap!.id, Users.token_hash(session_id), now)
  return ok(unavailable(conn)) if not opened.ok?

  Limiter.forgive("user:#{name}", now)
  ok(Bond.redirect(Auth.with_session(conn, session_id), "/boards", 303))
end

## Creates the first user and signs it in. Once a user exists it answers 403 and the page is the sign-in form.
def register(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(unavailable(conn)) if not pool.some?

  now = Time.now_ms()
  return ok(too_many(conn, now)) if not Limiter.attempt(address_key(conn), ADDRESS_ATTEMPTS, now)

  taken = Users.any?(pool.unwrap!)
  return ok(unavailable(conn)) if not taken.ok?
  return ok(closed(conn, pool)) if taken.unwrap!

  name = Users.normalize(Bond.form(conn, "username").unwrap_or(""))
  password = Bond.form(conn, "password").unwrap_or("")
  confirm = Bond.form(conn, "confirm").unwrap_or("")
  notes = register_notes(name, password, confirm)
  return ok(Bond.html(conn, 400, Views.register(notes, name))) if not notes.empty?

  hashed = Passwords.hash(password)
  return ok(unavailable(conn)) if not hashed.ok?

  session_id = Auth.new_session_id()
  created = Users.register(pool.unwrap!, name, hashed.unwrap!, Users.token_hash(session_id), now)
  case created
    ok(_) -> ok(Bond.redirect(Auth.with_session(conn, session_id), "/boards", 303))
    error(e) if e.is_a?("users.closed") -> ok(closed(conn, pool))
    error(_) -> ok(unavailable(conn))
  end
end

## Ends the session: its row is deleted, so the cookie is no good even if someone kept a copy. Without a session, the
## filter already sent the client to the login.
def logout(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  ok(Bond.redirect(Auth.sign_out(conn, pool), "/login", 303))
end

## The home page: every board with its counts. The page is drawn here, in one read of the store.
def boards(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Bond.html(conn, 503, Views.boards_unavailable())) if not pool.some?

  now = Time.now_ms()
  items = Overview.list(pool.unwrap!, now)
  if not items.ok?
    IO.warn("kanban: home page read failed: #{items.message}")
    return ok(Bond.html(conn, 503, Views.boards_unavailable()))
  end

  # The page is a snapshot: a stored copy would show boards that have since changed.
  ok(Bond.header(Bond.html(conn, 200, Views.boards(items.unwrap!, now)), "Cache-Control", "no-store"))
end

## The page of a board. A board opened by its number goes to its slug URL, because the live events are broadcast to
## `board:SLUG` and the script subscribes with what the URL says.
def board(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  reference = Bond.param(conn, "slug").unwrap_or("")
  if pool.some? and Regex.match?(reference, /^[0-9]+$/)
    found = Database.with_connection(pool.unwrap!) do |db| Boards.get_open(db, reference) end
    if found.ok? and found.unwrap!.slug != reference
      suffix = ""
      if not conn.query.empty?
        suffix = "?#{conn.query}"
      end

      return ok(Bond.redirect(conn, "/boards/#{found.unwrap!.slug}#{suffix}"))
    end
  end

  ok(Bond.html(conn, 200, Views.board(reference)))
end

private

USER_ATTEMPTS = 5
ADDRESS_ATTEMPTS = 30
LONGEST_PASSWORD = 1024

def address_key(conn: Bond.Conn) -> String = "address:#{conn.remote_addr}"

# The register form while no user exists, the sign-in form after.
def entry(conn: Bond.Conn, pool: Optional[Database.Pool], status: Int, notes: List[String], name: String) -> Bond.Conn
  open = pool.some? and not Users.any?(pool.unwrap!).unwrap_or(true)
  return Bond.html(conn, status, Views.register(notes, name)) if open

  Bond.html(conn, status, Views.login(notes, name))
end

def closed(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Bond.Conn
  entry(conn, pool, 403, ["Registration is closed: a user exists already. Sign in instead."], "")
end

def unavailable(conn: Bond.Conn) -> Bond.Conn
  Bond.html(conn, 503, Views.login(["The login is not available now. Try again in a moment."], ""))
end

def too_many(conn: Bond.Conn, now: Int) -> Bond.Conn
  page = Bond.html(conn, 429, Views.login(["Too many tries. Wait a few minutes and try again."], ""))
  Bond.header(page, "Retry-After", Limiter.retry_after(now).to_s)
end

def password_matches?(found: Optional[Users.Account], password: String) -> Bool
  return false if password.length > LONGEST_PASSWORD

  case found
    some(account) -> Passwords.verify(password, account.password_hash)
    none -> Passwords.verify_nobody(password)
  end
end

def register_notes(name: String, password: String, confirm: String) -> List[String]
  notes: List[String] = []
  case Users.username_problem(name)
    some(problem) -> notes = notes.push("The username #{problem}.")
    none -> notes = notes
  end

  for problem in Passwords.problems(password)
    notes = notes.push("The password #{problem}.")
  end

  if password != confirm
    notes = notes.push("The two passwords do not match.")
  end

  notes
end
