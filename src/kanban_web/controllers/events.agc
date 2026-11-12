import Bond from "pkg/bond/bond"
import Database from "../../kanban/repo/database"
import Events from "../../kanban/events"
import Failure from "../failure"
import Params from "../params"

export def index(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  params = Bond.query_params(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid query", some("query"))) if not params.ok?

  query = params.unwrap!
  after = Params.number(query, "after", 0)
  limit = Params.number(query, "limit", 100)
  card = Params.number(query, "card", 0)
  before = Params.number(query, "before", 0)
  if not after.ok? or not limit.ok? or not card.ok? or not before.ok? or (query.key?("before") and query.key?("after"))
    return ok(Failure.reject(conn, 400, "INVALID", "invalid query", some("query")))
  end

  card_id: Optional[Int] = none
  if query.key?("card")
    card_id = some(card.unwrap!)
  end

  before_id: Optional[Int] = none
  if query.key?("before")
    before_id = some(before.unwrap!)
  end

  page = Events.list(
    pool.unwrap!,
    Bond.param(conn, "board").unwrap_or(""),
    after.unwrap!,
    before_id,
    card_id,
    limit.unwrap!,
  )

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
