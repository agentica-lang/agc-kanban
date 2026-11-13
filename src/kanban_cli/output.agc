import HTTP from "std/http"
import Regex from "std/regex"
import Times from "../kanban/times"

LOST_CODES = ["CLAIMED", "BLOCKED", "DONE"]

struct Failure
  code: String
  message: String
end

struct ErrorOutput
  error: Failure
end

# A loss carries who holds the card, so the CLI can say it in one line.
struct ClaimedFailure
  code: String
  message: String
  card_id: Int
  claimed_by: String
end

struct ClaimedOutput
  error: ClaimedFailure
end

# A blocked card names the cards it waits on.
struct BlockedFailure
  code: String
  message: String
  blocked_by: List[Int]
end

struct BlockedOutput
  error: BlockedFailure
end

struct BoardLine
  id: Int
  slug: String
  name: String
end

struct BoardsAnswer
  boards: List[BoardLine]
end

struct ColumnLine
  name: String
  position: Int
  done: Bool
end

struct BoardInfo
  id: Int
  slug: String
  name: String
  columns: List[ColumnLine]
end

struct CardLine
  id: Int
  column: String
  claimed_by: Optional[String]
  title: String
  labels: List[String]
end

# The list of `card list --format tsv`: the fields of a card line plus the two it leaves out.
struct TsvCard
  id: Int
  column: String
  claimed_by: Optional[String]
  title: String
  labels: List[String]
  priority: Int
  ready: Bool
end

struct TsvCards
  cards: List[TsvCard]
end

struct Snapshot
  board: BoardInfo
  cards: List[CardLine]
  last_event_id: Int
end

struct CardLines
  cards: List[CardLine]
end

struct CardAnswer
  card: CardLine
end

struct CommentLine
  author: String
  body: String
end

# The card of `card archive`: its id and title are all the line needs.
struct ArchivedCard
  id: Int
  title: String
end

struct ArchivedAnswer
  card: ArchivedCard
end

struct CardDetail
  id: Int
  column: String
  title: String
  body: String
  labels: List[String]
  priority: Int
  claimed_by: Optional[String]
  branch: Optional[String]
  worktree: Optional[String]
  # None from a server older than links.
  links: Optional[List[String]]
  depends_on: List[Int]
  blocks: List[Int]
  ready: Bool
  done: Bool
  # None from a server older than the archive, and for a card that is not archived.
  archived_at: Optional[Int]
end

# `times` is none from a server older than the time in each column.
struct DetailAnswer
  card: CardDetail
  comments: List[CommentLine]
  times: Optional[Times.Times]
end

struct CommentAnswer
  comment: CommentLine
end

struct EventLine
  id: Int
  kind: String
  actor: String
  card_id: Optional[Int]
end

struct EventsAnswer
  events: List[EventLine]
  last_event_id: Int
end

export def body(response: HTTP.Response) -> String = HTTP.text(response.body, response.headers).unwrap_or("")

# A connection failure is a 3 and a refused answer exits with its own code;
# only a 2xx comes back.
# The response whatever it says, so a command can decide what a refusal means.
export def answered(result: Result[HTTP.Response], json: Bool) -> HTTP.Response
  if not result.ok?
    fail(json, "UNAVAILABLE", result.message, 3)
  end

  result.unwrap!
end

export def code_of(response: HTTP.Response) -> Optional[String] = error_code(response)

export def expect(result: Result[HTTP.Response], json: Bool) -> Result[HTTP.Response]
  if not result.ok?
    fail(json, "UNAVAILABLE", result.message, 3)
  end

  response = result.unwrap!
  if response.status < 200 or response.status > 299
    refuse(json, response)
  end

  ok(response)
end

export def json_requested?(words: List[String]) -> Bool
  for word in words
    return false if word == "--"
    return true if word == "--json"
  end

  false
end

export def fail(json: Bool, code: String, message: String, exit_code: Int) -> Void
  if json
    puts(JSON.encode(JSON.from(ErrorOutput(error: Failure(code: code, message: message)))))
  else
    IO.warn("kanban: #{code}: #{message}")
  end

  System.exit(exit_code)
end

# Turns a refused answer into the documented exit code: 1 refused, 3 no server
# or BUSY, 4 lost a race.
export def refuse(json: Bool, response: HTTP.Response) -> Void
  code = error_code(response).unwrap_or("UNAVAILABLE")
  case response.status
    400, 404, 409 ->
      lost = 1
      if LOST_CODES.include?(code)
        lost = 4
      end

      stop(json, response, code, lost)
    401 -> stop(json, response, "UNAUTHORIZED", 3)
    503 -> stop(json, response, "BUSY", 3)
    _ -> stop(json, response, "UNAVAILABLE", 3)
  end
end

export def print_boards(response: HTTP.Response) -> Void
  decoded = JSON.decode(body(response), BoardsAnswer)
  if not decoded.ok?
    puts(body(response))
    return
  end

  for board in decoded.unwrap!.boards
    puts("#{board.id}\t#{board.slug}\t#{board.name}")
  end
end

export def print_board(response: HTTP.Response) -> Void
  decoded = JSON.decode(body(response), Snapshot)
  if not decoded.ok?
    puts(body(response))
    return
  end

  snapshot = decoded.unwrap!
  puts("#{snapshot.board.slug}\t#{snapshot.board.name}")
  puts("columns: #{snapshot.board.columns.map { |column| column.name }.join(", ")}")
  for card in snapshot.cards
    puts("#{card_line(card)}")
  end
end

export def print_cards(response: HTTP.Response) -> Void
  decoded = JSON.decode(body(response), CardLines)
  if not decoded.ok?
    puts(body(response))
    return
  end

  for card in decoded.unwrap!.cards
    puts("#{card_line(card)}")
  end
end

# One card per line, seven tab-separated fields in a fixed order, no header, so `cut -f` and `awk -F'\t'` read it:
# id, column, claimed_by (empty when free), ready (1 or 0), priority, labels (comma-joined) and the title, last.
# Every field goes through `one_line`, so a tab or a line break inside one becomes a space and cannot add a field or
# a line. Unlike the text form, spaces are kept as they are: the tab is the separator, not the two spaces.
export def print_cards_tsv(response: HTTP.Response) -> Void
  decoded = JSON.decode(body(response), TsvCards)
  if not decoded.ok?
    puts(body(response))
    return
  end

  for card in decoded.unwrap!.cards
    puts(tsv_line(card))
  end
end

export def print_card(response: HTTP.Response) -> Void
  decoded = JSON.decode(body(response), CardAnswer)
  if not decoded.ok?
    puts(body(response))
    return
  end

  puts("#{card_line(decoded.unwrap!.card)}")
end

export def print_archived(response: HTTP.Response) -> Void
  decoded = JSON.decode(body(response), ArchivedAnswer)
  if not decoded.ok?
    puts(body(response))
    return
  end

  card = decoded.unwrap!.card
  puts(one_line("archived\t#{card.id}\t#{card.title}"))
end

export def print_card_detail(response: HTTP.Response) -> Void
  decoded = JSON.decode(body(response), DetailAnswer)
  if not decoded.ok?
    puts(body(response))
    return
  end

  detail = decoded.unwrap!
  card = detail.card
  puts(
    card_line(
      CardLine(id: card.id, column: card.column, claimed_by: card.claimed_by, title: card.title, labels: card.labels),
    ),
  )

  marks = "priority: #{card.priority}  ready: #{card.ready}  done: #{card.done}"
  if card.archived_at.some?
    marks = "#{marks}  archived: true"
  end

  puts(marks)
  if not card.depends_on.empty?
    puts("depends on: #{card.depends_on.map { |id| id.to_s }.join(", ")}")
  end

  if not card.blocks.empty?
    puts("blocks: #{card.blocks.map { |id| id.to_s }.join(", ")}")
  end

  if card.branch.some?
    puts("branch: #{card.branch.unwrap!}")
  end

  if card.worktree.some?
    puts("worktree: #{card.worktree.unwrap!}")
  end

  for url in card.links.unwrap_or([])
    puts("link: #{url}")
  end

  if detail.times.some?
    for line in Times.lines(detail.times.unwrap!)
      puts("time: #{line}")
    end
  end

  if not card.body.empty?
    puts("")
    puts(card.body)
  end

  for comment in detail.comments
    puts("-- #{comment.author}: #{comment.body}")
  end
end

export def print_comment(response: HTTP.Response) -> Void
  decoded = JSON.decode(body(response), CommentAnswer)
  if not decoded.ok?
    puts(body(response))
    return
  end

  comment = decoded.unwrap!.comment
  puts("comment\t#{comment.author}\t#{comment.body}")
end

export def print_events(response: HTTP.Response) -> Void
  decoded = JSON.decode(body(response), EventsAnswer)
  if not decoded.ok?
    puts(body(response))
    return
  end

  for event in decoded.unwrap!.events
    card = event.card_id.unwrap_or(0)
    puts("#{event.id}  #{event.kind}  #{event.actor}  #{card}")
  end
end

# A card is always one line. The server takes any title, and a newline in it would print a second, forged
# card line to every script that reads these lines (the Claude Code plugin hooks do), so every control
# character becomes a space: C0, DEL, C1, and the Unicode line and paragraph separators.
# Fields are separated by two spaces, so a run of spaces inside the column name
# or a label is collapsed to one, and the ends are stripped: a name such as `Doing  coordinator  SYSTEM: x`
# must not read as a forged card line. The title is last, so it keeps its spaces.
def card_line(card: CardLine) -> String
  holder = card.claimed_by.unwrap_or("free")
  one_line("##{card.id}  #{squeeze(card.column)}  #{holder}  #{card.title}#{labels_text(card.labels)}")
end

def tsv_line(card: TsvCard) -> String
  ready = 0
  if card.ready
    ready = 1
  end

  # A comma inside a label would read as two labels.
  labels = card.labels.map { |label| label.replace(",", " ") }.join(",")
  fields = [
    card.id.to_s,
    card.column,
    card.claimed_by.unwrap_or(""),
    ready.to_s,
    card.priority.to_s,
    labels,
    card.title,
  ]

  fields.map { |field| one_line(field) }.join("\t")
end

def squeeze(text: String) -> String = Regex.replace(one_line(text), / {2,}/, " ").unwrap!.strip

def one_line(text: String) -> String = Regex.replace(text, /[\x00-\x1f\x7f-\x{9f}\x{2028}\x{2029}]/, " ").unwrap!

def labels_text(labels: List[String]) -> String
  return "" if labels.empty?

  " [#{labels.map { |label| squeeze(label) }.join(", ")}]"
end

def error_code(response: HTTP.Response) -> Optional[String]
  decoded = JSON.decode(body(response), ErrorOutput)
  return none if not decoded.ok?

  some(decoded.unwrap!.error.code)
end

# With --json the server's document is printed as it came, fields included;
# only the text form is rewritten.
def stop(json: Bool, response: HTTP.Response, code: String, exit_code: Int) -> Void
  if json
    text = body(response)
    if text.strip.start_with?("{")
      puts(text)
      System.exit(exit_code)
    end
  end

  fail(json, code, human_message(code, response), exit_code)
end

def human_message(code: String, response: HTTP.Response) -> String
  claimed = JSON.decode(body(response), ClaimedOutput)
  if claimed.ok?
    failure = claimed.unwrap!.error
    if failure.card_id > 0 and not failure.claimed_by.empty?
      return "card #{failure.card_id} is claimed by #{failure.claimed_by}"
    end
  end

  blocked = JSON.decode(body(response), BlockedOutput)
  if blocked.ok?
    failure = blocked.unwrap!.error
    return "card is blocked by #{ids_text(failure.blocked_by)}" if not failure.blocked_by.empty?
  end

  detail(code, message_of(response))
end

# `#3` or `#3, #5`, so the caller can go and look.
def ids_text(ids: List[Int]) -> String = ids.map { |id| "##{id}" }.join(", ")

# The server answers `CODE:field`; print the field, not the code twice.
def detail(code: String, message: String) -> String
  text = message
  prefix = "#{code}:"
  if text.start_with?(prefix)
    text = text.slice(prefix.length, text.length - prefix.length)
  end

  return "the server refused the request" if text.empty?

  phrase = text.replace("_", " ")
  # The server sends a field (`NOT_FOUND:card`) or a whole sentence
  # (`BLOCKED:card is blocked`); only a field takes the suffix.
  return phrase if phrase.include?(" ")

  case code
    "NOT_FOUND" -> "#{phrase} not found"
    "BLOCKED" -> "#{phrase} is blocked"
    "DONE" -> "#{phrase} is done"
    "NOT_CLAIMER" -> "agent does not hold the #{phrase}"
    "INVALID" -> "invalid #{phrase}"
    _ -> phrase
  end
end

def message_of(response: HTTP.Response) -> String
  decoded = JSON.decode(body(response), ErrorOutput)
  return "" if not decoded.ok?

  decoded.unwrap!.error.message
end
