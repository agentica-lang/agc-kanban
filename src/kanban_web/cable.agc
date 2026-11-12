## The live side: `/cable` (Action Cable on bond-channels) and the broadcast of every event after its write.
##
## `BoardChannel` (param `board`, the slug) streams `board:SLUG`. The publisher (`publisher.agc`) is an actor
## (`std/actor`) under a supervisor (`std/supervisor`). It reads the events that are newer than the last one it sent
## and broadcasts them, so a broadcast always follows the commit, never runs inside it, and goes out in the order of
## the journal. A write sends it `Nudge`, at most one while one is pending; a timer sends `Tick` every 5 s, so a
## lost nudge is a delay and not a missed event. A client that misses a broadcast (a reconnect) fetches the board again.
##
## A restart builds the actor again from the job that the child captured, and the new one reads the cursor from the
## `ATS` cell that the job holds, so it goes on where the old one stopped.

import Actor from "std/actor"
import Supervisor from "std/supervisor"
import Bond from "pkg/bond/bond"
import Channels from "pkg/channels/channels"
import Auth from "auth"
import Database from "../kanban/repo/database"
import Publisher from "publisher"
import Routes from "routes"

BOARD_CHANNEL = "BoardChannel"
NAME = "publisher"
PENDING = "pending"
TICK_MS = 5_000
# The address of the publisher: a restart gives a new actor a new address, so the writes look it up on each nudge.
NAMES: ATS[String, Address[Msg]] = ATS.new()
# Set while a `Nudge` is in the inbox, so a burst of writes is one flush and not one read of the journal per write.
FLAGS: ATS[String, Int] = ATS.new()

enum Msg
  Nudge
  Tick
end

## What the writes need: the hub of the channels. The publisher is reached by name.
export struct Cable
  hub: Channels.Hub
end

## Starts the hub and, with a database, the publisher under a supervisor and its timer. Call it from the main task:
## the supervisor and the timer are its children.
export def start(pool: Optional[Database.Pool]) -> Cable
  hub = Channels.start_hub().unwrap!
  if pool.some?
    cursor: ATS[String, Int] = ATS.new()
    job = Publisher.new(pool.unwrap!, hub, cursor)
    # One try here, so that a write that follows the start is seen; the actor retries while the read fails.
    _ = Publisher.seeded(job)
    behaviour: Actor.Behaviour[Publisher.Publisher, Msg] = Actor.Behaviour(init: init_from do job end, handle: &handle)

    child = Supervisor.child(NAME, behaviour) do |address| NAMES.put(NAME, address) end
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

## Tells the publisher that a write may have added events. Only the nudge that sets the flag is sent.
export def nudge(_cable: Cable) -> Void
  return if not NAMES.get(NAME).ok?

  if FLAGS.put_new(PENDING, 1)
    if not cast(Msg.Nudge)
      FLAGS.delete(PENDING)
    end
  end
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

# Casts `Tick` to the publisher every 5 s, wherever it lives now.
def ticker() -> Void
  while true
    Task.sleep(TICK_MS)
    _ = cast(Msg.Tick)
  end
end

# A full inbox drops the message (timeout 0): a later tick or nudge reads the same journal.
def cast(message: Msg) -> Bool
  found = NAMES.get(NAME)
  return false if not found.ok?

  Actor.cast(found.unwrap!, message, 0).ok?
end

# The block of `init` gives the state of each new actor; the helper only types it as an `Fn`.
def init_from[R](f: Fn[R]) -> Fn[R] = f

# The flag is cleared before the flush: a write during the flush sends one more nudge. A crash that loses a pending
# nudge leaves the flag set, and the next tick clears it.
def handle(job: Publisher.Publisher, _message: Msg) -> Actor.Step[Publisher.Publisher]
  FLAGS.delete(PENDING)
  Actor.continue(Publisher.flush(Publisher.seeded(job)))
end
