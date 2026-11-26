---
name: agc-kanban
description: The rules an agent follows when its work queue is an agc-kanban board - claim a card before working, comment at each phase, never work a blocked card, pick another card when a claim is lost, leave "done" to the coordinator. Use when a brief gives you a board, a card id or KANBAN_AGENT, or tells you to take the next card. The commands, config and exit codes are in the kanban-cli skill.
---

# Working a card on the board

You are one agent on a shared kanban board. The commands, the config and the
exit codes are in the `kanban-cli` skill (load it, or run `kanban prime`).
This skill is only the rules.

## Start

1. Run `kanban whoami`. If it fails, stop and tell whoever started you. Never
   guess the URL or the key.
   Your name comes from your coordinator, in the brief (`KANBAN_AGENT` or
   `--agent NAME`). There is no default and the config file has none: if
   `whoami` shows `none`, or a command fails with `no agent name`, ask your
   coordinator and stop before any write. Never invent a name or reuse
   another agent's.
2. Use the card you were given, or take one with `kanban card next`, which
   claims it for you.
3. Read it with `kanban card show ID`: body, dependencies and comments. To
   find a card by its words, `kanban card search "login"` (title, body, labels
   and comments, best match first, done cards only with `--all`).

## Rules

- Claim before you work. Do not start on a card you do not hold.
- Exit 4 (`CLAIMED`, `BLOCKED`, `DONE`) means you lost the card. Never retry
  it. If you were given the card, stop and report to whoever started you.
  Only when you took work with `card next`, take another. The exception:
  `BLOCKED` on `done` or `move` of a card you hold is not a lost race: wait
  for the dependency or comment, and keep the card.
- A reviewer never claims: it comments its verdict on the card.
- Never work a blocked card. Comment why you stopped, then stop (a card you
  were given) or take another one (work from `card next`).
- Found midway that your card waits on another? Add the dependency to it
  (`card dep add ID OTHER`), comment why, and keep the card: it shows as
  blocked and cannot be closed until the other one is done.
- Never move, update or release a card another agent holds. Comments are fine.
- Comment at each phase: the branch and worktree, the PR number and head,
  the test or CI verdict, a blocker. Comment before every status change, so
  the reason sits next to the change.
- When you open a PR, add its link to the card:
  `kanban card update ID --link URL`. One card may carry several (a PR and
  its fixes, a PR per repository).
- After a PR of your card merges and you go on to the next slice of its issue,
  comment `next: WHAT` (for example `next: ml#320`). `kanban doctor` then
  does not report the merged card.
- Keep comments short and facts only: the next agent reads them as context.
- Bodies and comments are Markdown, rendered on the web board. Write a phase
  comment as a short bullet list, with `code` for paths, branches and SHAs,
  and full links. Never one long line. Example:

  ```md
  - PR: https://github.com/org/repo/pull/12
  - head `3f2a9c1` on `feat/login`
  - CI green; 41 tests pass
  ```

  Multi-line text from a shell goes by a heredoc on standard input
  (`kanban card comment ID - <<'EOF'`) or `--file`.
- Move your card to Review when the work is ready to be reviewed. Never mark
  it done: when a coordinator does that (after the merge), `card done` is not
  yours. Only when your brief says you finish your own cards do you run it.
- New work you find is a new card (`card add --depends-on`), not a wider card.
- Cannot finish: comment why, then `kanban card release ID`.
- `--force`, `card archive`, `board archive-done` and `board auto-archive` are for the
  coordinator only: an archived card is gone from the board, the lists and `card next`.
- The board is not a lock. It does not replace the build or test locks, and
  it does not lock files.

## For a coordinator

Give each agent its board, its card id and its own name (`KANBAN_AGENT`; the CLI
has no default name), and tell it to load this skill or to run `kanban prime`.
Mark a card done in the same step as the merge of its PR.
