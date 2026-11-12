import HTTP from "std/http"

LOST_CODES = ["CLAIMED", "BLOCKED", "DONE"]

struct Failure
  code: String
  message: String
end

struct ErrorOutput
  error: Failure
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

export def body(response: HttpResponse) -> String = HTTP.text(response.body, response.headers).unwrap_or("")

# A connection failure is a 3 and a refused answer exits with its own code;
# only a 2xx comes back.
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
      if LOST_CODES.include?(code)
        fail(json, code, message_of(response), 4)
      end

      fail(json, code, message_of(response), 1)
    401 -> fail(json, "UNAUTHORIZED", "authentication failed", 3)
    503 -> fail(json, "BUSY", "server is busy", 3)
    _ -> fail(json, "UNAVAILABLE", "server returned #{response.status}", 3)
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

def card_line(card: CardLine) -> String
  holder = card.claimed_by.unwrap_or("free")
  "#{card.id}\t#{card.column}\t#{holder}\t#{card.title}#{labels_text(card.labels)}"
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

def message_of(response: HttpResponse) -> String
  decoded = JSON.decode(body(response), ErrorOutput)
  return "" if not decoded.ok?

  decoded.unwrap!.error.message
end
