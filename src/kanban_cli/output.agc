import HTTP from "std/http"
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
  depends_on: List[Int]
  blocks: List[Int]
  ready: Bool
  done: Bool
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

export def body(response: HttpResponse) -> String = HTTP.text(response.body, response.headers).unwrap_or("")

# A connection failure is a 3 and a refused answer exits with its own code;
# only a 2xx comes back.
# The response whatever it says, so a command can decide what a refusal means.
export def answered(result: Result[HttpResponse], json: Bool) -> HttpResponse
  if not result.ok?
    fail(json, "UNAVAILABLE", result.message, 3)
  end

  result.unwrap!
end

export def code_of(response: HttpResponse) -> Optional[String] = error_code(response)

export def expect(result: Result[HttpResponse], json: Bool) -> Result[HttpResponse]
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
export def refuse(json: Bool, response: HttpResponse) -> Void
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

export def print_boards(response: HttpResponse) -> Void
  decoded = JSON.decode(body(response), BoardsAnswer)
  if not decoded.ok?
    puts(body(response))
    return
  end

  for board in decoded.unwrap!.boards
    puts("#{board.id}\t#{board.slug}\t#{board.name}")
  end
end

export def print_board(response: HttpResponse) -> Void
  decoded = JSON.decode(body(response), Snapshot)
  if not decoded.ok?
    puts(body(response))
    return
  end

  snapshot = decoded.unwrap!
  puts("#{snapshot.board.slug}\t#{snapshot.board.name}")
  puts("columns: #{snapshot.board.columns.map do |column| column.name end.join(", ")}")
  for card in snapshot.cards
    puts("#{card_line(card)}")
  end
end

export def print_cards(response: HttpResponse) -> Void
  decoded = JSON.decode(body(response), CardLines)
  if not decoded.ok?
    puts(body(response))
    return
  end

  for card in decoded.unwrap!.cards
    puts("#{card_line(card)}")
  end
end

export def print_card(response: HttpResponse) -> Void
  decoded = JSON.decode(body(response), CardAnswer)
  if not decoded.ok?
    puts(body(response))
    return
  end

  puts("#{card_line(decoded.unwrap!.card)}")
end

export def print_card_detail(response: HttpResponse) -> Void
  decoded = JSON.decode(body(response), DetailAnswer)
  if not decoded.ok?
    puts(body(response))
    return
  end

  detail = decoded.unwrap!
  card = detail.card
  puts("##{card.id}  #{card.column}  #{card.claimed_by.unwrap_or("free")}  #{card.title}#{labels_text(card.labels)}")
  puts("priority: #{card.priority}  ready: #{card.ready}  done: #{card.done}")
  if not card.depends_on.empty?
    puts("depends on: #{card.depends_on.map do |id| id.to_s end.join(", ")}")
  end

  if not card.blocks.empty?
    puts("blocks: #{card.blocks.map do |id| id.to_s end.join(", ")}")
  end

  if card.branch.some?
    puts("branch: #{card.branch.unwrap!}")
  end

  if card.worktree.some?
    puts("worktree: #{card.worktree.unwrap!}")
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

export def print_comment(response: HttpResponse) -> Void
  decoded = JSON.decode(body(response), CommentAnswer)
  if not decoded.ok?
    puts(body(response))
    return
  end

  comment = decoded.unwrap!.comment
  puts("comment\t#{comment.author}\t#{comment.body}")
end

export def print_events(response: HttpResponse) -> Void
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

def card_line(card: CardLine) -> String
  holder = card.claimed_by.unwrap_or("free")
  "##{card.id}  #{card.column}  #{holder}  #{card.title}#{labels_text(card.labels)}"
end

def labels_text(labels: List[String]) -> String
  return "" if labels.empty?

  " [#{labels.join(", ")}]"
end

def error_code(response: HttpResponse) -> Optional[String]
  decoded = JSON.decode(body(response), ErrorOutput)
  return none if not decoded.ok?

  some(decoded.unwrap!.error.code)
end

# With --json the server's document is printed as it came, fields included;
# only the text form is rewritten.
def stop(json: Bool, response: HttpResponse, code: String, exit_code: Int) -> Void
  if json
    text = body(response)
    if text.strip.start_with?("{")
      puts(text)
      System.exit(exit_code)
    end
  end

  fail(json, code, human_message(code, response), exit_code)
end

def human_message(code: String, response: HttpResponse) -> String
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
def ids_text(ids: List[Int]) -> String = ids.map do |id| "##{id}" end.join(", ")

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

def message_of(response: HttpResponse) -> String
  decoded = JSON.decode(body(response), ErrorOutput)
  return "" if not decoded.ok?

  decoded.unwrap!.error.message
end
