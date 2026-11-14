## The periodic archive of the boards that turned it on (`kanban board auto-archive`): one sweep every ten minutes.
## The publisher broadcasts the events it writes, as it does for any other write.

import Database from "../kanban/repo/database"
import AutoArchive from "../kanban/auto_archive"

## Starts the sweeps in a task of their own. Call it from the main task, with a database.
def start(pool: Database.Pool) -> Void
  _ = Task.spawn do loop(pool) end
end

private

SWEEP_MS = 600_000

def loop(pool: Database.Pool) -> Void
  while true
    Task.sleep(SWEEP_MS)
    swept = AutoArchive.sweep(pool, Time.now_ms())
    if not swept.ok?
      IO.warn("kanban: auto-archive sweep failed: #{swept.message}")
    end
  end
end
