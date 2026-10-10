---
name: status
description: Show the devteam's state, board, criteria and usage in a few lines.
---
# status

Run `dt status` (after a goal ended it shows the outcome: verified, partial, failed or blocked, with any open criteria), then print the board (`.devteam/goals/<goal>/board.md`) and `dt criteria show`. If the state is BLOCKED, show the reason and ask what to do. If `dt ledger` has data, add its one-line totals. Refer to people by name (`dt who <role>`). Keep the whole answer under 20 lines. Do not spawn anything.
