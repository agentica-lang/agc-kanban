import Migrate from "pkg/db/migrate"

PALETTE = [
  "#d73a4a",
  "#0075ca",
  "#7057ff",
  "#008672",
  "#e99695",
  "#fbca04",
  "#0e8a16",
  "#d876e3",
  "#1d76db",
  "#b60205",
  "#c5def5",
  "#bfd4f2",
]

# One row per name that the cards of a board carry, with a palette color taken in the order of the names, so that the
# colors of one board differ from each other until the palette runs out.
def migration() -> Migrate.Migration
  Migrate.sql(
    9,
    "labels",
    [
      "CREATE TABLE labels ( id INTEGER PRIMARY KEY, board_id INTEGER NOT NULL REFERENCES boards(id), name TEXT NOT NULL, color TEXT NOT NULL, created_at INTEGER NOT NULL, UNIQUE (board_id, name) )",
      "INSERT INTO labels (board_id, name, color, created_at) SELECT board_id, name, #{pick("n")}, CAST(strftime('%s', 'now') AS INTEGER) * 1000 FROM (SELECT board_id, name, row_number() OVER (PARTITION BY board_id ORDER BY name) - 1 AS n FROM (SELECT DISTINCT c.board_id AS board_id, j.value AS name FROM cards c, json_each(c.labels) j WHERE j.type = 'text' AND trim(j.value) <> ''))",
    ],
  )
end

private

def pick(index: String) -> String
  arms = (0...PALETTE.size).map { |i| "WHEN #{i} THEN '#{PALETTE[i]}'" }.join(" ")
  "CASE #{index} % #{PALETTE.size} #{arms} END"
end
