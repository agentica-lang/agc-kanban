import Db from "pkg/db/db"
import Boards from "boards"
import Cards from "cards"
import Database from "repo/database"

struct Snapshot
  board: Boards.Board
  cards: List[Cards.Card]
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
  rows = try Db.query(
    conn,
    "select coalesce(max(id), 0) as id from events where board_id = ?",
    [Db.Value.Int(board.id)],
  )

  last = case rows[0].get("id", Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> 0
  end

  ok(Snapshot(board: board, cards: cards, last_event_id: last))
end
