import Db from "pkg/db/db"
import Migrate from "pkg/db/migrate"
import Sqlite from "pkg/db/sqlite"
import Labels from "../src/kanban/labels"
import Migrations from "../src/kanban/repo/migrations"

# The first use of a name gives it a palette color, the next names take colors that the board does not wear yet, and a
# known name keeps its color.
def test_a_new_label_gets_an_unused_palette_color() -> Result[Void]
  conn = try Db.open("sqlite::memory:", [Sqlite.driver()])
  _ = try Migrate.up(conn, Migrations.all())
  _ = try Db.execute(conn, "insert into boards (slug, name, created_at, updated_at) values ('p', 'P', 1, 1)", [])
  names = (1..Labels.PALETTE.size).map do |n| "label-#{n}" end
  try Labels.ensure(conn, 1, names + [" "], 1)
  first = try Labels.list_by_board_id(conn, 1)
  colors = first.map do |label| label.color end
  try Labels.ensure(conn, 1, names + ["extra"], 2)
  second = try Labels.list_by_board_id(conn, 1)
  Db.close(conn)
  try Test.eq(first.size, Labels.PALETTE.size)
  try Test.eq(colors.uniq.size, Labels.PALETTE.size)
  try Test.eq(colors.all? { |color| Labels.PALETTE.include?(color) }, true)
  try Test.eq(second.size, Labels.PALETTE.size + 1)
  kept = second.select { |label| names.include?(label.name) }.map { |label| label.color }
  Test.eq(kept.sort, colors.sort)
end
