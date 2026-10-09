#!/bin/sh
# Fast path: do nothing, and start nothing, unless devteam is engaged in this project.
s="${CLAUDE_PROJECT_DIR:-.}/.devteam/state.json"
[ -f "$s" ] && grep -q '"engaged" *: *true' "$s" 2>/dev/null || exit 0
exec perl "$(dirname "$0")/hook.pl" "$@"
