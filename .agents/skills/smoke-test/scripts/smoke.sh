#!/usr/bin/env bash
# curl wrappers and assertions for a black-box smoke test. Source this file,
# call smoke_init once, then smoke_request plus the assertions, and finish with
# smoke_summary (its exit code is the test's).
#
# Requires curl. smoke_json needs jq; smoke_free_port needs python3.
# The EXIT trap below replaces any trap the caller installed.

SMOKE_PASS=0
SMOKE_FAIL=0
SMOKE_BODY="$(mktemp)"
# Call smoke_cleanup from your own EXIT trap if you install one after sourcing.
smoke_cleanup() { rm -f "$SMOKE_BODY"; }
trap 'smoke_cleanup' EXIT

smoke_init() { # base_url [key] [auth_header] [agent_header]
  SMOKE_URL="${1:?usage: smoke_init BASE_URL [API_KEY] [AUTH_HEADER] [AGENT_HEADER]}"
  SMOKE_KEY="${2-}"
  SMOKE_AUTH_HEADER="${3-apikey}"
  SMOKE_AGENT_HEADER="${4-X-Kanban-Agent}"
}

# Sends one request and prints its status code. The body is kept in
# $SMOKE_BODY for the assertions. An empty key or agent sends no header.
smoke_request() { # method path [body] [agent] [key] -> status
  local method="$1" path="$2" body="${3-}" agent="${4-}" key="${5-$SMOKE_KEY}"
  local args=(-s -o "$SMOKE_BODY" -w '%{http_code}' -X "$method" "$SMOKE_URL$path")
  [ -n "$key" ] && args+=(-H "$SMOKE_AUTH_HEADER: $key")
  [ -n "$agent" ] && args+=(-H "$SMOKE_AGENT_HEADER: $agent")
  [ -n "$body" ] && args+=(-H "Content-Type: application/json" -d "$body")
  curl "${args[@]}"
}

# Polls a path until it answers 2xx. Returns 1 after [seconds] (default 30).
smoke_wait() { # path [seconds]
  local path="$1" limit="${2-30}"
  for _ in $(seq 1 $((limit * 4))); do
    if curl -sf "$SMOKE_URL$path" >/dev/null 2>&1; then return 0; fi
    sleep 0.25
  done

  return 1
}

smoke_free_port() { # -> a port that was free a moment ago
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

smoke_status() { # name expected actual
  if [ "$2" = "$3" ]; then smoke_pass "$1"; else smoke_fail "$1" "expected $2 got $3"; fi
}

smoke_contains() { # name fragment
  if grep -qF -- "$2" "$SMOKE_BODY"; then
    smoke_pass "$1"
  else
    smoke_fail "$1" "'$2' missing in $(head -c 400 "$SMOKE_BODY")"
  fi
}

smoke_lacks() { # name fragment
  if grep -qF -- "$2" "$SMOKE_BODY"; then
    smoke_fail "$1" "'$2' present in $(head -c 400 "$SMOKE_BODY")"
  else
    smoke_pass "$1"
  fi
}

smoke_json() { # name jq_filter expected
  local found
  found="$(jq -r "$2" "$SMOKE_BODY" 2>/dev/null)"
  smoke_status "$1" "$3" "$found"
}

smoke_pass() { SMOKE_PASS=$((SMOKE_PASS + 1)); echo "PASS $1"; }

smoke_fail() { SMOKE_FAIL=$((SMOKE_FAIL + 1)); echo "FAIL $1: $2"; }

# Prints the counts and fails the shell when anything failed.
smoke_summary() {
  echo
  echo "$SMOKE_PASS passed, $SMOKE_FAIL failed"
  [ "$SMOKE_FAIL" -eq 0 ]
}
