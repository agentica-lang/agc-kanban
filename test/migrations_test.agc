import Db from "pkg/db/db"
import Migrate from "pkg/db/migrate"
import Database from "../src/kanban/repo/database"
import Migrations from "../src/kanban/repo/migrations"

def test_schema_migrates_once() -> Result[Void]
  conn = try Db.open("sqlite::memory:")
  first = Migrate.up(conn, Migrations.all())
  second = Migrate.up(conn, Migrations.all())
  Db.close(conn)
  try Test.eq(first, ok([1, 2, 3, 4, 5, 6]))
  Test.eq(second, ok([]))
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
  Test.eq(versions, [1, 2, 3, 4, 5, 6])
end
