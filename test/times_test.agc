import Times from "../src/kanban/times"

# A case of test/times_lines.json.
struct LinesCase
  times: Times.Times
  lines: List[String]
end

# Minutes from the card's creation, so the cases read as a timeline.
def step(minute: Int, column_id: Int, name: String) -> Times.Step
  Times.Step(at: minute * 60000, column_id: column_id, name: name)
end

def test_a_card_never_moved_counts_in_its_first_column() -> Result[Void]
  times = Times.build([step(0, 1, "Todo"), step(5, 1, "Todo")], false, 40 * 60000)
  try Test.eq(times.stays, [Times.Stay(column_id: 1, name: "Todo", ms: 40 * 60000)])
  try Test.eq(times.since, 0)
  try Test.eq(Times.lines(times), ["40 min in Todo"])
  ok()
end

def test_visits_to_the_same_column_add_up() -> Result[Void]
  steps = [step(0, 1, "Todo"), step(10, 2, "Doing"), step(70, 1, "Todo"), step(75, 2, "Doing")]
  times = Times.build(steps, false, 120 * 60000)
  try Test.eq(
    times.stays,
    [Times.Stay(column_id: 1, name: "Todo", ms: 15 * 60000), Times.Stay(column_id: 2, name: "Doing", ms: 105 * 60000)],
  )

  try Test.eq(Times.lines(times), ["Todo 15 min · Doing 1 h 45 min", "45 min in Doing"])
  ok()
end

def test_a_done_card_has_a_total_and_leaves_done_out() -> Result[Void]
  steps = [step(0, 1, "Todo"), step(30, 2, "Doing"), step(165, 3, "Review"), step(205, 4, "Done")]
  times = Times.build(steps, true, 900 * 60000)
  try Test.eq(times.total_ms, some(175 * 60000))
  try Test.eq(Times.lines(times), ["Todo 30 min · Doing 2 h 15 min · Review 40 min", "total 2 h 55 min"])
  ok()
end

def test_a_card_done_then_moved_back_is_open_again() -> Result[Void]
  steps = [step(0, 1, "Todo"), step(10, 4, "Done"), step(20, 2, "Doing")]
  times = Times.build(steps, false, 25 * 60000)
  try Test.eq(times.total_ms, none)
  try Test.eq(Times.lines(times), ["Todo 10 min · Done 10 min · Doing 5 min", "5 min in Doing"])
  ok()
end

def test_a_card_created_done_has_a_zero_total() -> Result[Void]
  try Test.eq(Times.lines(Times.build([step(0, 4, "Done")], true, 60000)), ["total < 1 min"])
  ok()
end

def test_human_leaves_out_zero_parts() -> Result[Void]
  try Test.eq(Times.human(59999), "< 1 min")
  try Test.eq(Times.human(3600000), "1 h")
  try Test.eq(Times.human(86400000 + 4 * 3600000 + 60000), "1 d 4 h")
  try Test.eq(Times.human(2 * 86400000), "2 d")
  ok()
end

# The cases that test/web/times.test.mjs checks against the web panel too, so the two stay alike.
def test_the_lines_match_the_shared_cases() -> Result[Void]
  cases = try JSON.decode(try File.read_text("test/times_lines.json"), List[LinesCase])
  try Test.eq(cases.empty?, false)
  for one in cases
    try Test.eq(Times.lines(one.times), one.lines)
  end

  ok()
end

def test_a_clock_that_steps_back_gives_no_negative_time() -> Result[Void]
  times = Times.build([step(10, 1, "Todo"), step(5, 2, "Doing")], false, 0)
  try Test.eq(times.stays.map do |stay| stay.ms end, [0, 0])
  try Test.eq(Times.lines(times), ["Todo < 1 min · Doing < 1 min", "< 1 min in Doing"])
  ok()
end

def test_a_renamed_column_shows_its_latest_name() -> Result[Void]
  steps = [step(0, 1, "Todo"), step(10, 2, "Doing"), step(20, 1, "Backlog")]
  times = Times.build(steps, false, 30 * 60000)
  try Test.eq(times.stays.map do |stay| stay.name end, ["Backlog", "Doing"])
  ok()
end
