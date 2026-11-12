import Migrate from "pkg/db/migrate"

export def migration() -> Migrate.Migration
  Migrate.sql(
    3,
    "cards",
    [
      "CREATE TABLE cards ( id INTEGER PRIMARY KEY, board_id INTEGER NOT NULL REFERENCES boards(id), column_id INTEGER NOT NULL REFERENCES columns(id), position INTEGER NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL DEFAULT '', labels TEXT NOT NULL DEFAULT '[]', priority INTEGER NOT NULL DEFAULT 2, claimed_by TEXT, claimed_at INTEGER, lease_until INTEGER, branch TEXT, worktree TEXT, created_by TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, done_at INTEGER, archived_at INTEGER, version INTEGER NOT NULL DEFAULT 1 )",
      "CREATE INDEX cards_column ON cards (column_id, position)",
      "CREATE INDEX cards_board ON cards (board_id, archived_at)",
      "CREATE INDEX cards_claimed_by ON cards (claimed_by) WHERE claimed_by IS NOT NULL",
    ],
  )
end
