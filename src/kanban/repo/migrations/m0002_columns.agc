import Migrate from "pkg/db/migrate"

export def migration() -> Migrate.Migration
  Migrate.sql(
    2,
    "columns",
    [
      "CREATE TABLE columns ( id INTEGER PRIMARY KEY, board_id INTEGER NOT NULL REFERENCES boards(id), name TEXT NOT NULL, position INTEGER NOT NULL, done INTEGER NOT NULL DEFAULT 0, wip_limit INTEGER, created_at INTEGER NOT NULL, UNIQUE (board_id, name), UNIQUE (board_id, position) )",
      "CREATE UNIQUE INDEX columns_one_done ON columns (board_id) WHERE done = 1",
    ],
  )
end
