---
id: prototype
shape: question, a throwaway build, the owner tries it, then keep, rebuild properly or discard
cadence: one prototype pass of 1 to 3 tasks; building it properly afterwards is a new goal
---
## Phases
1. Question: write down what the prototype must answer under Clarifications in goal.md.
2. Sketch: the smallest thing that answers it. No design document and no locked acceptance tests; criteria are manual or judgement.
3. Build: every file is disposable and says so (`PROTOTYPE: disposable` in its first lines, or it lives under `prototype/`).
4. Try and decide: the owner tries it and says keep, rebuild or discard; their words are the note on the confirmed check, which the closure report prints.
## Roles early
`ux-designer` (spec only) for a user-facing prototype. No QA acceptance step and no code review: a review is the first step of the keep path.
## Extra done-checks
- judgement: WHEN the files changed by this goal are listed THEN each lives under prototype/ or opens with a PROTOTYPE: disposable line
- manual: WHEN the owner has tried the prototype THEN they have said whether to keep it, rebuild it properly or discard it
## Ceremonies (PM bookkeeping only)
None. The decision is the retro.
