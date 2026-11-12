import Migrate from "pkg/db/migrate"

export def migration() -> Migrate.Migration
  Migrate.sql(
    4,
    "card_deps",
    [
      "CREATE TABLE card_deps ( card_id INTEGER NOT NULL REFERENCES cards(id), depends_on_id INTEGER NOT NULL REFERENCES cards(id), created_at INTEGER NOT NULL, PRIMARY KEY (card_id, depends_on_id), CHECK (card_id <> depends_on_id) )",
      "CREATE INDEX card_deps_reverse ON card_deps (depends_on_id)",
    ],
  )
end
