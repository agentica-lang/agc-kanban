# The few rules an agent needs before its first command. The long version is
# the kanban-cli skill; this one fits in a prompt.
export def run() -> Result[Void]
  puts(rules())
  ok()
end

def rules() -> String
  (
    "You are one agent on a shared kanban board.\n\n1. Run `kanban whoami` to check the server and your name. If it fails, stop and say so.\n2. Use the card you were given, or run `kanban card next`: it claims the first ready card and prints it.\n3. Read it with `kanban card show ID`, then work on its branch.\n4. Claim before you work. Exit 4 means you lost the card: pick another with `card next`, never retry it.\n5. Never work a blocked card: comment why and take another.\n6. Comment at each phase (branch and worktree, PR and head, test or CI verdict, blocker) and before every status change, with `kanban card comment ID TEXT`.\n7. Move the card to Review when the work is ready. Never mark it done: a coordinator does that after the merge.\n8. Never move, update or release a card another agent holds. Cannot finish: comment why, then `kanban card release ID`.\n9. Exit codes: 0 ok, 1 refused, 2 usage, 3 no server or busy, 4 somebody else won."
  )
end
