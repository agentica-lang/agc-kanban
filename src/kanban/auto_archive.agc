import Db from "pkg/db/db"
import Regex from "std/regex"
import Boards from "boards"
import Database from "repo/database"
import Transitions from "transitions"

## The name the server archives under: the actor of its events.
ACTOR = "auto-archive"

struct Setting
  board: String
  days: Optional[Int]
  actor: String
end

## Turns the automatic archive of a board on (`days`: its done cards are archived once they were done that many days
## ago, 1 to 36500) or off (none). One `board.updated` event records the change.
def set(pool: Database.Pool, input: Setting) -> Result[Boards.Board]
  return error("INVALID:board") if input.board.empty?
  return error("INVALID:days") if input.days.some? and (input.days.unwrap! < 1 or input.days.unwrap! > 36500)
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| write(tx, input) end end
end

## Archives, for every board that has the setting on, the done cards that were done long enough before `now`. Returns
## how many cards were archived. A board that fails does not stop the others: the next sweep tries it again.
def sweep(pool: Database.Pool, now: Int) -> Result[Int]
  boards = try Database.with_connection(pool) do |conn|
    Db.query(
      conn,
      "select slug, auto_archive_days as days from boards where auto_archive_days is not null order by id",
      [],
    )
  end

  total = 0
  for row in boards
    request = Transitions.ArchiveDone(board: text(row, "slug"), days: number(row, "days"), actor: ACTOR, now: now)
    result = Transitions.archive_done(pool, request)
    if result.ok?
      total = total + result.unwrap!.archived
    else
      IO.warn("kanban: auto-archive of #{request.board} failed: #{result.message}")
    end
  end

  ok(total)
end

private

def write(conn: Db.Connection, input: Setting) -> Result[Boards.Board]
  board = try Boards.get_open(conn, input.board)
  now = Time.now_ms()
  days: Db.Value = Db.Value.Null
  if input.days.some?
    days = Db.Value.Int(input.days.unwrap!)
  end

  _ = try Db.execute(
    conn,
    "update boards set auto_archive_days = ?, updated_at = ? where id = ?",
    [days, Db.Value.Int(now), Db.Value.Int(board.id)],
  )

  data = JSON.encode(JSON.object({"auto_archive_days": JSON.from(input.days)}))
  _ = try Db.execute(
    conn,
    "insert into events (board_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?)",
    [
      Db.Value.Int(board.id),
      Db.Value.Text("board.updated"),
      Db.Value.Text(input.actor),
      Db.Value.Text(data),
      Db.Value.Int(now),
    ],
  )

  Boards.get_open(conn, input.board)
end

def text(row: Db.Row, key: String) -> String
  case row.get(key, Db.Value.Null)
    Db.Value.Text(value) -> value
    _ -> ""
  end
end

def number(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> 0
  end
end
