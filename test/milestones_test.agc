import Db from "pkg/db/db"
import Migrate from "pkg/db/migrate"
import Sqlite from "pkg/db/sqlite"
import Milestones from "../src/kanban/milestones"
import Migrations from "../src/kanban/repo/migrations"

def put(conn: Db.Connection, sql: String) -> Result[Void]
  _ = try Db.execute(conn, sql, [])
  ok()
end

# Done cards count as closed whether or not they are archived, an archived card that was not done counts in
# neither, and
# the list puts open milestones first by due date (none last), then closed ones, the newest closed first.
def test_the_counts_and_the_order_of_milestones() -> Result[Void]
  conn = try Db.open("sqlite::memory:", [Sqlite.driver()])
  _ = try Migrate.up(conn, Migrations.all())
  try put(conn, "insert into boards (slug, name, created_at, updated_at) values ('p', 'P', 1, 1)")
  try put(
    conn,
    "insert into columns (board_id, name, position, done, created_at) values (1, 'Todo', 0, 0, 1), (1, 'Done', 1, 1, 1)",
  )

  try put(
    conn,
    "insert into labels (board_id, name, color, created_at) values (1, 'a', '#000000', 1), (1, 'b', '#000000', 1), (1, 'c', '#000000', 1), (1, 'd', '#000000', 1)",
  )

  try put(
    conn,
    "insert into milestones (label_id, due_on, closed_at, created_at) values (1, '2030-01-01', null, 1), (2, null, null, 1), (3, '2020-01-01', null, 1), (4, null, 5, 1)",
  )

  try put(
    conn,
    "insert into cards (board_id, column_id, position, title, labels, created_by, created_at, updated_at, archived_at) values (1, 1, 0, 'open', '[\"a\"]', 'x', 1, 1, null), (1, 2, 0, 'done', '[\"a\"]', 'x', 1, 1, null), (1, 2, 1, 'done archived', '[\"a\"]', 'x', 1, 1, 9), (1, 1, 1, 'dropped', '[\"a\"]', 'x', 1, 1, 9), (1, 1, 2, 'other', '[\"b\",\"c\"]', 'x', 1, 1, null)",
  )

  all = try Milestones.list_by_board_id(conn, 1, "all", "2026-06-01")
  open = try Milestones.list_by_board_id(conn, 1, "open", "2026-06-01")
  closed = try Milestones.list_by_board_id(conn, 1, "closed", "2026-06-01")
  Db.close(conn)
  try Test.eq(all.map(->(m) { m.name }), ["c", "a", "b", "d"])
  try Test.eq(open.map(->(m) { m.name }), ["c", "a", "b"])
  try Test.eq(closed.map(->(m) { m.name }), ["d"])
  a = all[1]
  try Test.eq([a.open, a.closed, a.percent], [1, 2, 66])
  try Test.eq(all.map(->(m) { m.overdue }), [true, false, false, false])
  Test.eq(all.map(->(m) { m.percent }), [0, 66, 0, 0])
end
