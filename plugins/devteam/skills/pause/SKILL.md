---
name: pause
description: Pause the running goal; resume later with /devteam:start.
disable-model-invocation: true
---
# pause

Only from ACTIVE: `dt state transition PAUSED`. Tell the user: an agent already running finishes its current step (it cannot be interrupted), no new agent can start while paused, and `/devteam:start` offers to resume. Nothing else.
