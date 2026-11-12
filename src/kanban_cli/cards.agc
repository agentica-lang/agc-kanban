import OP from "std/option_parser"
import URI from "std/uri"
import Client from "client"
import Input from "input"
import Output from "output"
import Settings from "settings"
import {Arg, Kind, Opt} from "std/option_parser"
import {Pair} from "std/uri"

export def run(words: List[String]) -> Result[Void]
  return error("card needs a command: add, list, show or update") if words.empty?

  rest = List.drop(words, 1)
  case words[0]
    "add" -> add(rest)
    "list" -> list(rest)
    "show" -> show(rest)
    "update" -> update(rest)
    _ -> error("unknown card command #{words[0]}")
  end
end

def add(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban card add",
    "Create a card",
    [Arg(name: "title")],
    [
      Opt(name: "body"),
      Opt(name: "body-file"),
      Opt(name: "column"),
      Opt(name: "label"),
      Opt(name: "priority", kind: Kind.Int),
      Opt(name: "depends-on"),
    ] +
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  require_agent(config)
  board = board_of(config)
  body = try Input.text(OP.optional_string(parsed, "body"), OP.optional_string(parsed, "body-file"))
  fields: Map[String, Json] = {"title": JSON.from(OP.string(parsed, "title"))}
  fields = put(fields, "body", body)
  fields = put(fields, "column", OP.optional_string(parsed, "column"))
  labels = Input.csv(OP.optional_string(parsed, "label"))
  if not labels.empty?
    fields = fields.put("labels", JSON.from(labels))
  end

  priority = OP.optional_int(parsed, "priority")
  if priority.some?
    fields = fields.put("priority", JSON.from(priority.unwrap!))
  end

  depends_on = try Input.ids(OP.optional_string(parsed, "depends-on"))
  if not depends_on.empty?
    fields = fields.put("depends_on", JSON.from(depends_on))
  end

  response = Output.expect(
    Client.post(Client.from(config), "/api/boards/#{board}/cards", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  print_card(config, response.unwrap!)
  ok()
end

def list(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban card list",
    "List the cards of a board",
    [],
    [
      Opt(name: "column"),
      Opt(name: "ready", kind: Kind.Flag),
      Opt(name: "mine", kind: Kind.Flag),
      Opt(name: "claimed-by"),
      Opt(name: "label"),
      Opt(name: "all", kind: Kind.Flag),
    ] +
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  board = board_of(config)
  pairs: List[Pair] = []
  column = OP.optional_string(parsed, "column")
  if column.some?
    pairs = pairs.push(Pair(name: "column", value: column.unwrap!))
  end

  if OP.flag(parsed, "ready")
    pairs = pairs.push(Pair(name: "ready", value: "1"))
  end

  claimed = OP.optional_string(parsed, "claimed-by")
  if OP.flag(parsed, "mine")
    if config.agent.empty?
      Output.fail(config.json, "INVALID", "--mine needs KANBAN_AGENT or --agent", 2)
    end

    claimed = some(config.agent)
  end

  if claimed.some?
    pairs = pairs.push(Pair(name: "claimed_by", value: claimed.unwrap!))
  end

  label = OP.optional_string(parsed, "label")
  if label.some?
    pairs = pairs.push(Pair(name: "label", value: label.unwrap!))
  end

  if not OP.flag(parsed, "all")
    pairs = pairs.push(Pair(name: "done", value: "0"))
  end

  path = "/api/boards/#{board}/cards"
  if not pairs.empty?
    path = "#{path}?#{URI.encode_www_form(pairs)}"
  end

  response = Output.expect(Client.get(Client.from(config), path), config.json)
  return ok() if not response.ok?

  if config.json
    puts(Output.body(response.unwrap!))
  else
    Output.print_cards(response.unwrap!)
  end

  ok()
end

def show(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban card show",
    "Show a card with its comments",
    [Arg(name: "id", kind: Kind.Int)],
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  response = Output.expect(Client.get(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}"), config.json)
  return ok() if not response.ok?

  if config.json
    puts(Output.body(response.unwrap!))
  else
    Output.print_card_detail(response.unwrap!)
  end

  ok()
end

def update(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban card update",
    "Change the fields of a card",
    [Arg(name: "id", kind: Kind.Int)],
    [
      Opt(name: "title"),
      Opt(name: "body"),
      Opt(name: "body-file"),
      Opt(name: "label"),
      Opt(name: "priority", kind: Kind.Int),
      Opt(name: "branch"),
      Opt(name: "worktree"),
      Opt(name: "force", kind: Kind.Flag),
    ] +
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  require_agent(config)
  body = try Input.text(OP.optional_string(parsed, "body"), OP.optional_string(parsed, "body-file"))
  fields: Map[String, Json] = {}
  fields = put(fields, "title", OP.optional_string(parsed, "title"))
  fields = put(fields, "body", body)
  fields = put(fields, "branch", OP.optional_string(parsed, "branch"))
  fields = put(fields, "worktree", OP.optional_string(parsed, "worktree"))
  labels = Input.csv(OP.optional_string(parsed, "label"))
  if not labels.empty?
    fields = fields.put("labels", JSON.from(labels))
  end

  priority = OP.optional_int(parsed, "priority")
  if priority.some?
    fields = fields.put("priority", JSON.from(priority.unwrap!))
  end

  if OP.flag(parsed, "force")
    fields = fields.put("force", JSON.from(true))
  end

  if fields.empty?
    Output.fail(config.json, "INVALID", "nothing to update: pass a field", 2)
  end

  response = Output.expect(
    Client.patch(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  print_card(config, response.unwrap!)
  ok()
end

def print_card(config: Settings.Config, response: HttpResponse) -> Void
  if config.json
    puts(Output.body(response))
    return
  end

  Output.print_card(response)
end

def put(fields: Map[String, Json], name: String, value: Optional[String]) -> Map[String, Json]
  case value
    none -> fields
    some(text) -> fields.put(name, JSON.from(text))
  end
end

def board_of(config: Settings.Config) -> String
  if config.board.empty?
    Output.fail(config.json, "INVALID", "board is required: pass --board or set KANBAN_BOARD", 2)
  end

  config.board
end

def require_agent(config: Settings.Config) -> Void
  if config.agent.empty?
    Output.fail(config.json, "INVALID", "KANBAN_AGENT is required for writes", 2)
  end
end
