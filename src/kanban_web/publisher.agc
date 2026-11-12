## The work of the live publisher: read the events after the cursor and broadcast them. `cable.agc` runs it as an actor.
##
## The cursor (the id of the last event sent) lives in an `ATS` cell that every start of the actor shares, so a restart
## goes on from the same place and a crash loses no event. The supervisor gives up after a few crashes and then
## crashes itself, which would end the live updates, so a bad event must never become a crash loop: each send runs in
## a task of its own, the failures of that one event are counted, and after MAX_FAILURES the cursor moves past it.

import Channels from "pkg/channels/channels"
import Database from "../kanban/repo/database"
import Events from "../kanban/events"
import SendFailures from "send_failures"

export LAST = "last"
BATCH = 100
# The failures of one event that make it a poison event. A bad `data` row is a different case: the read returns an
# error, which `flush` logs, and the cursor stays, so the live feed stops at that row until it is fixed (a client
# still gets the event on a reload). Only the failure of a send is counted.
export MAX_FAILURES = 5

## The state of the publisher. `send` is the seam of the tests. `bad` and `failures` are the event that failed last
## and its count in a row.
export struct Publisher
  pool: Database.Pool
  hub: Channels.Hub
  cursor: ATS[String, Int]
  send: Fn[Channels.Hub, Events.Published, Result[Void]]
  bad: Int
  failures: Int
end

## A publisher that broadcasts on `hub`.
export def new(pool: Database.Pool, hub: Channels.Hub, cursor: ATS[String, Int]) -> Publisher
  Publisher(pool: pool, hub: hub, cursor: cursor, send: &broadcast, bad: 0, failures: 0)
end

## The live broadcast starts at the newest event, so that history is not replayed. A failed read leaves the cursor
## unset (replaying the journal from 0 would flood the clients), and the next message tries again. A seed that
## succeeds late starts at the newest event, so the events written while the read failed are not broadcast live: a
## reload shows them.
export def seeded(job: Publisher) -> Publisher
  return job if job.cursor.get(LAST).ok?

  newest = Events.latest_id(job.pool)
  if not newest.ok?
    IO.warn("kanban: live start read failed: #{newest.message}")
    return job
  end

  job.cursor.put(LAST, newest.unwrap!)
  job
end

## Sends the events after the cursor and moves it. A failed read keeps it, so the next tick tries again. A send that
## crashes stops the batch and keeps the cursor on that event: the next tick tries it again, until MAX_FAILURES.
export def flush(job: Publisher) -> Publisher
  last = job.cursor.get(LAST)
  return job if not last.ok?

  found = Events.published_after(job.pool, last.unwrap!, BATCH)
  if not found.ok?
    IO.warn("kanban: live read failed: #{found.message}")
    return job
  end

  state = job
  for item in found.unwrap!
    outcome = Task.await(Task.spawn do job.send(job.hub, item) end)
    if outcome.ok?
      state.cursor.put(LAST, item.event.id)
      state = state.with(bad: 0, failures: 0)
    else
      id = item.event.id
      failures = SendFailures.next_failures(state.bad, state.failures, id)
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
def broadcast(hub: Channels.Hub, item: Events.Published) -> Result[Void]
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
