## What the home page shows of every board: the cards per column, how many are blocked, who holds a card and when
## the board last changed. One read for all the boards, in a fixed number of queries, so the page costs the same
## with 3 boards or 300.

import Db from "pkg/db/db"
import Database from "repo/database"

export struct ColumnCount
  name: String
  done: Bool
  cards: Int
end

export struct Overview
  id: Int
  slug: String
  name: String
  last_activity: Int
  columns: List[ColumnCount]
  blocked: Int
  agents: List[String]
end

## The boards in creation order. `now` decides which claims still hold: a claim whose lease ran out is not an active
## agent. The cards counted are the ones that are not archived, as on the board page.
export def list(pool: Database.Pool, now: Int) -> Result[List[Overview]]
  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| read(tx, now) end end
end

def read(conn: Db.Connection, now: Int) -> Result[List[Overview]]
  boards = try Db.query(conn, "select id, slug, name, created_at from boards order by id", [])
  columns = try Db.query(
    conn,
    "select col.board_id, col.name, col.done, count(c.id) as n from columns col left join cards c on c.column_id = col.id and c.archived_at is null group by col.id order by col.board_id, col.position",
    [],
  )

  # Blocked as the board page says it: an open card with a dependency that is not in a done column.
  blocked = try Db.query(
    conn,
    "select c.board_id, count(*) as n from cards c join columns col on col.id = c.column_id where c.archived_at is null and col.done = 0 and exists (select 1 from card_deps d join cards dep on dep.id = d.depends_on_id join columns dc on dc.id = dep.column_id where d.card_id = c.id and dep.archived_at is null and dc.done = 0) group by c.board_id",
    [],
  )

  agents = try Db.query(
    conn,
    "select c.board_id, c.claimed_by as agent from cards c join columns col on col.id = c.column_id where c.archived_at is null and col.done = 0 and c.claimed_by is not null and (c.lease_until is null or c.lease_until > ?) group by c.board_id, c.claimed_by order by c.board_id, c.claimed_by",
    [Db.Value.Int(now)],
  )

  events = try Db.query(conn, "select board_id, max(created_at) as at from events group by board_id", [])
  ok(boards.map do |row| overview(row, columns, blocked, agents, events) end)
end

def overview(
  row: Db.Row,
  columns: List[Db.Row],
  blocked: List[Db.Row],
  agents: List[Db.Row],
  events: List[Db.Row],
) -> Overview
  id = int_of(row, "id")
  mine = columns.select do |each| int_of(each, "board_id") == id end
  stuck = blocked.select do |each| int_of(each, "board_id") == id end
  held = agents.select do |each| int_of(each, "board_id") == id end
  seen = events.select do |each| int_of(each, "board_id") == id end
  last = int_of(row, "created_at")
  if not seen.empty?
    last = int_of(seen[0], "at")
  end

  blocked_count = 0
  if not stuck.empty?
    blocked_count = int_of(stuck[0], "n")
  end

  Overview(
    id: id,
    slug: text_of(row, "slug"),
    name: text_of(row, "name"),
    last_activity: last,
    columns: mine.map do |each|
      ColumnCount(name: text_of(each, "name"), done: int_of(each, "done") == 1, cards: int_of(each, "n"))
    end,
    blocked: blocked_count,
    agents: held.map do |each| text_of(each, "agent") end,
  )
end

def int_of(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> 0
  end
end

def text_of(row: Db.Row, key: String) -> String
  case row.get(key, Db.Value.Null)
    Db.Value.Text(value) -> value
    _ -> ""
  end
end
