import OP from "std/option_parser"
import Regex from "std/regex"
import Client from "client"
import Input from "input"
import Output from "output"
import Settings from "settings"
import Support from "support"
import {Kind, Opt} from "std/option_parser"

# Reads the open cards of a board and reports where they no longer match reality: a linked issue that is closed, a
# linked PR that is merged, a card in Review with no PR link, a card in Doing that nobody touched for a while.
# Exit 0 clean, 5 drift, 6 GitHub could not be read (the findings that need no GitHub are still printed), 3 no server.
def run(words: List[String]) -> Result[Void]
  parser = OP.new(
    "kanban doctor",
    "Report the cards that no longer match GitHub or the work",
    [],
    [
      Opt(
        name: "stale-minutes",
        kind: Kind.Int,
        default: "180",
        help: "minutes without an event before a card in Doing is stale",
      ),
      Opt(name: "no-github", kind: Kind.Flag, help: "skip the checks that need gh"),
      Opt(name: "cards", help: "check only these card ids, comma-separated"),
    ] +
    Settings.common_opts(),
  )

  parsed = try OP.parse(parser, words)
  config = try Settings.load(Settings.read_flags(parsed))
  board = Support.board_of(config)
  client = Client.from(config)
  only = try Input.ids(OP.optional_string(parsed, "cards"))
  cards = open_cards(client, config, board)
  if not only.empty?
    cards = cards.select do |card| only.include?(card.id) end
  end

  stale_ms = OP.int(parsed, "stale-minutes") * 60000
  checked = not OP.flag(parsed, "no-github")
  remote: Map[String, Remote] = {}
  github_error = ""
  if checked
    fetched = fetch_remote(cards)
    if fetched.ok?
      remote = fetched.unwrap!
    else
      github_error = fetched.message
    end
  end

  now = Time.now_ms()
  findings: List[Finding] = []
  for card in cards
    quiet = 0
    if card.column == "Doing"
      quiet = now - last_touch(client, config, board, card)
    end

    findings = findings + card_findings(card, remote, quiet, stale_ms)
  end

  report = Report(
    board: board,
    cards: cards.size,
    github: checked and github_error.empty?,
    github_error: github_error,
    findings: findings,
  )

  print_report(config.json, report)
  if not github_error.empty?
    System.exit(GITHUB_EXIT)
  end

  if not findings.empty?
    System.exit(DRIFT_EXIT)
  end

  ok()
end

private

DRIFT_EXIT = 5
GITHUB_EXIT = 6
CHUNK = 40
LINK = /^https:\/\/github\.com\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)\/(issues|pull)\/(\d+)\/?$/
PULL = /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/pull\/\d+\/?$/

struct Finding
  card: Int
  column: String
  kind: String
  reason: String
  action: String
  url: Optional[String]
end

struct Report
  board: String
  cards: Int
  github: Bool
  github_error: String
  findings: List[Finding]
end

struct Card
  id: Int
  column: String
  links: List[String]
  updated_at: Int
end

struct CardsAnswer
  cards: List[Card]
end

struct EventTime
  created_at: Int
end

struct EventsAnswer
  events: List[EventTime]
end

# What GitHub says about one issue or PR.
struct Remote
  closed: Bool
  merged: Bool
  pull: Bool
end

struct Ref
  key: String
  owner: String
  repo: String
  number: Int
end

def open_cards(client: Client.Client, config: Settings.Config, board: String) -> List[Card]
  response = Output.expect(Client.get(client, "/api/boards/#{board}/cards?done=0"), config.json)
  decoded = JSON.decode(Output.body(response.unwrap!), CardsAnswer)
  if not decoded.ok?
    Output.fail(config.json, "UNAVAILABLE", "invalid card list response", 3)
  end

  decoded.unwrap!.cards
end

# The newest of the card's own update and its newest event (a comment is an event, not an update).
def last_touch(client: Client.Client, config: Settings.Config, board: String, card: Card) -> Int
  path = "/api/boards/#{board}/events?card=#{card.id}&before=1000000000&limit=1"
  response = Output.expect(Client.get(client, path), config.json)
  decoded = JSON.decode(Output.body(response.unwrap!), EventsAnswer)
  return card.updated_at if not decoded.ok? or decoded.unwrap!.events.empty?

  newest = decoded.unwrap!.events[0].created_at
  if card.updated_at > newest
    newest = card.updated_at
  end

  newest
end

def ref_of(link: String) -> Optional[Ref]
  found = Regex.match(link, LINK)
  return none if not found.ok?

  groups = found.unwrap!.groups
  owner = groups[1].text
  repo = groups[2].text
  number = groups[4].text.to_i!
  some(Ref(key: key_of(owner, repo, groups[3].text, number), owner: owner, repo: repo, number: number))
end

# Issues and pulls share the number space of a repository, so the number alone names the item.
def key_of(owner: String, repo: String, _kind: String, number: Int) -> String = "#{owner}/#{repo}##{number}"

def link_refs(cards: List[Card]) -> List[Ref]
  refs: List[Ref] = []
  seen: Map[String, Bool] = {}
  for card in cards
    for link in card.links
      ref = ref_of(link)
      if ref.some? and not seen.key?(ref.unwrap!.key)
        seen = seen.put(ref.unwrap!.key, true)
        refs = refs.push(ref.unwrap!)
      end
    end
  end

  refs
end

# One GraphQL request per CHUNK links, across every repository: the number of gh calls does not grow with the cards.
def fetch_remote(cards: List[Card]) -> Result[Map[String, Remote]]
  refs = link_refs(cards)
  found: Map[String, Remote] = {}
  rest = refs
  while not rest.empty?
    chunk = List.take(rest, CHUNK)
    rest = List.drop(rest, CHUNK)
    part = try ask(chunk)
    for key in part.keys
      found = found.put(key, part.get(key).unwrap!)
    end
  end

  ok(found)
end

def query_of(chunk: List[Ref]) -> String
  parts: List[String] = []
  for index in 0..(chunk.size - 1)
    ref = chunk[index]
    parts = parts.push(
      "a#{index}: repository(owner: \"#{ref.owner}\", name: \"#{ref.repo}\") { issueOrPullRequest(number: #{ref.number}) { __typename ... on Issue { state } ... on PullRequest { state merged } } }",
    )
  end

  "{ #{parts.join(" ")} }"
end

def ask(chunk: List[Ref]) -> Result[Map[String, Remote]]
  process = try Process.spawn_captured(
    "gh",
    ["api", "graphql", "-f", "query=#{query_of(chunk)}"],
    Process.Options(timeout_ms: 30000),
  )

  status = Process.wait(process, 30000)
  output = Process.output(process, 30000)
  Process.close(process)
  return error("gh did not answer") if not status.ok? or not output.ok?

  # gh exits 1 when GitHub reports an error for one link (a deleted repository) but still prints the data of the rest.
  document = JSON.parse(output.unwrap!.stdout)
  if not document.ok? or not JSON.get(document.unwrap!, "data").ok?
    reason = output.unwrap!.stderr.strip.split("\n")[0]
    return error("gh failed: #{reason}")
  end

  data = JSON.get(document.unwrap!, "data").unwrap!
  found: Map[String, Remote] = {}
  for index in 0..(chunk.size - 1)
    item = remote_of(data, "a#{index}")
    if item.some?
      found = found.put(chunk[index].key, item.unwrap!)
    end
  end

  ok(found)
end

def remote_of(data: JSON.Value, alias: String) -> Optional[Remote]
  node = JSON.get(data, alias)
  return none if not node.ok?

  item = JSON.get(node.unwrap!, "issueOrPullRequest")
  return none if not item.ok?

  kind = JSON.get(item.unwrap!, "__typename")
  state = JSON.get(item.unwrap!, "state")
  return none if not kind.ok? or not state.ok?

  merged = JSON.get(item.unwrap!, "merged")
  some(
    Remote(
      closed: JSON.string(state.unwrap!).unwrap_or("") != "OPEN",
      merged: merged.ok? and JSON.bool(merged.unwrap!).unwrap_or(false),
      pull: JSON.string(kind.unwrap!).unwrap_or("") == "PullRequest",
    ),
  )
end

# A card may link several PRs and issues (a parent card, a part of an issue): it has drifted only when every PR it
# links is merged (and no issue it links is open, unless it is in Review or Doing), or every issue it links is closed.
# A closed PR that was not merged says nothing.
def card_findings(card: Card, remote: Map[String, Remote], quiet_ms: Int, stale_ms: Int) -> List[Finding]
  found: List[Finding] = []
  has_pull = false
  pulls_merged: List[String] = []
  pulls_open = 0
  issues_closed: List[String] = []
  issues_open = 0
  for link in card.links
    if Regex.match?(link, PULL)
      has_pull = true
    end

    ref = ref_of(link)
    if ref.some? and remote.key?(ref.unwrap!.key)
      state = remote.get(ref.unwrap!.key).unwrap!
      if state.pull and state.merged
        pulls_merged = pulls_merged.push(link)
      elsif state.pull and not state.closed
        pulls_open = pulls_open + 1
      elsif not state.pull and state.closed
        issues_closed = issues_closed.push(link)
      elsif not state.pull
        issues_open = issues_open + 1
      end
    end
  end

  # A card whose issue is still open is a part of it: merged work in Backlog or Todo waits on later slices, so only a
  # card in Review or Doing, which has nothing more to wait for, is reported.
  active = card.column == "Review" or card.column == "Doing"
  if not pulls_merged.empty? and pulls_open == 0 and (issues_open == 0 or active)
    action = "kanban card done #{card.id}"
    if issues_open > 0
      action = (
        "kanban card move #{card.id} Todo for the next slice, or kanban card done #{card.id} if the issue is finished"
      )
    end

    found = found.push(
      Finding(
        card: card.id,
        column: card.column,
        kind: "pr-merged",
        reason: "its linked PRs are all merged",
        action: action,
        url: some(pulls_merged[0]),
      ),
    )
  end

  if not issues_closed.empty? and issues_open == 0
    found = found.push(
      Finding(
        card: card.id,
        column: card.column,
        kind: "issue-closed",
        reason: "its issue is closed",
        action: "kanban card done #{card.id}, or unlink the issue if the card is only a part",
        url: some(issues_closed[0]),
      ),
    )
  end

  if card.column == "Review" and not has_pull
    found = found.push(
      Finding(
        card: card.id,
        column: card.column,
        kind: "review-no-pr",
        reason: "in Review with no PR link",
        action: "kanban card update #{card.id} --link PR_URL, or move it back",
        url: none,
      ),
    )
  end

  if card.column == "Doing" and quiet_ms > stale_ms
    found = found.push(
      Finding(
        card: card.id,
        column: card.column,
        kind: "doing-stale",
        reason: "no event for #{quiet_ms / 60000} min",
        action: "ask the holder, or kanban card release #{card.id}",
        url: none,
      ),
    )
  end

  found
end

def print_report(json: Bool, report: Report) -> Void
  if json
    puts(JSON.encode(JSON.from(report)))
    return
  end

  for finding in report.findings
    where = finding.url.map do |url| " (#{url})" end
    puts(
      "##{finding.card}  #{finding.column}  #{finding.kind}  #{finding.reason}#{where.unwrap_or("")}; next: #{finding.action}",
    )
  end

  if not report.github_error.empty?
    IO.warn("kanban: UNAVAILABLE: GitHub checks skipped: #{report.github_error}")
  elsif report.findings.empty?
    puts("no drift on #{report.board} (#{report.cards} open cards)")
  end
end
