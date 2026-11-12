#!/bin/sh
# Hook of the agc-kanban plugin: `board-context.sh session` runs at SessionStart and
# `board-context.sh subagent` at SubagentStart. It prints the JSON a hook answers with, whose
# additionalContext becomes part of the model's context: the rules about the agent name and the cards
# in progress on the board. Reads only; it never writes to the board and never invents an agent name.
#
# Silent (no output, exit 0) when `kanban` is not installed or no board is configured, so a session
# that does not use the board pays nothing. A configured board that cannot be read prints one notice.
# The exit code is always 0: a hook must not block a session start.
set -u

MODE=${1:-session}
MAX_LINES=15
# The longest title kept in a card line, in characters; a title has no limit on the server.
MAX_TITLE=120

# The hook input (session_id, cwd, agent_type, ...) is not needed; drain it so the writer never blocks.
cat >/dev/null 2>&1 || :

command -v kanban >/dev/null 2>&1 || exit 0

# A dead server must not hold a session start: `timeout` (GNU coreutils) is used when present.
if command -v timeout >/dev/null 2>&1; then
  run_kanban() { timeout 10 kanban "$@"; }
else
  run_kanban() { kanban "$@"; }
fi

errors=$(mktemp 2>/dev/null) || exit 0
trap 'rm -f "$errors"' EXIT

# Control characters would break the JSON string and could hide text; a card title comes from another agent,
# so it is data. iconv drops a multibyte character that the cut may have split.
clean() {
  tr -d '\000-\010\013\014\016-\037\177' | cut -c1-"$1" | { iconv -c -f UTF-8 -t UTF-8 2>/dev/null || cat; }
}

cards=$(run_kanban card list 2>"$errors")
status=$?
if [ "$status" -eq 2 ]; then
  # USAGE: no board is configured (KANBAN_BOARD, --board or the config file), so this project does not use one.
  exit 0
fi

me=${KANBAN_AGENT:-}
text=""
add() { text="$text$1
"; }

if [ "$status" -ne 0 ]; then
  reason=$(head -n 1 "$errors" | clean 200)
  add "agc-kanban: the board could not be read (${reason:-kanban exited with $status}). Do not guess the URL or the key: tell the user, and do not claim or write cards until \`kanban whoami\` works."
else
  case $MODE in
    subagent)
      add "agc-kanban: this project's work queue is a kanban board (the agc-kanban and kanban-cli skills have the rules and the commands)."
      add "You are a subagent. Ask your coordinator for your agent name; it gives it in your brief. Without a name, stop before any write (claim, move, update, comment, release, done) and ask for it. Reads are fine. Set the name as KANBAN_AGENT or --agent; never invent one and never use another agent's."
      ;;
    *)
      add "agc-kanban: this project's work queue is a kanban board (the agc-kanban and kanban-cli skills have the rules and the commands)."
      add "You are the coordinator of this session. Name yourself from your conversation with the user (a short name for your role), and set it as KANBAN_AGENT or --agent on every write. Never invent a name unrelated to the conversation and never use another agent's. Give each subagent its own name in its brief."
      ;;
  esac

  if [ -n "$me" ]; then
    add "KANBAN_AGENT is set to $me."
    mine=$(printf '%s\n' "$cards" | awk -F'  ' -v me="$me" '$3 == me' | clean 200)
    if [ -n "$mine" ]; then
      add "Your cards:"
      add "$mine"
    fi
  fi

  # Others' cards in Doing: what is in progress now, so you avoid the same files.
  doing=$(printf '%s\n' "$cards" | awk -F'  ' -v me="$me" '$2 == "Doing" && $3 != me' | clean 200)
  if [ -n "$doing" ]; then
    total=$(printf '%s\n' "$doing" | wc -l | tr -d ' ')
    add "In progress by other agents (Doing):"
    add "$(printf '%s\n' "$doing" | head -n "$MAX_LINES" | cut -c1-"$MAX_TITLE")"
    if [ "$total" -gt "$MAX_LINES" ]; then
      add "and $((total - MAX_LINES)) more"
    fi
  else
    add "No other agent has a card in Doing."
  fi
fi

event="SessionStart"
[ "$MODE" = subagent ] && event="SubagentStart"

# JSON string: escape backslash, quote and tab, and join the lines with \n. Control characters are gone already.
body=$(printf '%s' "$text" | awk '
  { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, ""); printf "%s%s", sep, $0; sep = "\\n" }
')
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$body"
exit 0
