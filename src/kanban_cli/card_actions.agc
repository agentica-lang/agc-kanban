import OP from "std/option_parser"
import Client from "client"
import Input from "input"
import Output from "output"
import Settings from "settings"
import Support from "support"
import {Arg, Kind, Opt} from "std/option_parser"

struct FreeCard
  claimed_by: Optional[String]
end

struct FreeAnswer
  card: FreeCard
end

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
  Support.require_agent(config)
  response = Output.expect(
    Client.post(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}/claim", "{}"),
    config.json,
  )

  return ok() if not response.ok?

  Support.print_card(config, response.unwrap!)
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
  Support.require_agent(config)
  board = Support.board_of(config)
  fields: Map[String, Json] = {}
  fields = Support.put(fields, "column", OP.optional_string(parsed, "column"))
  fields = Support.put(fields, "label", OP.optional_string(parsed, "label"))
  response = Output.expect(
    Client.post(Client.from(config), "/api/boards/#{board}/claim-next", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  Support.print_card(config, response.unwrap!)
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
  Support.require_agent(config)
  fields: Map[String, Json] = {}
  fields = Support.put(fields, "column", OP.optional_string(parsed, "to"))
  fields = Support.force(fields, parsed)
  client = Client.from(config)
  id = OP.int(parsed, "id")
  answer = Output.answered(
    Client.post(client, "/api/cards/#{id}/release", JSON.encode(JSON.object(fields))),
    config.json,
  )

  if answer.status >= 200 and answer.status <= 299
    Support.print_card(config, answer)
    return ok()
  end

  # Releasing a card nobody holds is already what the caller wanted; only a
  # card held by another agent is a refusal.
  if Output.code_of(answer) == some("NOT_CLAIMER") and not held?(client, config, id)
    print_already_free(config, client, id)
    return ok()
  end

  Output.refuse(config.json, answer)
  ok()
end

def held?(client: Client.Client, config: Settings.Config, id: Int) -> Bool
  response = Output.expect(Client.get(client, "/api/cards/#{id}"), config.json)
  return true if not response.ok?

  decoded = JSON.decode(Output.body(response.unwrap!), FreeAnswer)
  return true if not decoded.ok?

  decoded.unwrap!.card.claimed_by.some?
end

def print_already_free(config: Settings.Config, client: Client.Client, id: Int) -> Void
  if config.json
    puts(Output.body(Output.answered(Client.get(client, "/api/cards/#{id}"), config.json)))
    return
  end

  puts("released\t#{id}\talready free")
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
  Support.require_agent(config)
  fields: Map[String, Json] = {"column": JSON.from(OP.string(parsed, "column"))}
  position = OP.optional_int(parsed, "position")
  if position.some?
    fields = fields.put("position", JSON.from(position.unwrap!))
  end

  fields = Support.force(fields, parsed)
  response = Output.expect(
    Client.post(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}/move", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  Support.print_card(config, response.unwrap!)
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
  Support.require_agent(config)
  fields: Map[String, Json] = {}
  fields = Support.force(fields, parsed)
  response = Output.expect(
    Client.post(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}/done", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  Support.print_card(config, response.unwrap!)
  ok()
end

def comment(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban card comment",
    "Comment on a card",
    [Arg(name: "id", kind: Kind.Int)],
    [Opt(name: "file")] + Settings.common_opts(),
    "TEXT",
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  Support.require_agent(config)
  rest = OP.rest(parsed)
  text: Optional[String] = none
  if not rest.empty?
    text = some(rest.join(" "))
  end

  body = try Input.text(text, OP.optional_string(parsed, "file"))
  if body.none?
    Output.fail(config.json, "USAGE", "a comment needs text or --file", 2)
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
  Support.require_agent(config)
  body = JSON.encode(JSON.object({"depends_on": JSON.from(OP.int(parsed, "depends-on"))}))
  response = Output.expect(
    Client.post(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}/deps", body),
    config.json,
  )

  return ok() if not response.ok?

  Support.print_card(config, response.unwrap!)
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
  Support.require_agent(config)
  response = Output.expect(
    Client.delete(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}/deps/#{OP.int(parsed, "depends-on")}"),
    config.json,
  )

  return ok() if not response.ok?

  Support.print_card(config, response.unwrap!)
  ok()
end
