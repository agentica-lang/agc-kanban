import OP from "std/option_parser"
import {Arg, Kind, Opt} from "std/option_parser"
import HTTP from "std/http"
import Toml from "std/toml"

struct Failure
  code: String
  message: String
end

struct ErrorOutput
  error: Failure
end

struct AuthResult
  ok: Bool
end

struct Health
  ok: Bool
  version: String
end

struct Identity
  url: String
  agent: String
  board: String
  health: String
end

def main() -> Void
  parser = OP.new(
    "kanban",
    "Kanban client",
    [Arg(name: "command", choices: ["whoami"])],
    [Opt(name: "url"), Opt(name: "agent"), Opt(name: "board"), Opt(name: "json", kind: Kind.Flag)],
  )

  args = System.args()
  parsed_result = OP.parse(parser, args)
  if not parsed_result.ok? and not OP.help?(parsed_result.message) and json_requested?(args)
    fail(true, "INVALID", OP.message(parsed_result.message), 2)
  end

  parsed = OP.run!(parsed_result)
  url = value(OP.optional_string(parsed, "url"), "KANBAN_URL", "url", "http://127.0.0.1:4580", OP.flag(parsed, "json"))
  agent = value(OP.optional_string(parsed, "agent"), "KANBAN_AGENT", "agent", "", OP.flag(parsed, "json"))
  board = value(OP.optional_string(parsed, "board"), "KANBAN_BOARD", "board", "", OP.flag(parsed, "json"))
  result = request("#{url}/api/health", [])
  if not result.ok?
    fail(OP.flag(parsed, "json"), "UNAVAILABLE", result.message)
  end

  response = result.unwrap!
  if busy?(response)
    fail(OP.flag(parsed, "json"), "BUSY", "server is busy")
  end

  if response.status != 200
    fail(OP.flag(parsed, "json"), "UNAVAILABLE", "health returned #{response.status}")
  end

  health = JSON.decode(HTTP.text(response.body, response.headers).unwrap_or(""), Health)
  if not health.ok? or not health.unwrap!.ok or health.unwrap!.version.empty?
    fail(OP.flag(parsed, "json"), "UNAVAILABLE", "invalid health response")
  end

  key = value(none, "KANBAN_API_KEY", "api_key", "", OP.flag(parsed, "json"))
  auth = request("#{url}/api/auth-check", [Header(name: "apikey", value: key)])
  if not auth.ok?
    fail(OP.flag(parsed, "json"), "UNAVAILABLE", auth.message)
  end

  if busy?(auth.unwrap!)
    fail(OP.flag(parsed, "json"), "BUSY", "server is busy")
  end

  if auth.unwrap!.status == 401
    fail(OP.flag(parsed, "json"), "UNAUTHORIZED", "authentication failed")
  elsif auth.unwrap!.status != 200
    fail(OP.flag(parsed, "json"), "UNAVAILABLE", "authentication check returned #{auth.unwrap!.status}")
  end

  checked = JSON.decode(HTTP.text(auth.unwrap!.body, auth.unwrap!.headers).unwrap_or(""), AuthResult)
  if not checked.ok? or not checked.unwrap!.ok
    fail(OP.flag(parsed, "json"), "UNAVAILABLE", "invalid authentication response")
  end

  if OP.flag(parsed, "json")
    puts(JSON.encode(JSON.from(Identity(url: url, agent: agent, board: board, health: "ok"))))
  else
    puts("url: #{url}\nagent: #{agent}\nboard: #{board}\nhealth: ok")
  end
end

def value(flag: Optional[String], env: String, name: String, default: String, json: Bool) -> String
  return flag.unwrap! if flag.some?

  environment = System.env(env)
  return environment.unwrap! if environment.ok?

  file = file_value(name, default)
  if not file.ok?
    fail(json, "INVALID", file.message, 2)
  end

  file.unwrap!
end

def file_value(name: String, default: String) -> Result[String]
  home = System.env("HOME").unwrap_or("")
  path = "#{home}/.config/agc-kanban/config.toml"
  info = File.lstat(path)
  if not info.ok?
    return ok(default) if info.message == "filesystem: path does not exist"
    return error("cannot inspect config: #{info.message}")
  end

  text = try File.read_text(path)
  doc = try Toml.parse(text)
  case doc
    Toml.Value.Table(entries) ->
      case entries.get(name)
        none -> ok(default)
        some(Toml.Value.Str(value)) -> ok(value)
        some(_) -> error("config #{name} must be a string")
      end

    _ -> error("config must be a table")
  end
end

def fail(json: Bool, code: String, message: String, exit_code: Int = 3) -> Void
  if json
    puts(JSON.encode(JSON.from(ErrorOutput(error: Failure(code: code, message: message)))))
  else
    IO.warn("kanban: #{code}: #{message}")
  end

  System.exit(exit_code)
end

def request(url: String, headers: List[Header]) -> Result[HttpResponse]
  result = request_once(url, headers)
  for delay in [200, 400, 800]
    return result if result.ok? and not busy?(result.unwrap!)

    Task.sleep(delay)
    result = request_once(url, headers)
  end

  result
end

def request_once(url: String, headers: List[Header]) -> Result[HttpResponse]
  client = try HTTP.client(HttpClientOptions(timeout_ms: 5000))
  result = HTTP.request(client, "GET", url, "".bytes, headers)
  HTTP.close_client(client)
  result
end

def busy?(response: HttpResponse) -> Bool
  return false if response.status != 503

  decoded = JSON.decode(HTTP.text(response.body, response.headers).unwrap_or(""), ErrorOutput)
  decoded.ok? and decoded.unwrap!.error.code == "BUSY"
end

def json_requested?(args: List[String]) -> Bool
  for arg in args
    return false if arg == "--"
    return true if arg == "--json"
  end

  false
end
