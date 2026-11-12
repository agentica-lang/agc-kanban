import Db from "pkg/db/db"
import Prop from "pkg/prop/prop"
import Boards from "../src/kanban/boards"
import Cards from "../src/kanban/cards"
import Claims from "../src/kanban/claims"
import Comments from "../src/kanban/comments"
import Deps from "../src/kanban/deps"
import Database from "../src/kanban/repo/database"
import Transitions from "../src/kanban/transitions"

enum DepAction
  Add
  Remove
end

def test_command_sequences_keep_invariants() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-property-test-#{System.pid()}"
  pool = try Database.open(dir)
  _ = try Boards.create(pool, "Project", "project", "agent", ["Todo", "Doing", "Review", "Done"])
  # 25 runs of up to 10 commands fit the runner's step budget; 40 exhaust it.
  commands = Prop.list(Prop.int(0, 9), 10)
  outcome = Prop.check(commands, Prop.Config(runs: 25)) do |steps| run_sequence(pool, steps) end
  Database.close(pool)
  try Path.remove("#{dir}/kanban.sqlite3")
  _ = Path.remove(dir)
  outcome
end

def run_sequence(pool: Database.Pool, steps: List[Int]) -> Result[Void]
  try reset(pool)
  _ = try Boards.create(pool, "Project", "project", "agent", ["Todo", "Doing", "Review", "Done"])
  for seed in 1..3
    _ = try Cards.create(pool, card_input("Base #{seed}", [], "agent-a"))
  end

  try Prop.eq(try violations(pool), [])
  for index in 0...steps.size
    try apply(pool, index, steps[index])
    try Prop.eq(try violations(pool), [])
  end

  ok()
end

def apply(pool: Database.Pool, index: Int, code: Int) -> Result[Void]
  ids = try card_ids(pool)
  agent = ["agent-a", "agent-b", "agent-c"][index % 3]
  target = ids[index % ids.size]
  column = ["Todo", "Doing", "Review", "Done"][index % 4]
  case code
    0 -> discard(Cards.create(pool, card_input("C#{index}", [], agent)))
    1 -> discard(Cards.create(pool, card_input("D#{index}", [target], agent)))
    2 -> discard(Claims.claim(pool, target, agent, 30))
    3 -> discard(Transitions.release(pool, Transitions.Release(id: target, actor: agent, force: false, column: none)))
    4 ->
      discard(
        Transitions.move(
          pool,
          Transitions.Move(id: target, actor: agent, force: false, column: column, position: none, lease_minutes: 30),
        ),
      )
    5 -> discard(Transitions.finish(pool, Transitions.Action(id: target, actor: agent, force: false)))
    6 -> discard(dependency(pool, DepAction.Add, target, ids[(index + 1) % ids.size], agent))
    7 -> discard(dependency(pool, DepAction.Remove, target, ids[(index + 1) % ids.size], agent))
    8 ->
      discard(
        Comments.add(pool, Comments.Add(card_id: target, body: "note #{index}", actor: agent, lease_minutes: 30)),
      )
    _ ->
      discard(
        Claims.claim_next(
          pool,
          Claims.Next(board: "project", column: none, label: none, actor: agent, lease_minutes: 30),
        ),
      )
  end
end

def card_input(title: String, depends_on: List[Int], actor: String) -> Cards.Create
  Cards.Create(
    board: "project",
    title: title,
    body: "",
    column: none,
    labels: [],
    priority: 2,
    depends_on: depends_on,
    actor: actor,
  )
end

def dependency(pool: Database.Pool, action: DepAction, card_id: Int, other: Int, actor: String) -> Result[Cards.Card]
  change = Deps.Change(card_id: card_id, depends_on: other, actor: actor, lease_minutes: 30)
  case action
    DepAction.Add -> Deps.add(pool, change)
    DepAction.Remove -> Deps.remove(pool, change)
  end
end

def discard[T](value: Result[T]) -> Result[Void]
  return ok() if value.ok?

  ok()
end

def reset(pool: Database.Pool) -> Result[Void]
  Database.with_connection(pool) do |conn|
    Db.transaction(conn) do |tx|
      _ = try Db.execute(tx, "delete from comments", [])
      _ = try Db.execute(tx, "delete from events", [])
      _ = try Db.execute(tx, "delete from card_deps", [])
      _ = try Db.execute(tx, "delete from cards", [])
      _ = try Db.execute(tx, "delete from columns", [])
      _ = try Db.execute(tx, "delete from boards", [])
      ok()
    end
  end
end

def card_ids(pool: Database.Pool) -> Result[List[Int]]
  Database.with_connection(pool) do |conn| ids(conn, "select id from cards order by id") end
end

def ids(conn: Db.Connection, sql: String) -> Result[List[Int]]
  rows = try Db.query(conn, sql, [])
  ok(rows.map do |row| number(row, "id") end)
end

def violations(pool: Database.Pool) -> Result[List[String]]
  Database.with_connection(pool) do |conn|
    found: List[String] = []
    claimed_done = try ids(
      conn,
      "select c.id from cards c join columns col on col.id = c.column_id where c.claimed_by is not null and col.done = 1",
    )

    for id in claimed_done
      found = found.push("card #{id} is claimed in the done column")
    end

    misplaced = try ids(
      conn,
      "select c.id from cards c join columns col on col.id = c.column_id where (col.done = 1 and c.done_at is null) or (col.done = 0 and c.done_at is not null)",
    )

    for id in misplaced
      found = found.push("card #{id} has a wrong done_at")
    end

    half_claims = try ids(
      conn,
      "select id from cards where (claimed_by is null and (claimed_at is not null or lease_until is not null)) or (claimed_by is not null and claimed_at is null)",
    )

    for id in half_claims
      found = found.push("card #{id} has half a claim")
    end

    negative = try ids(conn, "select id from cards where position < 0")
    for id in negative
      found = found.push("card #{id} has a negative position")
    end

    duplicated = try ids(
      conn,
      "select min(id) from cards where archived_at is null group by column_id, position having count(*) > 1",
    )

    for id in duplicated
      found = found.push("cards share the position of card #{id}")
    end

    boards = try ids(conn, "select board_id as id from columns where done = 1 group by board_id having count(*) != 1")
    for id in boards
      found = found.push("board #{id} does not have exactly one done column")
    end

    cycles = try ids(
      conn,
      "with recursive reach(card_id, depends_on_id) as (select card_id, depends_on_id from card_deps union select r.card_id, d.depends_on_id from reach r join card_deps d on d.card_id = r.depends_on_id) select card_id as id from reach where card_id = depends_on_id limit 1",
    )

    for id in cycles
      found = found.push("card #{id} is in a dependency cycle")
    end

    ok(found)
  end
end

def number(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end
