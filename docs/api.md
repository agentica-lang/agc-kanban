# API

All paths are under `/api/`. Every request needs the `apikey` header (the
CLI) or the session cookie (the web: reads, the `color` of `PATCH /api/labels/:id`, and the archive paths
below). Writes need the
`X-Kanban-Agent` header: the agent name, 1 to 64 characters of
`[A-Za-z0-9._@/-]`. The name is not a proof of identity: anyone with the key
can use any name. It keeps honest agents apart, which is the goal.

Bodies are JSON. A `:board` in a path is the slug or the id. Answers are JSON
objects. The server does not check `Content-Type`, and a body that does not
decode reports `field: "body"`; field-level messages come from the domain once
the body decodes.

## Shapes

```json
{"board": {"id": 1, "slug": "auth", "name": "Auth rewrite",
           "columns": [{"id": 1, "name": "Todo", "position": 0, "done": false, "wip_limit": null}],
           "auto_archive_days": null, "created_at": 1762950000000, "updated_at": 1762950000000}}

{"card": {"id": 12, "board": "auth", "column": "Doing", "column_id": 2, "position": 0,
          "title": "Add login route", "body": "...", "labels": ["api"],
          "links": ["https://github.com/org/repo/pull/7"], "priority": 2,
          "claimed_by": "claude-2", "claimed_at": 1762950000000, "lease_until": null,
          "branch": "feat/login", "worktree": "/work/wt-login",
          "depends_on": [10, 11], "blocks": [14], "ready": false, "done": false,
          "created_by": "orchestrator", "created_at": 1762950000000,
          "updated_at": 1762950000000, "done_at": null, "archived_at": null, "version": 4}}

{"milestone": {"id": 3, "name": "0.37.0", "color": "#0075ca", "description": "The big one",
               "due_on": "2026-12-01", "state": "open", "closed_at": null,
               "open": 3, "closed": 2, "percent": 40, "overdue": false}}

{"error": {"code": "CLAIMED", "message": "card is claimed",
           "card_id": 12, "claimed_by": "claude-1"}}
```

A milestone is a label that the board flagged; its `id` is the label's. A card is in it by carrying the label, so the
cards of a milestone are the cards of `?label=NAME`. `closed` counts the cards in a done column, archived or not (the
auto archive does not lower the percent). `open` counts the cards that are neither archived nor done. An archived card
that was not done counts in neither. `percent` is `closed` over `open + closed`, rounded down (0 without cards).
Making a column done (or not) changes what its archived cards count as, so the numbers follow the flag. `overdue` is an open milestone with a due date before today (UTC) and open cards left. Milestones are per board. The
events are `milestone.updated` (data: the milestone) and `milestone.removed` (data: `id`, `name`). The web session
reads them and cannot write them: a write needs the key.

## Errors

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
| 500 | `INTERNAL` | An unexpected server error. |
| 503 | `BUSY` | The database is busy (pool or lock timeout). Safe to retry. |

Tests assert the `code` and the status, never the message.

## Endpoints

| Method and path | Request | Answer |
|---|---|---|
| `GET /api/health` (no auth) | | `{"ok": true, "version": "0.1.0"}` |
| `GET /api/auth-check` | | `{"ok": true}`; 401 without a good key, the CLI's probe |
| `GET /api/boards` | | `{"boards": [board]}` (without columns) |
| `POST /api/boards` | `{"name", "slug"?, "columns"?: ["Todo", ...]}` | 201 `{"board"}` |
| `GET /api/boards/:board` | | `{"board", "cards": [card], "last_event_id"}`: the snapshot the web draws; it also has `column_since` (since when each card is in its column) |
| `GET /api/boards/:board/search` | query: `q`, `all=1` (include done cards), `limit` (20, at most 100) | `{"results": [{"card", "snippet"}]}`, best match first (SQLite FTS5 `bm25` over title, body, labels and comments) |
| `GET /api/boards/:board/labels` | | `{"labels": [{"id", "name", "color"}]}`, by name; the snapshot has the same `labels` |
| `PATCH /api/labels/:id` | `{"name"?, "color"?: "#rrggbb"}` (one of them) | `{"label"}`; `label.updated` event; `INVALID`, `NOT_FOUND`, `CONFLICT` (name taken). The web session may send this one write for the `color` only (with `X-Kanban-Agent`; a `name` from the session is 401, a rename needs the key). A rename also writes a `card.updated` event per changed card |
| `GET /api/boards/:board/milestones` | query: `state` = `open` (default), `closed` or `all` (any other value is 400 `INVALID`) | `{"milestones": [milestone]}`; open ones first, the soonest due date first and the undated last, then closed ones, the newest closed first |
| `POST /api/boards/:board/milestones` | `{"name", "description"?, "due_on"?: "YYYY-MM-DD"}` (`description` at most 2000 characters) | 201 `{"milestone"}`; `INVALID` (blank name, a due date that is not a real date), `CONFLICT` (already a milestone). It flags the label of that name, and makes the label if no card has it yet |
| `PATCH /api/milestones/:id` | `{"description"?, "due_on"?, "state"?: "open" or "closed"}` (one of them; `"due_on": ""` clears the date, and `{"due_on": null}` alone is `INVALID:milestone`) | `{"milestone"}`; `INVALID`, `NOT_FOUND` |
| `DELETE /api/milestones/:id` | | 204; the label and the cards keep it |
| `POST /api/boards/:board/columns` | `{"name", "position"?, "done"?, "wip_limit"?}` | 201 `{"column"}` |
| `PATCH /api/columns/:id` | `{"name"?, "position"?, "done"?, "wip_limit"?, "force"?: false}` | `{"column"}`; making a column done is `BLOCKED` (`blocked_by` lists the cards of the column that wait for a card outside it) unless `force`, which the `column.updated` event records |
| `DELETE /api/columns/:id` | | 204, or `CONFLICT` if it has cards |
| `GET /api/boards/:board/cards` | query: `column`, `ready=1`, `claimed_by`, `label`, `done=0/1`, `archived=1`, `limit` | `{"cards": [card]}`, ordered by column, then position. With `archived=1` it lists the archived cards instead, the newest archive first (`ready` with it is `INVALID`); `limit` (1 to 1000) caps any list |
| `POST /api/boards/:board/cards` | `{"title", "body"?, "column"?, "labels"?, "priority"?, "depends_on"?: [id], "links"?: [url]}` (at most 50 links, repeats included) | 201 `{"card"}`; the first column by default |
| `GET /api/cards/:id` | | `{"card", "comments": [comment], "times"}`: `times` is the time the card spent in each column |
| `PATCH /api/cards/:id` | `{"title"?, "body"?, "labels"?, "priority"?, "branch"?, "worktree"?, "link"?: [url], "unlink"?: [url]}` | `{"card"}`; `CLAIMED` if another agent holds it. `unlink` removes, then `link` adds (each list at most 50, repeats included) the URLs the card lacks; when only links were asked and none changed, nothing is written (no version, no event), unless the actor holds a running lease and leases are on; then it renews the lease. |
| `POST /api/cards/:id/claim` | `{}` | `{"card"}`; `CLAIMED`, `BLOCKED`, `DONE`. Claiming a card you hold renews the lease. |
| `POST /api/boards/:board/claim-next` | `{"column"?, "label"?}` | `{"card"}` or `NO_READY_CARD` |
| `POST /api/cards/:id/release` | `{"force"?: false, "column"?}` | `{"card"}`; `NOT_CLAIMER` unless `force` |
| `POST /api/cards/:id/move` | `{"column", "position"?, "force"?: false}` | `{"card"}`; `CLAIMED` if another agent holds it, `BLOCKED` into the done column with an open dependency; `force` skips both |
| `POST /api/cards/:id/done` | `{"force"?: false}` | `{"card"}`: moved to the done column, claim cleared; `NOT_CLAIMER` or `BLOCKED` (an open dependency) unless `force` |
| `POST /api/cards/:id/archive` | `{"force"?: false}` (the web session may send it, with `X-Kanban-Agent`, but never `force`: 401) | `{"card"}` with `archived_at`: hidden from the board, the lists, `next`, claims and readiness; kept in the database, the journal (`card.archived`) and `GET /api/cards/:id`. No role is checked (the coordinator's by agreement); `CLAIMED` unless `force`, which drops the claim. An archived card is archived again with no new event. Every other write on it is `NOT_FOUND`. A dependency on it no longer blocks, so the web asks for a confirmation before it archives a card that is not done |
| `POST /api/cards/:id/unarchive` | `{}` | `{"card"}`: back on top of a done column (it keeps its `done_at`) or at the end of any other; a `card.unarchived` event. Unarchiving a card that is not archived writes nothing |
| `POST /api/boards/:board/archive-done` | `{"days": N}` (0 to 36500) | `{"archived": n, "days": N, "cards": [ids]}`: in one transaction, archives the cards of a done column whose `done_at` is at least N days old (0: every done card) and that nobody holds; a `card.archived` event per card and, when n is above 0, one `board.done_archived` event (`data`: `count`, `days`, `cards`) for the board. Cards of other columns are never touched |
| `POST /api/boards/:board/auto-archive` | `{"days": N}` (1 to 36500) or `{"days": null}` | `{"board"}` with `auto_archive_days`: turns on (or off, with null) the automatic archive of the board, off by default; a `board.updated` event (`data.auto_archive_days`). The key is needed (the web session cannot). Every ten minutes the server runs the `archive-done` rule for each board that has it on, as the actor `auto-archive`: the same `card.archived` and `board.done_archived` events |
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
