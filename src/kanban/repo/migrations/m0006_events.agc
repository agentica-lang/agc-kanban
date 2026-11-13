import Migrate from "pkg/db/migrate"

def migration() -> Migrate.Migration
  Migrate.sql(
    6,
    "events",
    [
      "CREATE TABLE events ( id INTEGER PRIMARY KEY, board_id INTEGER NOT NULL REFERENCES boards(id), card_id INTEGER REFERENCES cards(id), kind TEXT NOT NULL, actor TEXT NOT NULL, data TEXT NOT NULL, created_at INTEGER NOT NULL )",
      "CREATE INDEX events_board ON events (board_id, id)",
      "CREATE INDEX events_card ON events (card_id, id)",
    ],
  )
end
