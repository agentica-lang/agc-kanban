import Db from "pkg/db/db"
import Migrate from "pkg/db/migrate"
import Cards from "../src/kanban/cards"
import Database from "../src/kanban/repo/database"
import Migrations from "../src/kanban/repo/migrations"

def test_schema_migrates_once() -> Result[Void]
  conn = try Db.open("sqlite::memory:")
  first = Migrate.up(conn, Migrations.all())
  second = Migrate.up(conn, Migrations.all())
  Db.close(conn)
  try Test.eq(first, ok([1, 2, 3, 4, 5, 6, 7, 8]))
  Test.eq(second, ok([]))
end

# A card stored before the links column reads with no links, and gets them afterwards.
def test_a_card_from_before_links_has_none() -> Result[Void]
  conn = try Db.open("sqlite::memory:")
  _ = try Migrate.up(conn, Migrations.all().select do |migration| migration.version < 7 end)
  _ = try Db.execute(conn, "insert into boards (slug, name, created_at, updated_at) values ('p', 'P', 1, 1)", [])
  _ = try Db.execute(
    conn,
    "insert into columns (board_id, name, position, done, created_at) values (1, 'Todo', 0, 0, 1)",
    [],
  )

  _ = try Db.execute(
    conn,
    "insert into cards (board_id, column_id, position, title, created_by, created_at, updated_at) values (1, 1, 0, 'old', 'agent', 1, 1)",
    [],
  )

  try Test.eq(Migrate.up(conn, Migrations.all()), ok([7, 8]))
  card = Cards.load_at(conn, 1, 2)
  Db.close(conn)
  Test.eq((try card).links, [])
end

def test_data_directory_and_restart() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-db-test-#{System.pid()}"
  first = try Database.open(dir)
  Database.close(first)
  second = try Database.open(dir)
  Database.close(second)
  info = try File.stat("#{dir}/kanban.sqlite3")
  try Path.remove("#{dir}/kanban.sqlite3")
  try Path.remove(dir)
  Test.eq(info.kind, "file")
end

def test_migration_versions_are_consecutive() -> Result[Void]
  versions = Migrations.all().map do |migration| migration.version end
  Test.eq(versions, [1, 2, 3, 4, 5, 6, 7, 8])
end

def test_migration_files_are_all_listed() -> Result[Void]
  files = try Dir.list("src/kanban/repo/migrations")
  listed = files.map do |file| version_of(file) end
  versions = Migrations.all().map do |migration| migration.version end
  Test.eq(listed, versions)
end

# Every REFERENCES above depends on the driver's foreign_keys pragma; assert it is on.
def test_foreign_keys_are_enforced() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-fk-test-#{System.pid()}"
  pool = try Database.open(dir)
  state = Database.with_connection(pool) do |conn|
    rows = try Db.query(conn, "pragma foreign_keys", [])
    broken = Db.execute(
      conn,
      "insert into cards (board_id, column_id, position, title, created_by, created_at, updated_at) values (999, 999, 0, 'x', 'agent', 1, 1)",
      [],
    )

    ok([number(rows[0], "foreign_keys") == 1, broken.ok?])
  end

  Database.close(pool)
  try Path.remove(dir)
  try Test.eq(try state, [true, false])
  ok()
end

def number(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end

# Migration files are mNNNN_name.agc; another shape is a bug in the repository.
def version_of(file: String) -> Int = file.slice(1, 4).to_i!

# A card stored before the search index is indexed by the migration, and the triggers keep it up to date afterwards.
def test_search_index_backfills_and_follows_edits() -> Result[Void]
  conn = try Db.open("sqlite::memory:")
  _ = try Migrate.up(conn, Migrations.all().select do |migration| migration.version < 8 end)
  _ = try Db.execute(conn, "insert into boards (slug, name, created_at, updated_at) values ('p', 'P', 1, 1)", [])
  _ = try Db.execute(
    conn,
    "insert into columns (board_id, name, position, done, created_at) values (1, 'Todo', 0, 0, 1)",
    [],
  )

  _ = try Db.execute(
    conn,
    "insert into cards (board_id, column_id, position, title, created_by, created_at, updated_at) values (1, 1, 0, 'old quokka', 'agent', 1, 1)",
    [],
  )

  _ = try Migrate.up(conn, Migrations.all())
  before = try Db.query(conn, "select rowid from card_search where card_search match 'quokka'", [])
  _ = try Db.execute(conn, "update cards set title = 'new wombat' where id = 1", [])
  gone = try Db.query(conn, "select rowid from card_search where card_search match 'quokka'", [])
  found = try Db.query(conn, "select rowid from card_search where card_search match 'wombat'", [])
  Db.close(conn)
  try Test.eq(before.size, 1)
  try Test.eq(gone.size, 0)
  Test.eq(found.size, 1)
end
