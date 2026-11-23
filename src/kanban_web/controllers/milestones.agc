import Bond from "pkg/bond/bond"
import Database from "../../kanban/repo/database"
import Failure from "../failure"
import Milestones from "../../kanban/milestones"
import Params from "../params"

def index(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  params = Bond.query_params(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid query", some("query"))) if not params.ok?

  state = Params.text(params.unwrap!, "state").unwrap_or("open")
  result = Milestones.list(pool.unwrap!, Bond.param(conn, "board").unwrap_or(""), state, Milestones.today())
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, MilestonesAnswer.codec, MilestonesAnswer(milestones: result.unwrap!)))
end

def create(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, CreateMilestone)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  data = decoded.unwrap!
  input = Milestones.Create(
    board: Bond.param(conn, "board").unwrap_or(""),
    name: data.name,
    description: data.description.unwrap_or(""),
    due_on: data.due_on,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
  )

  result = Milestones.create(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 201, MilestoneAnswer.codec, MilestoneAnswer(milestone: result.unwrap!)))
end

def update(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, UpdateMilestone)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  data = decoded.unwrap!
  input = Milestones.Update(
    id: id.unwrap!,
    description: data.description,
    due_on: data.due_on,
    state: data.state,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
  )

  result = Milestones.update(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, MilestoneAnswer.codec, MilestoneAnswer(milestone: result.unwrap!)))
end

def remove(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  input = Milestones.Remove(id: id.unwrap!, actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""))
  result = Milestones.remove(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.status(conn, 204))
end

private

struct CreateMilestone
  name: String
  description: Optional[String]
  due_on: Optional[String]
end

struct UpdateMilestone
  description: Optional[String]
  due_on: Optional[String]
  state: Optional[String]
end

struct MilestoneAnswer
  milestone: Milestones.Milestone
end

struct MilestonesAnswer
  milestones: List[Milestones.Milestone]
end
