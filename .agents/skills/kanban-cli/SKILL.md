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
kanban board create "Project" --slug project   # slug: --slug, else KANBAN_BOARD, else the name
# without --columns: Todo, Doing, Review, Done
kanban board show [BOARD]

kanban column add Review --position 2 [--done] [--wip 3]   # --done moves the done flag off the old done column
#   and warns on stderr: "Done is no longer the done column; 2 cards are no longer done"
kanban column rename Review Check
kanban column move Check 1
kanban column remove Check             # refused when it has cards or is the done column

kanban card add "Fix login" --label api,ui --priority 1 --body-file task.md \
                [--link URL]...
kanban card list [--column Todo] [--ready] [--mine] [--claimed-by NAME] [--label api] [--all]
kanban card show 12
kanban card update 12 [--title T] [--body T | --body-file F] [--label L] \
                     [--priority N] [--branch B] [--worktree W] [--force] \
                     [--link URL]... [--unlink URL]...

kanban card claim 12                   # 4 when somebody else holds it
kanban card next [--column Todo] [--label api]
kanban card release 12 [--to Todo] [--force]   # releasing a free card is a no-op: "already free"
kanban card move 12 Doing [--position 0] [--force]
kanban card done 12 [--force]
kanban card comment 12 "ran the migration"   # or --file notes.md
kanban card dep add 12 10 [--force]    # 12 needs 10 first; allowed on a card you hold (it stays in its column, shown blocked)
                                       # while 10 is open, `done 12` and `move 12 Done` are refused (BLOCKED, exit 4)
                                       # --force: on done and move it skips CLAIMED, NOT_CLAIMER and that BLOCKED; on dep add or
                                       # remove it skips CLAIMED only (never CYCLE)
kanban card dep remove 12 10 [--force]   # --force skips CLAIMED only

kanban events [--after 42 | --before 42] [--card 12] [--limit 50]   # --before: newest first
```

`--link` and `--unlink` repeat (not after `--`). A link is an http(s) URL (a PR,
an issue, a CI run) in printable ASCII (an IDN host as punycode, a path
percent-encoded), at most 2,048 characters, with no credentials (`user@`),
spaces, quotes or angle brackets; a card holds at most 50, and one request adds
or removes at most 50. Anything else is `INVALID`. Adding a link the card has,
or removing one it has not, writes nothing when the update has no other field:
no new version and no event. A server older than links drops them, so the CLI
then exits 3 with `UNSUPPORTED` (the other fields were saved). When you open a
PR, add its link to the card.

Long text: `--body`, `--body-file PATH`, or `-` to read standard input
(`kanban card comment 12 - < notes.md`). Bodies and comments are Markdown (fenced
code, headings, lists, quotes, `code`, bold, italic, links), rendered on the web
view, so write a comment as a short list and not one long line; from a shell use
a heredoc, which keeps quotes and backticks as they are:

```sh
kanban card comment 12 - <<'EOF'
- PR: https://github.com/org/repo/pull/7
- head `3f2a9c1` on `fix/login`
- CI green
EOF
```
 Labels and `--depends-on` take a
comma-separated list.

Card ids are global, so `card show`, `claim`, `comment`, `done` and `dep` need
no board. `--board` is required by `column *`, `card add`, `card list`,
`card next` and `events`; `board show` takes the board as a positional
argument or from `KANBAN_BOARD`.

## Output

Boards, columns and comments print one tab-separated line each; card lines and
events use two spaces (`#12  Doing  claude-code  Fix login [api]`), so a card
line can be read with `cut -d' ' -f1` on the id. `card show` is a short
multi-line page with one `link:` line per link; its `time:` lines give the time in each column
(`time: Todo 25 min · Doing 2 h 15 min`, then `time: 40 min in Review`, or
`time: total 2 h 40 min` for a done card). `--json` prints the server answer
verbatim, with `times` in milliseconds.

```
$ kanban card list
#12  Doing  claude-code  Fix login [api, ui]
#13  Todo  free  Add logout
```

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | done |
| 1 | the server refused: `NOT_FOUND`, `INVALID`, `CONFLICT`, `CYCLE`, `NOT_CLAIMER` (another agent holds it), `NO_READY_CARD` |
| 2 | usage: unknown command, missing argument, missing agent or board; the code printed is `USAGE` |
| 3 | no server, `UNAUTHORIZED`, `BUSY` after the retries, `UNSUPPORTED` (a server too old for the request), or any other failure |
| 4 | lost the race: `CLAIMED`, `BLOCKED`, `DONE` (but `BLOCKED` on `done` or `move` of a card you hold is not a lost race: wait or comment, and keep the card) |

`bin/kanban` exits 141, silently, when its standard output is closed (`kanban board show | head -1`), as a Unix tool killed by SIGPIPE does.

A refusal is one line on stderr, with the card when that is what failed:

```
$ kanban card claim 12
kanban: CLAIMED: card 12 is claimed by claude-1
$ kanban card claim 14
kanban: BLOCKED: card is blocked by #10, #11
$ kanban bogus
kanban: USAGE: unknown command bogus
```

With `--json` the same error is the server document on stdout, every field
included, and stderr stays empty:

```
$ kanban card claim 12 --json
{"error":{"code":"CLAIMED","message":"card is claimed","card_id":12,"claimed_by":"claude-1"}}
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
kanban card show 12                 # body, deps, time in each column, comments
kanban card comment 12 "started"
kanban card move 12 Doing
kanban card done 12
kanban card list --mine             # nothing left held by this agent
```

`kanban card next` exits 1 with `NO_READY_CARD` when nothing is ready: that is
a normal end of work for one agent, not a failure of the tool.
