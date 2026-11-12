## How long a card stayed in each column, worked out from its events. Each event that carries the card names its
## column, so the card changed column where that name changes. No column is known by name, so it works on any board.
## Pure: `Cards.show` reads the events, and the API and the CLI use `build` and `lines`.

# Milliseconds.
MINUTE = 60000
HOUR = 3600000
DAY = 86400000

## One event of the card that names its column: when, and which column.
export struct Step
  at: Int
  column_id: Int
  name: String
end

## The time in one column, its visits summed.
export struct Stay
  column_id: Int
  name: String
  ms: Int
end

## `stays` are in the order of the first visit. The current column of an open card counts up to `now`; a done card
## leaves its done column out and has `total_ms`. `since` is when the card came into its current column.
export struct Times
  stays: List[Stay]
  column_id: Int
  column: String
  since: Int
  now: Int
  done: Bool
  total_ms: Optional[Int]
end

## `steps` oldest first; `done` says whether the card is in the done column now. The total of a done card runs from
## when it first left its first column to when it last came into the done column (0 when it never left the first one).
export def build(steps: List[Step], done: Bool, now: Int) -> Times
  visits: List[Step] = []
  for step in steps
    if visits.empty? or visits[visits.size - 1].column_id != step.column_id
      visits = visits.push(step)
    end
  end

  return Times(stays: [], column_id: 0, column: "", since: now, now: now, done: done, total_ms: none) if visits.empty?

  last = visits.size - 1
  order: List[Int] = []
  names: Map[Int, String] = {}
  sums: Map[Int, Int] = {}
  for index in 0...visits.size
    visit = visits[index]
    next if done and index == last

    finish = now
    if index < last
      finish = visits[index + 1].at
    end

    if not sums.key?(visit.column_id)
      order = order.push(visit.column_id)
    end

    names = names.put(visit.column_id, visit.name)
    sums = sums.put(visit.column_id, sums.get(visit.column_id, 0) + finish - visit.at)
  end

  total: Optional[Int] = none
  if done
    total = some(0)
    if last > 0
      total = some(visits[last].at - visits[1].at)
    end
  end

  Times(
    stays: order.map do |id| Stay(column_id: id, name: names.get(id, ""), ms: sums.get(id, 0)) end,
    column_id: visits[last].column_id,
    column: visits[last].name,
    since: visits[last].at,
    now: now,
    done: done,
    total_ms: total,
  )
end

## The lines that `kanban card show` prints and the web page shows:
## `Todo 5 min · Doing 2 h 15 min`, then `3 h in Doing` for an open card or `total 3 h` for a done one.
export def lines(times: Times) -> List[String]
  return [] if times.column.empty?

  stays = times.stays.map do |stay| "#{stay.name} #{human(stay.ms)}" end
  last = "#{human(times.now - times.since)} in #{times.column}"
  if times.total_ms.some?
    last = "total #{human(times.total_ms.unwrap!)}"
  end

  return [last] if stays.empty? or (not times.done and stays.size == 1)

  [stays.join(" · "), last]
end

## A length of time for people: `< 1 min`, `40 min`, `2 h 15 min`, `3 d 4 h`. A part that is 0 is left out.
export def human(ms: Int) -> String
  return "< 1 min" if ms < MINUTE

  if ms >= DAY
    hours = (ms % DAY) / HOUR
    return "#{ms / DAY} d" if hours == 0

    return "#{ms / DAY} d #{hours} h"
  end

  minutes = (ms % HOUR) / MINUTE
  return "#{minutes} min" if ms < HOUR
  return "#{ms / HOUR} h" if minutes == 0

  "#{ms / HOUR} h #{minutes} min"
end
