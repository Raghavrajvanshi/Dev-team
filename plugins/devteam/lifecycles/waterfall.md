---
id: waterfall
shape: requirements -> design -> build -> verify -> release, in sequence
cadence: none; one pass through the phases
---
## Phases
1. Requirements: the contract and criteria are final before design starts.
2. Design: the Architect writes the full design and module map.
3. Build: all tasks, engineers one at a time (v0.1).
4. Verify: QA runs the full suite and the traceability check.
5. Release: `dt close`, then the close-out question.
## Roles early
Architect completes the whole design before any engineer starts.
## Extra done-checks
Traceability: every criterion maps to at least one test or check, listed in the closure report.
## Ceremonies (PM bookkeeping only)
One phase-checkpoint line per phase in board.md; phase sign-off stops only if `lifecycle.phaseStops` is on.
