---
name: stop
description: Stop the goal now, clean up, and disengage the team.
disable-model-invocation: true
---
# stop

Honour this at once. Ask only if there is unmerged work.

1. `dt status`. If the integration branch holds commits not on the user's branch, ask once: keep the branch (default) or discard it (discarding needs the user to approve the exact command; never run a destructive command without it).
2. `dt state transition STOPPED`.
3. If the `restore` grant exists and a branch was started: `dt branch finish`; report any error instead of hiding it.
4. If `git worktree list` shows worktrees under `.claude/worktrees/` made for this goal, remove merged ones; keep or remove the rest only as the user said.
5. `dt state transition IDLE`, `dt disengage`. Report in three lines: what was kept, where, and how to start again (`/devteam:start`).
