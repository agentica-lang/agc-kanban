## The periodic archive of the boards that turned it on (`kanban board auto-archive`): a sweep a few seconds after the
## start and then one every ten minutes. The publisher broadcasts the events it writes on its own tick, so the live
## views see an automatic archive up to 5 s late.

import Database from "../kanban/repo/database"
import AutoArchive from "../kanban/auto_archive"

## Starts the sweeps in a task of their own. Call it from the main task, with a database.
def start(pool: Database.Pool) -> Void
  _ = Task.spawn do loop(pool) end
end

private

START_MS = 5_000
SWEEP_MS = 600_000

# Each sweep runs in a task of its own, so a crash of one is logged and the next one still runs.
def loop(pool: Database.Pool) -> Void
  Task.sleep(START_MS)
  while true
    swept = Task.await(Task.spawn do AutoArchive.sweep(pool, Time.now_ms()) end)
    if not swept.ok?
      IO.warn("kanban: auto-archive sweep failed: #{swept.message}")
    end

    Task.sleep(SWEEP_MS)
  end
end
