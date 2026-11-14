import HTTP from "std/http"
import OP from "std/option_parser"
import Client from "client"
import Output from "output"
import Settings from "settings"
import Support from "support"
import {Arg, Opt} from "std/option_parser"

def run(words: List[String]) -> Result[Void]
  return error("label needs a command: list or update") if words.empty?

  rest = List.drop(words, 1)
  case words[0]
    "list" -> list(rest)
    "update" -> update(rest)
    _ -> error("unknown label command #{words[0]}")
  end
end

private

struct LabelLine
  id: Int
  name: String
  color: String
end

struct LabelsAnswer
  labels: List[LabelLine]
end

struct LabelAnswer
  label: LabelLine
end

def list(words: List[String]) -> Result[Void]
  parser = OP.new("kanban label list", "List the labels of a board with their colors", [], Settings.common_opts())
  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  board = Support.board_of(config)
  response = Output.expect(Client.get(Client.from(config), "/api/boards/#{board}/labels"), config.json)
  return ok() if not response.ok?

  if config.json
    puts(Output.body(response.unwrap!))
    return ok()
  end

  for label in decode_all(config, response.unwrap!)
    puts("#{label.name}\t#{label.color}")
  end

  ok()
end

def update(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban label update",
    "Change the color or the name of a label (a rename changes the cards that carry it)",
    [Arg(name: "label")],
    [Opt(name: "color"), Opt(name: "name")] + Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  Support.require_agent(config)
  color = OP.optional_string(parsed, "color")
  renamed = OP.optional_string(parsed, "name")
  return error("label update needs --color or --name") if not color.some? and not renamed.some?

  client = Client.from(config)
  id = label_id(client, config, OP.string(parsed, "label"))
  fields: Map[String, JSON.Value] = {}
  fields = Support.put(Support.put(fields, "color", color), "name", renamed)
  response = Output.expect(Client.patch(client, "/api/labels/#{id}", JSON.encode(JSON.object(fields))), config.json)

  return ok() if not response.ok?

  if config.json
    puts(Output.body(response.unwrap!))
    return ok()
  end

  decoded = JSON.decode(Output.body(response.unwrap!), LabelAnswer)
  if not decoded.ok?
    Output.fail(false, "UNAVAILABLE", "invalid label answer", 3)
  end

  label = decoded.unwrap!.label
  puts("updated\t#{label.name}\t#{label.color}")
  ok()
end

def decode_all(config: Settings.Config, response: HTTP.Response) -> List[LabelLine]
  decoded = JSON.decode(Output.body(response), LabelsAnswer)
  if not decoded.ok?
    Output.fail(config.json, "UNAVAILABLE", "invalid labels answer", 3)
    return []
  end

  decoded.unwrap!.labels
end

def label_id(client: Client.Client, config: Settings.Config, name: String) -> Int
  board = Support.board_of(config)
  response = Output.expect(Client.get(client, "/api/boards/#{board}/labels"), config.json)
  return 0 if not response.ok?

  for label in decode_all(config, response.unwrap!)
    return label.id if label.name == name
  end

  Output.fail(config.json, "NOT_FOUND", "label not found: #{name}", 1)
  0
end
