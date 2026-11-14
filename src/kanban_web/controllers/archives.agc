import Answers from "../answers"
import AutoArchive from "../../kanban/auto_archive"
import Boards from "../../kanban/boards"
import Bond from "pkg/bond/bond"
import Database from "../../kanban/repo/database"
import Failure from "../failure"
import Transitions from "../../kanban/transitions"

def unarchive(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  data = JSON.parse(body.unwrap!)
  if not data.ok? or JSON.kind(data.unwrap!) != "object"
    return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body")))
  end

  input = Transitions.Action(
    id: id.unwrap!,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    force: false,
  )

  result = Transitions.unarchive(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message, some(id.unwrap!))) if not result.ok?

  ok(Bond.json_as(conn, 200, Answers.CardAnswer.codec, Answers.CardAnswer(card: result.unwrap!)))
end

def archive_done(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, ArchiveDoneInput)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  input = Transitions.ArchiveDone(
    board: Bond.param(conn, "board").unwrap_or(""),
    days: decoded.unwrap!.days,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    now: Time.now_ms(),
  )

  result = Transitions.archive_done(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, Transitions.ArchivedDone.codec, result.unwrap!))
end

def auto_archive(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, AutoArchiveInput)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  input = AutoArchive.Setting(
    board: Bond.param(conn, "board").unwrap_or(""),
    days: decoded.unwrap!.days,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
  )

  result = AutoArchive.set(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, BoardAnswer.codec, BoardAnswer(board: result.unwrap!)))
end

private

struct BoardAnswer
  board: Boards.Board
end

struct AutoArchiveInput
  days: Optional[Int]
end

struct ArchiveDoneInput
  days: Int
end
