import OP from "std/option_parser"
import Toml from "std/toml"
import {Kind, Opt, Parsed} from "std/option_parser"

struct Flags
  url: Optional[String]
  agent: Optional[String]
  board: Optional[String]
  json: Bool
end

struct Config
  url: String
  key: String
  agent: String
  board: String
  json: Bool
end

def common_opts() -> List[Opt]
  [
    Opt(name: "url", help: "server url"),
    Opt(name: "agent", help: "agent name sent on writes"),
    Opt(name: "board", help: "board used when a command takes none"),
    Opt(name: "json", kind: Kind.Flag, help: "print the server answer as JSON"),
  ]
end

def read_flags(parsed: Parsed) -> Flags
  Flags(
    url: OP.optional_string(parsed, "url"),
    agent: OP.optional_string(parsed, "agent"),
    board: OP.optional_string(parsed, "board"),
    json: OP.flag(parsed, "json"),
  )
end

def load(flags: Flags) -> Result[Config]
  from_file = try file_settings()
  if from_file.get("agent").some?
    IO.warn("kanban: warning: the agent key of the config file is ignored; set KANBAN_AGENT or --agent")
  end

  ok(resolve(flags, environment(), from_file))
end

# Flags, then environment, then the file, then the default; the key has no flag.
# The agent name has no file value and no default: a name shared by every
# session would let two agents act as one, so only a flag or the environment
# names the agent.
def resolve(flags: Flags, env: Map[String, String], file: Map[String, String]) -> Config
  Config(
    url: pick(flags.url, env.get("KANBAN_URL"), file.get("url"), DEFAULT_URL),
    key: pick(none, env.get("KANBAN_API_KEY"), file.get("api_key"), ""),
    agent: pick(flags.agent, env.get("KANBAN_AGENT"), none, ""),
    board: pick(flags.board, env.get("KANBAN_BOARD"), file.get("board"), ""),
    json: flags.json,
  )
end

private

CONFIG_FILE = ".config/agc-kanban/config.toml"
DEFAULT_URL = "http://127.0.0.1:4580"
ENV_NAMES = ["KANBAN_URL", "KANBAN_API_KEY", "KANBAN_AGENT", "KANBAN_BOARD"]
FILE_NAMES = ["url", "api_key", "agent", "board"]

def pick(flag: Optional[String], env: Optional[String], file: Optional[String], default: String) -> String
  return flag.unwrap! if flag.some?
  return env.unwrap! if env.some?

  file.unwrap_or(default)
end

def environment() -> Map[String, String]
  found: Map[String, String] = {}
  for name in ENV_NAMES
    value = System.env(name)
    if value.ok?
      found = found.put(name, value.unwrap!)
    end
  end

  found
end

def file_settings() -> Result[Map[String, String]]
  home = System.env("HOME").unwrap_or("")
  path = "#{home}/#{CONFIG_FILE}"
  info = File.lstat(path)
  if not info.ok?
    return ok({}) if info.message == "filesystem: path does not exist"
    return error("cannot inspect config: #{info.message}")
  end

  text = try File.read_text(path)
  document = try Toml.parse(text)
  case document
    Toml.Value.Table(entries) -> collect(entries)
    _ -> error("config must be a table")
  end
end

def collect(entries: Map[String, Toml.Value]) -> Result[Map[String, String]]
  found: Map[String, String] = {}
  for name in FILE_NAMES
    case entries.get(name)
      none -> found = found
      some(Toml.Value.Str(value)) -> found = found.put(name, value)
      some(_) -> return error("config #{name} must be a string")
    end
  end

  ok(found)
end
