import Migrate from "pkg/db/migrate"

# A milestone is a label that the board flagged: the row holds what a label lacks. No label is one until someone
# flags it.
def migration() -> Migrate.Migration
  Migrate.sql(
    12,
    "milestones",
    [
      "CREATE TABLE milestones ( label_id INTEGER PRIMARY KEY REFERENCES labels(id), description TEXT NOT NULL DEFAULT '', due_on TEXT, closed_at INTEGER )",
    ],
  )
end
