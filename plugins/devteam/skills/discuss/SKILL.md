---
name: discuss
description: PM procedure: one bounded, recorded discussion for a contested decision (2 rounds, Architect decides, ADR).
---
# PM: discuss

A discussion is the exception. It costs spawns, so it runs for one of three triggers and `dt discuss new` refuses anything else.

**Triggers**
- `dispute`: an engineer's DONE_WITH_CONCERNS contests a reviewer finding and the code does not settle it.
- `options`: the Architect's reply carries a `CONTESTED:` line (two viable designs that differ materially in cost or are hard to undo).
- `user`: the user asked for a debate (`/devteam:ask debate ...`).

**Never** for a security FIX (it is fixed, or goes to the user), a criterion or scope change (the user's call), a failing test, or in the tiny lane. At most two per goal; it counts against the spawn cap.

## Run it
1. `dt discuss new --trigger <t> --question "<the decision, one sentence>" --options "A=...|B=..." --evidence "<the finding and the objection, or the user's words>" --participants architect,<one or two of reviewer, security-engineer, researcher, ux-designer> [--context "<files to read>"]`. The Architect always takes part: its final position decides. Pick participants whose concern differs (cost, risk, maintainability), never two of one role.
2. Statements already on hand go in free: `dt discuss say <id> <role> --position <A|B> --source reply --text "<their words, at most 150>"` (the Architect's choice in `design.md`, an engineer's objection, the reviewer's finding). Round 1 only; engineers speak only this way. A view that is on record (an engineer's objection, a colleague the user quotes) must be a participant (`fullstack-engineer`) to count as dissent: never hand-edit the ADR or the record. A view whose owner cannot be a participant goes in at the end: `dt discuss decide <id> --dissent "<who>: <their words>"`.
3. For each other participant `dt discuss brief <id> <role>` prints its brief. Start them all in one message, `run_in_background: false`, as in orchestrate "Spawning an agent", and record each reply with `dt discuss say <id> <role> --position <P> --text "<its ARGUMENT>"`.
4. `dt discuss status <id>` says what is next. All agree: decide. Split: decide (the Architect's position stands) unless the others can add something new, then one more round with `brief`; there is no third. A refused `say` (words, round, role) is the cap working: shorten, do not argue.
5. `dt discuss decide <id>` writes the ADR (options, decision, dissent). Tell the user in one line: the decision, who dissented and the ADR path; they may overrule it at any time. If it changes the design or a task, say so in the next brief. `dt close` refuses while a discussion is open (`decide`, or `cancel --reason`).

Agents never message each other: you carry every statement. The ledger shows each discussion's spawns and tokens in the closure report.
