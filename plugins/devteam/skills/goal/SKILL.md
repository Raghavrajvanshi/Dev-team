---
name: goal
description: Goal Keeper intake: define and confirm the goal and its done-criteria before any work starts.
argument-hint: <what you want built or changed>
---
# Goal Keeper: intake

Nothing is built until the user confirms a goal here. Intake runs in the main thread; no agent is spawned. Input: `$ARGUMENTS`, or the user's last message.

**0. Check.** `dt status`. If devteam is not engaged, tell the user to run `/devteam:start`. If a goal is already running, this is not a new goal: use the `amend` skill if it changes the current goal, `dt queue add "<text>"` if it is unrelated (tell the user it is queued; one goal at a time), or just answer if it is a question. Continue only from IDLE. If `dt status` ends with `setup: incomplete`, invoke the `setup` skill first (it asks the one-time model question and scans the project, skipping what is done), then continue.

**1. Understand cheaply.** With the Read tool (never a shell probe), read `.devteam/profile.md` and `.devteam/standards.md` only; they exist once setup is complete. If `standards.md`'s `source-hash` no longer matches `shasum -a 256 CLAUDE.md`, regenerate it (see `onboard`). Do not explore the codebase.

**2. Size it.** Propose a lane: *tiny* (one file or a small, clear fix, no design), *standard* (a feature in code that exists), *large* (several modules or a new system). When unsure, choose the smaller.

**3. Ask, as one batch** (at most two consecutive AskUserQuestion prompts, no thinking between them). Ask only what you cannot infer: at most 5 questions (1-3 if the request is specific) covering objective, scope and non-goals, constraints, and "how will we know it is done?". Every question gives your recommended answer first, marked "(Recommended)". For standard and large lanes, also run the `architect-intake` skill and add its questions (at most 3). The user may answer "go with your recommendations". Keep their answers for goal.md.

**4. Draft the contract.** `dt goal new "<title>"`. Fill `.devteam/goals/<id>/goal.md`: objective, scope, non-goals, constraints, clarifications, assumptions. Write the done-criteria in EARS form, *WHEN situation THEN observable result*, each one testable:
- `dt criteria add --id C1 --text "WHEN ... THEN ..." --check "<command that exits 0 only when true>"` for anything a command can verify. Prefer the project's real test/lint/build commands. Never write a criterion that cannot fail.
- `--type manual` only when just the user can judge (taste, UX). `--type judgement` when the verifier agent can judge from evidence.
- If a check needs tests that do not exist yet (standard/large), QA writes them first and they get hash-locked; the check command is the one that will run them.

**5. Suggest the lifecycle.** Infer the signals and run `dt lifecycle suggest --requirements stable|evolving|unclear --risk regulated|high|normal --delivery project|product|maintenance --ops yes|no --size <lane>`. If the user already named a lifecycle, use it and skip the question.

**6. One combined confirmation.** One AskUserQuestion call with up to 4 questions:
1. *Contract*: show objective, scope and non-goals, and the criteria list. Options: Confirm / Change something.
2. *Lane*: your proposal (Recommended) and the neighbouring size.
3. *Lifecycle*: the recommendation with its reason (Recommended), the runner-up, and "Show all lifecycles". "Other" lets the user type any name, including a custom profile.
4. *Git permissions* (omit for the tiny lane), multi-select: create and switch to branch `devteam/<goal>` (`integration`); let engineers commit on it (`task_branches`); merge task work into it (`merges`); switch back to the user's branch at the end (`restore`). Say that push, PR and deploy are always asked separately.
If "Show all lifecycles" is chosen, list `dt lifecycle list` with one line each and ask again; that is the only permitted extra prompt.

**7. Confirm or revise.** If the user changes the contract, edit it and ask once more. When confirmed: `dt goal confirm --lane <lane> --lifecycle <name> --grants <comma-list>` (omit `--grants` for tiny). If `integration` was granted, run `dt branch start`. Then follow the `orchestrate` skill. If the user abandons the goal, `dt state transition IDLE`.
