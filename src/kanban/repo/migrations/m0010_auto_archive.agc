import Migrate from "pkg/db/migrate"

# Null (every board before this migration): the board does not archive its done cards by itself.
def migration() -> Migrate.Migration
  Migrate.sql(10, "auto_archive", ["ALTER TABLE boards ADD COLUMN auto_archive_days INTEGER"])
end
