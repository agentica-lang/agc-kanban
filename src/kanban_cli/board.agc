import OP from "std/option_parser"
import Client from "client"
import Output from "output"
import Settings from "settings"
import {Arg, Opt} from "std/option_parser"

struct BoardLine
  id: Int
  slug: String
  name: String
end

struct BoardAnswer
  board: BoardLine
end

export def run(words: List[String]) -> Result[Void]
  return error("board needs a command: list, create or show") if words.empty?

  rest = List.drop(words, 1)
  case words[0]
    "list" -> list(rest)
    "create" -> create(rest)
    "show" -> show(rest)
    _ -> error("unknown board command #{words[0]}")
  end
end

def list(words: List[String]) -> Result[Void]
  parser = OP.new("kanban board list", "List the boards", [], Settings.common_opts())
  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  response = Output.expect(Client.get(Client.from(config), "/api/boards"), config.json)
  return ok() if not response.ok?

  if config.json
    puts(Output.body(response.unwrap!))
  else
    Output.print_boards(response.unwrap!)
  end

  ok()
end

def create(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban board create",
    "Create a board",
    [Arg(name: "name")],
    [Opt(name: "slug"), Opt(name: "columns")] + Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  if config.agent.empty?
    Output.fail(config.json, "USAGE", "KANBAN_AGENT is required for writes", 2)
  end

  body = JSON.encode(JSON.object(payload(parsed, config)))
  response = Output.expect(Client.post(Client.from(config), "/api/boards", body), config.json)
  return ok() if not response.ok?

  answer = response.unwrap!
  if answer.status != 201
    Output.refuse(config.json, answer)
  end

  if config.json
    puts(Output.body(answer))
    return ok()
  end

  created = JSON.decode(Output.body(answer), BoardAnswer)
  if not created.ok?
    puts(Output.body(answer))
    return ok()
  end

  board = created.unwrap!.board
  puts("created\t#{board.slug}\t#{board.name}")
  ok()
end

def show(words: List[String]) -> Result[Void]
  parser = OP.new("kanban board show", "Show a board and its cards", [], Settings.common_opts(), "BOARD")
  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  requested = OP.rest(parsed)
  reference = config.board
  if not requested.empty?
    reference = requested[0]
  end

  if reference.empty?
    Output.fail(config.json, "USAGE", "board is required: pass BOARD or set KANBAN_BOARD", 2)
  end

  response = Output.expect(Client.get(Client.from(config), "/api/boards/#{reference}"), config.json)
  return ok() if not response.ok?

  if config.json
    puts(Output.body(response.unwrap!))
  else
    Output.print_board(response.unwrap!)
  end

  ok()
end

def payload(parsed: OP.Parsed, config: Settings.Config) -> Map[String, Json]
  fields: Map[String, Json] = {"name": JSON.from(OP.string(parsed, "name"))}
  # Creating the board the caller is configured for is the common case.
  slug = OP.optional_string(parsed, "slug")
  if slug.none? and not config.board.empty?
    slug = some(config.board)
  end

  if slug.some?
    fields = fields.put("slug", JSON.from(slug.unwrap!))
  end

  columns = OP.optional_string(parsed, "columns")
  if columns.some?
    values = columns.unwrap!.split(",").map do |value| value.strip end
    fields = fields.put("columns", JSON.from(values))
  end

  fields
end
