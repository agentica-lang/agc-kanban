import Bond from "pkg/bond/bond"
import Auth from "../auth"
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

export def boards(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.html(conn, 200, Views.boards()))

export def board(conn: Bond.Conn) -> Result[Bond.Conn]
  ok(Bond.html(conn, 200, Views.board(Bond.param(conn, "slug").unwrap_or(""))))
end
