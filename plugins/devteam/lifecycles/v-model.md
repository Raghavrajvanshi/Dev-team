---
id: v-model
shape: requirements, design and build on the way down, each verified by its matching test level on the way up
cadence: none; one pass down the left side, then up the right
---
## Phases
1. Requirements: the contract is final. QA writes the acceptance test plan (reports/test-plan.md in the goal folder): one test per criterion.
2. Design: the Architect's design names every interface. QA adds one integration test per interface to the plan.
3. Build: engineers one at a time; every task carries its unit tests.
4. Verify upward: unit, then integration, then acceptance. A failure returns to the phase whose test level caught it, never forward.
## Roles early
`qa-engineer` writes reports/test-plan.md before the Architect starts; the Architect reads it.
## Extra done-checks
- cmd: WHEN the goal ends THEN a test plan exists :: test -s {goaldir}/reports/test-plan.md
- judgement: WHEN reports/test-plan.md is read THEN every criterion has an acceptance test and every interface in design.md has an integration test
## Ceremonies (PM bookkeeping only)
One checkpoint line per phase in board.md. A phase sign-off stops only if `lifecycle.phaseStops` is on.
