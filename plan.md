# agc-kanban: the plan

A small shared Kanban board for coding agents. Agents use it from a CLI. The
owner watches it live in a browser. Everything that runs is written in
Agentica, except the browser script.

This file is the plan only. There is no product code yet.

## 1. Goal and non-goals

### Goal

- Agents that run in parallel under an orchestrator (Claude Code, OpenCode,
  Codex) share work on a board. They create boards, add columns, add cards,
  claim a card, move it, comment on it and mark it done.
- Agents use a CLI, `kanban`, through plain shell commands. A harness's
  subagents do not inherit the parent's tools, but every subagent can run a
  shell command, so the CLI works for all of them.
- An agent skill (`SKILL.md`) teaches agents the CLI and the rules.
- The owner opens a web page and sees the boards change in real time.
- A claim is atomic. Two agents never hold the same card.
- A card can depend on other cards. A card with open dependencies cannot be
  claimed or closed. A card already in progress can gain a dependency: it keeps
  its column and claim and shows as blocked, and only closing it waits.
- Comments stay. They are the shared context of a card.
- A card can record the git branch and worktree an agent works in.

### Non-goals (KISS)

- One API key for everything. No users, no roles, no sign-up.
- One server process. No cluster, no replication.
- No drag-and-drop and no writes from the web, except the color of a label:
  the web page stays otherwise view-only (see the open questions).
- No agent runner. The board does not start agents, open worktrees or run
  tests. The orchestrator does that.
- No GitHub sync, no MCP server, no notifications by email or chat.
- No delete of cards in v1. A card is archived instead (phase 5); the event
  log keeps its history.

## 2. Architecture

```text
 agents (shell)                                   owner (browser)
 kanban card claim 12 --json                      https://host:4580/
        |                                                ^   |
        | REST JSON, header `apikey`                     |   | GET pages, /api/* (cookie)
        v                                                |   v
 +--------------------------------------------------------------+
 |  kanban server (Agentica + Bond)                              |
 |   before filter: API key or session cookie                   |
 |   /api/* JSON routes -> domain (src/kanban) -> agentica-db   |
 |   after each commit: broadcast the event on bond-channels    |
 |   /cable: Action Cable WebSocket (bond-channels)  ----------+--> live events
 |   /assets: built CSS and JS (Bond.static)                    |
 +--------------------------------------------------------------+
                         |
                         v
           SQLite file: $KANBAN_DATA_DIR/kanban.sqlite3 (WAL)
```

### Components

| Component | What it is |
|---|---|
| Server | `server.agc`. Bond app: the JSON API, the web pages, `/cable` and the static assets. Owns the database. |
| CLI | `cli.agc`, run as `kanban`. Talks to the server over HTTP with `std/http`. Never opens the database. |
| Web | Plain JavaScript and SCSS in `app/`, built with pnpm, esbuild and Dart Sass into `public/assets/`. |
| Skill | `skill/agc-kanban/SKILL.md`. Teaches agents the loop and the rules. |

### How they talk

- The CLI and the web call the same REST JSON API under `/api/`.
- The CLI sends the API key in the `apikey` header, as evolution-api does.
  It sends the agent name in the `X-Kanban-Agent` header.
- The browser cannot set headers on a WebSocket. So the owner signs in once
  on `/login` with the API key. The server then sets a signed session cookie
  (`Bond.sessions`). The web reads `/api/` and opens `/cable` with that
  cookie.
- Live updates go over bond-channels (the Action Cable protocol,
  `actioncable-v1-json`). The server broadcasts one JSON event per change.

### Storage

- agentica-db with SQLite (decided by the owner): `pkg/db/db`,
  `pkg/db/db_pool` and `pkg/db/migrate`.
- The file is `$KANBAN_DATA_DIR/kanban.sqlite3`. `KANBAN_DATA_DIR` defaults
  to `./data`. The url is `sqlite:<data dir>/kanban.sqlite3`. agentica-db
  opens it in WAL mode with a `busy_timeout` of 5000 ms by default.
- Back up with `VACUUM INTO 'copy.sqlite3'` or with the server stopped.
  Copying the `.sqlite3` file alone while the server runs can lose the
  writes that are still in the `-wal` file.
- Only the server opens the file. The CLI talks to the server, so many CLI
  processes on many machines all go through one writer.

### Atomic claims

Each write runs in `Db.transaction`. On SQLite it starts with
`BEGIN IMMEDIATE`, so it takes the write lock first and two writes never
interleave. The claim itself is one conditional update:

```sql
UPDATE cards
   SET claimed_by = :agent, claimed_at = :now, lease_until = :lease,
       version = version + 1, updated_at = :now
 WHERE id = :id
   AND archived_at IS NULL
   AND column_id NOT IN (SELECT id FROM columns WHERE done = 1)
   AND (claimed_by IS NULL OR claimed_by = :agent OR lease_until < :now)
   AND NOT EXISTS (
         SELECT 1 FROM card_deps d
           JOIN cards b ON b.id = d.depends_on_id
           JOIN columns c ON c.id = b.column_id
          WHERE d.card_id = :id AND c.done = 0)
```

`Db.execute` returns the rows changed. One row: the claim is won. Zero
rows: the same transaction reads the card and answers why (`CLAIMED`,
`BLOCKED`, `DONE`, `NOT_FOUND`). The event row is written in the same
transaction. The broadcast goes out after the commit.

`claim-next` (claim the first ready card) runs the same update in a loop
over the ready cards, inside one transaction, and stops at the first win.
Many agents can call it at once and each gets a different card.

### Configuration of the server

| Variable | Default | Meaning |
|---|---|---|
| `KANBAN_API_KEY` | (required) | The one key. At least 32 characters. The server refuses to start without it. |
| `KANBAN_HOST` | `127.0.0.1` | Address to listen on. |
| `KANBAN_PORT` | `4580` | Port. |
| `KANBAN_DATA_DIR` | `./data` | Folder of `kanban.sqlite3`. Created with mode 0700. |
| `KANBAN_LEASE_MINUTES` | `0` | Claim lease. `0` means a claim never expires (see the open questions). |
| `KANBAN_COOKIE_SECURE` | `0` | `1` marks the session cookie Secure. Set it behind HTTPS only: over plain HTTP the browser drops the cookie and nobody can sign in. |

The session cookie is signed with a key derived from the API key
(HMAC-SHA256 of a fixed label). So there is one secret, and a new API key
signs everyone out.

### Repository layout

Copied from agentica-campfire, smaller.

```text
agentica.toml          name, [style], deps: bond, db, channels (bond-channels)
agentica.lock
Makefile               install, run, cli, check, fmt-check, test, assets
server.agc             main of the server: config, migrate, pool, hub, app
cli.agc                main of the CLI
src/kanban/            the domain, no HTTP: boards.agc, columns.agc, cards.agc,
                       claims.agc, deps.agc, comments.agc, events.agc,
                       config.agc, codes.agc (error codes)
src/kanban/repo/       database.agc (migrate, pool, with_connection, busy?),
                       migrations.agc, migrations/m0001_*.agc ..., rows.agc
src/kanban_web/        app.agc (build: the filter and the router), routes.agc
                       (paths), router.agc (the route table), auth.agc (apikey
                       filter, /login, session), failure.agc (domain error to
                       HTTP), params.agc (body and query), answers.agc (shared
                       envelopes), health.agc, controllers/ (one module per
                       resource), cable.agc (channels and broadcasts),
                       views.agc (EAG page shell), asset_names.agc (written by
                       make assets)
src/kanban_cli/        config.agc (env and file), client.agc (HTTP calls),
                       commands.agc (option_parser specs), output.agc (text
                       and --json), main flow
app/javascript/        application.js, cable.js, board.js, render.js
app/stylesheets/       application.scss, settings/, base/, components/
tools/assets.mjs       Dart Sass + esbuild, fingerprinted names
public/assets/         built CSS and JS, not in git (make assets)
package.json, pnpm-lock.yaml   only esbuild and sass, as dev dependencies
bin/kanban             shell wrapper: runs dist/kanban.agcb
skill/agc-kanban/SKILL.md
specs/                 *.feature, steps.agc, cli_steps.agc, cable_steps.agc,
                       fixtures/server.agc, fixtures/ws_client.agc
test/                  *_test.agc unit tests (migrations list, small pure parts)
refs/                  reference clones, ignored by git
```

The server and the CLI live in one repository and one `agentica.toml`. The
CLI imports only `std/` modules, so it needs no C compiler and no SQLite.

## 3. Data model (SQLite)

Times are Unix milliseconds (`INTEGER`). Ids are `INTEGER PRIMARY KEY`.
Booleans are `INTEGER` 0 or 1. `foreign_keys` is on (agentica-db's default).

```sql
CREATE TABLE boards (
  id          INTEGER PRIMARY KEY,
  slug        TEXT    NOT NULL UNIQUE,      -- [a-z0-9-]{1,40}, used in paths
  name        TEXT    NOT NULL,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);

CREATE TABLE columns (
  id          INTEGER PRIMARY KEY,
  board_id    INTEGER NOT NULL REFERENCES boards(id),
  name        TEXT    NOT NULL,
  position    INTEGER NOT NULL,             -- 0..n-1, renumbered on change
  done        INTEGER NOT NULL DEFAULT 0,   -- cards here count as done
  wip_limit   INTEGER,                      -- shown only, not enforced in v1
  created_at  INTEGER NOT NULL,
  UNIQUE (board_id, name),
  UNIQUE (board_id, position)
);
CREATE UNIQUE INDEX columns_one_done ON columns (board_id) WHERE done = 1;

CREATE TABLE cards (
  id          INTEGER PRIMARY KEY,          -- global, so `kanban card show 12`
  board_id    INTEGER NOT NULL REFERENCES boards(id),
  column_id   INTEGER NOT NULL REFERENCES columns(id),
  position    INTEGER NOT NULL,             -- 0..n-1 in its column
  title       TEXT    NOT NULL,
  body        TEXT    NOT NULL DEFAULT '',  -- Markdown, shown as text in v1
  labels      TEXT    NOT NULL DEFAULT '[]',-- JSON array of strings
  links       TEXT    NOT NULL DEFAULT '[]',-- JSON array of http(s) URLs (migration 7)
  priority    INTEGER NOT NULL DEFAULT 2,   -- 0 high .. 4 low, as Beads
  claimed_by  TEXT,                         -- agent name, NULL = free
  claimed_at  INTEGER,
  lease_until INTEGER,                      -- NULL = no expiry
  branch      TEXT,
  worktree    TEXT,
  created_by  TEXT    NOT NULL,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  done_at     INTEGER,
  archived_at INTEGER,
  version     INTEGER NOT NULL DEFAULT 1    -- +1 on every change
);
CREATE INDEX cards_column ON cards (column_id, position);
CREATE INDEX cards_board ON cards (board_id, archived_at);
CREATE INDEX cards_claimed_by ON cards (claimed_by) WHERE claimed_by IS NOT NULL;

CREATE TABLE card_deps (
  card_id       INTEGER NOT NULL REFERENCES cards(id),
  depends_on_id INTEGER NOT NULL REFERENCES cards(id),
  created_at    INTEGER NOT NULL,
  PRIMARY KEY (card_id, depends_on_id),
  CHECK (card_id <> depends_on_id)
);
CREATE INDEX card_deps_reverse ON card_deps (depends_on_id);

CREATE TABLE comments (
  id         INTEGER PRIMARY KEY,
  card_id    INTEGER NOT NULL REFERENCES cards(id),
  author     TEXT    NOT NULL,
  body       TEXT    NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX comments_card ON comments (card_id, id);

CREATE TABLE events (
  id         INTEGER PRIMARY KEY,           -- the order of all changes
  board_id   INTEGER NOT NULL REFERENCES boards(id),
  card_id    INTEGER REFERENCES cards(id),
  kind       TEXT    NOT NULL,              -- see the list below
  actor      TEXT    NOT NULL,              -- agent name, or "web"
  data       TEXT    NOT NULL,              -- JSON: what changed
  created_at INTEGER NOT NULL
);
CREATE INDEX events_board ON events (board_id, id);
CREATE INDEX events_card ON events (card_id, id);
```

Rules:

- A board has exactly one done column. A new board gets `Todo`, `Doing`,
  `Review` and `Done` unless the request names its columns. The last one is
  the done column.
- A card is **done** when its column is the done column. Moving a card into
  it sets `done_at` and clears the claim. Moving it out clears `done_at`.
- A card is **ready** when it is not archived, not done, not claimed (or its
  lease ended) and every card it depends on is done.
- Dependencies are "blocks" only (Beads' blocking type). They may cross
  boards. Adding one that makes a cycle is refused (`CYCLE`), checked with a
  recursive CTE in the same transaction.
- Labels are a JSON array of names in `cards.labels`, and the filter `--label`
  uses `json_each`. The `labels` table (migration 9: `board_id`, `name`, `color`
  as `#rrggbb`, `created_at`, UNIQUE (`board_id`, `name`)) only holds the color
  of each name per board. The first card that carries a name the board has not
  seen creates the row, with a palette color that no label of the board wears
  yet (any when all are taken); the migration backfills it from the cards. A
  rename (`PATCH /api/labels/:id` with `name`) rewrites the name on the cards of
  the board; a name that exists is `CONFLICT`. The color is validated
  (`INVALID`) and stored in lower case.
- Links are a JSON array of URLs too (a PR, an issue, a CI run), each once,
  at most 50 per card, and a create names at most 50 (repeats included). A
  link is http(s) with a host and no `@` before the path, in printable ASCII,
  at most 2,048 bytes, with no quote, angle bracket, backslash or `^`, `` ` ``,
  `{`, `|`, `}`: it is shown on the web and printed to terminals, so anything
  else is `INVALID`.
- Event kinds: `board.created`, `column.added`, `column.updated`,
  `column.removed`, `card.created`, `card.updated`, `card.moved`,
  `card.claimed`, `card.released`, `card.done`, `card.archived`,
  `dep.added`, `dep.removed`, `comment.added`, `label.updated`.

## 4. API

All paths are under `/api/`. Every request needs the `apikey` header (the
CLI) or the session cookie (the web: reads, and `PATCH /api/labels/:id`). Writes need the
`X-Kanban-Agent` header: the agent name, 1 to 64 characters of
`[A-Za-z0-9._@/-]`. The name is not a proof of identity: anyone with the key
can use any name. It keeps honest agents apart, which is the goal.

Bodies are JSON. A `:board` in a path is the slug or the id. Answers are JSON
objects. The server does not check `Content-Type`, and a body that does not
decode reports `field: "body"`; field-level messages come from the domain once
the body decodes.

### Shapes

```json
{"board": {"id": 1, "slug": "auth", "name": "Auth rewrite",
           "columns": [{"id": 1, "name": "Todo", "position": 0, "done": false, "wip_limit": null}],
           "created_at": 1762950000000, "updated_at": 1762950000000}}

{"card": {"id": 12, "board": "auth", "column": "Doing", "column_id": 2, "position": 0,
          "title": "Add login route", "body": "...", "labels": ["api"],
          "links": ["https://github.com/org/repo/pull/7"], "priority": 2,
          "claimed_by": "claude-2", "claimed_at": 1762950000000, "lease_until": null,
          "branch": "feat/login", "worktree": "/work/wt-login",
          "depends_on": [10, 11], "blocks": [14], "ready": false, "done": false,
          "created_by": "orchestrator", "created_at": 1762950000000,
          "updated_at": 1762950000000, "done_at": null, "version": 4}}

{"error": {"code": "CLAIMED", "message": "card 12 is claimed by claude-1",
           "card_id": 12, "claimed_by": "claude-1"}}
```

### Errors

| HTTP | `code` | When |
|---|---|---|
| 400 | `INVALID` | Bad JSON, a missing or bad field, a bad agent name. `field` names it. |
| 401 | `UNAUTHORIZED` | No key, a wrong key or no session. |
| 404 | `NOT_FOUND` | No such board, column or card. |
| 404 | `NO_READY_CARD` | `claim-next` found nothing ready. |
| 409 | `CLAIMED` | The card is claimed by another agent. `claimed_by` names it. |
| 409 | `BLOCKED` | A claim, `done` or a move into the done column of a card with a dependency that is not done (`force` skips it, except for a claim). `blocked_by` lists the card ids. |
| 409 | `NOT_CLAIMER` | Release or done by an agent that does not hold the claim (without `force`). |
| 409 | `DONE` | Claim or `done` of a card that is already done. |
| 409 | `CYCLE` | The dependency would make a cycle. |
| 409 | `CONFLICT` | A name or slug that exists, a column that still has cards. |
| 503 | `BUSY` | The database is busy (pool or lock timeout). Safe to retry. |

Tests assert the `code` and the status, never the message.

### Endpoints

| Method and path | Request | Answer |
|---|---|---|
| `GET /api/health` (no auth) | | `{"ok": true, "version": "0.1.0"}` |
| `GET /api/auth-check` | | `{"ok": true}`; 401 without a good key, the CLI's probe |
| `GET /api/boards` | | `{"boards": [board]}` (without columns) |
| `POST /api/boards` | `{"name", "slug"?, "columns"?: ["Todo", ...]}` | 201 `{"board"}` |
| `GET /api/boards/:board` | | `{"board", "cards": [card], "last_event_id"}`: the snapshot the web draws |
| `GET /api/boards/:board/labels` | | `{"labels": [{"id", "name", "color"}]}`, by name; the snapshot has the same `labels` |
| `PATCH /api/labels/:id` | `{"name"?, "color"?: "#rrggbb"}` (one of them) | `{"label"}`; `label.updated` event; `INVALID`, `NOT_FOUND`, `CONFLICT` (name taken). The web session may send this one write (with `X-Kanban-Agent`) |
| `POST /api/boards/:board/columns` | `{"name", "position"?, "done"?, "wip_limit"?}` | 201 `{"column"}` |
| `PATCH /api/columns/:id` | `{"name"?, "position"?, "done"?, "wip_limit"?, "force"?: false}` | `{"column"}`; making a column done is `BLOCKED` (`blocked_by` lists the cards of the column that wait for a card outside it) unless `force`, which the `column.updated` event records |
| `DELETE /api/columns/:id` | | 204, or `CONFLICT` if it has cards |
| `GET /api/boards/:board/cards` | query: `column`, `ready=1`, `claimed_by`, `label`, `done=0/1` | `{"cards": [card]}`, ordered by column, then position |
| `POST /api/boards/:board/cards` | `{"title", "body"?, "column"?, "labels"?, "priority"?, "depends_on"?: [id], "links"?: [url]}` (at most 50 links, repeats included) | 201 `{"card"}`; the first column by default |
| `GET /api/cards/:id` | | `{"card", "comments": [comment]}` |
| `PATCH /api/cards/:id` | `{"title"?, "body"?, "labels"?, "priority"?, "branch"?, "worktree"?, "link"?: [url], "unlink"?: [url]}` | `{"card"}`; `CLAIMED` if another agent holds it. `unlink` removes, then `link` adds (each list at most 50, repeats included) the URLs the card lacks; when only links were asked and none changed, nothing is written (no version, no event), unless the actor holds a running lease and leases are on; then it renews the lease. |
| `POST /api/cards/:id/claim` | `{}` | `{"card"}`; `CLAIMED`, `BLOCKED`, `DONE`. Claiming a card you hold renews the lease. |
| `POST /api/boards/:board/claim-next` | `{"column"?, "label"?}` | `{"card"}` or `NO_READY_CARD` |
| `POST /api/cards/:id/release` | `{"force"?: false, "column"?}` | `{"card"}`; `NOT_CLAIMER` unless `force` |
| `POST /api/cards/:id/move` | `{"column", "position"?, "force"?: false}` | `{"card"}`; `CLAIMED` if another agent holds it, `BLOCKED` into the done column with an open dependency; `force` skips both |
| `POST /api/cards/:id/done` | `{"force"?: false}` | `{"card"}`: moved to the done column, claim cleared; `NOT_CLAIMER` or `BLOCKED` (an open dependency) unless `force` |
| `POST /api/cards/:id/archive` | `{"force"?: false}` | `{"card"}` with `archived_at`: hidden from the board, the lists, `next`, claims and readiness; kept in the database, the journal (`card.archived`) and `GET /api/cards/:id`. No role is checked (the coordinator's by agreement); `CLAIMED` unless `force`, which drops the claim. An archived card is archived again with no new event. Every other write on it is `NOT_FOUND`. A dependency on it no longer blocks |
| `POST /api/cards/:id/comments` | `{"body"}` | 201 `{"comment": {"id", "card_id", "author", "body", "created_at"}}` |
| `POST /api/cards/:id/deps` | `{"depends_on": id, "force"?: false}` | 201 `{"card"}`; `CYCLE`; `CLAIMED` if another agent holds the card, unless `force`. The holder can add one: the card keeps its column and claim and shows blocked. A new card in the done column with an open dependency is `BLOCKED` too |
| `DELETE /api/cards/:id/deps/:other` | query: `force=1` | `{"card"}`; `CLAIMED` if another agent holds the card, unless `force` |
| `GET /api/boards/:board/events` | query: `after` (oldest first), or `before` (newest first, for the pages of older events; with `after` it is `INVALID`), `card`, `limit` (100, at most 1000) | `{"events": [event], "last_event_id"}` |

Event `data` holds the changed object: the `board`, `column`, `card` or
`comment` shape above, as `card.*` kinds do, with `forced` and `from` (the
column the card left: `{"id", "name"}`; missing in older events) beside the card
for `card.moved`, `card.released` and `card.done`. A column that changes the done
flag of its cards emits one `card.updated` per affected card in the same
transaction.

Who may change a card: anyone when it is free; only the claimer when it is
claimed. `force: true` overrides, for the orchestrator and the owner; the
event records it (`forced` in the data of `card.moved`, `card.done`,
`card.released`, `dep.added`, `dep.removed` and of a `column.updated` that made a
column done). It is one switch for the refusals that are about who or when:
`CLAIMED`, `NOT_CLAIMER` and the `BLOCKED` of `done`, of a move into the done
column and of making a column done. On a dependency add or remove it skips
`CLAIMED` only. It never skips `CYCLE`, a `BLOCKED` claim, or the `BLOCKED` of a
new card in the done column. Comments are always allowed, so another agent can
leave a note on a claimed card.

`claim` sets the card's column to the first column that is neither the first
nor done ("Doing") when the card sits in the first column. This keeps the
board honest without a second command. It is a rule of the server, so all
clients agree.

## 5. CLI

The CLI is `cli.agc`, compiled to `dist/kanban.agcb` by `make cli`.
`bin/kanban` runs it with `agentica run -- dist/kanban.agcb "$@"`.
`make install-cli` symlinks the wrapper into `~/.local/bin/kanban`; the
wrapper follows the link to find the repo, so it runs the current build.
Commands and flags use `std/option_parser`, one parser per command.

### Configuration

Read in this order; the first value wins:

1. Flags: `--url`, `--agent`, `--board`.
2. Environment: `KANBAN_URL`, `KANBAN_API_KEY`, `KANBAN_AGENT`,
   `KANBAN_BOARD`.
3. The file `~/.config/agc-kanban/config.toml` (read with `std/toml`):
   `url`, `api_key`, `board`. An `agent` key is ignored, with a one-line
   warning on stderr (see below).

The key is never a flag, so it does not show in `ps` or shell history.
`KANBAN_AGENT` (or `--agent`) names the agent, and nothing else does: no
config default, because a name shared by every session lets two agents act as
one (the owner's decision, issue 39). The orchestrator gives each subagent its
name in the brief, for example `KANBAN_AGENT=claude-2`. Every command that acts
as an agent (a write, `card next`, `card list --mine`) fails without a name:
`USAGE: no agent name; ask your coordinator, then set KANBAN_AGENT or --agent`,
exit 2. Reads need no name. `whoami` prints the name, or `none`.

### Commands

```text
kanban board list
kanban board create NAME [--slug S] [--columns "Todo,Doing,Review,Done"]
kanban board show [BOARD]                 columns and cards, the whole board

kanban column add NAME [--position N] [--done] [--wip N]
kanban column rename COLUMN NAME
kanban column move COLUMN POSITION
kanban column remove COLUMN

kanban card add TITLE [--body TEXT | --body-file F] [--column C]
                [--label L]... [--priority 0-4] [--depends-on ID]...
kanban card list [--column C] [--ready] [--mine] [--claimed-by A] [--label L] [--all]
                [--format text|tsv]
kanban card show ID                       card, dependencies, comments
kanban card claim ID
kanban card next [--column C] [--label L] claim the first ready card
kanban card release ID [--to COLUMN] [--force]
kanban card move ID COLUMN [--position N] [--force]
kanban card update ID [--title T] [--body TEXT | --body-file F] [--label L]...
                      [--priority N] [--branch B] [--worktree W]
kanban card comment ID TEXT | --file F    `-` reads stdin
kanban card done ID [--force]
kanban card archive ID [--force]          hides the card (the coordinator's)
kanban card dep add ID DEPENDS_ON_ID [--force]
kanban card dep remove ID DEPENDS_ON_ID [--force]

kanban events [--after N] [--card ID] [--limit N]
kanban whoami                             url, agent, board, server health
kanban prime                              print the agent rules (the skill, short)
```

`--board` applies to every command that needs a board. `card list` hides
done cards unless `--all`.

`kanban prime` prints the short form of the skill (the loop and the rules),
as `bd prime` and `flux prime` do. An orchestrator can paste it into a
subagent's prompt, or tell the subagent to run it, so a subagent that has
no skills installed still learns the rules from the shell alone.

### Output

- Default: short text for people. `card list` prints one line per card:
  `#12  Doing   claude-2  Add login route  [api]`. `card list --format tsv`
  prints one tab-separated line per card for scripts (id, column,
  claimed_by, ready, priority, labels, title; no header); it cannot be
  combined with `--json`.
- `--json`: one JSON document on stdout, the server's answer as is. Errors
  are `{"error": {...}}` on stdout too, so an agent reads one stream.
- Text errors go to stderr as `kanban: CLAIMED: card 12 is claimed by
  claude-1`. A usage error prints the code `USAGE`, so it cannot be mistaken
  for a refusal from the server.

Exit codes:

| Code | Meaning |
|---|---|
| 0 | Done. |
| 1 | The server refused it: `INVALID`, `NOT_FOUND`, `NO_READY_CARD`, `NOT_CLAIMER`, `CYCLE`, `CONFLICT`. |
| 2 | Bad usage (from `option_parser`), or the agent name is missing for a write, `card next` or `card list --mine`; the code is `USAGE`. |
| 3 | No server, `UNAUTHORIZED`, or `BUSY` after 3 tries. |
| 4 | Lost a race: `CLAIMED`, `BLOCKED` or `DONE`. Pick another card. (`BLOCKED` on `done` or `move` of a card you hold is not a lost race: wait or comment, and keep the card.) |

The CLI retries `BUSY` 3 times (200 ms, 400 ms, 800 ms). A connection failure
is retried only for `GET`: a write that failed in transport may have arrived,
and a retry would duplicate it.

## 6. Live web

### Pages

- `/login`: a form with the API key. A good key sets the session cookie and
  sends you to `/`.
- `/`: the list of boards with counts per column and the number of claimed
  cards.
- `/boards/:slug`: the columns side by side and the cards in them. A card
  shows the id, title, labels, claimer and age of the claim, branch, and a
  "blocked" mark when a dependency is open. Click a card to open a side panel
  with the body, dependencies and comments.
- A right-hand activity feed shows the last 50 events of the board.

The server sends a small HTML shell (EAG view) with the asset names. The
script fetches `/api/boards/:slug` and draws the board. No framework: a
single `render(state)` that rebuilds a column from data is enough at this
size.

### Channels

The browser opens one WebSocket to `/cable` with the protocol
`actioncable-v1-json`. `connect` reads the session cookie; no session is
`unauthorized` and the client does not reconnect.

| Channel (`identifier`) | Stream | Gets |
|---|---|---|
| `{"channel": "BoardsChannel"}` | `boards` | `board.created`, and a count change on any card event |
| `{"channel": "BoardChannel", "board": "auth"}` | `board:<id>` | every event of that board |

A broadcast is the event row as JSON plus the new state of what changed:

```json
{"type": "card.moved", "event_id": 381, "board_id": 1, "actor": "claude-2",
 "at": 1762950000000, "card": {"id": 12, "column_id": 3, "position": 0, ...},
 "data": {"from": "Doing", "to": "Review"}}
```

The browser fetches the board again after an event. The activity feed shows
the last 30 events (`?before=<newest>&limit=31`, newest first) and a "Ver mas"
button loads the 30 before the oldest shown (`before` is the cursor of the
older pages). On every confirmed subscription, the first too, it fetches the
board again and reads `?after=<newest seen>&limit=30` page by page, ordered
by id; the feed merges by id, so an event from the cable and from a fetch
shows once. So a missed broadcast is never a wrong board.

The server broadcasts after the commit, never inside the transaction. A
broadcast that fails is logged and dropped; the event log still has it.

### Build and look

- pnpm with only two dev dependencies, `esbuild` and `sass`, pinned in
  `package.json`, with `pnpm-lock.yaml` committed.
- `tools/assets.mjs`, as in Campfire: Dart Sass compiles
  `app/stylesheets/application.scss`, esbuild bundles
  `app/javascript/application.js` (IIFE, minified), both are named by the
  first 16 hex digits of their SHA-256, written to `public/assets/`, and
  their names go to `src/kanban_web/asset_names.agc`.
- The built files are not in git (`.gitignore`). `make run`, `make check` and
  `make test` build them first (`make assets`), and the Dockerfile builds them
  in its Node stage, so the server needs no Node at run time.
- `Bond.static` with `fingerprint` on serves them with
  `immutable` caching.
- The Action Cable client is a small hand-written module (`cable.js`), as
  Campfire's `live.js`: subscribe, receive, ping watch, reconnect with
  backoff. No `@rails/actioncable` dependency.
- The look: SCSS tokens in `settings/` (colors, spacing, radius, fonts), a
  light and a dark theme from `prefers-color-scheme`, system fonts, columns
  as soft panels, cards as white tiles with a colored left edge per label or
  priority, a pill for the claimer with a color from a hash of the name, and
  a short highlight when a card changes live. It stays readable at 1280 px
  with 6 columns and scrolls sideways beyond that.

## 7. The agent skill

`skill/agc-kanban/SKILL.md`, short, with front matter (`name`,
`description`). It assumes only a shell. It teaches:

1. Setup check: `kanban whoami --json`. If it fails, stop and tell the
   orchestrator. Never guess the URL or the key.
2. The loop:
   - find work: `kanban card next --json` (or `card list --ready --json`,
     then `card claim ID --json`);
   - read it before acting: `kanban card show ID --json` (body,
     dependencies, comments);
   - record where you work: `kanban card update ID --branch B --worktree W`;
   - work; comment progress and findings with `kanban card comment`;
   - found new work? `kanban card add ... --depends-on` or a new card that
     the current one depends on; never widen your own card;
   - finish: comment a summary (what changed, how it was checked), then
     `kanban card move ID Review` or `kanban card done ID`;
   - cannot finish: comment why, then `kanban card release ID`.
3. The rules:
   - Claim before you work. Exit code 4 means another agent won: pick
     another card, do not retry the same one.
   - Never move, update, release or finish a card that another agent
     claimed. Comments are fine.
   - Always pass `--json` and read the `error.code`, not the message.
   - Comment before you change a card's column, so the reason is next to
     the change.
   - Keep comments short and factual: they are the context the next agent
     reads. Pass long text with `--file` or stdin, not inline.
   - `--force` is for the orchestrator only.
4. For orchestrators: give each subagent its own name (`KANBAN_AGENT`, never a
   shared default), and put the board
   and the card id in the subagent's prompt, or tell it to run
   `kanban prime`. A subagent needs no other tool than the shell.

The skill shows each command once, with its JSON shape, and the exit
codes. It does not repeat the API.

## 8. Phases

Tests come first in each phase. Tests are written in Agentica and run with
`agentica test`: BDD features through the CLI and the HTTP API, unit tests
only for small pure parts, property tests only where they pay off. No Python
tests and no Python peers.

### Phase 0: skeleton and decisions

- [x] Answer the open questions (section 9).
- [x] `agentica.toml` with `bond`, `db` (`subdir = "src/db"`) and
      `channels` (bond-channels), at the same tags as agentica-campfire;
      `agentica install`; commit `agentica.lock`.
- [x] `Makefile` with `install`, `run`, `cli`, `check`, `fmt-check`, `test`,
      `assets` (asset targets are placeholders until the web phase).
- [x] `server.agc` that serves `GET /api/health`, and `cli.agc` with
      `kanban whoami`.
- [x] `specs/steps.agc` and `specs/fixtures/server.agc`: start the server
      on port 0 with a test key; the BDD runner stops it after each scenario.
      A temporary data directory is not needed until storage is added.
- [x] Health answers without authentication; a wrong key is 401 on the
      protected authentication check.
- CI queda aplazado: el proyecto permanece privado y local hasta nuevo aviso.

Done when: `make test` passes the health feature, and `bin/kanban whoami`
talks to a running server.

### Phase 1: server core, API and storage

- [x] Features first, one per area: `boards.feature`, `columns.feature`,
      `cards.feature`, `claims.feature`, `deps.feature`, `comments.feature`,
      `events.feature`, `auth.feature`, plus `busy.feature`. Steps call the
      API with `std/http` against the server fixture and assert the status
      and `error.code`.
- [x] Migrations with `Migrate.up`, one file each, as agentica-db's layout:
      `m0001_boards`, `m0002_columns`, `m0003_cards`, `m0004_card_deps`,
      `m0005_comments`, `m0006_events`. `migrations.agc` lists them.
- [x] `test/migrations_test.agc`: versions go 1 to N, with one migration per version.
- [x] `repo/database.agc`: migrate at start, `DbPool` for requests,
      `busy?` that maps to 503 `BUSY`.
- [x] Domain modules in `src/kanban/`. Each write: one `Db.transaction`,
      the change, the event row; return the event. Column update/removal
      and card update keep the same shape.
- [x] The conditional-update claim, `claim-next`, release, move, done,
      and the rules of "who may change a card".
- [x] Dependency add with the recursive-CTE cycle check; `ready` as one
      SQL query.
- [x] The `apikey` filter (constant-time compare) and `X-Kanban-Agent`
      validation.
- [x] Race scenario: 8 tasks claim the same card at once through HTTP;
      exactly one gets 200, seven get `CLAIMED`. And: 8 tasks call
      `claim-next` on a board with 8 ready cards; each gets a different card.
- [x] One property test with `prop` (agentica-lang/packages): a random
      sequence of add, claim, release, move, done and dep commands by 3
      agents keeps the invariants (one claimer at most, a claimed card is
      never in the done column, a command that puts a card in the done column
      leaves it with no open dependency, no dependency cycle). This is the one place where generated inputs pay off.

Done when: every feature passes, the race scenarios pass 20 runs in a row,
and `curl` with the key can run the whole loop by hand.

### Phase 2: the CLI

- [x] Features first: `cli_board.feature`, `cli_column.feature`,
      `cli_card.feature`, `cli_card_flow.feature`, `cli_events.feature`,
      `cli_errors.feature`. Each starts the server fixture, then runs
      `cli.agc` in a child process with `KANBAN_URL`, `KANBAN_API_KEY` and
      `KANBAN_AGENT`, and asserts stdout and the exit code.
- [x] Config order: flags, environment, `config.toml`.
- [x] Every command in section 5, with `--json` and text output. Labels and
      `--depends-on` take a comma-separated list, since a flag cannot repeat.
- [x] Exit codes 0 to 4 and the `BUSY` retry.
- [x] `--body-file` and `-` (stdin) for long text.
- [x] `make cli` (compile to `dist/kanban.agcb`), `bin/kanban`,
      `make install-cli` (a symlink, so the wrapper still finds the repo).
- [x] A scenario that runs two CLI processes claiming one card: one exits
      0, the other exits 4.
- [x] `.agents/skills/kanban-cli/SKILL.md`: how to install the CLI (wrapper,
      `make cli`, agentica version), the commands and flags with one example
      each, the config order, the exit codes and the `BUSY` retry. It is the
      usage skill for the tool, written last in this phase once the surface
      is stable; the operating rules for agents stay in phase 4.

Done when: every CLI feature passes, and a person can run the full loop
from a shell with only `bin/kanban`.

### Phase 3: the live web

Built small (the owner asked for a minimal, fast dashboard): the view is
read-only, the browser fetches the board again after each event, the list of
boards is not live, and the build uses pnpm (`corepack pnpm`).

- [x] Features first: `web.feature` (login sets the cookie, a wrong key
      does not, a page needs the session, the page names the fingerprinted
      assets) and `cable.feature`.
- [x] `specs/fixtures/ws_client/cable_client.agc`: the browser of
      `cable.feature`, a program of the package `websocket-client` (tag
      `websocket-client-0.2.0`, its own manifest as in bond-channels) that
      prints each frame as a line, which a step reads. It replaces the Python
      peer.
- [x] `cable.feature`: a client subscribes to `BoardChannel`; a CLI claim
      makes it receive `card.claimed`; a client with no session is refused.
- [x] `/login`, the session, the page shell (EAG), `Bond.static` for
      `/assets`.
- [x] `src/kanban_web/cable.agc`: hub, `BoardChannel`, and a publisher task
      that broadcasts the events after the commit, in journal order (a write
      nudges it, a five second tick catches the rest). `BoardsChannel` is left
      out: the list of boards is not live.
- [x] `package.json` (esbuild, sass), `pnpm-lock.yaml`, `tools/assets.mjs`,
      `make assets`; the built files are not in git. The Dockerfile builds them too.
- [x] `app/javascript`: `cable.js`, `board.js` (state, refetch after an event
      and after a reconnect), `render.js`. Plain JavaScript, no framework.
- [x] `app/stylesheets`: tokens, light and dark themes, board, column, card,
      feed. The side panel (body, dependencies, comments) is left out.
- [x] The activity feed pages with `before` (`kanban events --before N`), a
      "Ver mas" button, and `POST /logout`; `KANBAN_COOKIE_SECURE`.
- [x] A manual check with a browser (playwright-cli): open a board, run
      `kanban card move` in a shell, see the card move without a reload.

Done when: the features pass, and the owner watches a card move live while
an agent runs CLI commands.

### Phase 4: the skill and a real trial

- [x] `skill/agc-kanban/SKILL.md` as in section 7, short: the agent rules
      (claim before working, comment before a status change, never work a
      blocked card), separate from the CLI usage skill of phase 2
      (`.agents/skills/kanban-cli/`).
- [x] `kanban prime` prints the same rules; a CLI feature checks that it
      exits 0 and names `card next`.
- [x] Install the skill for Claude Code, OpenCode and Codex (each reads a
      `SKILL.md` folder or an `AGENTS.md` pointer; document the path for
      each in the README). Claude Code also has a plugin with the two
      session hooks (#46), and Codex takes the same hook script; OpenCode
      documents no such hook.
- [x] Trial: the board `agentica-lines` coordinated many agent lines on
      real work, far more than the 6 to 10 cards planned (see the trial
      note below).
- [x] Record what went wrong in a trial note, and fix the skill or the CLI
      (the required agent name, Markdown comments, the plugin hooks).

Done when: the trial ends with every card done, no two agents worked the
same card, and the owner watched it live. The board kept its backlog open,
so the first part is not literally met; no card was worked twice.

### Trial note from real use

The board `agentica-lines` (about 100 cards, 905 events from 2026-11-12 to
2026-11-13) coordinated many agent lines over two days: a coordinator and
one named agent per line, reviewers and design or release agents, each
working its own cards through the CLI.

What worked:

- Claims kept two agents off one card. The journal shows 63 cards claimed;
  two of them changed hands, each time after a release by the first holder,
  and none was held by two agents at once.
- The dependency chain ordered the work. A multi-PR feature was one chain of
  cards (each PR needs the one before it), and a blocked card stayed out of
  `card next` and `card list --ready` until its parent was done. 37
  dependencies were added, 6 removed.
- Comments as Markdown bullets, one per phase (claimed, reading, local
  commits, PR and head, CI), made `card show` a readable log of a card for
  the coordinator, and for the owner on the web.
- The coordinator closed each card after its PR was merged and checked. A
  line holds its card, so this is `done --force`: every one of the 66
  `card.done` events in the journal is forced, by the coordinator.
- Every write names an agent, so `kanban events` says who did what.

What was missing or went wrong:

- The agent name had a shared default in the config file. Two sessions on one
  machine could act as one agent, so the name became required (#51) and the
  hooks never invent one: the coordinator names itself, a subagent gets its
  name in the brief.
- Leases were never on: the board ran with `KANBAN_LEASE_MINUTES` at 0, and
  no card in the journal has a `lease_until`. The journal shows no stale
  claim, so the trial neither proves nor disproves leases. Four cards were
  released, one of them with `--force`.
- `done --force` on a merged card is the normal path of a coordinator, but
  the event records only `forced`, so a routine close looks the same as a
  rescue. A reason on the event, or a close for a card one does not hold
  that is not a force, would tell them apart. The same holds for the 14
  forced moves.
- A new agent started blind: before the plugin it learned the board from a
  brief only. The hook now lists the Doing cards of the other agents, so a
  line sees what is in progress and avoids the same files.
- A card had no field for its PR: the URL went in the body or a comment
  until card links (#30) came during the trial.

### Phase 5: polish

- [x] Card archive (`kanban card archive ID`), hidden from the board (#56).
- [x] A richer home page with a card per board (#52); Back and Forward step
      through the opened cards (#54); readable agent chips (#55).
- [x] Claim leases (see the open questions): `KANBAN_LEASE_MINUTES`, renew
      on any write by the claimer. The default is 0 (no expiry); the trial
      did not turn it on.
- [ ] A "stale" mark in the web for a claim whose lease has ended.
- [x] Filters in the web: label, claimer, ready only (`?label=`, `?claimer=`, `?ready=1`).
- [x] Markdown in card bodies and comments, escaped (`std/html`).
- [x] `kanban card list --format tsv` for agents that need a compact form: seven
      columns, no header, `--json` refused with `USAGE`; the hook keeps the text form.
- [ ] A README: run the server, install the CLI, install the skill (done:
      Claude Code, OpenCode and Codex), back up the database (not written).

Done when: the owner uses it for a week of real work without a manual fix
in the database.

## 9. Open questions for the owner

Storage is decided: agentica-db with SQLite.

1. **Deployment.**
   - a) Local only: `127.0.0.1`, agents on the same machine.
   - b) A small server on the LAN or a VPS, behind a reverse proxy with TLS.
   - Recommendation: a) first. The design does not change for b): set
     `KANBAN_HOST` and put Caddy or nginx with TLS in front. Over plain HTTP
     on a network the key travels in clear text, so b) needs TLS.
2. **Dependencies in v1.**
   - a) Yes, "blocks" only, checked at claim time.
   - b) No, later.
   - Recommendation: a). It is one table and one SQL condition, and the
     research names it a critical need. Leave out other kinds (parent,
     related, discovered-from) for now; a comment can say "found while
     working on #12".
3. **Can the web write, or only view?**
   - a) View-only.
   - b) The owner can move, comment and release from the web.
   - Decided (owner, 2026-11-12): a). There are no writes from the web, and
     the web stays view-only. Writes go through the CLI or the API; there is
     no drag-and-drop and no CSRF to protect.
4. **Claim expiry.** Decided: configurable, with b) implemented and a)
   as the default.
   - a) No expiry: a claim lasts until release or done; the owner or the
     orchestrator uses `release --force`. The web shows the claim's age.
   - b) A lease that any write by the claimer renews; an expired card is
     ready again.
   - `KANBAN_LEASE_MINUTES=0` (the default) keeps claims indefinite, so a)
     holds. A positive value sets `lease_until`; every write of the holder
     renews it, and a comment by another agent does not. An expired claim
     is treated as free. The schema had `lease_until` from the start, so
     this needed no migration.
5. **Card ids.**
   - a) One global number (`#12`), as now.
   - b) A per-board number (`auth-12`), as Beads' prefixed ids.
   - Recommendation: a). One number is the easiest thing for an agent to
     copy, and it stays unique when dependencies cross boards.
6. **How the CLI is installed.**
   - a) `bin/kanban` runs the compiled bytecode with the `agentica` on PATH.
   - b) A native binary.
   - Recommendation: a). Bytecode runs only on the same Agentica version,
     so `make cli` rebuilds it after an upgrade.
7. **The name of the API key header.**
   - a) `apikey`, as evolution-api.
   - b) `Authorization: Bearer KEY`.
   - Recommendation: a), as the owner asked. The server can accept b) too
     later, if a tool needs it.

## 10. References

Clones in `refs/` (ignored by git), read only. Nothing in them was run.

| Tool | What it is | What we take | What we leave out |
|---|---|---|---|
| Beads (`gastownhall/beads`) | Go issue tracker for agents, `bd` CLI, Dolt/SQL. | The claim as one compare-and-set `UPDATE ... WHERE` in a transaction, zero rows means lost, the answer names the holder (`internal/storage/issueops/claim.go`). `bd ready --claim` as our `card next`. Re-claiming your own card succeeds. "Ready" = open, free, every blocking dependency closed, sorted by priority. Priority 0 to 4. `comments` and `events` tables. `--json` on every verb, a typed error with a code. `bd prime`: the agent rules printed by the CLI. | Dolt, federation, about 20 dependency types (we keep "blocks"), pools, molecules, the 5-minute lease with heartbeat as a default (an open question here), hash ids. |
| beads-ui (`mantoni/beads-ui`) | Web UI over Beads. | Board lanes from data (Blocked is derived from dependencies, not set by hand). A snapshot, then per-item updates, and the client ignores what it already applied (our `event_id`). | Spawning the CLI and watching the database file: our server broadcasts after its own writes. Its custom WebSocket protocol: we use Action Cable through bond-channels. |
| Flux (`sirsjg/flux`) | Bun/TS board with CLI, MCP and a Preact web. | A tiny model: project, task with `depends_on` and comments. Ready as one filter. A short `prime` text with 4 rules. A key stored and compared in constant time. | Its `task start`, which is not atomic (two agents can start one task): the gap we must close. The JSON-file store, file polling for changes, webhooks, per-project key scopes. |
| Multica (`multica-ai/multica`) | Go + Postgres agent platform with a daemon. | Distinct exit codes per failure kind (network, auth, not found, validation) and a code for a lost claim. Long text through a file or stdin, never inline. The agent rule "read the card and its comments before acting, post the result as a comment". | Workspaces, the daemon that dispatches work, inbox, JWT, Postgres-only `SKIP LOCKED`. |
| Kandev (`kdlbs/kandev`) | Go orchestrator with workflow steps, MCP and a web. | Rules from its agent skill: never work on a blocked task (comment and stop), comment before changing status, split work into new tasks that block the current one. The agent id in an environment variable, sent as the actor. Columns with a position and a WIP limit (shown only). | Workflow steps with prompts and auto-advance, the run queue, about 60 MCP tools, user accounts. |
| KanBots (`leodavinci1/kanbots`, found from kanbots.dev) | Electron board where each card runs an agent in its own worktree. | Recording the worktree and branch on the card. SQLite with numbered migrations recorded in `schema_migrations`. Events stored in a table so the UI can replay them after a reconnect. | The agent runner, Electron, GitHub issue sync, autopilot. |

Our stack, read for this plan:

- Agentica (`/home/sonic182/apps/agentica`): `std/http` (client and
  server), `std/option_parser`, `std/toml`, `agentica compile` and
  `agentica run`, `agentica.toml` packages, `agentica test` with BDD
  features and `*_test.agc` unit tests.
- Bond: routes, `before` filters (the key check), `Bond.json_body` with a
  codec, `Bond.sessions`, `Bond.static` with fingerprints, `Bond.start` on
  port 0 for tests, `Testing.request` for in-process tests.
- bond-channels: `start_hub`, `mount(app, "/cable", hub, options)`, a
  `connect` that returns an `Identity` (it runs after the upgrade, never in
  a `before` filter), channel handlers whose `subscribed` returns the
  streams, and `broadcast_json(hub, topic, value)`.
- agentica-campfire: the layout (`src/<domain>/repo/` with migrations, one
  file each), `Database.with_connection` over `DbPool`, `tools/assets.mjs`
  (Dart Sass, esbuild, fingerprinted names, the `asset_names.agc` file,
  an `assets-check` of the committed output), a hand-written Action Cable client
  in `live.js`, and BDD specs that start the server as a fixture program.
  Campfire uses npm; we use pnpm as the owner asked. Campfire's cable tests
  use a Python peer; we write that peer in Agentica.
- agentica-db: `Db.transaction` starts with `BEGIN IMMEDIATE` on SQLite,
  `Db.execute` returns the rows changed, `Migrate.up` with a history table,
  WAL and `busy_timeout` 5000 ms by default.
- prop (`agentica-lang/packages`): property tests inside `agentica test`.

## Phase 0 decisions

The recommendations in section 9 are accepted: start locally, keep blocking
dependencies, make the web view-only, use claims without expiry by default,
use global card ids, run the bytecode CLI with Agentica on PATH, and use the
`apikey` header. Leases are configurable: zero disables expiry, and a positive
value renews a live claim on writes by its holder. When WebSocket tests are
needed, use `websocket-client-0.2.0` from agentica packages.
