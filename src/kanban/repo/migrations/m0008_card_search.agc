import Migrate from "pkg/db/migrate"

# The index of the card search: an FTS5 table whose rowid is the card id, with the title, the body, the labels (the
# JSON text, whose words the tokenizer splits) and the text of all the comments of the card. It is not an
# external-content table over `cards` because the comments column has no source column there; the triggers write the
# row again from `cards` and `comments` after each change that touches an indexed text, so the application code never
# has to remember to. The last statement builds the rows of the cards that exist before this migration.
export def migration() -> Migrate.Migration
  Migrate.sql(
    8,
    "card_search",
    [
      "CREATE VIRTUAL TABLE card_search USING fts5(title, body, labels, comments, tokenize = 'unicode61 remove_diacritics 2')",
      "CREATE TRIGGER card_search_insert AFTER INSERT ON cards BEGIN #{refresh("NEW.id")} END",
      "CREATE TRIGGER card_search_update AFTER UPDATE OF title, body, labels ON cards BEGIN #{refresh("NEW.id")} END",
      "CREATE TRIGGER card_search_delete AFTER DELETE ON cards BEGIN DELETE FROM card_search WHERE rowid = OLD.id; END",
      "CREATE TRIGGER card_search_comment AFTER INSERT ON comments BEGIN #{refresh("NEW.card_id")} END",
      "INSERT INTO card_search (rowid, title, body, labels, comments) SELECT c.id, c.title, c.body, c.labels, COALESCE((SELECT group_concat(m.body, ' ') FROM comments m WHERE m.card_id = c.id), '') FROM cards c",
    ],
  )
end

def refresh(id: String) -> String
  (
    "DELETE FROM card_search WHERE rowid = #{id}; INSERT INTO card_search (rowid, title, body, labels, comments) SELECT c.id, c.title, c.body, c.labels, COALESCE((SELECT group_concat(m.body, ' ') FROM comments m WHERE m.card_id = c.id), '') FROM cards c WHERE c.id = #{id};"
  )
end
