---
id: spiral
shape: loops of objectives, alternatives and risks, a build of the riskiest part, then review and commitment to the next loop
cadence: loop = 1 to 3 tasks, bounded by the lane's spawn cap and fix rounds; counted in tasks and budget, never calendar
---
## Phases (each loop)
1. Objectives: restate what this loop must prove and what constrains it.
2. Alternatives and risks: list the options and the top three risks in reports/risks.md in the goal folder, and choose the approach that retires the biggest risk first.
3. Build: the smallest slice that tests that risk, engineers one at a time, gates after each task.
4. Review: record each risk's outcome and decide the next loop. The user is asked only at close-out, or sooner when a risk invalidates the goal (an exception stop).
## Roles early
`architect` names the risks before any build; `researcher` when a risk is an unknown technology or version.
## Extra done-checks
- cmd: WHEN the goal ends THEN a risk register exists :: test -s {goaldir}/reports/risks.md
- judgement: WHEN reports/risks.md is read THEN every loop lists its top risks, the mitigation chosen and the outcome
## Ceremonies (PM bookkeeping only)
The risk register is the only artifact. Loop summaries are three lines in board.md.
