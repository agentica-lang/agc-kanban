## The live side: `/cable` (Action Cable on bond-channels) and the broadcast of every event after its write.
##
## `BoardChannel` (param `board`, the slug) streams `board:SLUG`. A task of its own, the publisher, reads the events
## that are newer than the last one it sent and broadcasts them, so a broadcast always follows the commit, never runs
## inside it, and goes out in the order of the journal. A write nudges it (`nudge`); a slow tick catches an event that a
## nudge missed, so a lost wake-up is a delay and not a missed event. A client that misses a broadcast (a reconnect)
## fetches the board again.

import Bond from "pkg/bond/bond"
import Channels from "pkg/channels/channels"
import Auth from "auth"
import Database from "../kanban/repo/database"
import Events from "../kanban/events"
import Routes from "routes"

BOARD_CHANNEL = "BoardChannel"
LAST = "last"
BATCH = 100
TICK_MS = 1_000

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
    cursor.put(LAST, Events.latest_id(pool.unwrap!).unwrap_or(0))
    _ = Task.spawn(&publish, Publisher(pool: pool.unwrap!, hub: hub, wake: wake, cursor: cursor))
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

def publish(job: Publisher) -> Void
  while not job.wake.closed?
    _ = job.wake.recv(TICK_MS)
    flush(job)
  end
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
    # A failed broadcast is logged and dropped: the journal still has the event.
    result = Channels.broadcast_json(job.hub, "board:#{item.slug}", payload(item.event))
    if not result.ok?
      IO.warn("kanban: broadcast failed: #{result.message}")
    end

    job.cursor.put(LAST, item.event.id)
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
