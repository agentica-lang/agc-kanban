#!/usr/bin/env bash
# Black-box smoke test of the board API. Without SMOKE_URL it starts the real
# server on a temporary data directory and an ephemeral port; with SMOKE_URL
# (and SMOKE_KEY) it runs against a target that is already up, such as the
# compose network at http://172.28.0.10:4580. Run with `make smoke` or
# `make smoke-docker`.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
. "$ROOT/.agents/skills/smoke-test/scripts/smoke.sh"

FROM_ENV="$(sed -n 's/^KANBAN_API_KEY=//p' "$ROOT/.env" 2>/dev/null || true)"
KEY="${SMOKE_KEY:-${FROM_ENV:-01234567890123456789012345678901}}"
DIR=""
PORT=""
SERVER=""

cleanup() {
  if [ -n "$SERVER" ]; then
    kill "$SERVER" 2>/dev/null || true
    wait "$SERVER" 2>/dev/null || true
  fi
  [ -n "$DIR" ] && rm -rf "$DIR"
  smoke_cleanup
}
trap cleanup EXIT

start_local() {
  DIR="$(mktemp -d)"
  PORT="$(smoke_free_port)"
  KANBAN_API_KEY="$KEY" KANBAN_DATA_DIR="$DIR" KANBAN_PORT="$PORT" \
    agentica server.agc >"$DIR/server.log" 2>&1 &
  SERVER=$!
  smoke_init "http://127.0.0.1:$PORT" "$KEY"
  if ! smoke_wait /api/health 60; then
    echo "FAIL the server did not start"
    cat "$DIR/server.log"
    exit 1
  fi
}

if [ -n "${SMOKE_URL:-}" ]; then
  smoke_init "$SMOKE_URL" "$KEY"
  if ! smoke_wait /api/health 30; then
    echo "FAIL $SMOKE_URL/api/health is not ready"
    exit 1
  fi
else
  start_local
fi

smoke_status "health is public" 200 "$(smoke_request GET /api/health)"
smoke_status "protected data needs a key" 401 "$(smoke_request GET /api/boards '' '' wrong)"
smoke_status "auth-check accepts the key" 200 "$(smoke_request GET /api/auth-check)"
smoke_status "writes need an agent" 400 "$(smoke_request POST /api/boards '{"name":"Project"}' '')"
smoke_status "create a board" 201 "$(smoke_request POST /api/boards '{"name":"Project","slug":"project"}' agent-1)"
smoke_contains "the board has the default columns" '"name":"Done"'
smoke_status "list boards" 200 "$(smoke_request GET /api/boards)"
smoke_contains "the board is listed" '"slug":"project"'
smoke_status "create a card" 201 "$(smoke_request POST /api/boards/project/cards '{"title":"First","labels":["api"]}' agent-1)"
smoke_contains "the card is ready" '"ready":true'
smoke_status "snapshot" 200 "$(smoke_request GET /api/boards/project)"
smoke_contains "the snapshot carries the cursor" '"last_event_id"'
smoke_status "list ready cards" 200 "$(smoke_request GET '/api/boards/project/cards?ready=1')"
smoke_contains "the ready card is listed" 'First'
smoke_status "claim the card" 200 "$(smoke_request POST /api/cards/1/claim '{}' agent-1)"
smoke_contains "the claim moves it to Doing" '"column":"Doing"'
smoke_contains "the claim names the holder" '"claimed_by":"agent-1"'
smoke_status "a second agent loses the claim" 409 "$(smoke_request POST /api/cards/1/claim '{}' agent-2)"
smoke_contains "the loss carries the card id" '"card_id":1'
smoke_contains "the loss names the holder" '"claimed_by":"agent-1"'
smoke_status "another agent cannot edit" 409 "$(smoke_request PATCH /api/cards/1 '{"title":"Hijacked"}' agent-2)"
smoke_status "the holder can edit" 200 "$(smoke_request PATCH /api/cards/1 '{"title":"Renamed"}' agent-1)"
smoke_contains "the edit is stored" '"title":"Renamed"'
smoke_status "another agent may comment" 201 "$(smoke_request POST /api/cards/1/comments '{"body":"note"}' agent-2)"
smoke_status "create a dependent card" 201 "$(smoke_request POST /api/boards/project/cards '{"title":"Second","depends_on":[1]}' agent-1)"
smoke_contains "the dependent card is not ready" '"ready":false'
smoke_status "create a free card" 201 "$(smoke_request POST /api/boards/project/cards '{"title":"Third"}' agent-1)"
smoke_status "a blocked card cannot be claimed" 409 "$(smoke_request POST /api/cards/2/claim '{}' agent-2)"
smoke_contains "the block names the blocker" 'BLOCKED'
smoke_status "claim next skips the blocked card" 200 "$(smoke_request POST /api/boards/project/claim-next '{}' agent-2)"
smoke_contains "claim next takes the free card" '"title":"Third"'
smoke_status "release clears the claim" 200 "$(smoke_request POST /api/cards/3/release '{}' agent-2)"
smoke_contains "the released card is free" '"claimed_by":null'
smoke_status "finish the first card" 200 "$(smoke_request POST /api/cards/1/done '{}' agent-1)"
smoke_contains "the finish lands in Done" '"column":"Done"'
smoke_status "an already done card is refused" 409 "$(smoke_request POST /api/cards/1/done '{}' agent-1)"
smoke_status "add a column" 201 "$(smoke_request POST /api/boards/project/columns '{"name":"QA"}' agent-1)"
smoke_status "rename a column" 200 "$(smoke_request PATCH /api/columns/5 '{"name":"Verified"}' agent-1)"
smoke_contains "the rename is stored" '"name":"Verified"'
smoke_status "a column with cards cannot be deleted" 409 "$(smoke_request DELETE /api/columns/1 '' agent-1)"
smoke_status "the event stream is ordered" 200 "$(smoke_request GET '/api/boards/project/events?limit=1000')"
smoke_contains "the stream records the claim" '"kind":"card.claimed"'
smoke_contains "the stream records the comment" '"kind":"comment.added"'
smoke_contains "the stream records the done" '"kind":"card.done"'
smoke_status "bad JSON is invalid" 400 "$(smoke_request POST /api/boards '{oops' agent-1)"
smoke_contains "the invalid body names the field" '"field":"body"'

# Persistence across a restart is only meaningful when this script owns the server.
if [ -n "$SERVER" ]; then
  kill "$SERVER"
  wait "$SERVER" 2>/dev/null || true
  SERVER=""
  KANBAN_API_KEY="$KEY" KANBAN_DATA_DIR="$DIR" KANBAN_PORT="$PORT" \
    agentica server.agc >>"$DIR/server.log" 2>&1 &
  SERVER=$!
  if ! smoke_wait /api/health 60; then
    echo "FAIL the server did not restart"
    cat "$DIR/server.log"
    exit 1
  fi
  smoke_status "the board survives a restart" 200 "$(smoke_request GET /api/boards/project)"
  smoke_contains "the finished card survives" '"title":"Renamed"'
fi

smoke_summary
