import Migrate from "pkg/db/migrate"

# Cards made before this migration get no links.
def migration() -> Migrate.Migration
  Migrate.sql(7, "card_links", ["ALTER TABLE cards ADD COLUMN links TEXT NOT NULL DEFAULT '[]'"])
end
