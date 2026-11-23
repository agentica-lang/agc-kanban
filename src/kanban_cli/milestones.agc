import HTTP from "std/http"
import OP from "std/option_parser"
import Client from "client"
import Output from "output"
import Settings from "settings"
import Support from "support"
import {Arg, Kind, Opt} from "std/option_parser"

def run(words: List[String]) -> Result[Void]
  return error("milestone needs a command: list, create, update, close, reopen or remove") if words.empty?

  rest = List.drop(words, 1)
  case words[0]
    "list" -> list(rest)
    "create" -> create(rest)
    "update" -> update(rest)
    "close" -> change_state(rest, "close", "closed", "closed")
    "reopen" -> change_state(rest, "reopen", "open", "reopened")
    "remove" -> remove(rest)
    _ -> error("unknown milestone command #{words[0]}")
  end
end

private

struct MilestoneLine
  id: Int
  name: String
  due_on: Optional[String]
  state: String
  open: Int
  closed: Int
  percent: Int
end

struct MilestoneAnswer
  milestone: MilestoneLine
end

struct MilestonesAnswer
  milestones: List[MilestoneLine]
end

def list(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban milestone list",
    "List the milestones of a board with their percent complete (state: open, closed or all)",
    [],
    [Opt(name: "state", default: "open")] + Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  board = Support.board_of(config)
  state = OP.string(parsed, "state")
  response = Output.expect(
    Client.get(Client.from(config), "/api/boards/#{board}/milestones?state=#{state}"),
    config.json,
  )

  return ok() if not response.ok?

  if config.json
    puts(Output.body(response.unwrap!))
    return ok()
  end

  for milestone in decode_all(config, response.unwrap!)
    puts(line(milestone))
  end

  ok()
end

def create(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban milestone create",
    "Flag a label as a milestone (the label is made when no card has it yet)",
    [Arg(name: "name")],
    [Opt(name: "description"), Opt(name: "due")] + Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  Support.require_agent(config)
  board = Support.board_of(config)
  fields: Map[String, JSON.Value] = {"name": JSON.from(OP.string(parsed, "name"))}
  fields = Support.put(
    Support.put(fields, "description", OP.optional_string(parsed, "description")),
    "due_on",
    OP.optional_string(parsed, "due"),
  )

  body = JSON.encode(JSON.object(fields))
  response = Output.expect(Client.post(Client.from(config), "/api/boards/#{board}/milestones", body), config.json)
  return ok() if not response.ok?

  print_one(config, response.unwrap!, "created")
  ok()
end

def update(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban milestone update",
    "Change the description or the due date of a milestone",
    [Arg(name: "milestone")],
    [Opt(name: "description"), Opt(name: "due"), Opt(name: "no-due", kind: Kind.Flag)] + Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  Support.require_agent(config)
  description = OP.optional_string(parsed, "description")
  due = OP.optional_string(parsed, "due")
  no_due = OP.flag(parsed, "no-due")
  if not description.some? and not due.some? and not no_due
    return error("milestone update needs --description, --due or --no-due")
  end

  if due.some? and due.unwrap!.empty?
    return error("milestone update --due needs a date: YYYY-MM-DD (--no-due clears it)")
  end

  return error("milestone update takes --due or --no-due, not both") if due.some? and no_due

  if no_due
    due = some("")
  end

  fields = Support.put(Support.put({}, "description", description), "due_on", due)
  patch(config, OP.string(parsed, "milestone"), fields, "updated")
end

def change_state(words: List[String], command: String, state: String, verb: String) -> Result[Void]
  parser = OP.new(
    "kanban milestone #{command}",
    "Set a milestone to #{state} (a closed one leaves the default list)",
    [Arg(name: "milestone")],
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  Support.require_agent(config)
  patch(config, OP.string(parsed, "milestone"), {"state": JSON.from(state)}, verb)
end

def remove(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban milestone remove",
    "Unflag a milestone (the label and the cards keep it)",
    [Arg(name: "milestone")],
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  Support.require_agent(config)
  client = Client.from(config)
  name = OP.string(parsed, "milestone")
  id = milestone_id(client, config, name)
  response = Output.expect(Client.delete(client, "/api/milestones/#{id}"), config.json)
  return ok() if not response.ok?

  if config.json
    puts(Output.body(response.unwrap!))
  else
    puts("removed\t#{name}")
  end

  ok()
end

def patch(config: Settings.Config, name: String, fields: Map[String, JSON.Value], verb: String) -> Result[Void]
  client = Client.from(config)
  id = milestone_id(client, config, name)
  response = Output.expect(
    Client.patch(client, "/api/milestones/#{id}", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  print_one(config, response.unwrap!, verb)
  ok()
end

def print_one(config: Settings.Config, response: HTTP.Response, verb: String) -> Void
  if config.json
    puts(Output.body(response))
    return
  end

  decoded = JSON.decode(Output.body(response), MilestoneAnswer)
  if not decoded.ok?
    Output.fail(false, "UNAVAILABLE", "invalid milestone answer", 3)
  end

  puts("#{verb}\t#{line(decoded.unwrap!.milestone)}")
end

def line(milestone: MilestoneLine) -> String
  due = milestone.due_on.unwrap_or("-")
  (
    "#{milestone.name}\t#{milestone.percent}%\t#{milestone.open} open\t#{milestone.closed} closed\t#{due}\t#{milestone.state}"
  )
end

def decode_all(config: Settings.Config, response: HTTP.Response) -> List[MilestoneLine]
  decoded = JSON.decode(Output.body(response), MilestonesAnswer)
  if not decoded.ok?
    Output.fail(config.json, "UNAVAILABLE", "invalid milestones answer", 3)
    return []
  end

  decoded.unwrap!.milestones
end

def milestone_id(client: Client.Client, config: Settings.Config, name: String) -> Int
  board = Support.board_of(config)
  response = Output.expect(Client.get(client, "/api/boards/#{board}/milestones?state=all"), config.json)
  return 0 if not response.ok?

  for milestone in decode_all(config, response.unwrap!)
    return milestone.id if milestone.name == name
  end

  Output.fail(config.json, "NOT_FOUND", "milestone not found: #{name}", 1)
  0
end
