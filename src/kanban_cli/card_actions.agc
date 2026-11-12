import OP from "std/option_parser"
import Client from "client"
import Input from "input"
import Output from "output"
import Settings from "settings"
import {Arg, Kind, Opt} from "std/option_parser"

export def run(words: List[String]) -> Result[Void]
  return error("card needs a command") if words.empty?

  rest = List.drop(words, 1)
  case words[0]
    "claim" -> claim(rest)
    "next" -> next(rest)
    "release" -> release(rest)
    "move" -> move(rest)
    "done" -> done(rest)
    "comment" -> comment(rest)
    "dep" -> dep(rest)
    _ -> error("unknown card action #{words[0]}")
  end
end

def claim(words: List[String]) -> Result[Void]
  parser = OP.new("kanban card claim", "Claim a card", [Arg(name: "id", kind: Kind.Int)], Settings.common_opts())
  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  require_agent(config)
  response = Output.expect(
    Client.post(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}/claim", "{}"),
    config.json,
  )

  return ok() if not response.ok?

  print_card(config, response.unwrap!)
  ok()
end

def next(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban card next",
    "Claim the first ready card",
    [],
    [Opt(name: "column"), Opt(name: "label")] + Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  require_agent(config)
  board = board_of(config)
  fields: Map[String, Json] = {}
  fields = put(fields, "column", OP.optional_string(parsed, "column"))
  fields = put(fields, "label", OP.optional_string(parsed, "label"))
  response = Output.expect(
    Client.post(Client.from(config), "/api/boards/#{board}/claim-next", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  print_card(config, response.unwrap!)
  ok()
end

def release(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban card release",
    "Release a claim",
    [Arg(name: "id", kind: Kind.Int)],
    [Opt(name: "to"), Opt(name: "force", kind: Kind.Flag)] + Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  require_agent(config)
  fields: Map[String, Json] = {}
  fields = put(fields, "column", OP.optional_string(parsed, "to"))
  fields = force(fields, parsed)
  response = Output.expect(
    Client.post(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}/release", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  print_card(config, response.unwrap!)
  ok()
end

def move(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban card move",
    "Move a card to a column",
    [Arg(name: "id", kind: Kind.Int), Arg(name: "column")],
    [Opt(name: "position", kind: Kind.Int), Opt(name: "force", kind: Kind.Flag)] + Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  require_agent(config)
  fields: Map[String, Json] = {"column": JSON.from(OP.string(parsed, "column"))}
  position = OP.optional_int(parsed, "position")
  if position.some?
    fields = fields.put("position", JSON.from(position.unwrap!))
  end

  fields = force(fields, parsed)
  response = Output.expect(
    Client.post(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}/move", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  print_card(config, response.unwrap!)
  ok()
end

def done(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban card done",
    "Finish a card",
    [Arg(name: "id", kind: Kind.Int)],
    [Opt(name: "force", kind: Kind.Flag)] + Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  require_agent(config)
  fields: Map[String, Json] = {}
  fields = force(fields, parsed)
  response = Output.expect(
    Client.post(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}/done", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  print_card(config, response.unwrap!)
  ok()
end

def comment(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban card comment",
    "Comment on a card",
    [Arg(name: "id", kind: Kind.Int), Arg(name: "text")],
    [Opt(name: "file")] + Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  require_agent(config)
  text = some(OP.string(parsed, "text"))
  if OP.optional_string(parsed, "file").some?
    text = none
  end

  body = try Input.text(text, OP.optional_string(parsed, "file"))
  if body.none?
    Output.fail(config.json, "INVALID", "a comment needs text or --file", 2)
  end

  fields: Map[String, Json] = {"body": JSON.from(body.unwrap!)}
  response = Output.expect(
    Client.post(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}/comments", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  if config.json
    puts(Output.body(response.unwrap!))
  else
    Output.print_comment(response.unwrap!)
  end

  ok()
end

def dep(words: List[String]) -> Result[Void]
  return error("card dep needs add or remove") if words.empty?

  rest = List.drop(words, 1)
  case words[0]
    "add" -> dep_add(rest)
    "remove" -> dep_remove(rest)
    _ -> error("unknown card dep command #{words[0]}")
  end
end

def dep_add(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban card dep add",
    "Make a card depend on another",
    [Arg(name: "id", kind: Kind.Int), Arg(name: "depends-on", kind: Kind.Int)],
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  require_agent(config)
  body = JSON.encode(JSON.object({"depends_on": JSON.from(OP.int(parsed, "depends-on"))}))
  response = Output.expect(
    Client.post(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}/deps", body),
    config.json,
  )

  return ok() if not response.ok?

  print_card(config, response.unwrap!)
  ok()
end

def dep_remove(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban card dep remove",
    "Remove a dependency",
    [Arg(name: "id", kind: Kind.Int), Arg(name: "depends-on", kind: Kind.Int)],
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  require_agent(config)
  response = Output.expect(
    Client.delete(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}/deps/#{OP.int(parsed, "depends-on")}"),
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

def force(fields: Map[String, Json], parsed: OP.Parsed) -> Map[String, Json]
  return fields if not OP.flag(parsed, "force")

  fields.put("force", JSON.from(true))
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
