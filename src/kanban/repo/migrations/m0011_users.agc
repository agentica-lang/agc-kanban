import Migrate from "pkg/db/migrate"

# The web login: the users (a username is stored in lowercase) and their sessions. A session row keeps the SHA-256 of
# the cookie's id, never the id.
def migration() -> Migrate.Migration
  Migrate.sql(
    11,
    "users",
    [
      "CREATE TABLE users ( id INTEGER PRIMARY KEY, username TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL, created_at INTEGER NOT NULL )",
      "CREATE TABLE sessions ( id INTEGER PRIMARY KEY, token_hash TEXT NOT NULL UNIQUE, user_id INTEGER NOT NULL REFERENCES users(id), created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL )",
      "CREATE INDEX sessions_expires_at ON sessions (expires_at)",
    ],
  )
end
