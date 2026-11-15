## The steps of `web.feature` and `cable.feature`: the pages with a cookie, and a live client that is a browser. The
## live client is `fixtures/ws_client/cable_client.agc`, a program of the package `websocket-client` that prints each
## frame as a line; a step reads those lines through a service, because a step cannot leave a task running.

import BDD from "std/bdd"
import Db from "pkg/db/db"
import Sqlite from "pkg/db/sqlite"
import HTTP from "std/http"
import Regex from "std/regex"
import URI from "std/uri"
import AssetNames from "../src/kanban_web/asset_names"

struct Reply
  status: Int
  cookies: Int
end

def steps() -> List[BDD.Step]
  [
    BDD.step("I sign in", &sign_in),
    BDD.step("I register the user {string} with the password {string}", &register),
    BDD.step(
      "I register the user {string} with the password {string} and the confirmation {string}",
      &register_confirmed,
    ),
    BDD.step("I sign in as {string} with the password {string}", &sign_in_as),
    BDD.step("I try to sign in {int} times as {string} with the password {string}", &sign_in_times),
    BDD.step("I post to {string} with the cookie and the origin {string}", &post_with_origin),
    BDD.step("two visitors register at once", &register_race),
    BDD.step("the response has {int} sign-ins and {int} refusals", &assert_race),
    BDD.step("the store has {int} users", &users_count),
    BDD.step("the store has {int} sessions", &sessions_count),
    BDD.step("the store keeps the password of {string} as a scrypt hash without {string}", &assert_hashed),
    BDD.step("the sessions of the store have ended", &end_sessions),
    BDD.step("I get the page {string}", &get_page),
    BDD.step("I get the page {string} with the session", &get_page_signed),
    BDD.step("I post to {string} with the session", &post_signed),
    BDD.step("I patch {string} with the session as agent {string} and the body {string}", &patch_signed),
    BDD.step("I post {string} with the session as agent {string} and the body {string}", &post_signed_as),
    BDD.step("I get the built stylesheet", &get_stylesheet),
    BDD.step("I get the page {string} with the key {string} as the apikey header", &get_page_with_key),
    BDD.step("the response sets the session cookie", &sets_cookie),
    BDD.step("the response sets no cookie", &sets_no_cookie),
    BDD.step("the response clears the session cookie", &clears_cookie),
    BDD.step("the response redirects to {string}", &redirects_to),
    BDD.step("the page names the built stylesheet and script", &names_assets),
    BDD.step("the page applies the saved theme before the stylesheet", &theme_first),
    BDD.step("the response header {string} contains {string}", &header_contains),
    BDD.step("the response has the header {string}", &has_header),
    BDD.step("a live client with the session subscribes to the board {string}", &subscribe_signed),
    BDD.step("a live client without a session subscribes to the board {string}", &subscribe_anonymous),
    BDD.step("the live client receives a frame containing {string}", &live_receives),
  ]
end

private

KEY = "01234567890123456789012345678901"
TEST_PASSWORD = "Sup3r-secret!"

# Relative to the working directory of the steps, the project folder.
CLIENT = "specs/fixtures/ws_client/cable_client.agc"

# Frames that a step skips on the way to the one it waits for (the confirmation, the ping).
SKIPPED_FRAMES = 50

def port_of(ctx: BDD.Context) -> Int = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!

def text_of(ctx: BDD.Context, name: String) -> String
  JSON.string(BDD.get(ctx, name).unwrap_or(JSON.from(""))).unwrap_or("")
end

# One request with no redirect followed, and its status, body and headers kept for the checks.
def fetch(ctx: BDD.Context, method: String, path: String, body: String, headers: List[HTTP.Header]) -> BDD.Context
  client = HTTP.client().unwrap!
  response = HTTP.request(client, method, "http://127.0.0.1:#{port_of(ctx)}#{path}", body.bytes, headers).unwrap!
  HTTP.close_client(client)
  names = response.headers.map do |field| field.name end
  values = response.headers.map do |field| field.value end
  kept = BDD.set(ctx, "status", JSON.from(response.status))
  kept = BDD.set(kept, "body", JSON.from(HTTP.text(response.body, response.headers).unwrap!))
  kept = BDD.set(kept, "header names", JSON.from(names))
  BDD.set(kept, "header values", JSON.from(values))
end

def header_of(ctx: BDD.Context, name: String) -> String
  names = JSON.decode(BDD.get(ctx, "header names").unwrap!, List[String]).unwrap!
  values = JSON.decode(BDD.get(ctx, "header values").unwrap!, List[String]).unwrap!
  for i in 0...names.size
    return values[i] if names[i] == name
  end

  ""
end

# A made-up user for the specs that only need a session.
def sign_in(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  post_form(ctx, "/register", form(["owner", TEST_PASSWORD, TEST_PASSWORD]))
end

def register(ctx: BDD.Context, args: List[String]) -> BDD.Context
  post_form(ctx, "/register", form([args[0], args[1], args[1]]))
end

def register_confirmed(ctx: BDD.Context, args: List[String]) -> BDD.Context
  post_form(ctx, "/register", form([args[0], args[1], args[2]]))
end

def sign_in_as(ctx: BDD.Context, args: List[String]) -> BDD.Context
  post_form(ctx, "/login", URI.encode_www_form(pairs(["username", "password"], [args[0], args[1]])))
end

# The status and the page are those of the last try.
def sign_in_times(ctx: BDD.Context, args: List[String]) -> BDD.Context
  current = ctx
  for _ in 1..args[0].to_i!
    current = sign_in_as(current, [args[1], args[2]])
  end

  current
end

# A browser form from another site: the cookie of the session, and an `Origin` that is not the server.
def post_with_origin(ctx: BDD.Context, args: List[String]) -> BDD.Context
  headers = [
    HTTP.Header(name: "Cookie", value: text_of(ctx, "cookie")),
    HTTP.Header(name: "Origin", value: args[1]),
    HTTP.Header(name: "Content-Type", value: "application/x-www-form-urlencoded"),
  ]

  fetch(ctx, "POST", args[0], "", headers)
end

def post_form(ctx: BDD.Context, path: String, body: String) -> BDD.Context
  headers = [HTTP.Header(name: "Content-Type", value: "application/x-www-form-urlencoded")]
  done = fetch(ctx, "POST", path, body, headers)
  cookie = header_of(done, "set-cookie").split(";")[0]
  return done if cookie == ""

  BDD.set(done, "cookie", JSON.from(cookie))
end

def form(values: List[String]) -> String = URI.encode_www_form(pairs(["username", "password", "confirm"], values))

def pairs(names: List[String], values: List[String]) -> List[URI.Pair]
  (0...names.size).map { |i| URI.Pair(name: names[i], value: values[i]) }
end

# Two visitors send the register form together, as two different users; one wins, the other finds it closed.
def register_race(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  port = port_of(ctx)
  replies = Task.map(["first", "second"], 2, 60000) do |name| race_register(port, name) end
  statuses: List[Reply] = []
  for reply in replies
    statuses = statuses.push(reply.unwrap!)
  end

  BDD.set(ctx, "race", JSON.from(statuses))
end

def race_register(port: Int, name: String) -> Result[Reply]
  client = try HTTP.client()
  headers = [HTTP.Header(name: "Content-Type", value: "application/x-www-form-urlencoded")]
  response = HTTP.request(
    client,
    "POST",
    "http://127.0.0.1:#{port}/register",
    form([name, TEST_PASSWORD, TEST_PASSWORD]).bytes,
    headers,
  )

  HTTP.close_client(client)
  reply = try response
  cookies = reply.headers.select { |field| field.name == "set-cookie" }
  ok(Reply(status: reply.status, cookies: cookies.size))
end

def assert_race(ctx: BDD.Context, args: List[String]) -> BDD.Context
  replies = JSON.decode(BDD.get(ctx, "race").unwrap!, List[Reply]).unwrap!
  signed = replies.select { |reply| reply.status == 303 and reply.cookies == 1 }
  refused = replies.select { |reply| reply.status == 403 and reply.cookies == 0 }
  BDD.assert(
    ctx,
    signed.size == args[0].to_i! and refused.size == args[1].to_i!,
    "replies were #{JSON.encode(JSON.from(replies))}",
  )
end

def count_rows(ctx: BDD.Context, table: String) -> Int
  dir = JSON.string(BDD.get(ctx, "data_dir").unwrap!).unwrap!
  conn = Db.open("sqlite:#{dir}/kanban.sqlite3", [Sqlite.driver()]).unwrap!
  rows = Db.query(conn, "select count(*) as total from #{table}", []).unwrap!
  Db.close(conn)
  case rows[0].get("total", Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end

def users_count(ctx: BDD.Context, args: List[String]) -> BDD.Context
  total = count_rows(ctx, "users")
  BDD.assert(ctx, total == args[0].to_i!, "users were #{total}")
end

def sessions_count(ctx: BDD.Context, args: List[String]) -> BDD.Context
  total = count_rows(ctx, "sessions")
  BDD.assert(ctx, total == args[0].to_i!, "sessions were #{total}")
end

def assert_hashed(ctx: BDD.Context, args: List[String]) -> BDD.Context
  dir = JSON.string(BDD.get(ctx, "data_dir").unwrap!).unwrap!
  conn = Db.open("sqlite:#{dir}/kanban.sqlite3", [Sqlite.driver()]).unwrap!
  rows = Db.query(conn, "select password_hash from users where username = ?", [Db.Value.Text(args[0])]).unwrap!
  Db.close(conn)
  stored = ""
  case rows[0].get("password_hash", Db.Value.Null)
    Db.Value.Text(value) -> stored = value
    _ -> stored = ""
  end

  BDD.assert(ctx, stored.start_with?("scrypt$") and not stored.include?(args[1]), "the stored hash was #{stored}")
end

def end_sessions(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  dir = JSON.string(BDD.get(ctx, "data_dir").unwrap!).unwrap!
  conn = Db.open("sqlite:#{dir}/kanban.sqlite3", [Sqlite.driver()]).unwrap!
  _ = Db.execute(conn, "update sessions set expires_at = 1", []).unwrap!
  Db.close(conn)
  ctx
end

def get_page(ctx: BDD.Context, args: List[String]) -> BDD.Context = fetch(ctx, "GET", args[0], "", [])

def get_page_signed(ctx: BDD.Context, args: List[String]) -> BDD.Context
  fetch(ctx, "GET", args[0], "", [HTTP.Header(name: "Cookie", value: text_of(ctx, "cookie"))])
end

# A write with the cookie and no `apikey` header: the session never writes the API.
def post_signed(ctx: BDD.Context, args: List[String]) -> BDD.Context
  fetch(ctx, "POST", args[0], "{}", [HTTP.Header(name: "Cookie", value: text_of(ctx, "cookie"))])
end

# The writes that the session may make (a label color, an archive): the cookie, the agent name of the page, and no
# `apikey` header.
def patch_signed(ctx: BDD.Context, args: List[String]) -> BDD.Context = send_signed(ctx, "PATCH", args)

def post_signed_as(ctx: BDD.Context, args: List[String]) -> BDD.Context = send_signed(ctx, "POST", args)

def send_signed(ctx: BDD.Context, method: String, args: List[String]) -> BDD.Context
  headers = [HTTP.Header(name: "Cookie", value: text_of(ctx, "cookie"))]
  if not args[1].empty?
    headers = headers.push(HTTP.Header(name: "X-Kanban-Agent", value: args[1]))
  end

  fetch(ctx, method, args[0], args[2], headers)
end

def get_page_with_key(ctx: BDD.Context, args: List[String]) -> BDD.Context
  fetch(ctx, "GET", args[0], "", [HTTP.Header(name: "apikey", value: args[1])])
end

def get_stylesheet(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  fetch(ctx, "GET", AssetNames.STYLESHEET, "", [])
end

def sets_cookie(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  cookie = header_of(ctx, "set-cookie")
  BDD.assert(ctx, cookie.start_with?("kanban_session=") and cookie.include?("HttpOnly"), "set-cookie was #{cookie}")
end

def sets_no_cookie(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  BDD.assert(ctx, header_of(ctx, "set-cookie") == "", "set-cookie was #{header_of(ctx, "set-cookie")}")
end

def clears_cookie(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  cookie = header_of(ctx, "set-cookie")
  BDD.assert(ctx, cookie.start_with?("kanban_session=") and cookie.include?("Max-Age=0"), "set-cookie was #{cookie}")
end

def redirects_to(ctx: BDD.Context, args: List[String]) -> BDD.Context
  BDD.assert(ctx, header_of(ctx, "location") == args[0], "location was #{header_of(ctx, "location")}")
end

def has_header(ctx: BDD.Context, args: List[String]) -> BDD.Context
  BDD.assert(ctx, header_of(ctx, args[0]) != "", "no header #{args[0]}")
end

def header_contains(ctx: BDD.Context, args: List[String]) -> BDD.Context
  value = header_of(ctx, args[0])
  BDD.assert(ctx, value.include?(args[1]), "#{args[0]} was #{value}")
end

# The inline script must come before the stylesheet, or a dark choice paints light first.
def theme_first(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  page = text_of(ctx, "body")
  theme = page.index_of("localStorage.getItem(\"agc-kanban.theme\")")
  sheet = page.index_of(AssetNames.STYLESHEET)
  BDD.assert(ctx, theme.some? and sheet.some? and theme.unwrap! < sheet.unwrap!, "the page was #{page}")
end

def names_assets(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  page = text_of(ctx, "body")
  fingerprinted = Regex.match?(AssetNames.STYLESHEET, /^\/assets\/application-[0-9a-f]{16}\.css$/)
  named = page.include?(AssetNames.STYLESHEET) and page.include?(AssetNames.SCRIPT)
  BDD.assert(ctx, fingerprinted and named, "the page was #{page}")
end

# Starts the live client and keeps it behind a service: a request `{"timeout_ms": N}` answers its next line.
def subscribe(ctx: BDD.Context, cookie: String, board: String) -> BDD.Context
  process = Process.spawn_captured("agentica", [CLIENT, "#{port_of(ctx)}", cookie, board]).unwrap!
  service: Fn[JSON.Value, Result[JSON.Value]] = ->(request) { next_line(process, request) }
  BDD.keep(ctx, "live", service)
end

def next_line(process: Process, request: JSON.Value) -> Result[JSON.Value]
  wait = JSON.int(JSON.get(request, "timeout_ms").unwrap!).unwrap!
  ok(JSON.from(try Process.read_line(process, wait)))
end

def subscribe_signed(ctx: BDD.Context, args: List[String]) -> BDD.Context
  subscribe(ctx, text_of(ctx, "cookie"), args[0])
end

def subscribe_anonymous(ctx: BDD.Context, args: List[String]) -> BDD.Context = subscribe(ctx, "", args[0])

def live_receives(ctx: BDD.Context, args: List[String]) -> BDD.Context
  seen: List[String] = []
  for _ in 0...SKIPPED_FRAMES
    answer = BDD.call(ctx, "live", JSON.from({"timeout_ms": JSON.from(10_000)}))
    return BDD.assert(ctx, false, "no frame with #{args[0]}, got #{seen}") if not answer.ok?

    line = JSON.string(answer.unwrap!).unwrap!
    return BDD.assert(ctx, true, "") if line.include?(args[0])

    seen = seen.push(line)
  end

  BDD.assert(ctx, false, "no frame with #{args[0]} in #{SKIPPED_FRAMES} frames, got #{seen}")
end
