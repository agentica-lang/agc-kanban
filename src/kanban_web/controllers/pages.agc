import Bond from "pkg/bond/bond"
import Regex from "std/regex"
import Auth from "../auth"
import Cable from "../cable"
import Limiter from "../limiter"
import Passwords from "../../kanban/passwords"
import Users from "../../kanban/users"
import Boards from "../../kanban/boards"
import Database from "../../kanban/repo/database"
import Milestones from "../../kanban/milestones"
import Overview from "../../kanban/overview"
import Params from "../params"
import Views from "../views"

def root(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.redirect(conn, "/boards"))

## The sign-in page; while no user exists it is the form that creates the first one.
def login_form(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Bond.redirect(conn, "/boards")) if Auth.signed_in?(conn, pool)

  ok(entry(conn, pool, 200, [], ""))
end

## Signs in with a username and a password. An unknown user and a wrong password get the same answer, and the same
## work, so the answer does not tell which usernames exist. Too many tries from one address, of one username from one
## address, or of one username get 429; so does a login while the server hashes as many as it allows.
def login(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(unavailable(conn)) if not pool.some?

  name = Users.normalize(Bond.form(conn, "username").unwrap_or(""))
  password = Bond.form(conn, "password").unwrap_or("")
  # No user can have such a name: the answer is the usual one, before the limiter keeps anything about it.
  return ok(refused(conn, pool, "")) if Users.username_problem(name).some?

  now = Time.now_ms()
  return ok(too_many(conn, now)) if not Limiter.login_allowed?(name, conn.remote_addr, now)
  return ok(busy(conn)) if not Limiter.start_hash()

  checked = authenticate(pool.unwrap!, name, password)
  Limiter.end_hash()
  case checked
    ok(account) -> ok(answer_login(conn, pool.unwrap!, name, account, now))
    error(_) -> ok(unavailable(conn))
  end
end

## Creates the first user and signs it in. Once a user exists it answers 403 and the page is the sign-in form.
def register(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(unavailable(conn)) if not pool.some?

  now = Time.now_ms()
  return ok(too_many(conn, now)) if not Limiter.register_allowed?(conn.remote_addr, now)

  taken = Users.any?(pool.unwrap!)
  return ok(unavailable(conn)) if not taken.ok?
  return ok(closed(conn, pool)) if taken.unwrap!

  name = Users.normalize(Bond.form(conn, "username").unwrap_or(""))
  password = Bond.form(conn, "password").unwrap_or("")
  confirm = Bond.form(conn, "confirm").unwrap_or("")
  notes = register_notes(name, password, confirm)
  return ok(Bond.html(conn, 400, Views.register(notes, name))) if not notes.empty?

  return ok(busy(conn)) if not Limiter.start_hash()

  hashed = Passwords.hash(password)
  Limiter.end_hash()
  return ok(unavailable(conn)) if not hashed.ok?

  session_id = Auth.new_session_id()
  created = Users.register(pool.unwrap!, name, hashed.unwrap!, Users.token_hash(session_id), now)
  case created
    ok(_) -> ok(Bond.redirect(Auth.with_session(conn, session_id), "/boards", 303))
    error(e) if e.is_a?("users.closed") -> ok(closed(conn, pool))
    error(_) -> ok(unavailable(conn))
  end
end

## Ends the session: its row is deleted, so the cookie is no good even if someone kept a copy, and its live sockets
## are closed. Without a session, the filter already sent the client to the login.
def logout(conn: Bond.Conn, pool: Optional[Database.Pool], cable: Cable.Cable) -> Result[Bond.Conn]
  key = Auth.session_key(conn, pool)
  signed_out = Auth.sign_out(conn, pool)
  if key.some?
    Cable.end_session(cable, key.unwrap!)
  end

  ok(Bond.redirect(signed_out, "/login", 303))
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

## The milestones of a board, open (the default) or closed (`?state=closed`). The session is checked before, as for the
## other pages; an unknown board is a 404 page and a store that is down a 503 one.
def milestones(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Bond.html(conn, 503, Views.boards_unavailable())) if not pool.some?

  reference = Bond.param(conn, "slug").unwrap_or("")
  found = Database.with_connection(pool.unwrap!) do |db|
    board = try Boards.get_open(db, reference)
    items = try Milestones.list_by_board_id(db, board.id, "all", Milestones.today())
    ok(MilestonesPage(board: board, items: items))
  end

  if not found.ok?
    return ok(Bond.html(conn, 404, Views.board_missing())) if found.message.start_with?("NOT_FOUND:")

    IO.warn("kanban: milestones page read failed: #{found.message}")
    return ok(Bond.html(conn, 503, Views.boards_unavailable()))
  end

  state = "open"
  query = Bond.query_params(conn)
  if query.ok? and Params.text(query.unwrap!, "state") == some("closed")
    state = "closed"
  end

  page = found.unwrap!
  html = Views.milestones(page.board.slug, page.board.name, page.items, state)
  ok(Bond.header(Bond.html(conn, 200, html), "Cache-Control", "no-store"))
end

private

LONGEST_PASSWORD = 1024
BUSY_RETRY_SECONDS = 2

struct MilestonesPage
  board: Boards.Board
  items: List[Milestones.Milestone]
end

def authenticate(pool: Database.Pool, name: String, password: String) -> Result[Optional[Users.Account]]
  found = try Users.find(pool, name)
  return ok(none) if not password_matches?(found, password)

  ok(found)
end

def answer_login(
  conn: Bond.Conn,
  pool: Database.Pool,
  name: String,
  account: Optional[Users.Account],
  now: Int,
) -> Bond.Conn
  case account
    some(found) -> start_session(conn, pool, found, now)
    none -> refused(conn, some(pool), name)
  end
end

def start_session(conn: Bond.Conn, pool: Database.Pool, account: Users.Account, now: Int) -> Bond.Conn
  session_id = Auth.new_session_id()
  opened = Users.open_session(pool, account.id, Users.token_hash(session_id), now)
  return unavailable(conn) if not opened.ok?

  Limiter.login_succeeded(account.username, conn.remote_addr, now)
  Bond.redirect(Auth.with_session(conn, session_id), "/boards", 303)
end

def refused(conn: Bond.Conn, pool: Optional[Database.Pool], name: String) -> Bond.Conn
  entry(conn, pool, 401, ["Invalid username or password."], name)
end

def busy(conn: Bond.Conn) -> Bond.Conn
  page = Bond.html(conn, 429, Views.login(["The server is busy. Try again in a moment."], ""))
  Bond.header(page, "Retry-After", BUSY_RETRY_SECONDS.to_s)
end

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
