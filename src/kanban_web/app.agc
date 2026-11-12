import Bond from "pkg/bond/bond"
import Regex from "std/regex"
import Boards from "../kanban/boards"
import Events from "../kanban/events"
import Database from "../kanban/repo/database"

struct CreateBoard
  name: String
  slug: Optional[String]
  columns: Optional[List[String]]
end

struct BoardAnswer
  board: Boards.Board
end

struct BoardsAnswer
  boards: List[Boards.BoardSummary]
end

struct ApiError
  code: String
  message: String
  field: Optional[String]
end

struct ErrorAnswer
  error: ApiError
end

export def build(key: String, pool: Optional[Database.Pool] = none) -> Bond.App
  (
    Bond.app()
    |> Bond.before() do |conn| authorize(conn, key) end
    |> Bond.get("/api/health", &health)
    |> Bond.get("/api/auth-check", &auth_check)
    |> Bond.get("/api/boards") do |conn| list_boards(conn, pool) end
    |> Bond.post("/api/boards") do |conn| create_board(conn, pool) end
    |> Bond.get("/api/boards/:board/events") do |conn| board_events(conn, pool) end
  )
end

def authorize(conn: Bond.Conn, key: String) -> Result[Bond.Conn]
  return ok(conn) if conn.path == "/api/health" or not conn.path.start_with?("/api/")

  given = Bond.request_header(conn, "apikey").unwrap_or("")
  if not OpenSSL.HMAC.secure_compare(given.bytes, key.bytes)
    return ok(reject(conn, 401, "UNAUTHORIZED", "unauthorized"))
  end

  if conn.method != "GET" and conn.method != "HEAD"
    agent = Bond.request_header(conn, "X-Kanban-Agent").unwrap_or("")
    if not Regex.match?(agent, /^[A-Za-z0-9._@\/-]{1,64}$/)
      return ok(reject(conn, 400, "INVALID", "invalid agent", some("X-Kanban-Agent")))
    end
  end

  ok(conn)
end

def reject(conn: Bond.Conn, status: Int, code: String, message: String, field: Optional[String] = none) -> Bond.Conn
  Bond.json_as(
    conn,
    status,
    ErrorAnswer.codec,
    ErrorAnswer(error: ApiError(code: code, message: message, field: field)),
  ).with(halted: true)
end

def health(conn: Bond.Conn) -> Result[Bond.Conn]
  ok(Bond.json(conn, 200, JSON.parse("{\"ok\":true,\"version\":\"0.1.0\"}").unwrap!))
end

def auth_check(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.json(conn, 200, JSON.parse("{\"ok\":true}").unwrap!))

def list_boards(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  boards = Boards.list(pool.unwrap!)
  return ok(failure(conn, boards.message)) if not boards.ok?

  ok(Bond.json_as(conn, 200, BoardsAnswer.codec, BoardsAnswer(boards: boards.unwrap!)))
end

def create_board(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  body = Bond.body_text(conn)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, CreateBoard)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  input = decoded.unwrap!
  generated = Regex.replace(input.name.downcase, /[^a-z0-9]+/, "-").unwrap!
  slug = input.slug.unwrap_or(generated)
  names = input.columns.unwrap_or(["Todo", "Doing", "Review", "Done"])
  agent = Bond.request_header(conn, "X-Kanban-Agent").unwrap_or("")
  created = Boards.create(pool.unwrap!, input.name, slug, agent, names)
  return ok(failure(conn, created.message)) if not created.ok?

  ok(Bond.json_as(conn, 201, BoardAnswer.codec, BoardAnswer(board: created.unwrap!)))
end

def failure(conn: Bond.Conn, message: String) -> Bond.Conn
  if message.start_with?("INVALID:")
    return reject(conn, 400, "INVALID", message, some(message.slice(8, message.length - 8)))
  end

  return reject(conn, 409, "CONFLICT", message) if message.start_with?("CONFLICT:")
  return reject(conn, 404, "NOT_FOUND", message) if message.start_with?("NOT_FOUND:")
  return reject(conn, 503, "BUSY", "database busy") if Database.busy?(message)

  reject(conn, 500, "INTERNAL", "internal error")
end

def board_events(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  params = Bond.query_params(conn)
  return ok(reject(conn, 400, "INVALID", "invalid query", some("query"))) if not params.ok?

  query = params.unwrap!
  after = query_number(query, "after", 0)
  limit = query_number(query, "limit", 100)
  card = query_number(query, "card", 0)
  if not after.ok? or not limit.ok? or not card.ok?
    return ok(reject(conn, 400, "INVALID", "invalid query", some("query")))
  end

  card_id: Optional[Int] = none
  if query.key?("card")
    card_id = some(card.unwrap!)
  end

  page = Events.list(pool.unwrap!, Bond.param(conn, "board").unwrap_or(""), after.unwrap!, card_id, limit.unwrap!)
  return ok(failure(conn, page.message)) if not page.ok?

  result = page.unwrap!
  events = result.events.map do |entry| event_json(entry) end
  ok(
    Bond.json(
      conn,
      200,
      JSON.object({"events": JSON.array(events), "last_event_id": JSON.from(result.last_event_id)}),
    ),
  )
end

def query_number(params: Map[String, List[String]], name: String, default: Int) -> Result[Int]
  case params.get(name)
    none -> ok(default)
    some(values) -> values[0].to_i()
  end
end

def event_json(entry: Events.Event) -> Json
  JSON.object({
    "id": JSON.from(entry.id),
    "board_id": JSON.from(entry.board_id),
    "card_id": JSON.from(entry.card_id),
    "kind": JSON.from(entry.kind),
    "actor": JSON.from(entry.actor),
    "data": entry.data,
    "created_at": JSON.from(entry.created_at),
  })
end
