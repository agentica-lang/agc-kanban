import Answers from "../answers"
import Bond from "pkg/bond/bond"
import Claims from "../../kanban/claims"
import Database from "../../kanban/repo/database"
import Failure from "../failure"
import Transitions from "../../kanban/transitions"

def claim(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  data = JSON.parse(body.unwrap!)
  if not data.ok? or JSON.kind(data.unwrap!) != "object"
    return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body")))
  end

  actor = Bond.request_header(conn, "X-Kanban-Agent").unwrap_or("")
  result = Claims.claim(pool.unwrap!, id.unwrap!, actor, lease_minutes)
  return ok(Failure.answer(conn, result.message, some(id.unwrap!))) if not result.ok?

  ok(Bond.json_as(conn, 200, Answers.CardAnswer.codec, Answers.CardAnswer(card: result.unwrap!)))
end

def next_card(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, ClaimNext)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  data = decoded.unwrap!
  input = Claims.Next(
    board: Bond.param(conn, "board").unwrap_or(""),
    column: data.column,
    label: data.label,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    lease_minutes: lease_minutes,
  )

  result = Claims.claim_next(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, Answers.CardAnswer.codec, Answers.CardAnswer(card: result.unwrap!)))
end

def release(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  data = JSON.decode(body.unwrap!, ReleaseInput)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not data.ok?

  input = Transitions.Release(
    id: id.unwrap!,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    force: data.unwrap!.force.unwrap_or(false),
    column: data.unwrap!.column,
  )

  result = Transitions.release(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message, some(id.unwrap!))) if not result.ok?

  ok(Bond.json_as(conn, 200, Answers.CardAnswer.codec, Answers.CardAnswer(card: result.unwrap!)))
end

def move(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  data = JSON.decode(body.unwrap!, MoveInput)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not data.ok?

  input = Transitions.Move(
    id: id.unwrap!,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    force: data.unwrap!.force.unwrap_or(false),
    column: data.unwrap!.column,
    position: data.unwrap!.position,
    lease_minutes: lease_minutes,
  )

  result = Transitions.move(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message, some(id.unwrap!))) if not result.ok?

  ok(Bond.json_as(conn, 200, Answers.CardAnswer.codec, Answers.CardAnswer(card: result.unwrap!)))
end

def done(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, ForceInput)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  input = Transitions.Action(
    id: id.unwrap!,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    force: decoded.unwrap!.force.unwrap_or(false),
  )

  result = Transitions.finish(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message, some(id.unwrap!))) if not result.ok?

  ok(Bond.json_as(conn, 200, Answers.CardAnswer.codec, Answers.CardAnswer(card: result.unwrap!)))
end

def archive(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, ForceInput)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  input = Transitions.Action(
    id: id.unwrap!,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    force: decoded.unwrap!.force.unwrap_or(false),
  )

  result = Transitions.archive(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message, some(id.unwrap!))) if not result.ok?

  ok(Bond.json_as(conn, 200, Answers.CardAnswer.codec, Answers.CardAnswer(card: result.unwrap!)))
end

private

struct MoveInput
  column: String
  position: Optional[Int]
  force: Optional[Bool]
end

struct ReleaseInput
  column: Optional[String]
  force: Optional[Bool]
end

struct ForceInput
  force: Optional[Bool]
end

struct ClaimNext
  column: Optional[String]
  label: Optional[String]
end
