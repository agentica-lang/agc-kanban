import Board from "src/kanban_cli/board"
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
    Output.fail(Output.json_requested?(words), "INVALID", result.message, 2)
  end
end

def dispatch(words: List[String]) -> Result[Void]
  rest = List.drop(words, 1)
  case words[0]
    "board" -> Board.run(rest)
    "column" -> Columns.run(rest)
    "whoami" -> Whoami.run(rest)
    _ -> error("unknown command #{words[0]}")
  end
end

def usage() -> String
  (
    "kanban: the board client\n\n  kanban board list\n  kanban board create NAME [--slug S] [--columns C1,C2]\n  kanban board show [BOARD]\n  kanban column add NAME [--position N] [--done] [--wip N]\n  kanban column rename COLUMN NAME\n  kanban column move COLUMN POSITION\n  kanban column remove COLUMN\n  kanban whoami\n\nFlags: --url URL, --agent NAME, --board SLUG, --json"
  )
end
