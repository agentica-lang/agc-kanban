## The live side: `/cable` (Action Cable on bond-channels) and the broadcast of every event after its write.
##
## `BoardChannel` (param `board`, the slug) streams `board:SLUG`. A task of its own, the publisher, reads the events
## that are newer than the last one it sent and broadcasts them, so a broadcast always follows the commit, never runs
## inside it, and goes out in the order of the journal. A write nudges it (`nudge`); a slow tick catches an event that a
## nudge missed, so a lost wake-up is a delay and not a missed event. A client that misses a broadcast (a reconnect)
## fetches the board again.
##
## The cursor (the id of the last event sent) lives in an `ATS` table, not in the loop of the publisher: a supervisor task
## starts the publisher again if it crashes, and the new one goes on from the cursor, so a crash loses no event.

import Bond from "pkg/bond/bond"
import Channels from "pkg/channels/channels"
import Auth from "auth"
import Database from "../kanban/repo/database"
import Events from "../kanban/events"
import Restarts from "restarts"
import Routes from "routes"

BOARD_CHANNEL = "BoardChannel"
LAST = "last"
# The id of the event the publisher is sending now (0 between events), so that a crash names the event it died on.
CURRENT = "current"
BATCH = 100
TICK_MS = 1_000
# A crash on the same event this many times in a row is a poison event: the publisher goes on after it. A bad `data`
# row is not a crash: the read returns an error, which `flush` logs, and the cursor stays and the read is tried again
# on each tick (the live feed stops until the row is fixed). Only a crash is counted.
MAX_RESTARTS = 5

## What the writes and the publisher share: the nudge channel (one place, a nudge while one waits is enough).
export struct Cable
  hub: Channels.Hub
  wake: Channel[Int]
end

struct Publisher
  pool: Database.Pool
  hub: Channels.Hub
  wake: Channel[Int]
  cursor: ATS[String, Int]
end

## Starts the hub and, with a database, the publisher.
export def start(pool: Optional[Database.Pool]) -> Cable
  hub = Channels.start_hub().unwrap!
  wake: Channel[Int] = Channel.new(1)
  if pool.some?
    cursor: ATS[String, Int] = ATS.new()
    job = Publisher(pool: pool.unwrap!, hub: hub, wake: wake, cursor: cursor)
    # One try here, so that a write that follows the start is seen; `publish` retries while the read fails.
    _ = seeded?(job)
    _ = Task.spawn(&supervise, job)
  end

  Cable(hub: hub, wake: wake)
end

## Mounts `/cable`.
export def mount(app: Bond.App, cable: Cable) -> Bond.App
  options = Channels.MountOptions(connect: &connect, handlers: {BOARD_CHANNEL: Channels.handler(&board_subscribed)})
  Channels.mount(app, Routes.CABLE, cable.hub, options).unwrap!
end

## Tells the publisher that a write may have added events.
export def nudge(cable: Cable) -> Void
  _ = cable.wake.send(1, 0)
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

# Runs the publisher and runs it again after a crash (a runtime error in a task ends only that task). `publish` records
# the event it is sending in CURRENT; after MAX_RESTARTS crashes on that same event the cursor moves past it, so the
# live feed does not stay stuck. Only that event is skipped: it stays in the journal, and a client sees it on reload.
def supervise(job: Publisher) -> Void
  bad = 0
  failures = 0
  while not job.wake.closed?
    outcome = Task.await(Task.spawn(&publish, job))
    if not outcome.ok?
      IO.warn("kanban: the live publisher stopped, starting it again: #{outcome.message}")
      handling = job.cursor.get(CURRENT).unwrap_or(0)
      failures = Restarts.next_failures(bad, failures, handling)
      bad = handling
      if bad > 0 and failures >= MAX_RESTARTS
        IO.warn("kanban: skipping the event #{bad} after #{MAX_RESTARTS} crashes of the live publisher")
        job.cursor.put(LAST, bad)
        job.cursor.put(CURRENT, 0)
        bad = 0
        failures = 0
      end

      Task.sleep(TICK_MS)
    end
  end
end

# The live broadcast starts at the newest event, so that history is not replayed. A failed read leaves the cursor
# unset: replaying the journal from 0 would flood the clients.
def seeded?(job: Publisher) -> Bool
  return true if job.cursor.get(LAST).ok?

  newest = Events.latest_id(job.pool)
  if not newest.ok?
    IO.warn("kanban: live start read failed: #{newest.message}")
    return false
  end

  job.cursor.put(LAST, newest.unwrap!)
  true
end

def publish(job: Publisher) -> Result[Void]
  while not seeded?(job)
    Task.sleep(TICK_MS)
  end

  while not job.wake.closed?
    _ = job.wake.recv(TICK_MS)
    flush(job)
  end

  ok()
end

# Sends the events after the cursor and moves it. A failed read keeps it, so the next tick tries again.
def flush(job: Publisher) -> Void
  last = job.cursor.get(LAST).unwrap_or(0)
  found = Events.published_after(job.pool, last, BATCH)
  if not found.ok?
    IO.warn("kanban: live read failed: #{found.message}")
    return
  end

  for item in found.unwrap!
    # A failed broadcast is logged and dropped, and the cursor moves on: a client can miss that event in its feed until
    # it reloads. The journal still has it, and the board itself is fetched again after each event.
    job.cursor.put(CURRENT, item.event.id)
    result = Channels.broadcast_json(job.hub, "board:#{item.slug}", payload(item.event))
    if not result.ok?
      IO.warn("kanban: broadcast failed: #{result.message}")
    end

    job.cursor.put(LAST, item.event.id)
    job.cursor.put(CURRENT, 0)
  end

  if found.unwrap!.size == BATCH
    flush(job)
  end
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
