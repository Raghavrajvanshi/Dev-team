---
name: amend
description: Change the running goal: criteria, scope, lane, lifecycle, git grants or a waived rule.
argument-hint: <the change>
---
# amend

The user's instruction beats the Architect, the PM and the hooks. If it is risky, say so in one line, then comply, and record it in an ADR (`status: user-override`).

1. `dt status`. A goal must exist (INTAKE, ACTIVE, PAUSED or BLOCKED).
2. Apply the change:
   - *Criteria or scope*: edit `goal.md`; `dt criteria add|edit|remove` (an edit resets that criterion). If an acceptance test must change, have QA change it, then `dt criteria lock` again.
   - *Lane*: `dt goal lane <tiny|standard|large>` (it resets the spawn and turn caps; spawns already used still count). Say the new caps. A tiny goal that outgrows its lane is upgraded this way and announced; never downgrade silently.
   - *Lifecycle*: use the `lifecycle` skill.
   - *Git permissions*: `dt grant set|revoke <integration|task_branches|merges|restore>`.
   - *Waive a rule* (for example "scaffolding allowed"): write it under "Waived" in goal.md and tell the reviewer in later briefs. Gates still apply at close unless the user removes that criterion.
   - *Models*: use the `changemodels` skill.
3. Re-plan only the affected tasks on the board. Do not redo finished work.
4. If a criterion or the scope changed, show a three-line summary and ask for confirmation once; otherwise apply and report in one line.
5. If the goal was PAUSED or BLOCKED only because of this, `dt state transition ACTIVE` and continue with `orchestrate`.
