import HTTP from "std/http"
import OP from "std/option_parser"
import Output from "output"
import Settings from "settings"

# The checks and output every command repeats.

def board_of(config: Settings.Config) -> String
  if config.board.empty?
    Output.fail(config.json, "USAGE", "board is required: pass --board or set KANBAN_BOARD", 2)
  end

  config.board
end

# Every command that acts as an agent needs a name from --agent or KANBAN_AGENT;
# the name never has a default, so the coordinator must give each agent its own.
def require_agent(config: Settings.Config) -> Void
  if config.agent.empty?
    Output.fail(config.json, "USAGE", "no agent name; ask your coordinator, then set KANBAN_AGENT or --agent", 2)
  end
end

def put(fields: Map[String, JSON.Value], name: String, value: Optional[String]) -> Map[String, JSON.Value]
  case value
    none -> fields
    some(text) -> fields.put(name, JSON.from(text))
  end
end

def force(fields: Map[String, JSON.Value], parsed: OP.Parsed) -> Map[String, JSON.Value]
  return fields if not OP.flag(parsed, "force")

  fields.put("force", JSON.from(true))
end

def print_card(config: Settings.Config, response: HTTP.Response) -> Void
  if config.json
    puts(Output.body(response))
    return
  end

  Output.print_card(response)
end
