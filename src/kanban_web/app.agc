import Bond from "pkg/bond/bond"
import Regex from "std/regex"
import Auth from "auth"
import Boards from "../kanban/boards"
import Cards from "../kanban/cards"
import Claims from "../kanban/claims"
import Columns from "../kanban/columns"
import Comments from "../kanban/comments"
import Database from "../kanban/repo/database"
import Deps from "../kanban/deps"
import Events from "../kanban/events"
import Failure from "failure"
import Health from "health"
import Params from "params"
import Routes from "routes"
import Snapshots from "../kanban/snapshots"
import Transitions from "../kanban/transitions"

struct CreateBoard
  name: String
  slug: Optional[String]
  columns: Optional[List[String]]
end

struct CardsAnswer
  cards: List[Cards.Card]
end

struct DependencyInput
  depends_on: Int
end

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

struct CommentInput
  body: String
end

struct CommentAnswer
  comment: Cards.Comment
end

struct CardAnswer
  card: Cards.Card
end

struct CreateColumn
  name: String
  position: Optional[Int]
  done: Optional[Bool]
  wip_limit: Optional[Int]
end

struct UpdateColumn
  name: Optional[String]
  position: Optional[Int]
  done: Optional[Bool]
  wip_limit: Optional[Int]
end

struct ColumnAnswer
  column: Boards.Column
end

struct BoardAnswer
  board: Boards.Board
end

struct BoardsAnswer
  boards: List[Boards.BoardSummary]
end

export def build(key: String, pool: Optional[Database.Pool] = none, lease_minutes: Int = 0) -> Bond.App
  (
    Bond.app()
    |> Bond.before() do |conn| Auth.authorize(conn, key) end
    |> Bond.get(Routes.HEALTH) do |conn| Health.health(conn) end
    |> Bond.get(Routes.AUTH_CHECK) do |conn| Health.auth_check(conn) end
    |> Bond.get(Routes.BOARDS) do |conn| list_boards(conn, pool) end
    |> Bond.post(Routes.BOARDS) do |conn| create_board(conn, pool) end
    |> Bond.get(Routes.BOARD) do |conn| show_board(conn, pool) end
    |> Bond.post(Routes.CLAIM_NEXT) do |conn| claim_next(conn, pool, lease_minutes) end
    |> Bond.get(Routes.BOARD_CARDS) do |conn| list_cards(conn, pool) end
    |> Bond.post(Routes.BOARD_CARDS) do |conn| create_card(conn, pool) end
    |> Bond.post(Routes.CARD_DEPS) do |conn| add_dependency(conn, pool, lease_minutes) end
    |> Bond.delete(Routes.CARD_DEP) do |conn| remove_dependency(conn, pool, lease_minutes) end
    |> Bond.post(Routes.CARD_RELEASE) do |conn| release_card(conn, pool) end
    |> Bond.post(Routes.CARD_MOVE) do |conn| move_card(conn, pool, lease_minutes) end
    |> Bond.post(Routes.CARD_DONE) do |conn| done_card(conn, pool) end
    |> Bond.post(Routes.CARD_CLAIM) do |conn| claim_card(conn, pool, lease_minutes) end
    |> Bond.get(Routes.CARD) do |conn| show_card(conn, pool) end
    |> Bond.patch(Routes.CARD) do |conn| update_card(conn, pool, lease_minutes) end
    |> Bond.post(Routes.CARD_COMMENTS) do |conn| add_comment(conn, pool, lease_minutes) end
    |> Bond.post(Routes.BOARD_COLUMNS) do |conn| add_column(conn, pool) end
    |> Bond.patch(Routes.COLUMN) do |conn| update_column(conn, pool) end
    |> Bond.delete(Routes.COLUMN) do |conn| delete_column(conn, pool) end
    |> Bond.get(Routes.BOARD_EVENTS) do |conn| board_events(conn, pool) end
  )
end

def list_boards(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  boards = Boards.list(pool.unwrap!)
  return ok(Failure.answer(conn, boards.message)) if not boards.ok?

  ok(Bond.json_as(conn, 200, BoardsAnswer.codec, BoardsAnswer(boards: boards.unwrap!)))
end

def create_board(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
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

def board_events(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  params = Bond.query_params(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid query", some("query"))) if not params.ok?

  query = params.unwrap!
  after = Params.number(query, "after", 0)
  limit = Params.number(query, "limit", 100)
  card = Params.number(query, "card", 0)
  if not after.ok? or not limit.ok? or not card.ok?
    return ok(Failure.reject(conn, 400, "INVALID", "invalid query", some("query")))
  end

  card_id: Optional[Int] = none
  if query.key?("card")
    card_id = some(card.unwrap!)
  end

  page = Events.list(pool.unwrap!, Bond.param(conn, "board").unwrap_or(""), after.unwrap!, card_id, limit.unwrap!)
  return ok(Failure.answer(conn, page.message)) if not page.ok?

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

def add_column(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, CreateColumn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  data = decoded.unwrap!
  input = Columns.Add(
    board: Bond.param(conn, "board").unwrap_or(""),
    name: data.name,
    position: data.position,
    done: data.done.unwrap_or(false),
    wip_limit: data.wip_limit,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
  )

  result = Columns.add(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 201, ColumnAnswer.codec, ColumnAnswer(column: result.unwrap!)))
end

def create_card(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
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

  ok(Bond.json_as(conn, 201, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def show_card(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  result = Cards.show(pool.unwrap!, id.unwrap!)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, Cards.Detail.codec, result.unwrap!))
end

def list_cards(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
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

def show_board(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  result = Snapshots.get(pool.unwrap!, Bond.param(conn, "board").unwrap_or(""))
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, Snapshots.Snapshot.codec, result.unwrap!))
end

def claim_card(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
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

  ok(Bond.json_as(conn, 200, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def claim_next(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
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

  ok(Bond.json_as(conn, 200, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def done_card(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
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

  ok(Bond.json_as(conn, 200, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def release_card(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
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

  ok(Bond.json_as(conn, 200, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def move_card(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
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

  ok(Bond.json_as(conn, 200, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def add_dependency(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
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

  ok(Bond.json_as(conn, 201, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def remove_dependency(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
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

  ok(Bond.json_as(conn, 200, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def update_column(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, UpdateColumn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  data = decoded.unwrap!
  input = Columns.Update(
    id: id.unwrap!,
    name: data.name,
    position: data.position,
    done: data.done,
    wip_limit: data.wip_limit,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
  )

  result = Columns.update(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, ColumnAnswer.codec, ColumnAnswer(column: result.unwrap!)))
end

def delete_column(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  input = Columns.Remove(id: id.unwrap!, actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""))
  result = Columns.remove(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.status(conn, 204))
end

def update_card(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
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

  ok(Bond.json_as(conn, 200, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def add_comment(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
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
