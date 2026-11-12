import BDD from "std/bdd"
import HTTP from "std/http"

def main() -> Void
  BDD.run([
    BDD.step("the test server is running", &start_server),
    BDD.step("the database server is running", &start_database_server),
    BDD.step("I post a board named {string} with slug {string} as {string}", &post_board),
    BDD.step("I list boards", &list_boards),
    BDD.step("I get the project snapshot", &project_snapshot),
    BDD.step("I add a card titled {string}", &add_card),
    BDD.step("I get card {int}", &get_card),
    BDD.step("I list project cards", &list_cards),
    BDD.step("I add the column {string} at position {int}", &add_column),
    BDD.step("I get board events for {string} after {int}", &board_events),
    BDD.step("the response contains {string}", &response_contains),
    BDD.step("an unrelated server is running", &start_unrelated),
    BDD.step("a server with broken authentication is running", &start_broken),
    BDD.step("a transient server is running", &start_transient),
    BDD.step("the home fixture is {string}", &fixture_home),
    BDD.step("a server with an invalid authentication response is running", &start_invalid_auth),
    BDD.step("a server is busy {string}", &start_busy),
    BDD.step("I run whoami with key {string}", &whoami),
    BDD.step("whoami exits with code {int}", &whoami_status),
    BDD.step("I run whoami as JSON with key {string}", &whoami_json),
    BDD.step("whoami output contains {string}", &whoami_output),
    BDD.step("I get {string} with key {string}", &request),
    BDD.step("the response status is {int}", &status),
  ])
end

def start_server(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  started = BDD.given_program(ctx, "fixtures/server.agc")
  port = BDD.read_line(started, 30000).unwrap!.to_i!
  BDD.set(started, "port", JSON.from(port))
end

def request(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  client = HTTP.client().unwrap!
  response = HTTP.request(
    client,
    "GET",
    "http://127.0.0.1:#{port}#{args[0]}",
    "".bytes,
    [Header(name: "apikey", value: args[1])],
  ).unwrap!

  HTTP.close_client(client)
  BDD.set(ctx, "status", JSON.from(response.status))
end

def status(ctx: BDD.Context, args: List[String]) -> BDD.Context
  actual = JSON.int(BDD.get(ctx, "status").unwrap!).unwrap!
  BDD.assert(ctx, actual == args[0].to_i!, "status was #{actual}")
end

def start_unrelated(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  started = BDD.given_program(ctx, "fixtures/unrelated.agc")
  port = BDD.read_line(started, 30000).unwrap!.to_i!
  BDD.set(started, "port", JSON.from(port))
end

def whoami(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  env = {"KANBAN_API_KEY": args[0]}
  process = Process.spawn_captured(
    "agentica",
    ["cli.agc", "whoami", "--url", "http://127.0.0.1:#{port}"],
    Process.Options(env: env),
  ).unwrap!

  code = Process.wait(process, 30000).unwrap!
  Process.close(process)
  BDD.set(ctx, "exit", JSON.from(code))
end

def whoami_status(ctx: BDD.Context, args: List[String]) -> BDD.Context
  code = JSON.int(BDD.get(ctx, "exit").unwrap!).unwrap!
  BDD.assert(ctx, code == args[0].to_i!, "exit was #{code}")
end

def whoami_json(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  process = Process.spawn_captured(
    "agentica",
    ["cli.agc", "whoami", "--json", "--url", "http://127.0.0.1:#{port}"],
    Process.Options(env: {"KANBAN_API_KEY": args[0]}),
  ).unwrap!

  code = Process.wait(process, 30000).unwrap!
  output = Process.output(process, 30000).unwrap!
  Process.close(process)
  with_code = BDD.set(ctx, "exit", JSON.from(code))
  BDD.set(with_code, "output", JSON.from(output.stdout))
end

def whoami_output(ctx: BDD.Context, args: List[String]) -> BDD.Context
  output = JSON.string(BDD.get(ctx, "output").unwrap!).unwrap!
  BDD.assert(ctx, output.include?(args[0]), "output was #{output}")
end

def start_broken(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  started = BDD.given_program(ctx, "fixtures/broken_auth.agc")
  port = BDD.read_line(started, 30000).unwrap!.to_i!
  BDD.set(started, "port", JSON.from(port))
end

def start_transient(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  started = BDD.given_program(ctx, "fixtures/transient.agc")
  port = BDD.read_line(started, 30000).unwrap!.to_i!
  BDD.set(started, "port", JSON.from(port))
end

def start_busy(ctx: BDD.Context, args: List[String]) -> BDD.Context
  configured = BDD.given_env(ctx, "BUSY_ALWAYS", args[0])
  started = BDD.given_program(configured, "fixtures/busy.agc")
  port = BDD.read_line(started, 30000).unwrap!.to_i!
  BDD.set(started, "port", JSON.from(port))
end

def start_invalid_auth(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  started = BDD.given_program(ctx, "fixtures/invalid_auth.agc")
  port = BDD.read_line(started, 30000).unwrap!.to_i!
  BDD.set(started, "port", JSON.from(port))
end

def fixture_home(ctx: BDD.Context, args: List[String]) -> BDD.Context
  home = "#{Path.cwd().unwrap!}/specs/fixtures/#{args[0]}"
  BDD.given_env(ctx, "HOME", home)
end

def start_database_server(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  home = System.env("HOME").unwrap!
  Dir.mkdir("#{home}/.cache").unwrap!
  dir = "#{home}/.cache/kanban-bdd-#{System.pid()}"
  configured = BDD.given_env(ctx, "KANBAN_DATA_DIR", dir)
  started = BDD.given_program(configured, "fixtures/database_server.agc")
  hooked = BDD.after(started) do |last| cleanup_database(last, dir) end
  port = BDD.read_line(hooked, 30000).unwrap!.to_i!
  BDD.set(hooked, "port", JSON.from(port))
end

def post_board(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  body = JSON.encode(JSON.from({"name": args[0], "slug": args[1]}))
  client = HTTP.client().unwrap!
  response = HTTP.request(
    client,
    "POST",
    "http://127.0.0.1:#{port}/api/boards",
    body.bytes,
    [
      Header(name: "apikey", value: "01234567890123456789012345678901"),
      Header(name: "X-Kanban-Agent", value: args[2]),
      Header(name: "Content-Type", value: "application/json"),
    ],
  ).unwrap!

  HTTP.close_client(client)
  stored = BDD.set(ctx, "status", JSON.from(response.status))
  BDD.set(stored, "body", JSON.from(HTTP.text(response.body, response.headers).unwrap!))
end

def list_boards(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  client = HTTP.client().unwrap!
  response = HTTP.request(
    client,
    "GET",
    "http://127.0.0.1:#{port}/api/boards",
    "".bytes,
    [Header(name: "apikey", value: "01234567890123456789012345678901")],
  ).unwrap!

  HTTP.close_client(client)
  stored = BDD.set(ctx, "status", JSON.from(response.status))
  BDD.set(stored, "body", JSON.from(HTTP.text(response.body, response.headers).unwrap!))
end

def response_contains(ctx: BDD.Context, args: List[String]) -> BDD.Context
  body = JSON.string(BDD.get(ctx, "body").unwrap!).unwrap!
  BDD.assert(ctx, body.include?(args[0]), "response was #{body}")
end

def cleanup_database(ctx: BDD.Context, dir: String) -> Result[Void]
  closed = BDD.when_eof(ctx)
  _ = BDD.then_exit(closed, 0, 30000)
  try Path.remove("#{dir}/kanban.sqlite3")
  Path.remove(dir)
end

def board_events(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  client = HTTP.client().unwrap!
  response = HTTP.request(
    client,
    "GET",
    "http://127.0.0.1:#{port}/api/boards/#{args[0]}/events?after=#{args[1]}",
    "".bytes,
    [Header(name: "apikey", value: "01234567890123456789012345678901")],
  ).unwrap!

  HTTP.close_client(client)
  stored = BDD.set(ctx, "status", JSON.from(response.status))
  BDD.set(stored, "body", JSON.from(HTTP.text(response.body, response.headers).unwrap!))
end

def add_column(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  data = JSON.object({"name": JSON.from(args[0]), "position": JSON.from(args[1].to_i!)})
  client = HTTP.client().unwrap!
  response = HTTP.request(
    client,
    "POST",
    "http://127.0.0.1:#{port}/api/boards/project/columns",
    JSON.encode(data).bytes,
    [
      Header(name: "apikey", value: "01234567890123456789012345678901"),
      Header(name: "X-Kanban-Agent", value: "agent-1"),
      Header(name: "Content-Type", value: "application/json"),
    ],
  ).unwrap!

  HTTP.close_client(client)
  stored = BDD.set(ctx, "status", JSON.from(response.status))
  BDD.set(stored, "body", JSON.from(HTTP.text(response.body, response.headers).unwrap!))
end

def add_card(ctx: BDD.Context, args: List[String]) -> BDD.Context
  body = JSON.encode(JSON.from({"title": args[0]}))
  api_request(ctx, "POST", "/api/boards/project/cards", body)
end

def get_card(ctx: BDD.Context, args: List[String]) -> BDD.Context
  api_request(ctx, "GET", "/api/cards/#{args[0]}", "")
end

def api_request(ctx: BDD.Context, method: String, path: String, body: String) -> BDD.Context
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  client = HTTP.client().unwrap!
  response = HTTP.request(
    client,
    method,
    "http://127.0.0.1:#{port}#{path}",
    body.bytes,
    [
      Header(name: "apikey", value: "01234567890123456789012345678901"),
      Header(name: "X-Kanban-Agent", value: "agent-1"),
      Header(name: "Content-Type", value: "application/json"),
    ],
  ).unwrap!

  HTTP.close_client(client)
  stored = BDD.set(ctx, "status", JSON.from(response.status))
  BDD.set(stored, "body", JSON.from(HTTP.text(response.body, response.headers).unwrap!))
end

def list_cards(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  api_request(ctx, "GET", "/api/boards/project/cards", "")
end

def project_snapshot(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  api_request(ctx, "GET", "/api/boards/project", "")
end
