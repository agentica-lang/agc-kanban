import Bond from "pkg/bond/bond"
import Regex from "std/regex"
import Auth from "../auth"
import Boards from "../../kanban/boards"
import Database from "../../kanban/repo/database"
import Views from "../views"

export def root(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.redirect(conn, "/boards"))

export def login_form(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.redirect(conn, "/boards")) if Auth.signed_in?(conn)

  ok(Bond.html(conn, 200, Views.login("")))
end

export def login(conn: Bond.Conn, key: String) -> Result[Bond.Conn]
  given = Bond.form(conn, "key").unwrap_or("")
  return ok(Bond.html(conn, 401, Views.login("wrong key"))) if not Auth.key_matches?(given, key)

  ok(Bond.redirect(Auth.sign_in(conn), "/boards", 303))
end

## Ends the session. It only clears the cookie: the cookie is a signed value, not a row, so a copy of it stays valid
## until it expires (14 days) or the API key changes. Without a session, the filter has already sent the client to the login.
export def logout(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.redirect(Bond.clear_session(conn), "/login", 303))

export def boards(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.html(conn, 200, Views.boards()))

## The page of a board. A board opened by its number goes to its slug URL, because the live events are broadcast to
## `board:SLUG` and the script subscribes with what the URL says.
export def board(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
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
