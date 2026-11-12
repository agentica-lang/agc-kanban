## The live side: `/cable` (Action Cable on bond-channels) and the broadcast of every event after its write.
##
## `BoardChannel` (param `board`, the slug) streams `board:SLUG`. The publisher is an actor (`std/actor`) under a
## supervisor (`std/supervisor`). It reads the events that are newer than the last one it sent and broadcasts them,
## so a broadcast always follows the commit, never runs inside it, and goes out in the order of the journal. A write
## sends it `Nudge`; a timer sends `Tick` each second, so a lost nudge is a delay and not a missed event. A client that
## misses a broadcast (a reconnect) fetches the board again.
##
## The cursor (the id of the last event sent) lives in an `ATS` cell, not in the state of the actor: a restart gives
## the actor a new state from `init`, and the cell is what lets the new one go on from the same place, so a crash
## loses no event. (Seeding the new state from a stored id would need the same cell, so the cell is the simpler way.)
##
## The supervisor gives up after a few crashes and then crashes itself, which would end the live updates. So a bad
## event must never become a crash loop: `handle` sends each event in a task of its own, counts the failures of that
## one event, and after MAX_FAILURES moves the cursor past it. The actor crashes only for a real bug of its own.

import Actor from "std/actor"
import Supervisor from "std/supervisor"
import Bond from "pkg/bond/bond"
import Channels from "pkg/channels/channels"
import Auth from "auth"
import Database from "../kanban/repo/database"
import Events from "../kanban/events"
import Restarts from "restarts"
import Routes from "routes"

BOARD_CHANNEL = "BoardChannel"
PUBLISHER = "publisher"
LAST = "last"
BATCH = 100
TICK_MS = 1_000
# The failures of one event that make it a poison event: the publisher goes on after it. A bad `data` row is a
# different case: the read returns an error, which `flush` logs, and the cursor stays, so the live feed stops at that
# row until it is fixed (a client still gets the event on a reload). Only the failure of a send is counted.
MAX_FAILURES = 5
# The address of the publisher: a restart gives a new actor a new address, so the writes look it up on each nudge.
NAMES: ATS[String, Address[Msg]] = ATS.new()

# `Start` gives the actor its context. `init` takes no argument and there are no closures in this version, so the
# register block of the child, which runs for each new actor (a restart too), sends `Start` first. Until then the
# state is `none` and the other messages do nothing. The cursor cell inside the context is shared by all the actors.
enum Msg
  Start(Publisher)
  Nudge
  Tick
end

## What the writes need: the hub of the channels. The publisher is reached by name.
export struct Cable
  hub: Channels.Hub
end

# The state of the publisher actor. `bad` and `failures` are the event that failed last and its count in a row.
struct Publisher
  pool: Database.Pool
  hub: Channels.Hub
  cursor: ATS[String, Int]
  bad: Int
  failures: Int
end

## Starts the hub and, with a database, the publisher under a supervisor and its timer. Call it from the main task:
## the supervisor and the timer are its children.
export def start(pool: Optional[Database.Pool]) -> Cable
  hub = Channels.start_hub().unwrap!
  if pool.some?
    cursor: ATS[String, Int] = ATS.new()
    job = Publisher(pool: pool.unwrap!, hub: hub, cursor: cursor, bad: 0, failures: 0)
    # One try here, so that a write that follows the start is seen; the actor retries while the read fails.
    _ = seeded(job)
    behaviour: Actor.Behaviour[Optional[Publisher], Msg] = Actor.Behaviour(init: &idle, handle: &handle)
    child = Supervisor.child(PUBLISHER, behaviour) do |address|
      _ = Actor.cast(address, Msg.Start(job))
      NAMES.put(PUBLISHER, address)
    end

    _ = Supervisor.start([child])
    _ = Task.spawn(&ticker)
  end

  Cable(hub: hub)
end

## Mounts `/cable`.
export def mount(app: Bond.App, cable: Cable) -> Bond.App
  options = Channels.MountOptions(connect: &connect, handlers: {BOARD_CHANNEL: Channels.handler(&board_subscribed)})
  Channels.mount(app, Routes.CABLE, cable.hub, options).unwrap!
end

## Tells the publisher that a write may have added events.
export def nudge(_cable: Cable) -> Void
  cast(Msg.Nudge)
end

# The session was checked at the handshake: no session is an `unauthorized` disconnect, and the client stays out.
def connect(conn: Bond.Conn) -> Result[Channels.Identity]
  return error("no session") if not Auth.signed_in?(conn)

  ok(Channels.Identity(id: "owner", data: JSON.from("owner")))
end

def board_subscribed(session: Channels.Session, params: Json) -> Result[Channels.Subscription]
  board = try JSON.string(try JSON.get(params, "board"))
  return error("board is empty") if board.empty?

  ok(Channels.Subscription(streams: ["board:#{board}"]))
end

# Casts `Tick` to the publisher each second, wherever it lives now.
def ticker() -> Void
  while true
    Task.sleep(TICK_MS)
    cast(Msg.Tick)
  end
end

# A full inbox drops the message (timeout 0): a later tick or nudge reads the same journal.
def cast(message: Msg) -> Void
  found = NAMES.get(PUBLISHER)
  if found.ok?
    _ = Actor.cast(found.unwrap!, message, 0)
  end
end

def idle() -> Optional[Publisher] = none

def handle(state: Optional[Publisher], message: Msg) -> Actor.Step[Optional[Publisher]]
  case message
    Msg.Start(job) -> Actor.continue(some(flush(seeded(job))))
    Msg.Nudge -> Actor.continue(step(state))
    Msg.Tick -> Actor.continue(step(state))
  end
end

def step(state: Optional[Publisher]) -> Optional[Publisher]
  return none if not state.some?

  some(flush(seeded(state.unwrap!)))
end

# The live broadcast starts at the newest event, so that history is not replayed. A failed read leaves the cursor
# unset: replaying the journal from 0 would flood the clients. The next message tries again.
def seeded(job: Publisher) -> Publisher
  return job if job.cursor.get(LAST).ok?

  newest = Events.latest_id(job.pool)
  if not newest.ok?
    IO.warn("kanban: live start read failed: #{newest.message}")
    return job
  end

  job.cursor.put(LAST, newest.unwrap!)
  job
end

# Sends the events after the cursor and moves it. A failed read keeps it, so the next tick tries again. A send that
# crashes stops the batch and keeps the cursor on that event: the next tick tries it again, until MAX_FAILURES.
def flush(job: Publisher) -> Publisher
  last = job.cursor.get(LAST)
  return job if not last.ok?

  found = Events.published_after(job.pool, last.unwrap!, BATCH)
  if not found.ok?
    IO.warn("kanban: live read failed: #{found.message}")
    return job
  end

  state = job
  for item in found.unwrap!
    outcome = Task.await(Task.spawn do send(job.hub, item) end)
    if outcome.ok?
      state.cursor.put(LAST, item.event.id)
      state = state.with(bad: 0, failures: 0)
    else
      id = item.event.id
      failures = Restarts.next_failures(state.bad, state.failures, id)
      IO.warn("kanban: the live send of the event #{id} failed (#{failures}): #{outcome.message}")
      return state.with(bad: id, failures: failures) if failures < MAX_FAILURES

      IO.warn("kanban: skipping the event #{id}; a client sees it on reload")
      state.cursor.put(LAST, id)
      state = state.with(bad: 0, failures: 0)
    end
  end

  return flush(state) if found.unwrap!.size == BATCH

  state
end

# A failed broadcast is logged and dropped, and the cursor moves on: a client can miss that event in its feed until
# it reloads. The journal still has it, and the board itself is fetched again after each event.
def send(hub: Channels.Hub, item: Events.Published) -> Result[Void]
  result = Channels.broadcast_json(hub, "board:#{item.slug}", payload(item.event))
  if not result.ok?
    IO.warn("kanban: broadcast failed: #{result.message}")
  end

  ok()
end

def payload(event: Events.Event) -> Json
  JSON.object({
    "type": JSON.from(event.kind),
    "event_id": JSON.from(event.id),
    "board_id": JSON.from(event.board_id),
    "card_id": JSON.from(event.card_id),
    "actor": JSON.from(event.actor),
    "data": event.data,
    "at": JSON.from(event.created_at),
  })
end
