## What the home page shows of every board: the cards per column, how many are blocked, who holds a card and when
## the board last changed. One read for all the boards, in four queries, so the page costs the same
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
  # The last event comes from the index of `events` (board_id, id): one lookup per board, no scan of the table.
  boards = try Db.query(
    conn,
    "select b.id, b.slug, b.name, coalesce((select e.created_at from events e where e.board_id = b.id order by e.id desc limit 1), b.created_at) as last_at from boards b order by b.id",
    [],
  )

  columns = try Db.query(
    conn,
    "select col.board_id, col.name, col.done, count(c.id) as n from columns col left join cards c on c.column_id = col.id and c.archived_at is null group by col.id order by col.board_id, col.position",
    [],
  )

  # Blocked as the server's ready rule says it (a dependency on any board counts): an open card with a dependency
  # that is not in a done column.
  blocked = try Db.query(
    conn,
    "select c.board_id, count(*) as n from cards c join columns col on col.id = c.column_id where c.archived_at is null and col.done = 0 and exists (select 1 from card_deps d join cards dep on dep.id = d.depends_on_id join columns dc on dc.id = dep.column_id where d.card_id = c.id and dep.archived_at is null and dc.done = 0) group by c.board_id",
    [],
  )

  # A card in the done column that still has a claimer holds nothing, so only open cards count.
  agents = try Db.query(
    conn,
    "select c.board_id, c.claimed_by as agent from cards c join columns col on col.id = c.column_id where c.archived_at is null and col.done = 0 and c.claimed_by is not null and (c.lease_until is null or c.lease_until > ?) group by c.board_id, c.claimed_by order by c.board_id, c.claimed_by",
    [Db.Value.Int(now)],
  )

  by_columns = group(columns)
  by_blocked = group(blocked)
  by_agents = group(agents)
  ok(boards.map(->(row) { overview(row, by_columns, by_blocked, by_agents) }))
end

# The rows by `board_id`, in the order they came, so each board finds its own without a pass over all the rows.
def group(rows: List[Db.Row]) -> Map[Int, List[Db.Row]]
  groups: Map[Int, List[Db.Row]] = {}
  for row in rows
    id = int_of(row, "board_id")
    groups = groups.put(id, groups.get(id, []).push(row))
  end

  groups
end

def overview(
  row: Db.Row,
  columns: Map[Int, List[Db.Row]],
  blocked: Map[Int, List[Db.Row]],
  agents: Map[Int, List[Db.Row]],
) -> Overview
  id = int_of(row, "id")
  stuck = blocked.get(id, [])
  blocked_count = 0
  if not stuck.empty?
    blocked_count = int_of(stuck[0], "n")
  end

  Overview(
    id: id,
    slug: text_of(row, "slug"),
    name: text_of(row, "name"),
    last_activity: int_of(row, "last_at"),
    columns: columns.get(id, [])
      .map do |each|
        ColumnCount(name: text_of(each, "name"), done: int_of(each, "done") == 1, cards: int_of(each, "n"))
      end,
    blocked: blocked_count,
    agents: agents.get(id, []).map do |each| text_of(each, "agent") end,
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
