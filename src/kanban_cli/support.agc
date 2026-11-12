import OP from "std/option_parser"
import Output from "output"
import Settings from "settings"

# The checks and output every command repeats.

export def board_of(config: Settings.Config) -> String
  if config.board.empty?
    Output.fail(config.json, "USAGE", "board is required: pass --board or set KANBAN_BOARD", 2)
  end

  config.board
end

export def require_agent(config: Settings.Config) -> Void
  if config.agent.empty?
    Output.fail(config.json, "USAGE", "KANBAN_AGENT is required for writes", 2)
  end
end

export def put(fields: Map[String, Json], name: String, value: Optional[String]) -> Map[String, Json]
  case value
    none -> fields
    some(text) -> fields.put(name, JSON.from(text))
  end
end

export def force(fields: Map[String, Json], parsed: OP.Parsed) -> Map[String, Json]
  return fields if not OP.flag(parsed, "force")

  fields.put("force", JSON.from(true))
end

export def print_card(config: Settings.Config, response: HttpResponse) -> Void
  if config.json
    puts(Output.body(response))
    return
  end

  Output.print_card(response)
end
