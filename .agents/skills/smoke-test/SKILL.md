---
name: smoke-test
description: Write and run a black-box smoke test that proves a running service still does the minimum a client depends on after a change, a restart or a handoff. Use when asked for a smoke test, a quick end-to-end check, or "does it still work" against a real server or CLI. Covers one happy-path flow plus the few negative cases clients branch on; does not cover load or performance testing, full regression suites, unit tests, security audits, or CI wiring.
---

# Black-box smoke test

A smoke test is a short script that talks to the real service only through its
public interface and fails loudly. It answers "the thing starts and the flow
still works", not "every branch is correct". One run should take seconds.

## Scope it

Before writing anything, list the flow a client would actually perform, in
order, and the negative answers it branches on. For a task board that is:
create a board, add a card, claim it, lose a second claim, comment, block a
card with a dependency, claim the next free card, finish one, read the event
stream. The negatives are the codes the client handles: unauthenticated,
malformed body, already claimed, blocked, conflict, done.

Cover 10 to 20 checks. If a check needs a query the public interface does not
offer, the check is wrong, not the service.

## Isolate the run

- Start the service yourself on an ephemeral port (`smoke_free_port`) and a
  temporary data directory, with a throwaway key. Never point a smoke test at
  the user's database or a shared instance.
- Clean up with an `EXIT` trap that kills the process, removes the temporary
  directory and calls `smoke_cleanup` (the wrapper's body file), including on
  failure. Install the trap **after** sourcing the wrapper, or it replaces the
  wrapper's own.
- Restart the service once at the end with the same directory and re-read a
  resource: that is the only check that proves persistence.

## Write it

Copy `scripts/smoke.sh` from this skill next to the test (for example
`tools/smoke.sh` keeps it at hand) and source it. It is the curl wrapper: one
request helper that keeps the body, assertions for status, body fragments and
`jq` fields, a readiness poll, and a summary whose exit code is the test's. Read
it before extending it; it is about 40 lines and the only bundled file.

Keep the flow in a separate script so it survives a service change. Adapt the
comments and the path of `smoke_request` to your API; the shape stays:

```bash
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/smoke.sh"          # the copied wrapper
smoke_init "http://127.0.0.1:$PORT" "$KEY"

status() { smoke_status "$1" "$2" "$3"; }   # optional, short local alias

status "health is public" 200 "$(smoke_request GET /api/health)"
status "data needs the key" 401 "$(smoke_request GET /api/boards '' '' wrong)"
status "writes need an agent" 400 "$(smoke_request POST /api/boards '{"name":"P"}' '')"
status "create a board" 201 "$(smoke_request POST /api/boards '{"name":"P"}' agent-1)"
smoke_contains "the board is answered" '"slug":"p"'
status "claim the card" 200 "$(smoke_request POST /api/cards/1/claim '{}' agent-1)"
smoke_json "the claim moves the card" '.card.column' "Doing"
status "a second agent loses" 409 "$(smoke_request POST /api/cards/1/claim '{}' agent-2)"
smoke_contains "the loss names the holder" '"claimed_by":"agent-1"'

smoke_summary
```

Rules that keep the run honest:

- Assert the status **and** one body fragment per step. A status alone passes
  when the service answers the right code with the wrong resource.
- Assert the negative cases by code, not by message.
- Do not read the database, import the app, or call internal helpers. If a
  check needs that, it belongs in a unit test.
- Keep `set -uo pipefail` (not `-e`): every check runs, then `smoke_summary`
  fails the run with the count.

For a CLI instead of HTTP, keep the same shape: one helper spawns the binary
with a temporary `HOME` and config, one asserts the exit code, one asserts a
stdout fragment.

## Read failures before fixing

A red check is a claim about the world, not proof of a bug. Decide which of
the three it is and say so:

1. **The service is wrong.** The status or the body contradicts its own
   contract; report it with the request that reproduces it.
2. **The script assumed something untrue.** Seen in practice: `claim-next`
   answers "nothing ready" when the only free card is blocked (add a third free
   card to test the skip), a new column collides with a default column name,
   and a claim moves the card to the second column before the assertion reads
   it.
3. **The environment.** The port was taken, the service was already running, or
   it died at startup; print its log in the failure path.

Never delete or weaken a red check to make the run green. If a check is
genuinely out of scope, remove it and say why.

## Report

Give the command to reproduce, the pass/fail count, and one line per failure
with the request, the expected and the actual. Keep the test in the repo (for
example `tools/smoke.sh` plus a `make smoke` target) so the next person runs it
instead of rewriting it.
