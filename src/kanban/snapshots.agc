import Db from "pkg/db/db"
import Boards from "boards"
import Cards from "cards"
import Database from "repo/database"
import Labels from "labels"

## When a card came into the column it is in now, in ms: the page shows the time in the column of every card of the board
## without reading the events of each one.
struct Since
  id: Int
  since: Int
end

struct Snapshot
  board: Boards.Board
  cards: List[Cards.Card]
  labels: List[Labels.Label]
  column_since: List[Since]
  last_event_id: Int
end

def get(pool: Database.Pool, reference: String) -> Result[Snapshot]
  return error("INVALID:board") if reference.empty?

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| read(tx, reference) end end
end

private

def read(conn: Db.Connection, reference: String) -> Result[Snapshot]
  board = try Boards.get_open(conn, reference)
  filters = Cards.Filters(column: none, ready: none, claimed_by: none, label: none, done: none)
  cards = try Cards.list_open(conn, board.slug, filters)
  labels = try Labels.list_by_board_id(conn, board.id)
  rows = try Db.query(
    conn,
    "select coalesce(max(id), 0) as id from events where board_id = ?",
    [Db.Value.Int(board.id)],
  )

  since = try column_since(conn, board.id)
  last = case rows[0].get("id", Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> 0
  end

  ok(Snapshot(board: board, cards: cards, labels: labels, column_since: since, last_event_id: last))
end

# The first event of the run in the current column: every event that names a column counts as a stay there, as in
# `Cards.steps_of`, and the run starts after the last event that named another column.
def column_since(conn: Db.Connection, board_id: Int) -> Result[List[Since]]
  rows = try Db.query(
    conn,
    "with s as (select id, card_id, created_at as at, coalesce(json_extract(data, '$.column_id'), json_extract(data, '$.card.column_id')) as column_id from events where board_id = ? and card_id is not null) select c.id as id, (select min(a.at) from s a where a.card_id = c.id and a.column_id is not null and a.id > coalesce((select max(b.id) from s b where b.card_id = c.id and b.column_id is not null and b.column_id != c.column_id), 0)) as since from cards c where c.board_id = ? and c.archived_at is null",
    [Db.Value.Int(board_id), Db.Value.Int(board_id)],
  )

  found: List[Since] = []
  for row in rows
    id = int_of(row, "id")
    since = int_of(row, "since")
    if since > 0
      found = found.push(Since(id: id, since: since))
    end
  end

  ok(found)
end

def int_of(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> 0
  end
end
