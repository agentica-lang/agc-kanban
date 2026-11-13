import Migrate from "pkg/db/migrate"

def migration() -> Migrate.Migration
  Migrate.sql(
    5,
    "comments",
    [
      "CREATE TABLE comments ( id INTEGER PRIMARY KEY, card_id INTEGER NOT NULL REFERENCES cards(id), author TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL )",
      "CREATE INDEX comments_card ON comments (card_id, id)",
    ],
  )
end
