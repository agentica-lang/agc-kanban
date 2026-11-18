#!/bin/sh
# Hooks of the agc-kanban plugin that keep the board close to reality (the logic is in drift.py):
#   drift.sh post-tool      PostToolUse on Bash and Agent: after `gh pr create`, `gh pr merge`, `gh issue close` or a
#                           watch_ci run that merged, link the PR or say which card still needs a move; for the
#                           coordinator, also the queued suggestions of drift.sh subagent-stop
#   drift.sh prompt-submit  UserPromptSubmit: the coordinator gets `kanban doctor` at most every 10 minutes
#   drift.sh subagent-stop  SubagentStop: suggests what to do with the cards the finished subagent still holds (rules
#                           on the GitHub state of their links, else Haiku), leaves the answer as a card comment and in
#                           a queue for the coordinator, and logs it (`python3 drift.py score` prints the hit rate)
# Only the PR link is ever written to a card by itself. The exit code is always 0 and a hook that has nothing to say
# prints nothing, so it can never block a session. An unrelated Bash command leaves here after one `case`.
set -u

MODE=${1:-post-tool}
COORDINATOR=${KANBAN_COORDINATOR:-coordinator}

# The child `claude -p` of subagent-stop sets this, so its own hooks leave at once.
[ -z "${KANBAN_HOOK_CHILD:-}" ] || exit 0

input=$(cat 2>/dev/null) || exit 0

CACHE=${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/agc-kanban
KEY=$(printf '%s' "${KANBAN_BOARD:-default}" | tr -c 'A-Za-z0-9._-' '_')
QUEUE="$CACHE/queue-$KEY.txt"

case $MODE in
  post-tool)
    case $input in
      *"pr create"*|*"pr merge"*|*"issue close"*|*watch_ci*) ;;
      *)
        # Nothing about GitHub: only the coordinator with a queued suggestion has anything to say.
        [ "${KANBAN_AGENT:-}" = "$COORDINATOR" ] && [ -s "$QUEUE" ] || exit 0
        ;;
    esac
    ;;
  prompt-submit)
    [ "${KANBAN_AGENT:-}" = "$COORDINATOR" ] || exit 0
    ;;
  subagent-stop) ;;
  *) exit 0 ;;
esac

command -v kanban >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

here=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || exit 0
printf '%s' "$input" | CACHE="$CACHE" KEY="$KEY" QUEUE="$QUEUE" COORDINATOR="$COORDINATOR" \
  python3 -I "$here/drift.py" "$MODE" 2>/dev/null
exit 0
