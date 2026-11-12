# The few rules an agent needs before its first command. The long version is
# the kanban-cli skill; this one fits in a prompt.
export def run() -> Result[Void]
  puts(rules())
  ok()
end

def rules() -> String
  (
    "You are one agent on a shared kanban board.\n\n1. Run `kanban whoami` to check the server and your name.\n2. Run `kanban card next` to claim the first ready card; it prints the card you hold.\n3. Read the card with `kanban card show ID`, then do the work on its branch.\n4. Comment what matters and finish with `kanban card done ID`.\n5. Exit codes: 0 ok, 1 refused, 2 usage, 3 no server or busy, 4 somebody else won.\n\nA card claimed by another agent is not yours: pick the next one."
  )
end
