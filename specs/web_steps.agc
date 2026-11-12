## The steps of `web.feature` and `cable.feature`: the pages with a cookie, and a live client that is a browser. The
## live client is `fixtures/ws_client/cable_client.agc`, a program of the package `websocket-client` that prints each
## frame as a line; a step reads those lines through a service, because a step cannot leave a task running.

import BDD from "std/bdd"
import HTTP from "std/http"
import Regex from "std/regex"
import AssetNames from "../src/kanban_web/asset_names"

KEY = "01234567890123456789012345678901"
# Relative to the working directory of the steps, the project folder.
CLIENT = "specs/fixtures/ws_client/cable_client.agc"
# Frames that a step skips on the way to the one it waits for (the confirmation, the ping).
SKIPPED_FRAMES = 50

export def steps() -> List[BDD.Step]
  [
    BDD.step("I sign in with the key {string}", &sign_in),
    BDD.step("I get the page {string}", &get_page),
    BDD.step("I get the page {string} with the session", &get_page_signed),
    BDD.step("I post to {string} with the session", &post_signed),
    BDD.step("I get the built stylesheet", &get_stylesheet),
    BDD.step("I get the page {string} with the key {string} as the apikey header", &get_page_with_key),
    BDD.step("the response sets the session cookie", &sets_cookie),
    BDD.step("the response sets no cookie", &sets_no_cookie),
    BDD.step("the response clears the session cookie", &clears_cookie),
    BDD.step("the response redirects to {string}", &redirects_to),
    BDD.step("the page names the built stylesheet and script", &names_assets),
    BDD.step("the page applies the saved theme before the stylesheet", &theme_first),
    BDD.step("the response header {string} contains {string}", &header_contains),
    BDD.step("a live client with the session subscribes to the board {string}", &subscribe_signed),
    BDD.step("a live client without a session subscribes to the board {string}", &subscribe_anonymous),
    BDD.step("the live client receives a frame containing {string}", &live_receives),
  ]
end

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

def sign_in(ctx: BDD.Context, args: List[String]) -> BDD.Context
  form = [HTTP.Header(name: "Content-Type", value: "application/x-www-form-urlencoded")]
  done = fetch(ctx, "POST", "/login", "key=#{args[0]}", form)
  cookie = header_of(done, "set-cookie").split(";")[0]
  BDD.set(done, "cookie", JSON.from(cookie))
end

def get_page(ctx: BDD.Context, args: List[String]) -> BDD.Context = fetch(ctx, "GET", args[0], "", [])

def get_page_signed(ctx: BDD.Context, args: List[String]) -> BDD.Context
  fetch(ctx, "GET", args[0], "", [HTTP.Header(name: "Cookie", value: text_of(ctx, "cookie"))])
end

# A write with the cookie and no `apikey` header: the session never writes the API.
def post_signed(ctx: BDD.Context, args: List[String]) -> BDD.Context
  fetch(ctx, "POST", args[0], "{}", [HTTP.Header(name: "Cookie", value: text_of(ctx, "cookie"))])
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

def serving(f: Fn[Json, Result[Json]]) -> Fn[Json, Result[Json]] = f

# Starts the live client and keeps it behind a service: a request `{"timeout_ms": N}` answers its next line.
def subscribe(ctx: BDD.Context, cookie: String, board: String) -> BDD.Context
  process = Process.spawn_captured("agentica", [CLIENT, "#{port_of(ctx)}", cookie, board]).unwrap!
  service = serving do |request| next_line(process, request) end
  BDD.keep(ctx, "live", service)
end

def next_line(process: Process, request: Json) -> Result[Json]
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
