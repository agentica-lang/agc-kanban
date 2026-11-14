import Auth from "../auth"
import Bond from "pkg/bond/bond"
import Database from "../../kanban/repo/database"
import Failure from "../failure"
import LabelUpdates from "../../kanban/label_updates"
import Labels from "../../kanban/labels"

def index(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  result = Labels.list(pool.unwrap!, Bond.param(conn, "board").unwrap_or(""))
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, LabelsAnswer.codec, LabelsAnswer(labels: result.unwrap!)))
end

def update(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, UpdateLabel)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  data = decoded.unwrap!
  if data.name.some? and Auth.session_write?(conn)
    return ok(Failure.reject(conn, 401, "UNAUTHORIZED", "a rename needs the api key"))
  end

  input = LabelUpdates.Update(
    id: id.unwrap!,
    name: data.name,
    color: data.color,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
  )

  result = LabelUpdates.update(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, LabelAnswer.codec, LabelAnswer(label: result.unwrap!)))
end

private

struct UpdateLabel
  name: Optional[String]
  color: Optional[String]
end

struct LabelAnswer
  label: Labels.Label
end

struct LabelsAnswer
  labels: List[Labels.Label]
end
