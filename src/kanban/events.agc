import Db from "pkg/db/db"
import Database from "repo/database"

export struct Event
  id: Int
  board_id: Int
  card_id: Optional[Int]
  kind: String
  actor: String
  data: Json
  created_at: Int
end

export struct Page
  events: List[Event]
  last_event_id: Int
end

export def list(pool: Database.Pool, board: String, after: Int, card: Optional[Int], limit: Int) -> Result[Page]
  return error("INVALID:board") if board.empty?
  return error("INVALID:after") if after < 0
  return error("INVALID:card") if card.some? and card.unwrap! <= 0
  return error("INVALID:limit") if limit < 1 or limit > 1000

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| read(tx, board, after, card, limit) end end
end

def read(conn: Db.Connection, board: String, after: Int, card: Optional[Int], limit: Int) -> Result[Page]
  found = try Db.query(
    conn,
    "select id from boards where slug = ? or cast(id as text) = ? order by case when slug = ? then 0 else 1 end limit 1",
    [Db.Value.Text(board), Db.Value.Text(board), Db.Value.Text(board)],
  )

  return error("NOT_FOUND:board") if found.empty?

  id = int_of(found[0], "id")
  card_value = case card
    some(value) -> Db.Value.Int(value)
    none -> Db.Value.Null
  end

  rows = try Db.query(
    conn,
    "select id, board_id, card_id, kind, actor, data, created_at from events where board_id = ? and id > ? and (? is null or card_id = ?) order by id limit ?",
    [Db.Value.Int(id), Db.Value.Int(after), card_value, card_value, Db.Value.Int(limit)],
  )

  events: List[Event] = []
  for row in rows
    events = events.push(try event(row))
  end

  last = after
  if not events.empty?
    last = events[events.size - 1].id
  end

  ok(Page(events: events, last_event_id: last))
end

def event(row: Db.Row) -> Result[Event]
  data = try JSON.parse(text_of(row, "data"))
  card = case row.get("card_id", Db.Value.Null)
    Db.Value.Int(value) -> some(value)
    _ -> none
  end

  ok(
    Event(
      id: int_of(row, "id"),
      board_id: int_of(row, "board_id"),
      card_id: card,
      kind: text_of(row, "kind"),
      actor: text_of(row, "actor"),
      data: data,
      created_at: int_of(row, "created_at"),
    ),
  )
end

def int_of(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end

def text_of(row: Db.Row, key: String) -> String
  case row.get(key, Db.Value.Null)
    Db.Value.Text(value) -> value
    _ -> ""
  end
end
