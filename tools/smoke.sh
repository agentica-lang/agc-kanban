#!/usr/bin/env bash
# Black-box smoke test: starts the real server on a temporary data directory and
# checks the minimum a client depends on. Run with `make smoke`.
set -uo pipefail

KEY="01234567890123456789012345678901"
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
DIR="$(mktemp -d)"
BODY="$DIR/body"
URL="http://127.0.0.1:$PORT"
PASS=0
FAIL=0
SERVER=""

cleanup() {
  if [ -n "$SERVER" ]; then
    kill "$SERVER" 2>/dev/null || true
    wait "$SERVER" 2>/dev/null || true
  fi
  rm -rf "$DIR"
}
trap cleanup EXIT

start_server() {
  KANBAN_API_KEY="$KEY" KANBAN_DATA_DIR="$DIR" KANBAN_PORT="$PORT" agentica server.agc >"$DIR/server.log" 2>&1 &
  SERVER=$!
  for _ in $(seq 1 120); do
    if curl -sf "$URL/api/health" >/dev/null 2>&1; then return 0; fi
    sleep 0.25
  done
  echo "FAIL server did not start"
  cat "$DIR/server.log"
  exit 1
}

request() { # method path [body] [agent] [key]
  local method="$1" path="$2" body="${3-}" agent="${4-agent-1}" key="${5-$KEY}"
  local args=(-s -o "$BODY" -w '%{http_code}' -X "$method" "$URL$path")
  [ -n "$key" ] && args+=(-H "apikey: $key")
  [ -n "$agent" ] && args+=(-H "X-Kanban-Agent: $agent")
  [ -n "$body" ] && args+=(-H "Content-Type: application/json" -d "$body")
  curl "${args[@]}"
}

status() { # name expected actual
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 expected $2 got $3"; fi
}

contains() { # name text
  if grep -qF -- "$2" "$BODY"; then PASS=$((PASS+1)); echo "PASS $1"; else FAIL=$((FAIL+1)); echo "FAIL $1: $2 missing in $(cat "$BODY")"; fi
}

start_server

status "health is public" 200 "$(curl -s -o "$BODY" -w '%{http_code}' "$URL/api/health")"
status "protected data needs a key" 401 "$(request GET /api/boards "" "agent-1" "")"
status "auth-check accepts the key" 200 "$(request GET /api/auth-check)"
status "writes need an agent" 400 "$(request POST /api/boards '{"name":"Project"}' "")"
status "create a board" 201 "$(request POST /api/boards '{"name":"Project","slug":"project"}')"
contains "board has the default columns" '"name":"Done"'
status "list boards" 200 "$(request GET /api/boards)"
contains "the board is listed" '"slug":"project"'
status "create a card" 201 "$(request POST /api/boards/project/cards '{"title":"First","labels":["api"]}')"
contains "the card is ready" '"ready":true'
status "snapshot" 200 "$(request GET /api/boards/project)"
contains "the snapshot carries the cursor" '"last_event_id"'
status "list ready cards" 200 "$(request GET '/api/boards/project/cards?ready=1')"
contains "the ready card is listed" 'First'
status "claim the card" 200 "$(request POST /api/cards/1/claim '{}' agent-1)"
contains "the claim moves it to Doing" '"column":"Doing"'
contains "the claim names the holder" '"claimed_by":"agent-1"'
status "a second agent loses the claim" 409 "$(request POST /api/cards/1/claim '{}' agent-2)"
contains "the loss carries the card id" '"card_id":1'
contains "the loss names the holder" '"claimed_by":"agent-1"'
status "another agent cannot edit" 409 "$(request PATCH /api/cards/1 '{"title":"Hijacked"}' agent-2)"
status "the holder can edit" 200 "$(request PATCH /api/cards/1 '{"title":"Renamed"}' agent-1)"
contains "the edit is stored" '"title":"Renamed"'
status "another agent may comment" 201 "$(request POST /api/cards/1/comments '{"body":"note"}' agent-2)"
status "create a dependent card" 201 "$(request POST /api/boards/project/cards '{"title":"Second","depends_on":[1]}')"
contains "the dependent card is not ready" '"ready":false'
status "create a free card" 201 "$(request POST /api/boards/project/cards '{"title":"Third"}')"
status "a blocked card cannot be claimed" 409 "$(request POST /api/cards/2/claim '{}' agent-2)"
contains "the block names the blocker" 'BLOCKED'
status "claim next skips the blocked card" 200 "$(request POST /api/boards/project/claim-next '{}' agent-2)"
contains "claim next takes the free card" '"title":"Third"'
status "release clears the claim" 200 "$(request POST /api/cards/3/release '{}' agent-2)"
contains "the released card is free" '"claimed_by":null'
status "finish the first card" 200 "$(request POST /api/cards/1/done '{}' agent-1)"
contains "the finish lands in Done" '"column":"Done"'
status "an already done card is refused" 409 "$(request POST /api/cards/1/done '{}' agent-1)"
status "add a column" 201 "$(request POST /api/boards/project/columns '{"name":"QA"}')"
status "rename a column" 200 "$(request PATCH /api/columns/5 '{"name":"Verified"}')"
contains "the rename is stored" '"name":"Verified"'
status "a column with cards cannot be deleted" 409 "$(request DELETE /api/columns/1)"
status "the event stream is ordered" 200 "$(request GET '/api/boards/project/events?limit=1000')"
contains "the stream records the claim" '"kind":"card.claimed"'
contains "the stream records the comment" '"kind":"comment.added"'
contains "the stream records the done" '"kind":"card.done"'
status "bad JSON is invalid" 400 "$(request POST /api/boards '{oops')"
contains "the invalid body names the field" '"field":"body"'

# Persistence across a restart.
kill "$SERVER"; wait "$SERVER" 2>/dev/null; SERVER=""
start_server
status "the board survives a restart" 200 "$(request GET /api/boards/project)"
contains "the finished card survives" '"title":"Renamed"'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
