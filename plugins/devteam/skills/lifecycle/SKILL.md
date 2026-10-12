---
name: lifecycle
description: Show, suggest or change the process lifecycle (Agile, DevOps, Waterfall, V-model, Spiral, Prototype, custom).
argument-hint: [name]
---
# lifecycle

- No argument: `dt status` for the current one and `dt lifecycle list` for the installed ones. Give each a one-line "best for" from its profile's `shape` line (`lifecycles/<name>.md`).
- With a name: check it is listed, then `dt lifecycle set <name>`. A custom profile is any file `.devteam/lifecycles/<name>.md` (copy `lifecycles/_template.md`).
- `dt lifecycle set` also swaps the profile's done-checks (open ones of the old profile go, the new profile's are added as L1, L2, ...): tell the user which.
- If a goal is running, re-plan **only the remaining tasks** under the new profile's phases and update the board; do not redo finished work. Say which phases now apply.
- To get a recommendation, infer the signals and run `dt lifecycle suggest ...` (see the `goal` skill). If the best fit is not installed in this release, `dt` says so; offer the best installed one.
