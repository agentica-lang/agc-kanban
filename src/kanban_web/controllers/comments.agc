import Bond from "pkg/bond/bond"
import Cards from "../../kanban/cards"
import Comments from "../../kanban/comments"
import Database from "../../kanban/repo/database"
import Failure from "../failure"

struct CommentInput
  body: String
end

struct CommentAnswer
  comment: Cards.Comment
end

export def add(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, CommentInput)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  input = Comments.Add(
    card_id: id.unwrap!,
    body: decoded.unwrap!.body,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    lease_minutes: lease_minutes,
  )

  result = Comments.add(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 201, CommentAnswer.codec, CommentAnswer(comment: result.unwrap!)))
end
