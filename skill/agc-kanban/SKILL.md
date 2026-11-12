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
2. Use the card you were given, or take one with `kanban card next`, which
   claims it for you.
3. Read it with `kanban card show ID`: body, dependencies and comments.

## Rules

- Claim before you work. Do not start on a card you do not hold.
- Exit 4 (`CLAIMED`, `BLOCKED`, `DONE`) means you lost the card. Never retry
  it. If you were given the card, stop and report to whoever started you.
  Only when you took work with `card next`, take another.
- A reviewer never claims: it comments its verdict on the card.
- Never work a blocked card. Comment why you stopped, then stop (a card you
  were given) or take another one (work from `card next`).
- Never move, update or release a card another agent holds. Comments are fine.
- Comment at each phase: the branch and worktree, the PR number and head,
  the test or CI verdict, a blocker. Comment before every status change, so
  the reason sits next to the change.
- Keep comments short and facts only: the next agent reads them as context.
  Long text goes by `--file` or standard input.
- Move your card to Review when the work is ready to be reviewed. Never mark
  it done: when a coordinator does that (after the merge), `card done` is not
  yours. Only when your brief says you finish your own cards do you run it.
- New work you find is a new card (`card add --depends-on`), not a wider card.
- Cannot finish: comment why, then `kanban card release ID`.
- `--force` is for the coordinator only.
- The board is not a lock. It does not replace the build or test locks, and
  it does not lock files.

## For a coordinator

Give each agent its board, its card id and its name (`KANBAN_AGENT`), and tell
it to load this skill or to run `kanban prime`.
