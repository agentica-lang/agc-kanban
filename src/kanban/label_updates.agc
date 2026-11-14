import Db from "pkg/db/db"
import Regex from "std/regex"
import Cards from "cards"
import Database from "repo/database"
import Labels from "labels"

struct Update
  id: Int
  name: Optional[String]
  color: Optional[String]
  actor: String
end

def update(pool: Database.Pool, input: Update) -> Result[Labels.Label]
  return error("INVALID:id") if input.id <= 0
  return error("INVALID:label") if not input.name.some? and not input.color.some?
  return error("INVALID:name") if input.name.some? and input.name.unwrap!.strip.empty?
  return error("INVALID:color") if input.color.some? and not valid_color?(input.color.unwrap!)
  return error("INVALID:agent") if not Regex.match?(input.actor, /^[A-Za-z0-9._@\/-]{1,64}$/)

  Database.with_connection(pool) do |conn| Db.transaction(conn) do |tx| update_open(tx, input) end end
end

private

# The data of a label.updated event: the label as it is now and the name it had.
struct Changed
  id: Int
  name: String
  color: String
  previous_name: String
end

def valid_color?(color: String) -> Bool = Regex.match?(color, /^#[0-9A-Fa-f]{6}$/)

def update_open(conn: Db.Connection, input: Update) -> Result[Labels.Label]
  rows = try Db.query(conn, "select id, board_id, name, color from labels where id = ?", [Db.Value.Int(input.id)])

  return error("NOT_FOUND:label") if rows.empty?

  current = label(rows[0])
  board_id = number_of(rows[0], "board_id")
  name = input.name.unwrap_or(current.name)
  color = input.color.unwrap_or(current.color).downcase
  return ok(current) if name == current.name and color == current.color

  if name != current.name
    taken = try Db.query(
      conn,
      "select id from labels where board_id = ? and name = ?",
      [Db.Value.Int(board_id), Db.Value.Text(name)],
    )

    return error("CONFLICT:name") if not taken.empty?
  end

  now = Time.now_ms()
  _ = try Db.execute(
    conn,
    "update labels set name = ?, color = ? where id = ?",
    [Db.Value.Text(name), Db.Value.Text(color), Db.Value.Int(input.id)],
  )

  if name != current.name
    try rename_on_cards(conn, board_id, current.name, name, input.actor, now)
  end

  updated = Labels.Label(id: input.id, name: name, color: color)
  _ = try Db.execute(
    conn,
    "insert into events (board_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?)",
    [
      Db.Value.Int(board_id),
      Db.Value.Text("label.updated"),
      Db.Value.Text(input.actor),
      Db.Value.Text(
        JSON.encode(JSON.from(Changed(id: input.id, name: name, color: color, previous_name: current.name))),
      ),
      Db.Value.Int(now),
    ],
  )

  ok(updated)
end

def rename_on_cards(
  conn: Db.Connection,
  board_id: Int,
  old_name: String,
  new_name: String,
  actor: String,
  now: Int,
) -> Result[Void]
  rows = try Db.query(
    conn,
    "select c.id, c.labels from cards c where c.board_id = ? and exists (select 1 from json_each(c.labels) j where j.value = ?)",
    [Db.Value.Int(board_id), Db.Value.Text(old_name)],
  )

  for row in rows
    id = number_of(row, "id")
    names = try JSON.decode(text_of(row, "labels"), List[String])
    renamed = names.map { |name| swapped(name, old_name, new_name) }.uniq
    _ = try Db.execute(
      conn,
      "update cards set labels = ?, updated_at = ?, version = version + 1 where id = ?",
      [Db.Value.Text(JSON.encode(JSON.from(renamed))), Db.Value.Int(now), Db.Value.Int(id)],
    )

    card = try Cards.load_any_at(conn, id, now)
    if not card.archived_at.some?
      _ = try Db.execute(
        conn,
        "insert into events (board_id, card_id, kind, actor, data, created_at) values (?, ?, ?, ?, ?, ?)",
        [
          Db.Value.Int(board_id),
          Db.Value.Int(id),
          Db.Value.Text("card.updated"),
          Db.Value.Text(actor),
          Db.Value.Text(JSON.encode(JSON.from(card))),
          Db.Value.Int(now),
        ],
      )
    end
  end

  ok()
end

def swapped(name: String, old_name: String, new_name: String) -> String
  return new_name if name == old_name

  name
end

def label(row: Db.Row) -> Labels.Label
  Labels.Label(id: number_of(row, "id"), name: text_of(row, "name"), color: text_of(row, "color"))
end

def number_of(row: Db.Row, key: String) -> Int
  case row.get(key, Db.Value.Null)
    Db.Value.Int(value) -> value
    _ -> -1
  end
end

def text_of(row: Db.Row, key: String) -> String
  case row.get(key, Db.Value.Null)
    Db.Value.Text(value) -> value
    _ -> ""
  end
end
