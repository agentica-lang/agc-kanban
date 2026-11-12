import BDD from "std/bdd"
import Db from "pkg/db/db"
import HTTP from "std/http"

struct RaceReply
  status: Int
  body: String
end

def main() -> Void
  BDD.run([
    BDD.step("the test server is running", &start_server),
    BDD.step("the database server is running", &start_database_server),
    BDD.step("a database server with a short busy timeout is running", &start_busy_database_server),
    BDD.step("I post a board while the database is locked", &post_board_locked),
    BDD.step("I post a board named {string} with slug {string} as {string}", &post_board),
    BDD.step("I list boards", &list_boards),
    BDD.step("I get the project snapshot", &project_snapshot),
    BDD.step("I add a card titled {string}", &add_card),
    BDD.step("agent {string} retitles card {int} to {string}", &retitle_card),
    BDD.step("agent {string} forces a new title on card {int} to {string}", &force_retitle_card),
    BDD.step("agent {string} comments on card {int} with {string}", &comment_card),
    BDD.step("I read boards with key {string} and agent {string}", &read_boards_as),
    BDD.step("I create a board named {string} with key {string} and agent {string}", &create_board_as),
    BDD.step("I get card {int}", &get_card),
    BDD.step("I make card {int} depend on card {int}", &add_dependency),
    BDD.step("I remove the dependency of card {int} on card {int}", &remove_dependency),
    BDD.step("agent {string} claims card {int}", &claim_card),
    BDD.step("agent {string} marks card {int} done", &done_card),
    BDD.step("agent {string} releases card {int}", &release_card),
    BDD.step("I move card {int} to {string}", &move_card),
    BDD.step("eight agents race to claim card {int}", &race_claims),
    BDD.step("I add eight cards", &add_eight_cards),
    BDD.step("eight agents race to claim the next card", &race_next),
    BDD.step("each agent claims a different card", &assert_distinct_claims),
    BDD.step("one agent wins and seven receive CLAIMED", &assert_race),
    BDD.step("I list project cards", &list_cards),
    BDD.step("I add the column {string} at position {int}", &add_column),
    BDD.step("I rename column {int} to {string}", &rename_column),
    BDD.step("I delete column {int}", &delete_column),
    BDD.step("I mark column {int} as done", &mark_column_done),
    BDD.step("I get board events for {string} after {int}", &board_events),
    BDD.step("the response contains {string}", &response_contains),
    BDD.step("the response does not contain {string}", &response_lacks),
    BDD.step("the response contains exactly {int} occurrences of {string}", &response_occurrences),
    BDD.step("I list project cards with query {string}", &list_cards_query),
    BDD.step("agent {string} claims the next card", &claim_next),
    BDD.step("an unrelated server is running", &start_unrelated),
    BDD.step("a server with broken authentication is running", &start_broken),
    BDD.step("a transient server is running", &start_transient),
    BDD.step("the home fixture is {string}", &fixture_home),
    BDD.step("a server with an invalid authentication response is running", &start_invalid_auth),
    BDD.step("a server is busy {string}", &start_busy),
    BDD.step("I run kanban {string}", &run_kanban),
    BDD.step("kanban exits with code {int}", &kanban_status),
    BDD.step("kanban output contains {string}", &kanban_output),
    BDD.step("kanban output does not contain {string}", &kanban_output_lacks),
    BDD.step("I run kanban without a key {string}", &run_kanban_no_key),
    BDD.step("I run kanban without an agent {string}", &run_kanban_no_agent),
    BDD.step("two agents run kanban {string}", &run_two_kanban),
    BDD.step("kanban exit codes are {string}", &kanban_codes),
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
  dir = "#{home}/.cache/kanban-bdd-#{System.pid()}-#{Random.int(0, 999_999)}"
  configured = BDD.given_env(ctx, "KANBAN_DATA_DIR", dir)
  started = BDD.given_program(configured, "fixtures/database_server.agc")
  hooked = BDD.after(started) do |last| cleanup_database(last, dir) end
  port = BDD.read_line(hooked, 30000).unwrap!.to_i!
  stored = BDD.set(hooked, "data_dir", JSON.from(dir))
  BDD.set(stored, "port", JSON.from(port))
end

def start_busy_database_server(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  home = System.env("HOME").unwrap!
  Dir.mkdir("#{home}/.cache").unwrap!
  dir = "#{home}/.cache/kanban-bdd-busy-#{System.pid()}-#{Random.int(0, 999_999)}"
  configured = BDD.given_env(ctx, "KANBAN_DATA_DIR", dir)
  started = BDD.given_program(configured, "fixtures/busy_database_server.agc")
  hooked = BDD.after(started) do |last| cleanup_database(last, dir) end
  port = BDD.read_line(hooked, 30000).unwrap!.to_i!
  stored = BDD.set(hooked, "data_dir", JSON.from(dir))
  BDD.set(stored, "port", JSON.from(port))
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
  api_request_as(ctx, "agent-1", method, path, body)
end

def api_request_as(ctx: BDD.Context, agent: String, method: String, path: String, body: String) -> BDD.Context
  raw_request(ctx, "01234567890123456789012345678901", method, path, body, agent)
end

def raw_request(
  ctx: BDD.Context,
  key: String,
  method: String,
  path: String,
  body: String,
  agent: String,
) -> BDD.Context
  fields = [Header(name: "apikey", value: key)]
  if not agent.empty?
    fields = fields.push(Header(name: "X-Kanban-Agent", value: agent))
  end

  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  client = HTTP.client().unwrap!
  response = HTTP.request(client, method, "http://127.0.0.1:#{port}#{path}", body.bytes, fields).unwrap!

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

def claim_card(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  client = HTTP.client().unwrap!
  response = HTTP.request(
    client,
    "POST",
    "http://127.0.0.1:#{port}/api/cards/#{args[1]}/claim",
    "{}".bytes,
    [
      Header(name: "apikey", value: "01234567890123456789012345678901"),
      Header(name: "X-Kanban-Agent", value: args[0]),
      Header(name: "Content-Type", value: "application/json"),
    ],
  ).unwrap!

  HTTP.close_client(client)
  stored = BDD.set(ctx, "status", JSON.from(response.status))
  BDD.set(stored, "body", JSON.from(HTTP.text(response.body, response.headers).unwrap!))
end

def race_claims(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  url = "http://127.0.0.1:#{port}/api/cards/#{args[0]}/claim"
  agents = ["agent-1", "agent-2", "agent-3", "agent-4", "agent-5", "agent-6", "agent-7", "agent-8"]
  replies = Task.map(agents, 8, 30000) do |agent| race_claim(url, agent) end
  answers: List[RaceReply] = []
  for reply in replies
    answers = answers.push(reply.unwrap!)
  end

  BDD.set(ctx, "race", JSON.from(answers))
end

def race_claim(url: String, agent: String) -> Result[RaceReply]
  client = try HTTP.client()
  response = HTTP.request(
    client,
    "POST",
    url,
    "{}".bytes,
    [Header(name: "apikey", value: "01234567890123456789012345678901"), Header(name: "X-Kanban-Agent", value: agent)],
  )

  HTTP.close_client(client)
  reply = try response
  ok(RaceReply(status: reply.status, body: try HTTP.text(reply.body, reply.headers)))
end

def assert_race(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  answers = JSON.decode(BDD.get(ctx, "race").unwrap!, List[RaceReply]).unwrap!
  wins = answers.select do |reply| reply.status == 200 end
  losses = answers.select do |reply| reply.status == 409 and reply.body.include?("CLAIMED") end
  BDD.assert(ctx, wins.size == 1 and losses.size == 7, "unexpected race results: #{JSON.encode(JSON.from(answers))}")
end

def add_eight_cards(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  current = ctx
  for index in 1..8
    current = api_request(
      current,
      "POST",
      "/api/boards/project/cards",
      JSON.encode(JSON.from({"title": "Card #{index}"})),
    )

    current = BDD.assert(current, JSON.int(BDD.get(current, "status").unwrap!).unwrap! == 201, "card creation failed")
  end

  current
end

def race_next(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  url = "http://127.0.0.1:#{port}/api/boards/project/claim-next"
  agents = ["agent-1", "agent-2", "agent-3", "agent-4", "agent-5", "agent-6", "agent-7", "agent-8"]
  replies = Task.map(agents, 8, 30000) do |agent| race_claim(url, agent) end
  answers: List[RaceReply] = []
  for reply in replies
    answers = answers.push(reply.unwrap!)
  end

  BDD.set(ctx, "race", JSON.from(answers))
end

def assert_distinct_claims(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  answers = JSON.decode(BDD.get(ctx, "race").unwrap!, List[RaceReply]).unwrap!
  ids: Set[Int] = Set.new([])
  for answer in answers
    _ = BDD.assert(ctx, answer.status == 200, "claim next failed: #{answer.body}")
    body = JSON.parse(answer.body).unwrap!
    card = JSON.get(body, "card").unwrap!
    id = JSON.int(JSON.get(card, "id").unwrap!).unwrap!
    ids = ids.add(id)
  end

  BDD.assert(ctx, ids.size == 8, "claim next returned duplicate cards")
end

def done_card(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  client = HTTP.client().unwrap!
  response = HTTP.request(
    client,
    "POST",
    "http://127.0.0.1:#{port}/api/cards/#{args[1]}/done",
    "{}".bytes,
    [
      Header(name: "apikey", value: "01234567890123456789012345678901"),
      Header(name: "X-Kanban-Agent", value: args[0]),
    ],
  ).unwrap!

  HTTP.close_client(client)
  stored = BDD.set(ctx, "status", JSON.from(response.status))
  BDD.set(stored, "body", JSON.from(HTTP.text(response.body, response.headers).unwrap!))
end

def release_card(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  client = HTTP.client().unwrap!
  response = HTTP.request(
    client,
    "POST",
    "http://127.0.0.1:#{port}/api/cards/#{args[1]}/release",
    "{}".bytes,
    [
      Header(name: "apikey", value: "01234567890123456789012345678901"),
      Header(name: "X-Kanban-Agent", value: args[0]),
    ],
  ).unwrap!

  HTTP.close_client(client)
  stored = BDD.set(ctx, "status", JSON.from(response.status))
  BDD.set(stored, "body", JSON.from(HTTP.text(response.body, response.headers).unwrap!))
end

def move_card(ctx: BDD.Context, args: List[String]) -> BDD.Context
  api_request(ctx, "POST", "/api/cards/#{args[0]}/move", JSON.encode(JSON.from({"column": args[1]})))
end

def add_dependency(ctx: BDD.Context, args: List[String]) -> BDD.Context
  body = JSON.encode(JSON.from({"depends_on": args[1].to_i!}))
  api_request(ctx, "POST", "/api/cards/#{args[0]}/deps", body)
end

def remove_dependency(ctx: BDD.Context, args: List[String]) -> BDD.Context
  api_request(ctx, "DELETE", "/api/cards/#{args[0]}/deps/#{args[1]}", "")
end

def rename_column(ctx: BDD.Context, args: List[String]) -> BDD.Context
  body = JSON.encode(JSON.from({"name": args[1]}))
  api_request(ctx, "PATCH", "/api/columns/#{args[0]}", body)
end

def delete_column(ctx: BDD.Context, args: List[String]) -> BDD.Context
  api_request(ctx, "DELETE", "/api/columns/#{args[0]}", "")
end

def mark_column_done(ctx: BDD.Context, args: List[String]) -> BDD.Context
  body = JSON.encode(JSON.from({"done": true}))
  api_request(ctx, "PATCH", "/api/columns/#{args[0]}", body)
end

def retitle_card(ctx: BDD.Context, args: List[String]) -> BDD.Context
  body = JSON.encode(JSON.from({"title": args[2]}))
  api_request_as(ctx, args[0], "PATCH", "/api/cards/#{args[1]}", body)
end

def force_retitle_card(ctx: BDD.Context, args: List[String]) -> BDD.Context
  body = JSON.encode(JSON.object({"title": JSON.from(args[2]), "force": JSON.from(true)}))
  api_request_as(ctx, args[0], "PATCH", "/api/cards/#{args[1]}", body)
end

def comment_card(ctx: BDD.Context, args: List[String]) -> BDD.Context
  body = JSON.encode(JSON.from({"body": args[2]}))
  api_request_as(ctx, args[0], "POST", "/api/cards/#{args[1]}/comments", body)
end

def read_boards_as(ctx: BDD.Context, args: List[String]) -> BDD.Context
  raw_request(ctx, args[0], "GET", "/api/boards", "", args[1])
end

def create_board_as(ctx: BDD.Context, args: List[String]) -> BDD.Context
  body = JSON.encode(JSON.from({"name": args[0]}))
  raw_request(ctx, args[1], "POST", "/api/boards", body, args[2])
end

# A write lock from another connection makes the server wait out its busy timeout and answer BUSY.
def post_board_locked(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  dir = JSON.string(BDD.get(ctx, "data_dir").unwrap!).unwrap!
  conn = Db.open("sqlite:#{dir}/kanban.sqlite3").unwrap!
  _ = Db.execute(conn, "begin immediate", []).unwrap!
  answered = post_board(ctx, ["Project", "project", "agent-1"])
  _ = Db.execute(conn, "rollback", []).unwrap!
  Db.close(conn)
  answered
end

def response_lacks(ctx: BDD.Context, args: List[String]) -> BDD.Context
  body = JSON.string(BDD.get(ctx, "body").unwrap!).unwrap!
  BDD.assert(ctx, not body.include?(args[0]), "response was #{body}")
end

def response_occurrences(ctx: BDD.Context, args: List[String]) -> BDD.Context
  body = JSON.string(BDD.get(ctx, "body").unwrap!).unwrap!
  found = body.split(args[1]).size - 1
  BDD.assert(ctx, found == args[0].to_i!, "found #{found} of #{args[1]} in #{body}")
end

def list_cards_query(ctx: BDD.Context, args: List[String]) -> BDD.Context
  api_request(ctx, "GET", "/api/boards/project/cards?#{args[0]}", "")
end

def claim_next(ctx: BDD.Context, args: List[String]) -> BDD.Context
  api_request_as(ctx, args[0], "POST", "/api/boards/project/claim-next", "{}")
end

def run_kanban(ctx: BDD.Context, args: List[String]) -> BDD.Context
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  process = Process.spawn_captured(
    "agentica",
    ["cli.agc"] + args[0].split(" "),
    Process.Options(
      env: {
        "KANBAN_URL": "http://127.0.0.1:#{port}",
        "KANBAN_API_KEY": "01234567890123456789012345678901",
        "KANBAN_AGENT": "agent-1",
      },
    ),
  ).unwrap!

  code = Process.wait(process, 30000).unwrap!
  output = Process.output(process, 30000).unwrap!
  Process.close(process)
  stored = BDD.set(ctx, "kanban_exit", JSON.from(code))
  BDD.set(stored, "kanban_output", JSON.from("#{output.stdout}#{output.stderr}"))
end

def kanban_status(ctx: BDD.Context, args: List[String]) -> BDD.Context
  code = JSON.int(BDD.get(ctx, "kanban_exit").unwrap!).unwrap!
  BDD.assert(ctx, code == args[0].to_i!, "exit was #{code}")
end

def kanban_output(ctx: BDD.Context, args: List[String]) -> BDD.Context
  output = JSON.string(BDD.get(ctx, "kanban_output").unwrap!).unwrap!
  BDD.assert(ctx, output.include?(args[0]), "output was #{output}")
end

def kanban_output_lacks(ctx: BDD.Context, args: List[String]) -> BDD.Context
  output = JSON.string(BDD.get(ctx, "kanban_output").unwrap!).unwrap!
  BDD.assert(ctx, not output.include?(args[0]), "output was #{output}")
end

def kanban_env(ctx: BDD.Context) -> Map[String, String]
  port = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!
  {
    "KANBAN_URL": "http://127.0.0.1:#{port}",
    "KANBAN_API_KEY": "01234567890123456789012345678901",
    "KANBAN_AGENT": "agent-1",
  }
end

def kanban_process(ctx: BDD.Context, words: List[String], env: Map[String, String]) -> Process
  Process.spawn_captured("agentica", ["cli.agc"] + words, Process.Options(env: env)).unwrap!
end

def run_kanban_no_key(ctx: BDD.Context, args: List[String]) -> BDD.Context
  env = kanban_env(ctx)
  env = env.put("KANBAN_API_KEY", "")
  process = kanban_process(ctx, args[0].split(" "), env)
  code = Process.wait(process, 30000).unwrap!
  output = Process.output(process, 30000).unwrap!
  Process.close(process)
  stored = BDD.set(ctx, "kanban_exit", JSON.from(code))
  BDD.set(stored, "kanban_output", JSON.from("#{output.stdout}#{output.stderr}"))
end

def run_kanban_no_agent(ctx: BDD.Context, args: List[String]) -> BDD.Context
  env = kanban_env(ctx)
  env = env.put("KANBAN_AGENT", "")
  process = kanban_process(ctx, args[0].split(" "), env)
  code = Process.wait(process, 30000).unwrap!
  output = Process.output(process, 30000).unwrap!
  Process.close(process)
  stored = BDD.set(ctx, "kanban_exit", JSON.from(code))
  BDD.set(stored, "kanban_output", JSON.from("#{output.stdout}#{output.stderr}"))
end

# Two real processes, two names, one card: exactly one exits 0 and the other 4.
def run_two_kanban(ctx: BDD.Context, args: List[String]) -> BDD.Context
  words = args[0].split(" ")
  one = kanban_process(ctx, words, kanban_env(ctx))
  two_env = kanban_env(ctx).put("KANBAN_AGENT", "agent-2")
  two = kanban_process(ctx, words, two_env)
  first = Process.wait(one, 30000).unwrap!
  second = Process.wait(two, 30000).unwrap!
  output = "#{Process.output(one, 30000).unwrap!.stdout}#{Process.output(two, 30000).unwrap!.stdout}"
  Process.close(one)
  Process.close(two)
  low = first
  high = second
  if low > high
    low = second
    high = first
  end

  stored = BDD.set(ctx, "kanban_codes", JSON.from("#{low},#{high}"))
  BDD.set(stored, "kanban_output", JSON.from(output))
end

def kanban_codes(ctx: BDD.Context, args: List[String]) -> BDD.Context
  codes = JSON.string(BDD.get(ctx, "kanban_codes").unwrap!).unwrap!
  BDD.assert(ctx, codes == args[0], "exit codes were #{codes}")
end
