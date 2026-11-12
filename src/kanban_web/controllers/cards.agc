import Answers from "../answers"
import Bond from "pkg/bond/bond"
import Cards from "../../kanban/cards"
import Database from "../../kanban/repo/database"
import Failure from "../failure"
import Params from "../params"

struct CreateCard
  title: String
  body: Optional[String]
  column: Optional[String]
  labels: Optional[List[String]]
  priority: Optional[Int]
  depends_on: Optional[List[Int]]
end

struct UpdateCard
  title: Optional[String]
  body: Optional[String]
  labels: Optional[List[String]]
  priority: Optional[Int]
  branch: Optional[String]
  worktree: Optional[String]
  force: Optional[Bool]
end

struct CardsAnswer
  cards: List[Cards.Card]
end

export def create(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, CreateCard)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  data = decoded.unwrap!
  input = Cards.Create(
    board: Bond.param(conn, "board").unwrap_or(""),
    title: data.title,
    body: data.body.unwrap_or(""),
    column: data.column,
    labels: data.labels.unwrap_or([]),
    priority: data.priority.unwrap_or(2),
    depends_on: data.depends_on.unwrap_or([]),
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
  )

  result = Cards.create(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 201, Answers.CardAnswer.codec, Answers.CardAnswer(card: result.unwrap!)))
end

export def show(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  result = Cards.show(pool.unwrap!, id.unwrap!)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, Cards.Detail.codec, result.unwrap!))
end

export def index(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  params = Bond.query_params(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid query", some("query"))) if not params.ok?

  query = params.unwrap!
  ready = Params.flag(query, "ready")
  done = Params.flag(query, "done")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid query", some("query"))) if not ready.ok? or not done.ok?

  filters = Cards.Filters(
    column: Params.text(query, "column"),
    ready: ready.unwrap!,
    claimed_by: Params.text(query, "claimed_by"),
    label: Params.text(query, "label"),
    done: done.unwrap!,
  )

  result = Cards.list(pool.unwrap!, Bond.param(conn, "board").unwrap_or(""), filters)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, CardsAnswer.codec, CardsAnswer(cards: result.unwrap!)))
end

export def update(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, UpdateCard)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  data = decoded.unwrap!
  input = Cards.Update(
    id: id.unwrap!,
    title: data.title,
    body: data.body,
    labels: data.labels,
    priority: data.priority,
    branch: data.branch,
    worktree: data.worktree,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    force: data.force.unwrap_or(false),
    lease_minutes: lease_minutes,
  )

  result = Cards.update(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message, some(id.unwrap!))) if not result.ok?

  ok(Bond.json_as(conn, 200, Answers.CardAnswer.codec, Answers.CardAnswer(card: result.unwrap!)))
end
