import OP from "std/option_parser"
import URI from "std/uri"
import Client from "client"
import Output from "output"
import Settings from "settings"
import Support from "support"
import {Pair} from "std/uri"
import {Kind, Opt} from "std/option_parser"

def run(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban events",
    "Read the board journal",
    [],
    [
      Opt(name: "after", kind: Kind.Int),
      Opt(name: "before", kind: Kind.Int),
      Opt(name: "card", kind: Kind.Int),
      Opt(name: "limit", kind: Kind.Int),
    ] +
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  board = Support.board_of(config)
  pairs: List[Pair] = []
  after = OP.optional_int(parsed, "after")
  if after.some?
    pairs = pairs.push(Pair(name: "after", value: after.unwrap!.to_s))
  end

  before = OP.optional_int(parsed, "before")
  if before.some?
    pairs = pairs.push(Pair(name: "before", value: before.unwrap!.to_s))
  end

  card = OP.optional_int(parsed, "card")
  if card.some?
    pairs = pairs.push(Pair(name: "card", value: card.unwrap!.to_s))
  end

  limit = OP.optional_int(parsed, "limit")
  if limit.some?
    pairs = pairs.push(Pair(name: "limit", value: limit.unwrap!.to_s))
  end

  path = "/api/boards/#{board}/events"
  if not pairs.empty?
    path = "#{path}?#{URI.encode_www_form(pairs)}"
  end

  response = Output.expect(Client.get(Client.from(config), path), config.json)
  return ok() if not response.ok?

  if config.json
    puts(Output.body(response.unwrap!))
  else
    Output.print_events(response.unwrap!)
  end

  ok()
end
