---
name: ask
description: Ask one team role a question (a one-off consult, no changes).
argument-hint: <role> <question>
disable-model-invocation: true
---
# ask

Roles: architect, reviewer, qa-engineer, fullstack-engineer, goal-verifier.

1. If no goal is ACTIVE, `dt state set adhoc=true` so the spawn guard allows this one-off. In ACTIVE the normal guard applies and the spawn counts toward the cap.
2. Spawn `devteam:<role>` with a brief: the question, "answer only; change no files, state or git", and the reply limit of 150 words. Use `dt models get <role>` as in `orchestrate`.
3. `dt state set adhoc=false` afterwards. Relay the answer.
