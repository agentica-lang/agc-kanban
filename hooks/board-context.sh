#!/bin/sh
# Hook of the agc-kanban plugin: `board-context.sh session` runs at SessionStart and
# `board-context.sh subagent` at SubagentStart. It prints the JSON a hook answers with, whose
# additionalContext becomes part of the model's context: the rules about the agent name and the cards
# in progress on the board. Reads only; it never writes to the board and never invents an agent name.
#
# Silent (no output, exit 0) when `kanban` is not installed or no board is configured, so a session
# that does not use the board pays nothing. A configured board that cannot be read prints one notice.
# The exit code is always 0: a hook must not block a session start.
#
# It relies on the CLI to print one card per line: `kanban card list` replaces every control character of a
# title with a space (card_line in src/kanban_cli/output.agc), so no title can add a line that looks like a card.
# The hook still strips control characters and cuts each line, because the lines end up in JSON and in the context.
set -u

MODE=${1:-session}
MAX_LINES=15
# The longest card line kept, in characters; a title has no limit on the server.
MAX_LINE=160

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

# Control characters would break the JSON string and could hide text, and the cut is in characters. A card
# title comes from another agent, so it is data. iconv drops a multibyte character that the cut may have split.
clean() {
  tr -d '\000-\010\013\014\016-\037\177' | cut -c1-"$1" | { iconv -c -f UTF-8 -t UTF-8 2>/dev/null || cat; }
}

cards=$(run_kanban card list 2>"$errors")
status=$?
if [ "$status" -eq 2 ]; then
  # USAGE: no board is configured (KANBAN_BOARD, --board or the config file), so this project does not use one.
  exit 0
fi

# The name of this session (the coordinator's); a subagent has the same environment.
me=$(printf '%s\n' "${KANBAN_AGENT:-}" | head -n 1 | clean 64)
text=""
add() { text="$text$1
"; }

# add_cards HEADER LINES: the header and as many LINES as `budget` allows, then "and N more"; the budget is shared
# by every list, so the whole output keeps to MAX_LINES card lines.
budget=$MAX_LINES
add_cards() {
  [ -n "$2" ] || return 0
  total=$(printf '%s\n' "$2" | wc -l | tr -d ' ')
  shown=$total
  [ "$shown" -le "$budget" ] || shown=$budget
  add "$1"
  [ "$shown" -eq 0 ] || add "$(printf '%s\n' "$2" | head -n "$shown")"
  [ "$total" -le "$shown" ] || add "and $((total - shown)) more"
  budget=$((budget - shown))
}

if [ "$status" -ne 0 ]; then
  reason=$(grep -v '^kanban: warning:' "$errors" | head -n 1 | clean 200)
  add "agc-kanban: the board could not be read (${reason:-kanban exited with $status}). The URL and the key come from KANBAN_URL and KANBAN_API_KEY or the config file, and \`kanban whoami\` shows what fails. Claims and writes need a working board."
else
  add "agc-kanban: this project's work queue is a kanban board; the agc-kanban and kanban-cli skills have the rules and the commands."
  add "Every command that writes (and \`card next\`, \`card list --mine\`) needs the agent's own name, from KANBAN_AGENT or --agent; reads do not."
  case $MODE in
    subagent)
      add "A subagent's name comes from its coordinator's brief, and a subagent without one asks its coordinator before any write."
      [ -z "$me" ] || add "This session's KANBAN_AGENT is $me (the coordinator's name); a subagent uses the name in its brief (\`--agent NAME\` or its own KANBAN_AGENT)."
      # The coordinator's cards are not the subagent's: every card in Doing is listed.
      doing=$(printf '%s\n' "$cards" | awk -F'  ' '$2 == "Doing"' | clean "$MAX_LINE")
      add_cards "In progress (Doing):" "$doing"
      [ -n "$doing" ] || add "No card is in Doing."
      ;;
    *)
      add "This session is the coordinator: it names itself from its conversation with the user, and gives each subagent a name in its brief."
      if [ -n "$me" ]; then
        add "KANBAN_AGENT is set to $me."
        # ENVIRON, not -v: -v would read backslash escapes in the name.
        mine=$(printf '%s\n' "$cards" | ME="$me" awk -F'  ' '$3 == ENVIRON["ME"]' | clean "$MAX_LINE")
        add_cards "Your cards:" "$mine"
      fi
      doing=$(printf '%s\n' "$cards" | ME="$me" awk -F'  ' '$2 == "Doing" && $3 != ENVIRON["ME"]' | clean "$MAX_LINE")
      add_cards "In progress by other agents (Doing):" "$doing"
      [ -n "$doing" ] || add "No other agent has a card in Doing."
      ;;
  esac
fi

event="SessionStart"
[ "$MODE" = subagent ] && event="SubagentStart"

# JSON string: escape backslash, quote and tab, and join the lines with \n. Control characters are gone already.
body=$(printf '%s' "$text" | awk '
  { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, ""); printf "%s%s", sep, $0; sep = "\\n" }
')
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$body"
exit 0
