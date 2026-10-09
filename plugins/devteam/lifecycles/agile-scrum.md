---
id: agile-scrum
shape: backlog -> iteration -> review -> retro, repeated
cadence: iteration = a batch of 2-4 tasks ending in an integrated, verified increment
---
## Phases
1. Backlog: order tasks by value and risk, each traceable to a criterion.
2. Iteration plan: pick the next batch that fits the spawn and fix-round caps.
3. Build: engineers one at a time (v0.1), gates after each task.
4. Review: the increment is merged, criteria re-verified, a 3-line summary written.
5. Retro: at most 3 lessons appended to profile.md, then plan the next iteration or close.
## Roles early
QA writes the acceptance tests for the iteration before the build.
## Extra done-checks
Every iteration ends with a passing full gate run on the merged tree.
## Ceremonies (PM bookkeeping only, never a multi-agent meeting)
planning, review and retro are short entries in board.md.
