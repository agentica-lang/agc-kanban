---
name: kanban-cli
description: Install and drive the agc-kanban board from a shell with the `kanban` command-line client. Use when a person or an agent needs to check the server, create boards and columns, add, list, show, update, claim, release, move, finish or comment on cards, wire dependencies, read the event journal, or hand an agent its starting rules (whoami, card next, prime). Covers the config order, the exit codes and the retry on a busy server.
---

# kanban CLI

`kanban` is a thin client over the REST API: it holds no state. Most commands
are one request; a column command first reads the board to turn a name into an
id, `whoami` checks health and auth, and `prime` calls nothing.

## Install

Requires Agentica 0.30.1 (the version the server and the Docker image pin) and
a running server.

```sh
make cli            # compiles dist/kanban.agcb
make install-cli    # symlinks bin/kanban into ~/.local/bin/kanban
```

Then configure, and check with `kanban whoami`.

`bin/kanban` is a `/bin/sh` wrapper that finds the repo from its own path, so
the symlink keeps working after the sources change. Without installing, run
`./bin/kanban` from the repository.

## Configure

First value wins: flags, environment, `~/.config/agc-kanban/config.toml`,
defaults.

| Flag | Environment | Default |
| --- | --- | --- |
| `--url URL` | `KANBAN_URL` | `http://127.0.0.1:4580` |
| `--agent NAME` | `KANBAN_AGENT` | none, required for writes |
| `--board SLUG` | `KANBAN_BOARD` | none, required by board-wide commands |
| `--json` | | text output |

The API key is environment or file only, never a flag:

```toml
# ~/.config/agc-kanban/config.toml
url = "http://172.28.0.10:4580"
api_key = "7b95…"
agent = "claude-code"
board = "project"
```

```sh
export KANBAN_API_KEY="$(openssl rand -hex 32)"   # must match the server
```

## Commands

```sh
kanban whoami                          # url, agent, board and health
kanban prime                           # the agent rules, ready for a prompt

kanban board list
kanban board create "Project" --columns "Todo,Doing,Done"   # last column is the done one
kanban board create "Project" --slug project   # slug defaults to KANBAN_BOARD
# without --columns: Todo, Doing, Review, Done
kanban board show [BOARD]

kanban column add Review --position 2 [--done] [--wip 3]   # --done moves the done flag off the old done column
kanban column rename Review Check
kanban column move Check 1
kanban column remove Check             # refused when it has cards or is the done column

kanban card add "Fix login" --label api,ui --priority 1 --body-file task.md
kanban card list [--column Todo] [--ready] [--mine] [--claimed-by NAME] [--label api] [--all]
kanban card show 12
kanban card update 12 [--title T] [--body T | --body-file F] [--label L] \
                     [--priority N] [--branch B] [--worktree W] [--force]

kanban card claim 12                   # 4 when somebody else holds it
kanban card next [--column Todo] [--label api]
kanban card release 12 [--to Todo] [--force]
kanban card move 12 Doing [--position 0] [--force]
kanban card done 12 [--force]
kanban card comment 12 "ran the migration"   # or --file notes.md
kanban card dep add 12 10              # 12 needs 10 first
kanban card dep remove 12 10

kanban events [--after 42] [--card 12] [--limit 50]
```

Long text: `--body`, `--body-file PATH`, or `-` to read standard input
(`kanban card comment 12 - < notes.md`). Labels and `--depends-on` take a
comma-separated list.

Card ids are global, so `card show`, `claim`, `comment`, `done` and `dep` need
no board. `--board` is required by `column *`, `card add`, `card list`,
`card next` and `events`; `board show` takes the board as a positional
argument or from `KANBAN_BOARD`.

## Output

Boards, columns and comments print one tab-separated line each; card lines and
events use two spaces (`#12  Doing  claude-code  Fix login [api]`), so a card
line can be read with `cut -d' ' -f1` on the id. `card show` is a short
multi-line page. `--json` prints the server answer verbatim.

```
$ kanban card list
#12  Doing  claude-code  Fix login [api, ui]
#13  Todo  free  Add logout
```

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | done |
| 1 | the server refused: `NOT_FOUND`, `INVALID`, `CONFLICT`, `CYCLE`, `NOT_CLAIMER`, `NO_READY_CARD` |
| 2 | usage: unknown command, missing argument, missing agent or board; the code printed is `USAGE` |
| 3 | no server, `UNAUTHORIZED`, `BUSY` after the retries, or any other failure |
| 4 | lost the race: `CLAIMED`, `BLOCKED`, `DONE` |

A refusal is one line on stderr, with the card when that is what failed:

```
$ kanban card claim 12
kanban: CLAIMED: card 12 is claimed by claude-1
$ kanban card claim 14
kanban: BLOCKED: card is blocked by #10, #11
```

The client retries a `503` after 200, 400 and 800 ms and then exits 3, so a
short restart of the server is invisible. A failed write is never repeated
because the request may have arrived; only `GET` is retried on a connection
failure.

## A full loop

```sh
export KANBAN_URL=http://172.28.0.10:4580 KANBAN_AGENT=claude-code KANBAN_BOARD=project
kanban whoami
kanban card next                    # claims the first ready card and prints it
kanban card show 12                 # body, deps, comments
kanban card comment 12 "started"
kanban card move 12 Doing
kanban card done 12
kanban card list --mine             # nothing left held by this agent
```

`kanban card next` exits 1 with `NO_READY_CARD` when nothing is ready: that is
a normal end of work for one agent, not a failure of the tool.
