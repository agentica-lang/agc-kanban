import Boards from "../../kanban/boards"
import Bond from "pkg/bond/bond"
import Database from "../../kanban/repo/database"
import Failure from "../failure"
import Regex from "std/regex"
import Snapshots from "../../kanban/snapshots"

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

export def index(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  boards = Boards.list(pool.unwrap!)
  return ok(Failure.answer(conn, boards.message)) if not boards.ok?

  ok(Bond.json_as(conn, 200, BoardsAnswer.codec, BoardsAnswer(boards: boards.unwrap!)))
end

export def create(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, CreateBoard)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  input = decoded.unwrap!
  generated = Regex.replace(input.name.downcase, /[^a-z0-9]+/, "-").unwrap!
  slug = input.slug.unwrap_or(generated)
  names = input.columns.unwrap_or(["Todo", "Doing", "Review", "Done"])
  agent = Bond.request_header(conn, "X-Kanban-Agent").unwrap_or("")
  created = Boards.create(pool.unwrap!, input.name, slug, agent, names)
  return ok(Failure.answer(conn, created.message)) if not created.ok?

  ok(Bond.json_as(conn, 201, BoardAnswer.codec, BoardAnswer(board: created.unwrap!)))
end

export def show(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  result = Snapshots.get(pool.unwrap!, Bond.param(conn, "board").unwrap_or(""))
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, Snapshots.Snapshot.codec, result.unwrap!))
end
