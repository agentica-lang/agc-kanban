import Answers from "../answers"
import Bond from "pkg/bond/bond"
import Database from "../../kanban/repo/database"
import Deps from "../../kanban/deps"
import Failure from "../failure"

struct DependencyInput
  depends_on: Int
end

export def add(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  data = JSON.decode(body.unwrap!, DependencyInput)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not data.ok?

  input = Deps.Change(
    card_id: id.unwrap!,
    depends_on: data.unwrap!.depends_on,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    lease_minutes: lease_minutes,
  )

  result = Deps.add(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message, some(id.unwrap!))) if not result.ok?

  ok(Bond.json_as(conn, 201, Answers.CardAnswer.codec, Answers.CardAnswer(card: result.unwrap!)))
end

export def remove(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  other = Bond.param_int(conn, "other")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok? or not other.ok?

  input = Deps.Change(
    card_id: id.unwrap!,
    depends_on: other.unwrap!,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    lease_minutes: lease_minutes,
  )

  result = Deps.remove(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, Answers.CardAnswer.codec, Answers.CardAnswer(card: result.unwrap!)))
end
