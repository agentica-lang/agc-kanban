import Bond from "pkg/bond/bond"
import Regex from "std/regex"
import Boards from "../kanban/boards"
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
  return reject(conn, 503, "BUSY", "database busy") if Database.busy?(message)

  reject(conn, 500, "INTERNAL", "internal error")
end
