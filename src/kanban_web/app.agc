import Bond from "pkg/bond/bond"
import Regex from "std/regex"
import Boards from "../kanban/boards"
import Cards from "../kanban/cards"
import Claims from "../kanban/claims"
import Columns from "../kanban/columns"
import Deps from "../kanban/deps"
import Events from "../kanban/events"
import Snapshots from "../kanban/snapshots"
import Transitions from "../kanban/transitions"
import Database from "../kanban/repo/database"

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

struct ApiError
  code: String
  message: String
  field: Optional[String]
end

struct ClaimedError
  code: String
  message: String
  claimed_by: String
end

struct ClaimedAnswer
  error: ClaimedError
end

struct BlockedError
  code: String
  message: String
  blocked_by: List[Int]
end

struct BlockedAnswer
  error: BlockedError
end

struct ErrorAnswer
  error: ApiError
end

export def build(key: String, pool: Optional[Database.Pool] = none, lease_minutes: Int = 0) -> Bond.App
  (
    Bond.app()
    |> Bond.before() do |conn| authorize(conn, key) end
    |> Bond.get("/api/health", &health)
    |> Bond.get("/api/auth-check", &auth_check)
    |> Bond.get("/api/boards") do |conn| list_boards(conn, pool) end
    |> Bond.post("/api/boards") do |conn| create_board(conn, pool) end
    |> Bond.get("/api/boards/:board") do |conn| show_board(conn, pool) end
    |> Bond.post("/api/boards/:board/claim-next") do |conn| claim_next(conn, pool, lease_minutes) end
    |> Bond.get("/api/boards/:board/cards") do |conn| list_cards(conn, pool) end
    |> Bond.post("/api/boards/:board/cards") do |conn| create_card(conn, pool) end
    |> Bond.post("/api/cards/:id/deps") do |conn| add_dependency(conn, pool, lease_minutes) end
    |> Bond.delete("/api/cards/:id/deps/:other") do |conn| remove_dependency(conn, pool, lease_minutes) end
    |> Bond.post("/api/cards/:id/release") do |conn| release_card(conn, pool) end
    |> Bond.post("/api/cards/:id/move") do |conn| move_card(conn, pool, lease_minutes) end
    |> Bond.post("/api/cards/:id/done") do |conn| done_card(conn, pool) end
    |> Bond.post("/api/cards/:id/claim") do |conn| claim_card(conn, pool, lease_minutes) end
    |> Bond.get("/api/cards/:id") do |conn| show_card(conn, pool) end
    |> Bond.patch("/api/cards/:id") do |conn| update_card(conn, pool, lease_minutes) end
    |> Bond.post("/api/boards/:board/columns") do |conn| add_column(conn, pool) end
    |> Bond.patch("/api/columns/:id") do |conn| update_column(conn, pool) end
    |> Bond.delete("/api/columns/:id") do |conn| delete_column(conn, pool) end
    |> Bond.get("/api/boards/:board/events") do |conn| board_events(conn, pool) end
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

  if message.start_with?("CLAIMED:")
    holder = message.slice(8, message.length - 8)
    answer = ClaimedAnswer(error: ClaimedError(code: "CLAIMED", message: "card is claimed", claimed_by: holder))
    return Bond.json_as(conn, 409, ClaimedAnswer.codec, answer).with(halted: true)
  end

  if message.start_with?("BLOCKED:")
    ids = message.slice(8, message.length - 8).split(",").map do |value| value.to_i! end
    answer = BlockedAnswer(error: BlockedError(code: "BLOCKED", message: "card is blocked", blocked_by: ids))
    return Bond.json_as(conn, 409, BlockedAnswer.codec, answer).with(halted: true)
  end

  return reject(conn, 409, "CYCLE", "dependency cycle") if message.start_with?("CYCLE:")
  return reject(conn, 409, "NOT_CLAIMER", "agent does not hold the claim") if message.start_with?("NOT_CLAIMER:")
  return reject(conn, 409, "DONE", "card is done") if message.start_with?("DONE:")
  return reject(conn, 409, "CONFLICT", message) if message.start_with?("CONFLICT:")
  return reject(conn, 404, "NO_READY_CARD", "no ready card") if message.start_with?("NO_READY_CARD:")
  return reject(conn, 404, "NOT_FOUND", message) if message.start_with?("NOT_FOUND:")
  return reject(conn, 503, "BUSY", "database busy") if Database.busy?(message)

  reject(conn, 500, "INTERNAL", "internal error")
end

def board_events(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  params = Bond.query_params(conn)
  return ok(reject(conn, 400, "INVALID", "invalid query", some("query"))) if not params.ok?

  query = params.unwrap!
  after = query_number(query, "after", 0)
  limit = query_number(query, "limit", 100)
  card = query_number(query, "card", 0)
  if not after.ok? or not limit.ok? or not card.ok?
    return ok(reject(conn, 400, "INVALID", "invalid query", some("query")))
  end

  card_id: Optional[Int] = none
  if query.key?("card")
    card_id = some(card.unwrap!)
  end

  page = Events.list(pool.unwrap!, Bond.param(conn, "board").unwrap_or(""), after.unwrap!, card_id, limit.unwrap!)
  return ok(failure(conn, page.message)) if not page.ok?

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

def query_number(params: Map[String, List[String]], name: String, default: Int) -> Result[Int]
  case params.get(name)
    none -> ok(default)
    some(values) -> values[0].to_i()
  end
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
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  body = Bond.body_text(conn)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, CreateColumn)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

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
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 201, ColumnAnswer.codec, ColumnAnswer(column: result.unwrap!)))
end

def create_card(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  body = Bond.body_text(conn)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, CreateCard)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

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
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 201, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def show_card(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  result = Cards.show(pool.unwrap!, id.unwrap!)
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, Cards.Detail.codec, result.unwrap!))
end

def list_cards(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  params = Bond.query_params(conn)
  return ok(reject(conn, 400, "INVALID", "invalid query", some("query"))) if not params.ok?

  query = params.unwrap!
  ready = query_bool(query, "ready")
  done = query_bool(query, "done")
  return ok(reject(conn, 400, "INVALID", "invalid query", some("query"))) if not ready.ok? or not done.ok?

  filters = Cards.Filters(
    column: query_text(query, "column"),
    ready: ready.unwrap!,
    claimed_by: query_text(query, "claimed_by"),
    label: query_text(query, "label"),
    done: done.unwrap!,
  )

  result = Cards.list(pool.unwrap!, Bond.param(conn, "board").unwrap_or(""), filters)
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, CardsAnswer.codec, CardsAnswer(cards: result.unwrap!)))
end

def query_text(params: Map[String, List[String]], name: String) -> Optional[String]
  case params.get(name)
    none -> none
    some(values) -> some(values[0])
  end
end

def query_bool(params: Map[String, List[String]], name: String) -> Result[Optional[Bool]]
  case query_text(params, name)
    none -> ok(none)
    some("1") -> ok(some(true))
    some("0") -> ok(some(false))
    _ -> error("invalid boolean")
  end
end

def show_board(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  result = Snapshots.get(pool.unwrap!, Bond.param(conn, "board").unwrap_or(""))
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, Snapshots.Snapshot.codec, result.unwrap!))
end

def claim_card(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  data = JSON.parse(body.unwrap!)
  if not data.ok? or JSON.kind(data.unwrap!) != "object"
    return ok(reject(conn, 400, "INVALID", "invalid body", some("body")))
  end

  actor = Bond.request_header(conn, "X-Kanban-Agent").unwrap_or("")
  result = Claims.claim(pool.unwrap!, id.unwrap!, actor, lease_minutes)
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def claim_next(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  body = Bond.body_text(conn)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, ClaimNext)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  data = decoded.unwrap!
  input = Claims.Next(
    board: Bond.param(conn, "board").unwrap_or(""),
    column: data.column,
    label: data.label,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    lease_minutes: lease_minutes,
  )

  result = Claims.claim_next(pool.unwrap!, input)
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def done_card(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, ForceInput)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  input = Transitions.Action(
    id: id.unwrap!,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    force: decoded.unwrap!.force.unwrap_or(false),
  )

  result = Transitions.finish(pool.unwrap!, input)
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def release_card(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  data = JSON.decode(body.unwrap!, ReleaseInput)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not data.ok?

  input = Transitions.Release(
    id: id.unwrap!,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    force: data.unwrap!.force.unwrap_or(false),
    column: data.unwrap!.column,
  )

  result = Transitions.release(pool.unwrap!, input)
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def move_card(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  data = JSON.decode(body.unwrap!, MoveInput)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not data.ok?

  input = Transitions.Move(
    id: id.unwrap!,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    force: data.unwrap!.force.unwrap_or(false),
    column: data.unwrap!.column,
    position: data.unwrap!.position,
    lease_minutes: lease_minutes,
  )

  result = Transitions.move(pool.unwrap!, input)
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def add_dependency(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  data = JSON.decode(body.unwrap!, DependencyInput)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not data.ok?

  input = Deps.Change(
    card_id: id.unwrap!,
    depends_on: data.unwrap!.depends_on,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    lease_minutes: lease_minutes,
  )

  result = Deps.add(pool.unwrap!, input)
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 201, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def remove_dependency(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  other = Bond.param_int(conn, "other")
  return ok(reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok? or not other.ok?

  input = Deps.Change(
    card_id: id.unwrap!,
    depends_on: other.unwrap!,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    lease_minutes: lease_minutes,
  )

  result = Deps.remove(pool.unwrap!, input)
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end

def update_column(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, UpdateColumn)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

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
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, ColumnAnswer.codec, ColumnAnswer(column: result.unwrap!)))
end

def delete_column(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  input = Columns.Remove(id: id.unwrap!, actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""))
  result = Columns.remove(pool.unwrap!, input)
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.status(conn, 204))
end

def update_card(conn: Bond.Conn, pool: Optional[Database.Pool], lease_minutes: Int) -> Result[Bond.Conn]
  return ok(reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, UpdateCard)
  return ok(reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

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
  return ok(failure(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, CardAnswer.codec, CardAnswer(card: result.unwrap!)))
end
