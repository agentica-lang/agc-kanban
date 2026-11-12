import OP from "std/option_parser"
import Board from "src/kanban_cli/board"
import Prime from "src/kanban_cli/prime"
import CardActions from "src/kanban_cli/card_actions"
import Events from "src/kanban_cli/events"
import Cards from "src/kanban_cli/cards"
import Columns from "src/kanban_cli/columns"
import Output from "src/kanban_cli/output"
import Whoami from "src/kanban_cli/whoami"

export def main() -> Void
  words = System.args()
  if words.empty? or words[0] == "--help" or words[0] == "-h"
    puts(usage())
    return
  end

  result = dispatch(words)
  if not result.ok?
    if OP.help?(result.message)
      puts(OP.message(result.message))
      return
    end

    Output.fail(Output.json_requested?(words), "USAGE", OP.message(result.message), 2)
  end
end

def card(words: List[String]) -> Result[Void]
  return Cards.run(words) if words.empty?

  case words[0]
    "add", "list", "show", "update" -> Cards.run(words)
    _ -> CardActions.run(words)
  end
end

def dispatch(words: List[String]) -> Result[Void]
  rest = List.drop(words, 1)
  case words[0]
    "board" -> Board.run(rest)
    "column" -> Columns.run(rest)
    "card" -> card(rest)
    "events" -> Events.run(rest)
    "prime" -> Prime.run()
    "whoami" -> Whoami.run(rest)
    _ -> error("unknown command #{words[0]}")
  end
end

def usage() -> String
  (
    "kanban: the board client\n\n  kanban board list\n  kanban board create NAME [--slug S] [--columns C1,C2]\n  kanban board show [BOARD]\n  kanban column add NAME [--position N] [--done] [--wip N]\n  kanban column rename COLUMN NAME\n  kanban column move COLUMN POSITION\n  kanban column remove COLUMN\n  kanban card add TITLE [--body T | --body-file F] [--column C] [--label L] [--priority N] [--depends-on IDS]\n  kanban card list [--column C] [--ready] [--mine] [--claimed-by A] [--label L] [--all]\n  kanban card show ID\n  kanban card update ID [--title T] [--body T | --body-file F] [--label L] [--priority N] [--branch B] [--worktree W] [--force]\n  kanban card claim ID\n  kanban card next [--column C] [--label L]\n  kanban card release ID [--to COLUMN] [--force]\n  kanban card move ID COLUMN [--position N] [--force]\n  kanban card done ID [--force]\n  kanban card comment ID TEXT | --file F\n  kanban card dep add ID DEPENDS_ON\n  kanban card dep remove ID DEPENDS_ON\n  kanban events [--after N | --before N] [--card ID] [--limit N]\n  kanban whoami\n\nFlags: --url URL, --agent NAME, --board SLUG, --json"
  )
end
