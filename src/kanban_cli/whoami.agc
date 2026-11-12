import HTTP from "std/http"
import OP from "std/option_parser"
import Client from "client"
import Output from "output"
import Settings from "settings"

struct Health
  ok: Bool
  version: String
end

struct AuthResult
  ok: Bool
end

# A session without a name has agent none (null in JSON): whoami does not need one.
struct Identity
  url: String
  agent: Optional[String]
  board: String
  health: String
end

export def run(words: List[String]) -> Result[Void]
  parser = OP.new("kanban whoami", "Show the server, the agent and the board", [], Settings.common_opts())
  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  client = Client.from(config)
  _ = try check_health(client, config.json)
  check_auth(client, config.json)
  agent: Optional[String] = none
  if not config.agent.empty?
    agent = some(config.agent)
  end

  if config.json
    puts(JSON.encode(JSON.from(Identity(url: config.url, agent: agent, board: config.board, health: "ok"))))
  else
    puts("url: #{config.url}\nagent: #{agent.unwrap_or("none")}\nboard: #{config.board}\nhealth: ok")
  end

  ok()
end

def check_health(client: Client.Client, json: Bool) -> Result[HTTP.Response]
  result = Client.get(client, "/api/health")
  if not result.ok?
    Output.fail(json, "UNAVAILABLE", result.message, 3)
  end

  response = result.unwrap!
  if response.status != 200
    Output.refuse(json, response)
  end

  health = JSON.decode(Output.body(response), Health)
  if not health.ok? or not health.unwrap!.ok or health.unwrap!.version.empty?
    Output.fail(json, "UNAVAILABLE", "invalid health response", 3)
  end

  ok(response)
end

def check_auth(client: Client.Client, json: Bool) -> Void
  result = Client.get(client, "/api/auth-check")
  if not result.ok?
    Output.fail(json, "UNAVAILABLE", result.message, 3)
  end

  response = result.unwrap!
  if response.status != 200
    Output.refuse(json, response)
  end

  checked = JSON.decode(Output.body(response), AuthResult)
  if not checked.ok? or not checked.unwrap!.ok
    Output.fail(json, "UNAVAILABLE", "invalid authentication response", 3)
  end
end
