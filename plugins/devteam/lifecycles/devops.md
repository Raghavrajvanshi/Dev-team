---
id: devops
shape: pipeline first, then small changes through it; the owner deploys, the team never does
cadence: continuous, one pipeline-verified change per task (engineers one at a time)
---
## Phases
1. Pipeline: the DevOps Engineer defines or adjusts build, test and container steps before any feature code, so every later task is verified by them.
2. Change: each task is a small commit on the goal branch that runs through the project's gates.
3. Release candidate: the artifacts build from the goal branch and the deploy facts are written down (what runs, where, secrets by name, the rollback).
4. Hand over: DEPLOY FACTS go in the close-out question. The owner deploys and operates; the team does not.
## Roles early
`devops-engineer` before any feature task; `security-engineer` reviews every pipeline or infrastructure change.
## Extra done-checks
- cmd: WHEN the full gates run on the final tree THEN at least one gate is configured and every gate passes :: {dt} gate run --full --require
- judgement: WHEN the deploy facts are read THEN they name a rollback and how it was exercised without deploying
- manual: WHEN the owner has run the deploy facts against staging THEN the deploy succeeded and the rollback worked
## Ceremonies (PM bookkeeping only)
One checkpoint line per phase in board.md. No release meeting: the close-out question is the release review.
