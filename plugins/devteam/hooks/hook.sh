#!/bin/sh
# Fast path: do nothing, and start nothing, unless devteam is engaged in this project.
s="${CLAUDE_PROJECT_DIR:-.}/.devteam/state.json"
[ -f "$s" ] && grep -q '"engaged" *: *true' "$s" 2>/dev/null || exit 0
# The trace-only handler does nothing unless tracing is on, so it must not even start perl.
if [ "$1" = trace ] && [ -z "$DT_TRACE" ]; then
  grep -q '"trace" *: *true' "${CLAUDE_PROJECT_DIR:-.}/.devteam/config.json" 2>/dev/null || exit 0
fi
exec perl "$(dirname "$0")/hook.pl" "$@"
