import Channels from "pkg/channels/channels"
import Boards from "../src/kanban/boards"
import Cards from "../src/kanban/cards"
import Database from "../src/kanban/repo/database"
import Events from "../src/kanban/events"
import Publisher from "../src/kanban_web/publisher"
import SendFailures from "../src/kanban_web/send_failures"

POISON = 3

def test_only_the_same_event_adds_up() -> Result[Void]
  try Test.eq(SendFailures.next_failures(0, 0, 7), 1)
  try Test.eq(SendFailures.next_failures(7, 1, 7), 2)
  try Test.eq(SendFailures.next_failures(7, 4, 7), 5)
  try Test.eq(SendFailures.next_failures(7, 4, 8), 1)
  ok()
end

# A send that crashes on one event (a runtime error, not a Result) is tried again on each flush; after MAX_FAILURES the
# cursor moves past that event only, and the events after it are sent.
def test_a_poison_event_is_retried_and_then_skipped() -> Result[Void]
  home = try System.env("HOME")
  try Dir.mkdir("#{home}/.cache")
  dir = "#{home}/.cache/kanban-publisher-test-#{System.pid()}"
  pool = try Database.open(dir)
  _ = try Boards.create(pool, "Project", "project", "agent", ["Todo", "Doing", "Done"])
  input = Cards.Create(
    board: "project",
    title: "First",
    body: "",
    column: none,
    labels: [],
    priority: 2,
    depends_on: [],
    actor: "agent",
  )

  for title in ["A", "B", "C"]
    _ = try Cards.create(pool, input.with(title: title))
  end

  newest = try Events.latest_id(pool)
  try Test.eq(newest, 4)

  hub = try Channels.start_hub()
  cursor: ATS[String, Int] = ATS.new()
  cursor.put(Publisher.LAST, 0)
  job = Publisher.new(pool, hub, cursor).with(send: &crash_on_poison)

  state = Publisher.flush(job)
  try Test.eq(cursor.get(Publisher.LAST), ok(POISON - 1))
  try Test.eq(state.failures, 1)
  for _ in 2..(Publisher.MAX_FAILURES - 1)
    state = Publisher.flush(state)
    try Test.eq(cursor.get(Publisher.LAST), ok(POISON - 1))
  end

  try Test.eq(state.bad, POISON)
  try Test.eq(state.failures, Publisher.MAX_FAILURES - 1)
  state = Publisher.flush(state)
  try Test.eq(cursor.get(Publisher.LAST), ok(newest))
  try Test.eq(state.failures, 0)

  try Channels.stop_hub(hub)
  Database.close(pool)
  try Path.remove("#{dir}/kanban.sqlite3")
  Path.remove(dir)
end

def crash_on_poison(_hub: Channels.Hub, item: Events.Published) -> Result[Void]
  zero = item.event.id - POISON
  if zero == 0
    puts("#{1 / zero}")
  end

  ok()
end
