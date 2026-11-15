## The users of the web login and their sessions. A session is a random id in the cookie; the store keeps its SHA-256
## (`token_hash`), so a copy of the database holds no id that works.

import Db from "pkg/db/db"
import Regex from "std/regex"
import Database from "repo/database"

## How long a session lives, from its start (7 days).
SESSION_MS = 604_800_000

## A user as the login reads it.
struct Account
  id: Int
  username: String
  password_hash: String
end

## The username as it is stored: no spaces around it, in lowercase, so that "Ana" and "ana" are one user.
def normalize(username: String) -> String = username.strip.downcase

## Why a username is refused (a phrase that goes after "The username"), or none when it is fine (`normalize` it first).
def username_problem(username: String) -> Optional[String]
  if username.length < 3 or username.length > 32
    return some("must be 3 to 32 characters long (it has #{username.length})")
  end

  return some("may have only letters, numbers, dots, dashes and underscores") if not valid?(username)

  none
end

## The id that goes in the cookie is this text hashed: what the store keeps and looks up.
def token_hash(token: String) -> String = OpenSSL.Digest.sha256_hexdigest(token.bytes)

## Whether any user exists. Registration is open only while none does.
def any?(pool: Database.Pool) -> Result[Bool]
  rows = try Database.with_connection(pool) do |conn| Db.query(conn, "select 1 as found from users limit 1", []) end
  ok(not rows.empty?)
end

## Creates the first user and its session in one transaction. The insert has the check in its own statement (no user
## yet), so two requests at once cannot both pass: the loser gets the error of kind `users.closed`.
def register(
  pool: Database.Pool,
  username: String,
  password_hash: String,
  token_hash: String,
  now: Int,
) -> Result[Void]
  Database.with_connection(pool) do |conn|
    Db.transaction(conn) do |tx| create_first(tx, username, password_hash, token_hash, now) end
  end
end

## The user of a (normalized) username, or none.
def find(pool: Database.Pool, username: String) -> Result[Optional[Account]]
  rows = try Database.with_connection(pool) do |conn|
    Db.query(conn, "select id, username, password_hash from users where username = ?", [Db.Value.Text(username)])
  end

  return ok(none) if rows.empty?

  ok(
    some(
      Account(
        id: number(rows[0], "id"),
        username: text(rows[0], "username"),
        password_hash: text(rows[0], "password_hash"),
      ),
    ),
  )
end

## Starts a session for a user and forgets the sessions that have ended.
def open_session(pool: Database.Pool, user_id: Int, token_hash: String, now: Int) -> Result[Void]
  Database.with_connection(pool) do |conn|
    Db.transaction(conn) do |tx|
      _ = try Db.execute(tx, "delete from sessions where expires_at <= ?", [Db.Value.Int(now)])
      insert_session(tx, user_id, token_hash, now)
    end
  end
end

## The username of a session that has not ended, or none.
def session_user(pool: Database.Pool, token_hash: String, now: Int) -> Result[Optional[String]]
  rows = try Database.with_connection(pool) do |conn|
    Db.query(
      conn,
      "select u.username as username from sessions s join users u on u.id = s.user_id where s.token_hash = ? and s.expires_at > ?",
      [Db.Value.Text(token_hash), Db.Value.Int(now)],
    )
  end

  return ok(none) if rows.empty?

  ok(some(text(rows[0], "username")))
end

## Ends a session (a hash that is not there is fine).
def close_session(pool: Database.Pool, token_hash: String) -> Result[Void]
  _ = try Database.with_connection(pool) do |conn|
    Db.execute(conn, "delete from sessions where token_hash = ?", [Db.Value.Text(token_hash)])
  end

  ok()
end

private

def valid?(username: String) -> Bool = Regex.match?(username, /^[a-z0-9._-]+$/)

def create_first(
  tx: Db.Connection,
  username: String,
  password_hash: String,
  token_hash: String,
  now: Int,
) -> Result[Void]
  inserted = try Db.execute(
    tx,
    "insert into users (username, password_hash, created_at) select ?, ?, ? where not exists (select 1 from users)",
    [Db.Value.Text(username), Db.Value.Text(password_hash), Db.Value.Int(now)],
  )

  return error("registration is closed: a user exists already", kind: "users.closed") if inserted == 0

  rows = try Db.query(tx, "select id from users where username = ?", [Db.Value.Text(username)])
  insert_session(tx, number(rows[0], "id"), token_hash, now)
end

def insert_session(tx: Db.Connection, user_id: Int, token_hash: String, now: Int) -> Result[Void]
  _ = try Db.execute(
    tx,
    "insert into sessions (token_hash, user_id, created_at, expires_at) values (?, ?, ?, ?)",
    [Db.Value.Text(token_hash), Db.Value.Int(user_id), Db.Value.Int(now), Db.Value.Int(now + SESSION_MS)],
  )

  ok()
end

def number(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end

def text(row: Db.Row, key: String) -> String
  case row.get(key, Db.Value.Null)
    Db.Value.Text(value) -> value
    _ -> ""
  end
end
