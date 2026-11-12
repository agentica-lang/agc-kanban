import OP from "std/option_parser"
import Client from "client"
import Output from "output"
import Settings from "settings"
import Support from "support"
import {Arg, Kind, Opt} from "std/option_parser"

struct ColumnLine
  id: Int
  name: String
  position: Int
  done: Bool
end

struct BoardInfo
  columns: List[ColumnLine]
end

struct SnapshotCard
  column: String
end

struct Snapshot
  board: BoardInfo
  cards: List[SnapshotCard]
end

struct ColumnAnswer
  column: ColumnLine
end

export def run(words: List[String]) -> Result[Void]
  return error("column needs a command: add, rename, move or remove") if words.empty?

  rest = List.drop(words, 1)
  case words[0]
    "add" -> add(rest)
    "rename" -> rename(rest)
    "move" -> move(rest)
    "remove" -> remove(rest)
    _ -> error("unknown column command #{words[0]}")
  end
end

def add(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban column add",
    "Add a column",
    [Arg(name: "name")],
    [Opt(name: "position", kind: Kind.Int), Opt(name: "done", kind: Kind.Flag), Opt(name: "wip", kind: Kind.Int)] +
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  Support.require_agent(config)
  board = Support.board_of(config)
  fields: Map[String, Json] = {"name": JSON.from(OP.string(parsed, "name"))}
  position = OP.optional_int(parsed, "position")
  if position.some?
    fields = fields.put("position", JSON.from(position.unwrap!))
  end

  if OP.flag(parsed, "done")
    fields = fields.put("done", JSON.from(true))
  end

  wip = OP.optional_int(parsed, "wip")
  if wip.some?
    fields = fields.put("wip_limit", JSON.from(wip.unwrap!))
  end

  client = Client.from(config)
  note: Optional[String] = none
  if OP.flag(parsed, "done")
    note = done_note(client, config)
  end

  response = Output.expect(
    Client.post(client, "/api/boards/#{board}/columns", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  print_column(config, response.unwrap!, "added")
  if note.some?
    IO.warn("kanban: warning: #{note.unwrap!}")
  end

  ok()
end

# Moving the done flag un-dones the cards that sat in the old done column; say
# so before it happens, since the answer cannot list them.
def done_note(client: Client.Client, config: Settings.Config) -> Optional[String]
  board = Support.board_of(config)
  response = Output.expect(Client.get(client, "/api/boards/#{board}"), config.json)
  return none if not response.ok?

  snapshot = JSON.decode(Output.body(response.unwrap!), Snapshot)
  return none if not snapshot.ok?

  data = snapshot.unwrap!
  done_name = ""
  for column in data.board.columns
    if column.done
      done_name = column.name
    end
  end

  return none if done_name.empty?

  affected = data.cards.select do |card| card.column == done_name end
  return none if affected.empty?

  count = affected.size
  return some("#{done_name} is no longer the done column; 1 card is no longer done") if count == 1

  some("#{done_name} is no longer the done column; #{count} cards are no longer done")
end

def rename(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban column rename",
    "Rename a column",
    [Arg(name: "column"), Arg(name: "name")],
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  Support.require_agent(config)
  client = Client.from(config)
  id = column_id(client, config, OP.string(parsed, "column"))
  body = JSON.encode(JSON.object({"name": JSON.from(OP.string(parsed, "name"))}))
  response = Output.expect(Client.patch(client, "/api/columns/#{id}", body), config.json)
  return ok() if not response.ok?

  print_column(config, response.unwrap!, "renamed")
  ok()
end

def move(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban column move",
    "Move a column to a position",
    [Arg(name: "column"), Arg(name: "position", kind: Kind.Int)],
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  Support.require_agent(config)
  client = Client.from(config)
  id = column_id(client, config, OP.string(parsed, "column"))
  body = JSON.encode(JSON.object({"position": JSON.from(OP.int(parsed, "position"))}))
  response = Output.expect(Client.patch(client, "/api/columns/#{id}", body), config.json)
  return ok() if not response.ok?

  print_column(config, response.unwrap!, "moved")
  ok()
end

def remove(words: List[String]) -> Result[Void]
  parser = OP.new("kanban column remove", "Remove an empty column", [Arg(name: "column")], Settings.common_opts())
  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  Support.require_agent(config)
  client = Client.from(config)
  name = OP.string(parsed, "column")
  id = column_id(client, config, name)
  response = Output.expect(Client.delete(client, "/api/columns/#{id}"), config.json)
  return ok() if not response.ok?

  if config.json
    puts(Output.body(response.unwrap!))
  else
    puts("removed\t#{name}")
  end

  ok()
end

def column_id(client: Client.Client, config: Settings.Config, reference: String) -> Int
  board = Support.board_of(config)
  response = Output.expect(Client.get(client, "/api/boards/#{board}"), config.json)
  return 0 if not response.ok?

  snapshot = JSON.decode(Output.body(response.unwrap!), Snapshot)
  if not snapshot.ok?
    Output.fail(config.json, "UNAVAILABLE", "invalid board answer", 3)
  end

  for column in snapshot.unwrap!.board.columns
    return column.id if column.name == reference or column.id.to_s == reference
  end

  Output.fail(config.json, "NOT_FOUND", "column not found: #{reference}", 1)
  0
end

def print_column(config: Settings.Config, response: HttpResponse, verb: String) -> Void
  if config.json
    puts(Output.body(response))
    return
  end

  decoded = JSON.decode(Output.body(response), ColumnAnswer)
  if not decoded.ok?
    puts(Output.body(response))
    return
  end

  column = decoded.unwrap!.column
  puts("#{verb}\t#{column.name}\t#{column.position}")
end
