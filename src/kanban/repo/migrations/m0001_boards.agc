import Migrate from "pkg/db/migrate"

export def migration() -> Migrate.Migration
  Migrate.sql(
    1,
    "boards",
    [
      "CREATE TABLE boards ( id INTEGER PRIMARY KEY, slug TEXT NOT NULL UNIQUE, name TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL )",
    ],
  )
end
