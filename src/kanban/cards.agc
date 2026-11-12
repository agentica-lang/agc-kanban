import Db from "pkg/db/db"
import Regex from "std/regex"
import Database from "repo/database"
import Times from "times"

# A link is untrusted text shown on the web and printed to terminals: http(s) only, a host with no credentials (no `@`
# before the path), printable ASCII only (an IDN host as punycode, a path percent-encoded) and none of the characters
# that end a URL in HTML or Markdown (quotes, angle brackets, backslash and the like), so it stays one plain URL
# wherever it is printed. ASCII only, so LINK_MAX counts bytes. A card holds at most LINKS_MAX links, and a request
# names at most LINKS_MAX to add and LINKS_MAX to remove, repeats included, checked before the transaction so that a
# huge list never reaches `merged`, which is quadratic.
LINK_MAX = 2048
LINKS_MAX = 50

export struct Card
  id: Int
  board: String
  column: String
  column_id: Int
  position: Int
  title: String
  body: String
  labels: List[String]
  links: List[String]
  priority: Int
  claimed_by: Optional[String]
  claimed_at: Optional[Int]
  lease_until: Optional[Int]
  branch: Optional[String]
  worktree: Optional[String]
  depends_on: List[Int]
  blocks: List[Int]
  ready: Bool
  done: Bool
  created_by: String
  created_at: Int
  updated_at: Int
  done_at: Optional[Int]
  version: Int
end

export struct Comment
  id: Int
  card_id: Int
  author: String
  body: String
  created_at: Int
end

export struct Detail
  card: Card
  comments: List[Comment]
  times: Times.Times
end

export struct Create
  board: String
  title: String
  body: String
  column: Optional[String]
  labels: List[String]
  priority: Int
  depends_on: List[Int]
  actor: String
  links: List[String] = []
end

export struct Filters
  column: Optional[String]
  ready: Optional[Bool]
  claimed_by: Optional[String]
  label: Optional[String]
  done: Optional[Bool]
end

export struct Update
  id: Int
  title: Optional[String]
  body: Optional[String]
  labels: Optional[List[String]]
  priority: Optional[Int]
  branch: Optional[String]
  worktree: Optional[String]
  actor: String
  force: Bool
  lease_minutes: Int
  # Added after removed, each once and in the order given. Adding a link the card has, or removing one it has not, is
  # no change: an update of links alone that changes none writes nothing (no version, no event).
  link: List[String] = []
  unlink: List[String] = []
end

export def create(pool: Database.Pool, input: Create) -> Result[Card]
  return error("INVALID:board") if input.board.empty?
  return error("INVALID:title") if input.title.strip.empty?
  return error("INVALID:priority") if input.priority < 0 or input.priority > 4
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)
  for label in input.labels
    return error("INVALID:labels") if label.strip.empty?
  end

  return error("INVALID:links") if input.links.size > LINKS_MAX or not valid_links?(input.links)

  for id in input.depends_on
    return error("INVALID:depends_on") if id <= 0
    repeats = input.depends_on.select do |other| id == other end
    return error("INVALID:depends_on") if repeats.size > 1
  end

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| insert(tx, input) end end
end

export def show(pool: Database.Pool, id: Int) -> Result[Detail]
  return error("INVALID:id") if id <= 0

  Database.with_connection(pool) do |conn|
    Db.transaction(conn) do |tx|
      card = try load(tx, id)
      rows = try Db.query(
        tx,
        "select id, card_id, author, body, created_at from comments where card_id = ? order by id",
        [Db.Value.Int(id)],
      )

      comments = rows.map do |row|
        Comment(
          id: number(row, "id"),
          card_id: number(row, "card_id"),
          author: text(row, "author"),
          body: text(row, "body"),
          created_at: number(row, "created_at"),
        )
      end

      now = Time.now_ms()
      steps = (try steps_of(tx, id)).map do |step| named(step, card) end
      ok(Detail(card: card, comments: comments, times: Times.build(steps, card.done, now)))
    end
  end
end

export def list(pool: Database.Pool, board: String, filters: Filters) -> Result[List[Card]]
  return error("INVALID:board") if board.empty?

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| list_open(tx, board, filters) end end
end

export def list_open(conn: Db.Connection, board: String, filters: Filters) -> Result[List[Card]]
  found = try Db.query(
    conn,
    "select id from boards where slug = ? or cast(id as text) = ? order by case when slug = ? then 0 else 1 end limit 1",
    [Db.Value.Text(board), Db.Value.Text(board), Db.Value.Text(board)],
  )

  return error("NOT_FOUND:board") if found.empty?

  board_id = number(found[0], "id")
  now = Time.now_ms()
  column = optional_value(filters.column)
  claimed = optional_value(filters.claimed_by)
  label = optional_value(filters.label)
  ready = bool_value(filters.ready)
  done = bool_value(filters.done)
  rows = try Db.query(
    conn,
    "select c.id from cards c join columns col on col.id = c.column_id where c.board_id = ? and c.archived_at is null and (? is null or col.name = ? or cast(col.id as text) = ?) and (? is null or c.claimed_by = ?) and (? is null or exists (select 1 from json_each(c.labels) j where j.value = ?)) and (? is null or col.done = ?) and (? is null or (case when col.done = 0 and (c.claimed_by is null or c.lease_until <= ?) and not exists (select 1 from card_deps d join cards dep on dep.id = d.depends_on_id join columns dc on dc.id = dep.column_id where d.card_id = c.id and dc.done = 0) then 1 else 0 end) = ?) order by col.position, c.position, c.id",
    [
      Db.Value.Int(board_id),
      column,
      column,
      column,
      claimed,
      claimed,
      label,
      label,
      done,
      done,
      ready,
      Db.Value.Int(now),
      ready,
    ],
  )

  cards: List[Card] = []
  for row in rows
    cards = cards.push(try load_at(conn, number(row, "id"), now))
  end

  ok(cards)
end

export def update(pool: Database.Pool, input: Update) -> Result[Card]
  return error("INVALID:id") if input.id <= 0
  return error("INVALID:title") if input.title.some? and input.title.unwrap!.strip.empty?
  if input.priority.some? and (input.priority.unwrap! < 0 or input.priority.unwrap! > 4)
    return error("INVALID:priority")
  end

  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)
  return error("INVALID:lease") if input.lease_minutes < 0 or input.lease_minutes > 1000000000
  if input.link.size > LINKS_MAX or input.unlink.size > LINKS_MAX or not valid_links?(input.link)
    return error("INVALID:links")
  end

  if input.labels.some?
    for label in input.labels.unwrap!
      return error("INVALID:labels") if label.strip.empty?
    end
  end

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| update_open(tx, input) end end
end

# The ids of the cards `id` depends on that are not done yet (in a column that is not a done column), lowest first.
export def open_blockers(conn: Db.Connection, id: Int) -> Result[List[Int]]
  rows = try Db.query(
    conn,
    "select dep.id from card_deps d join cards dep on dep.id = d.depends_on_id join columns col on col.id = dep.column_id where d.card_id = ? and col.done = 0 order by dep.id",
    [Db.Value.Int(id)],
  )

  ok(rows.map do |row| number(row, "id") end)
end

# Of `ids`, the cards that are not done yet, once each, in the order given: what a new card in the done column would
# wait for.
export def open_among(conn: Db.Connection, ids: List[Int]) -> Result[List[Int]]
  open: List[Int] = []
  for id in ids
    rows = try Db.query(
      conn,
      "select 1 as present from cards c join columns col on col.id = c.column_id where c.id = ? and col.done = 0",
      [Db.Value.Int(id)],
    )

    if not rows.empty? and not open.include?(id)
      open = open.push(id)
    end
  end

  ok(open)
end

export def load_at(conn: Db.Connection, id: Int, now: Int) -> Result[Card]
  rows = try Db.query(
    conn,
    "select c.*, b.slug as board_slug, col.name as column_name, col.done as column_done, case when c.archived_at is null and col.done = 0 and (c.claimed_by is null or c.lease_until <= ?) and not exists (select 1 from card_deps d join cards dep on dep.id = d.depends_on_id join columns dc on dc.id = dep.column_id where d.card_id = c.id and dc.done = 0) then 1 else 0 end as ready from cards c join boards b on b.id = c.board_id join columns col on col.id = c.column_id where c.id = ? and c.archived_at is null",
    [Db.Value.Int(now), Db.Value.Int(id)],
  )

  return error("NOT_FOUND:card") if rows.empty?

  row = rows[0]
  labels = try JSON.decode(text(row, "labels"), List[String])
  links = try JSON.decode(text(row, "links"), List[String])
  deps = try Db.query(
    conn,
    "select depends_on_id as id from card_deps where card_id = ? order by depends_on_id",
    [Db.Value.Int(id)],
  )

  blocks = try Db.query(
    conn,
    "select card_id as id from card_deps where depends_on_id = ? order by card_id",
    [Db.Value.Int(id)],
  )

  ok(
    Card(
      id: id,
      board: text(row, "board_slug"),
      column: text(row, "column_name"),
      column_id: number(row, "column_id"),
      position: number(row, "position"),
      title: text(row, "title"),
      body: text(row, "body"),
      labels: labels,
      links: links,
      priority: number(row, "priority"),
      claimed_by: optional_text(row, "claimed_by"),
      claimed_at: optional_number(row, "claimed_at"),
      lease_until: optional_number(row, "lease_until"),
      branch: optional_text(row, "branch"),
      worktree: optional_text(row, "worktree"),
      depends_on: deps.map do |item| number(item, "id") end,
      blocks: blocks.map do |item| number(item, "id") end,
      ready: number(row, "ready") == 1,
      done: number(row, "column_done") == 1,
      created_by: text(row, "created_by"),
      created_at: number(row, "created_at"),
      updated_at: number(row, "updated_at"),
      done_at: optional_number(row, "done_at"),
      version: number(row, "version"),
    ),
  )
end

def optional_value(value: Optional[String]) -> Db.Value
  case value
    none -> Db.Value.Null
    some(text) -> Db.Value.Text(text)
  end
end

def bool_value(value: Optional[Bool]) -> Db.Value
  case value
    none -> Db.Value.Null
    some(flag) -> bool_int(flag)
  end
end

def update_open(conn: Db.Connection, input: Update) -> Result[Card]
  now = Time.now_ms()
  card = try load_at(conn, input.id, now)
  holder = card.claimed_by
  active = holder.some? and (not card.lease_until.some? or card.lease_until.unwrap! > now)
  return error("CLAIMED:#{holder.unwrap!}") if active and holder.unwrap! != input.actor and not input.force

  title = input.title.unwrap_or(card.title)
  body = input.body.unwrap_or(card.body)
  labels = input.labels.unwrap_or(card.labels)
  priority = input.priority.unwrap_or(card.priority)
  links = merged(card.links.select do |url| not input.unlink.include?(url) end, input.link)
  return error("INVALID:links") if links.size > LINKS_MAX
  # The holder's update renews the lease, so it is a write even when the links come out the same.
  renews = active and holder.unwrap! == input.actor and input.lease_minutes > 0
  return ok(card) if links_only?(input, renews) and links == card.links
  lease: Db.Value = nullable_number(card.lease_until)
  if renews
    lease = Db.Value.Int(now + input.lease_minutes * 60000)
  end

  _ = try Db.execute(
    conn,
    "update cards set title = ?, body = ?, labels = ?, links = ?, priority = ?, branch = ?, worktree = ?, lease_until = ?, updated_at = ?, version = version + 1 where id = ?",
    [
      Db.Value.Text(title),
      Db.Value.Text(body),
      Db.Value.Text(JSON.encode(JSON.from(labels))),
      Db.Value.Text(JSON.encode(JSON.from(links))),
      Db.Value.Int(priority),
      branch_value(input.branch, card.branch),
      branch_value(input.worktree, card.worktree),
      lease,
      Db.Value.Int(now),
      Db.Value.Int(input.id),
    ],
  )

  updated = try load_at(conn, input.id, now)
  board = try Db.query(conn, "select board_id from cards where id = ?", [Db.Value.Int(input.id)])
  _ = try Db.execute(
    conn,
    "insert into events (board_id, card_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?, ?)",
    [
      Db.Value.Int(number(board[0], "board_id")),
      Db.Value.Int(input.id),
      Db.Value.Text("card.updated"),
      Db.Value.Text(input.actor),
      Db.Value.Text(JSON.encode(JSON.from(updated))),
      Db.Value.Int(now),
    ],
  )

  ok(updated)
end

def valid_links?(links: List[String]) -> Bool
  links.all? do |url|
    (
      url.length <= LINK_MAX and
      Regex.match?(url, /^https?:\/\/[!$-&(-.0-;=A-\[\]_a-z~]+([\/?#][!#-&(-;=?-\[\]_a-z~]*)?$/)
    )
  end
end

# Only links were asked for: the update is a no-op when they come out the same. A lease renewal (`renews`) is an ask
# of its own, so it is not links only. `force` is not: it only skips the CLAIMED check and stores nothing.
def links_only?(input: Update, renews: Bool) -> Bool
  others = [
    renews,
    input.title.some?,
    input.body.some?,
    input.labels.some?,
    input.priority.some?,
    input.branch.some?,
    input.worktree.some?,
  ]

  not others.any? do |given| given end and not (input.link.empty? and input.unlink.empty?)
end

# `links` with each of `added` it lacks, in order.
def merged(links: List[String], added: List[String]) -> List[String]
  result = links
  for url in added
    next if result.include?(url)

    result = result.push(url)
  end

  result
end

def branch_value(given: Optional[String], current: Optional[String]) -> Db.Value
  case given
    some(text) -> Db.Value.Text(text)
    none -> optional_value(current)
  end
end

def nullable_number(value: Optional[Int]) -> Db.Value
  case value
    none -> Db.Value.Null
    some(number) -> Db.Value.Int(number)
  end
end

def insert(conn: Db.Connection, input: Create) -> Result[Card]
  board = try Db.query(
    conn,
    "select id from boards where slug = ? or cast(id as text) = ? order by case when slug = ? then 0 else 1 end limit 1",
    [Db.Value.Text(input.board), Db.Value.Text(input.board), Db.Value.Text(input.board)],
  )

  return error("NOT_FOUND:board") if board.empty?

  board_id = number(board[0], "id")
  column = try find_column(conn, board_id, input.column)
  for id in input.depends_on
    found = try Db.query(conn, "select id from cards where id = ? and archived_at is null", [Db.Value.Int(id)])
    return error("NOT_FOUND:depends_on") if found.empty?
  end

  # A card is never created closed with an open dependency (the rule of `done` and of a move into the done column).
  if number(column, "done") == 1
    waiting = try open_among(conn, input.depends_on)
    return error("BLOCKED:#{waiting.map do |id| id.to_s end.join(",")}") if not waiting.empty?
  end

  now = Time.now_ms()
  column_id = number(column, "id")
  position_rows = try Db.query(
    conn,
    "select coalesce(max(position) + 1, 0) as next from cards where column_id = ? and archived_at is null",
    [Db.Value.Int(column_id)],
  )

  done_at: Db.Value = Db.Value.Null
  if number(column, "done") == 1
    done_at = Db.Value.Int(now)
  end

  _ = try Db.execute(
    conn,
    "insert into cards (board_id, column_id, position, title, body, labels, links, priority, created_by, created_at, updated_at, done_at) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    [
      Db.Value.Int(board_id),
      Db.Value.Int(column_id),
      Db.Value.Int(number(position_rows[0], "next")),
      Db.Value.Text(input.title),
      Db.Value.Text(input.body),
      Db.Value.Text(JSON.encode(JSON.from(input.labels))),
      Db.Value.Text(JSON.encode(JSON.from(merged([], input.links)))),
      Db.Value.Int(input.priority),
      Db.Value.Text(input.actor),
      Db.Value.Int(now),
      Db.Value.Int(now),
      done_at,
    ],
  )

  inserted = try Db.query(conn, "select last_insert_rowid() as id", [])
  id = number(inserted[0], "id")
  for dep in input.depends_on
    _ = try Db.execute(
      conn,
      "insert into card_deps (card_id, depends_on_id, created_at) values (?, ?, ?)",
      [Db.Value.Int(id), Db.Value.Int(dep), Db.Value.Int(now)],
    )
  end

  card = try load(conn, id)
  _ = try Db.execute(
    conn,
    "insert into events (board_id, card_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?, ?)",
    [
      Db.Value.Int(board_id),
      Db.Value.Int(id),
      Db.Value.Text("card.created"),
      Db.Value.Text(input.actor),
      Db.Value.Text(JSON.encode(JSON.from(card))),
      Db.Value.Int(now),
    ],
  )

  ok(card)
end

def find_column(conn: Db.Connection, board_id: Int, requested: Optional[String]) -> Result[Db.Row]
  rows = case requested
    none ->
      Db.query(
        conn,
        "select id, done from columns where board_id = ? order by position limit 1",
        [Db.Value.Int(board_id)],
      )
    some(value) ->
      Db.query(
        conn,
        "select id, done from columns where board_id = ? and (name = ? or cast(id as text) = ?) order by case when name = ? then 0 else 1 end limit 1",
        [Db.Value.Int(board_id), Db.Value.Text(value), Db.Value.Text(value), Db.Value.Text(value)],
      )
  end

  found = try rows
  return error("NOT_FOUND:column") if found.empty?

  ok(found[0])
end

def load(conn: Db.Connection, id: Int) -> Result[Card] = load_at(conn, id, Time.now_ms())

def number(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end

def text(row: Db.Row, key: String) -> String
  case row.get(key, Db.Value.Null)
    Db.Value.Text(value) -> value
    _ -> ""
  end
end

def optional_number(row: Db.Row, key: String) -> Optional[Int]
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> some(value)
    _ -> none
  end
end

def optional_text(row: Db.Row, key: String) -> Optional[String]
  case row.get(key, Db.Value.Null)
    Db.Value.Text(value) -> some(value)
    _ -> none
  end
end

def bool_int(flag: Bool) -> Db.Value
  if flag
    Db.Value.Int(1)
  else
    Db.Value.Int(0)
  end
end

# Every event of the card that carries the card names its column: `column_id` at the top (created, claimed, updated)
# or under `card` (moved, released, done), with the column's name at that time. The name of the column table is only
# for an event without one, and only from the card's board: the id of a removed column can be reused.
def steps_of(conn: Db.Connection, id: Int) -> Result[List[Times.Step]]
  rows = try Db.query(
    conn,
    "select s.at, s.column_id, coalesce(s.name, col.name) as name from (select id, created_at as at, coalesce(json_extract(data, '$.column_id'), json_extract(data, '$.card.column_id')) as column_id, coalesce(json_extract(data, '$.column'), json_extract(data, '$.card.column')) as name from events where card_id = ?) s left join columns col on col.id = s.column_id and col.board_id = (select board_id from cards where id = ?) where s.column_id is not null order by s.id",
    [Db.Value.Int(id), Db.Value.Int(id)],
  )

  ok(
    rows.map do |row|
      Times.Step(at: number(row, "at"), column_id: number(row, "column_id"), name: text(row, "name"))
    end,
  )
end

# The column the card is in now goes by its name now, so a stay in a column renamed since says the name it has.
def named(step: Times.Step, card: Card) -> Times.Step
  return step if step.column_id != card.column_id

  Times.Step(at: step.at, column_id: step.column_id, name: card.column)
end
