import Migrate from "pkg/db/migrate"
import M0001 from "migrations/m0001_boards"
import M0002 from "migrations/m0002_columns"
import M0003 from "migrations/m0003_cards"
import M0004 from "migrations/m0004_card_deps"
import M0005 from "migrations/m0005_comments"
import M0006 from "migrations/m0006_events"
import M0007 from "migrations/m0007_card_links"
import M0008 from "migrations/m0008_card_search"
import M0009 from "migrations/m0009_labels"

def all() -> List[Migrate.Migration]
  [
    M0001.migration(),
    M0002.migration(),
    M0003.migration(),
    M0004.migration(),
    M0005.migration(),
    M0006.migration(),
    M0007.migration(),
    M0008.migration(),
    M0009.migration(),
  ]
end
