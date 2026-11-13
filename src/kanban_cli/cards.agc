import HTTP from "std/http"
import OP from "std/option_parser"
import URI from "std/uri"
import Client from "client"
import Input from "input"
import Output from "output"
import Settings from "settings"
import Support from "support"
import {Arg, Kind, Opt} from "std/option_parser"
import {Pair} from "std/uri"

export def run(words: List[String]) -> Result[Void]
  if words.empty?
    return error(
      "card needs a command: add, list, search, show, update, claim, next, release, move, done, archive, comment or dep",
    )
  end

  rest = List.drop(words, 1)
  case words[0]
    "add" -> add(rest)
    "list" -> list(rest)
    "show" -> show(rest)
    "update" -> update(rest)
    "search" -> search(rest)
    _ -> error("unknown card command #{words[0]}")
  end
end

def add(words: List[String]) -> Result[Void]
  opts = [
    Opt(name: "body"),
    Opt(name: "body-file"),
    Opt(name: "column"),
    Opt(name: "label"),
    Opt(name: "priority", kind: Kind.Int),
    Opt(name: "depends-on"),
    Opt(name: "link", help: "a URL to link, repeatable"),
  ].concat(Settings.common_opts())

  parser = OP.new("kanban card add", "Create a card", [Arg(name: "title")], opts)
  links = try Input.repeated(words, "link", opts)
  parsed = try OP.parse(parser, links.rest)
  config = try Settings.load(Settings.read_flags(parsed))
  Support.require_agent(config)
  board = Support.board_of(config)
  body = try Input.text(OP.optional_string(parsed, "body"), OP.optional_string(parsed, "body-file"))
  fields: Map[String, Json] = {"title": JSON.from(OP.string(parsed, "title"))}
  fields = Support.put(fields, "body", body)
  fields = Support.put(fields, "column", OP.optional_string(parsed, "column"))
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

  if not links.values.empty?
    fields = fields.put("links", JSON.from(links.values))
  end

  response = Output.expect(
    Client.post(Client.from(config), "/api/boards/#{board}/cards", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  require_links(config, response.unwrap!, not links.values.empty?)
  Support.print_card(config, response.unwrap!)
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
      Opt(
        name: "format",
        default: "text",
        choices: ["text", "tsv"],
        help: "text lines, or tsv: one card per line, tab-separated",
      ),
    ] +
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  tsv = OP.string(parsed, "format") == "tsv"
  # --json prints the server document and tsv a table: one run cannot print both, so it is refused, not guessed.
  if tsv and config.json
    Output.fail(config.json, "USAGE", "--format tsv cannot be used with --json", 2)
  end

  board = Support.board_of(config)
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
    Support.require_agent(config)
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
  elsif tsv
    Output.print_cards_tsv(response.unwrap!)
  else
    Output.print_cards(response.unwrap!)
  end

  ok()
end

# Read-only, so it needs no agent name. The order is the server's: best match first.
def search(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban card search",
    "Find the cards of a board by their title, body, labels and comments, best match first",
    [Arg(name: "query")],
    [
      Opt(name: "all", kind: Kind.Flag, help: "include the cards in a done column"),
      Opt(name: "limit", kind: Kind.Int, default: "20", help: "at most this many cards (1 to 100)"),
    ] +
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  board = Support.board_of(config)
  pairs = [
    Pair(name: "q", value: OP.string(parsed, "query")),
    Pair(name: "limit", value: OP.int(parsed, "limit").to_s),
  ]

  if OP.flag(parsed, "all")
    pairs = pairs.push(Pair(name: "all", value: "1"))
  end

  path = "/api/boards/#{board}/search?#{URI.encode_www_form(pairs)}"
  response = Output.expect(Client.get(Client.from(config), path), config.json)
  return ok() if not response.ok?

  if config.json
    puts(Output.body(response.unwrap!))
  else
    Output.print_hits(response.unwrap!)
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
  opts = [
    Opt(name: "title"),
    Opt(name: "body"),
    Opt(name: "body-file"),
    Opt(name: "label"),
    Opt(name: "priority", kind: Kind.Int),
    Opt(name: "branch"),
    Opt(name: "worktree"),
    Opt(name: "force", kind: Kind.Flag),
    Opt(name: "link", help: "a URL to link, repeatable"),
    Opt(name: "unlink", help: "a linked URL to remove, repeatable"),
  ].concat(Settings.common_opts())

  parser = OP.new("kanban card update", "Change the fields of a card", [Arg(name: "id", kind: Kind.Int)], opts)
  links = try Input.repeated(words, "link", opts)
  unlinks = try Input.repeated(links.rest, "unlink", opts)
  parsed = try OP.parse(parser, unlinks.rest)
  config = try Settings.load(Settings.read_flags(parsed))
  Support.require_agent(config)
  body = try Input.text(OP.optional_string(parsed, "body"), OP.optional_string(parsed, "body-file"))
  fields: Map[String, Json] = {}
  fields = Support.put(fields, "title", OP.optional_string(parsed, "title"))
  fields = Support.put(fields, "body", body)
  fields = Support.put(fields, "branch", OP.optional_string(parsed, "branch"))
  fields = Support.put(fields, "worktree", OP.optional_string(parsed, "worktree"))
  labels = Input.csv(OP.optional_string(parsed, "label"))
  if not labels.empty?
    fields = fields.put("labels", JSON.from(labels))
  end

  priority = OP.optional_int(parsed, "priority")
  if priority.some?
    fields = fields.put("priority", JSON.from(priority.unwrap!))
  end

  if not links.values.empty?
    fields = fields.put("link", JSON.from(links.values))
  end

  if not unlinks.values.empty?
    fields = fields.put("unlink", JSON.from(unlinks.values))
  end

  if OP.flag(parsed, "force")
    fields = fields.put("force", JSON.from(true))
  end

  if fields.empty?
    Output.fail(config.json, "USAGE", "nothing to update: pass a field", 2)
  end

  response = Output.expect(
    Client.patch(Client.from(config), "/api/cards/#{OP.int(parsed, "id")}", JSON.encode(JSON.object(fields))),
    config.json,
  )

  return ok() if not response.ok?

  require_links(config, response.unwrap!, not (links.values.empty? and unlinks.values.empty?))
  Support.print_card(config, response.unwrap!)
  ok()
end

# A server older than links answers the write and drops the links it does not know; that is no silent success. The
# other fields of the request were saved.
def require_links(config: Settings.Config, response: HTTP.Response, asked: Bool) -> Void
  return if not asked

  return if has_links?(Output.body(response))

  Output.fail(config.json, "UNSUPPORTED", "the server is older than card links: the links were not saved", 3)
end

def has_links?(body: String) -> Bool
  doc = JSON.parse(body)
  return false if not doc.ok?

  card = JSON.get(doc.unwrap!, "card")
  card.ok? and JSON.get(card.unwrap!, "links").ok?
end
