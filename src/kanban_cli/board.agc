import OP from "std/option_parser"
import Client from "client"
import Output from "output"
import Settings from "settings"
import Support from "support"
import {Arg, Kind, Opt} from "std/option_parser"

def run(words: List[String]) -> Result[Void]
  return error("board needs a command: list, create, show, archive-done or auto-archive") if words.empty?

  rest = List.drop(words, 1)
  case words[0]
    "list" -> list(rest)
    "create" -> create(rest)
    "show" -> show(rest)
    "archive-done" -> archive_done(rest)
    "auto-archive" -> auto_archive(rest)
    _ -> error("unknown board command #{words[0]}")
  end
end

private

struct BoardLine
  id: Int
  slug: String
  name: String
end

struct BoardAnswer
  board: BoardLine
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
  Support.require_agent(config)

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

# Archives the cards of the done columns that were done at least --days days ago (3 by default). The summary line is
# the only output; with --json it is the server answer, which lists the ids.
def archive_done(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban board archive-done",
    "Archive the done cards that were done at least DAYS days ago",
    [],
    [Opt(name: "days", kind: Kind.Int, default: "3", help: "0 archives every done card")] + Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  Support.require_agent(config)
  board = Support.board_of(config)
  fields: Map[String, JSON.Value] = {"days": JSON.from(OP.int(parsed, "days"))}
  response = Output.expect(
    Client.post(Client.from(config), "/api/boards/#{board}/archive-done", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  if config.json
    puts(Output.body(response.unwrap!))
  else
    Output.print_archived_done(response.unwrap!)
  end

  ok()
end

# Turns the automatic archive of the board on (--days N: the server archives the done cards that were done N days ago,
# checking every ten minutes) or off (--off). It is off by default.
def auto_archive(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban board auto-archive",
    "Archive the done cards of the board by itself after DAYS days, or stop doing it",
    [],
    [
      Opt(name: "days", kind: Kind.Int, help: "1 to 36500"),
      Opt(name: "off", kind: Kind.Flag, help: "stop archiving by itself"),
    ] +
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  Support.require_agent(config)
  days = OP.optional_int(parsed, "days")
  if days.some? == OP.flag(parsed, "off")
    Output.fail(config.json, "USAGE", "pass --days N or --off", 2)
  end

  board = Support.board_of(config)
  fields: Map[String, JSON.Value] = {"days": JSON.from(days)}
  response = Output.expect(
    Client.post(Client.from(config), "/api/boards/#{board}/auto-archive", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  if config.json
    puts(Output.body(response.unwrap!))
  else
    Output.print_auto_archive(response.unwrap!)
  end

  ok()
end

def payload(parsed: OP.Parsed, config: Settings.Config) -> Map[String, JSON.Value]
  fields: Map[String, JSON.Value] = {"name": JSON.from(OP.string(parsed, "name"))}
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
