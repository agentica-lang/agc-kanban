# Claude Code plugin

The repository is also a Claude Code plugin (`.claude-plugin/`): it carries the three skills and the hooks of `hooks/hooks.json`. They are for Claude Code only; [agents.md](agents.md) uses only `board-context.sh` for Codex.

- `SessionStart` and `SubagentStart` run `hooks/board-context.sh`, which adds to the context the rule about the agent name and the cards in progress, at most 15 card lines in all, then "and N more". A session start lists the coordinator's own cards first, then the Doing cards of the other agents; a subagent start lists every Doing card, the coordinator's too. They only read the board.
- `PostToolUse` (on `Bash`, `Agent` and `Task`) runs `hooks/drift.sh post-tool`. After `gh pr create` it links the new PR to a card in Doing only when the PR's repository is one the card is about (its links, or the origin of its worktree) and the PR's head branch (`--head`, else the branch of the current directory) is the card's `branch` (or the branch of its worktree): this is the only write a hook makes by itself, and a card needs `--branch` for it.

  Otherwise, and after `gh pr merge`, a `watch_ci.py` run that merged, or `gh issue close`, it adds context that names the card that should get the link, or the linked cards that `kanban doctor --cards` finds drifted (so a parent card whose issue is still open gets nothing in Backlog or Todo, and a slice hint in Review or Doing; this one call reads GitHub). An unrelated command leaves after one `case`, with no network.
- `UserPromptSubmit` runs `hooks/drift.sh prompt-submit`: for the coordinator only (`KANBAN_AGENT=coordinator`, or the `KANBAN_COORDINATOR` name), the queued suggestions of `SubagentStop` first, then `kanban doctor` at most once every 10 minutes (a stamp under `~/.cache/agc-kanban/`; a doctor that takes more than 25 s is killed with its children), and both go to the context.
- `SubagentStop` runs `hooks/drift.sh subagent-stop` (as an async hook, so the parent does not wait). It says nothing when the subagent only stopped to wait on its own background work (a background command, Monitor or agent it started that has no end notice or `TaskStop` in its transcript, and no `SubagentHandback` since its last input): it resumes later.

  Otherwise it finds the kanban name of the subagent from its own identity only (`--agent NAME` or `KANBAN_AGENT=NAME` in its Bash commands, or `You are NAME` at the start of its brief; a name the brief merely mentions does not count) and, for each card that agent still holds, reads the issues and PRs the card links in one `gh api graphql` call (kind, state, and for an open PR the CI of its last commit; never a title or a body, so no text from GitHub reaches Haiku). Rules decide first, on the newest PR: failing CI keeps the card with a note, pending CI keeps it, open and green suggests Review; every PR merged or closed with the issue closed suggests Done.

  A card no rule decides, or one with a GitHub link the hook could not read (it reads at most 20), goes to `claude -p --model haiku` (hooks off, no tools, the column rules and those facts in the prompt, at most 40 s; the whole hook stops within 55 s) with the subagent's final report (the message of its last `SubagentHandback`, else the last assistant message).

  It never moves a card. Claude Code gives a `SubagentStop` hook no way to reach the parent session, so a suggestion that moves the card (or a keep with a note) is written as a comment of the agent `kanban-hook` on the card, and in a queue file under `~/.cache/agc-kanban/` that the coordinator's next `PostToolUse` or `UserPromptSubmit` hook prints once; each names its source (`rule: newest PR green`, `Haiku: ...`), and the same suggestion for a card is told once. Card titles and comments still reach Haiku, marked as data written by agents.

  Every suggestion, keep included, is logged as a JSON line with the stop time, its source and facts in `~/.cache/agc-kanban/suggestions-BOARD.jsonl` (mode 0600); `python3 hooks/drift.py score` prints the hit rate of the rules and of Haiku against the first move each card got after the stop (`kanban events`; no move is keep, and a suggestion of the card's own column is a keep).

Every drift hook needs `python3`, exits 0 whatever happens and prints nothing when it has nothing to say. `SubagentStop` also needs `claude` on `PATH`, and `gh` for the rules (without it every card goes to Haiku).

```sh
claude plugin marketplace add agentica-lang/agc-kanban
claude plugin install agc-kanban@agc-kanban
```

The plugin needs the `kanban` client on `PATH` (`make install-cli`) and `KANBAN_URL`, `KANBAN_API_KEY` and `KANBAN_BOARD` in the environment or in the config file. Without `kanban` or without a board, the hooks print nothing; with a board that cannot be read, they print one notice. The hooks use GNU `timeout` to give up on a server that does not answer after 10 s; without it (macOS has none by default) a hung server can run past the 15 s hook timeout, and the session then gets no board context. The hooks never choose an agent name: the main agent names itself from its conversation with you, and a subagent asks its coordinator.

To try it without installing: `claude --plugin-dir /path/to/agc-kanban`. Check the manifests with `claude plugin validate .`.
