# Changelog

All notable changes to the `devteam` plugin. The version is the one in `plugins/devteam/.claude-plugin/plugin.json`, and every version is a GitHub release (created with `scripts/release`).

## [0.2.17] - 2026-10-14
Evals (gap G3): the harness that measures the team against a plain session, five cases, and the page that says how. No result is claimed yet; see Notes.
### Added
- **`scripts/evals`** (a maintainer tool, not shipped in the plugin): `list`, `check`, `run` and `report`. `run` drives the working-tree plugin as the PM agent through three scripted answers per goal (`claude -p --resume`), runs a plain session with no plugin on the same goal and the same check commands, and records cost, turns, spawns, diff size, stray files and whether the criteria hold, per run, as small JSON files under `evals/results/`. `report` prints medians, cost ratios against the design's targets (tiny 1.3x, standard 2.5x), the diff size against a reference patch, and the change between two runs.
- **`evals/`**: five cases with fixtures and reference patches: `tiny-fix`, `standard-feature`, `slop-fixture` (a seeded-slop task: a ready helper, a near-duplicate, a TODO), `no-goal` (idle team, plain question: nothing may spawn, and the always-on cost shows) and `tamper-attempt` (a criterion's check is rewritten to `true` outside `dt` after confirmation; the goal must not close verified).
- **`scripts/evals check`** proves without a model call that every case can fail and can pass: each non-regression criterion fails on the fixture, all pass with the reference patch applied. It refused one of the five cases' criteria on its first run (an empty-output check that passed when the command did not exist).
- **`docs/EVALS.md`**: method, cases, how to read the numbers, what is not covered, and a results block `scripts/evals report --write` fills.
- `tests/evals.t` (117 tests): the cases, the runner against a fake `claude` (arms, flags, cumulative cost, scripted answers, early stop, the budget, tamper, stray files, nothing spent without `--yes`) and the report on synthetic results.
### Notes
- **Cost is read once.** In a resumed session `total_cost_usd` is cumulative and includes subagents (a recorded run: 0.19, 0.55, 0.57 after three turns), so summing the turns would count the first turn three times.
- **Surveyed `claude plugin eval`**, which this is not built on: a case there is one prompt in an empty workspace with no way to answer a question, and a goal here is a conversation run as the PM. Repeated runs with a no-plugin baseline, a versioned JSON result, a cost ceiling and model pinning are adopted. Details in `docs/EVALS.md`.
- **Not run yet.** The harness is tested offline end to end against a fake `claude`, but its first real sessions need the user's go-ahead (they are real spend, in nested sessions with permissions bypassed in scratch repositories). The register keeps G3 in progress until three runs per case with a baseline are recorded.
- Still owed in G3: a user-facing page case scored on the design-quality rubric (needs a neutral judge for both arms), and the decision on a per-edit lint hook and a complexity-budget flag, which the slop fixture is there to inform.

## [0.2.16] - 2026-10-14
Install ergonomics (gap G12): `/devteam:doctor`, and a README status line that is true. The demo and the directory submissions wait for G1 and G4.
### Added
- **`dt doctor` and `/devteam:doctor`.** One read-only command that checks the whole install and prints a plain-language `fix:` under every problem: Claude Code's version, the platform, perl and its core modules, git, the plugin's files and line endings, `hooks.json` against the hook handlers that exist, **every hook started the way Claude Code starts it** (in a throwaway project, so a missing `sh`, a broken perl or a CRLF script shows here), whether the `dt` first on PATH is this plugin's, this copy's version against the latest release (one request to GitHub, skipped with `--offline`), what `claude plugin list` says is installed (behind, disabled, in two scopes), and this project's seal and setup. Exit 1 on a FAIL.
- `tests/doctor.t` (56 tests): a healthy install, then each fault made in a copy of the plugin (a missing file, CRLF, a hook naming no handler, a Hooks.pm that does not compile, an old claude, a native Windows perl, a stale `dt` first on PATH, a newer release, a disabled or doubled install, a tampered or unreadable `.devteam`), `--offline` making no request, and the doctor leaving the real project untouched.
### Changed
- **README.** The status line said v0.1 and that the flow had not run end to end; it now says what is true (1075 tests on macOS, Linux and Windows with Git for Windows, headless live passes, never interactive, never on Windows under Claude Code). The commands table and the troubleshooting table lead with `/devteam:doctor`.
### Notes
- The doctor found two things on its first run, here: the machine's installed copy was 0.2.3 (the release is 0.2.15), and that stale copy's `dt` came first on PATH, so its old scripts would have run under the new skills. Both are the cases the tool is for.
- A hook the doctor runs must never touch the real project: its first version let `DT_ROOT` (which a hook obeys before `CLAUDE_PROJECT_DIR`) point the smoke test at the project and a hook re-sealed an edited file. The test that found it is in the suite.
- Still open in G12, by the register's own order: GitHub topics (your yes), the demo recording and directory submissions (after G1 and G4).

## [0.2.15] - 2026-10-13
Windows (gap G14): native Windows with Git for Windows runs the whole offline suite in CI; WSL is documented as the Linux it is.
### Added
- **A CI job on `windows-latest`** runs the offline suite under Git for Windows' own perl, one file at a time (that perl has no `prove`), next to the Ubuntu and macOS jobs. All 19 files pass (1,019 tests).
- **`.gitattributes`**: every checkout gets LF line endings, whatever `core.autocrlf` says. Git for Windows turns it on by default, and a script with CRLF does not start (`#!/bin/sh^M`).
- **One spelling per path.** Claude Code hands hooks Windows paths (`C:\Users\me\proj\x.py`) and Git for Windows' perl works in `/c/Users/me/proj`, so a prefix test between them missed: a subagent write to `.devteam\state.json` through a backslash path was not refused. Every path in a hook's input, `CLAUDE_PROJECT_DIR` and the session registry is converted first; macOS and Linux are untouched.
- `dt preflight` names the platform on Windows and refuses a native Windows perl (Strawberry or ActiveState: no `setsid`, a different `fork`).
- `dt shot` finds Chrome or Edge in the usual Windows folders and falls back to `python` when there is no `python3`.
- A live Claude Code process is looked up by its Windows pid (`ps -W`), because `kill` cannot see it from Git for Windows' perl.
- `tests/windows.t` (52 tests): the path spellings, CRLF under a lock, hooks given backslash paths, Chrome discovery, the hook file's shape, and, on a Windows perl only, the Windows pid lookup.
### Changed
- **Hooks are shell commands now** (`sh "${CLAUDE_PLUGIN_ROOT}/hooks/hook.sh" guard`) instead of exec form with `sh` as the program. Exec form needs `sh` on the Windows PATH, which Git for Windows does not set by default; a shell command runs in Git Bash, which finds `sh` itself. Confirmed live on macOS: the self-test confirms 14 checks, none refuted, through the new form.
- A locked acceptance test holds when its bytes match or when they match after normalising line endings to LF or CRLF; any other difference is still a violation.
### Fixed
- `dt sessions` treated a path under a folder that does not exist as different from the same path under the root, on Windows (a removed worktree, a subfolder not made yet); the nearest existing folder is now canonicalised.
### Notes
- **Not run live under Claude Code on Windows.** The suite proves the scripts and the hook handlers fed the path forms Claude Code is documented to send; what Claude Code really sends, how it starts Git Bash, and Chrome, Edge and the session registry on a desktop are unobserved.
- Without Git for Windows the hooks cannot start, and the fail-closed spawn guard should then block the Agent tool in every project while the plugin is enabled (the hook documentation says a hook that cannot start is a failure). Not observed; `claude plugin disable devteam@devteam-marketplace` switches it off.
- WSL has no job of its own: it is Linux, which the Ubuntu job covers.

## [0.2.14] - 2026-10-13
Bounded discussion (gap G18): a contested decision gets a short, recorded, mediated exchange and an ADR, only when a trigger fired. Two older defects found by the live pass are fixed.
### Added
- **`dt discuss`** and the `devteam:discuss` skill. Three triggers start a discussion and `dt discuss new` refuses anything else: `dispute` (an engineer's DONE_WITH_CONCERNS contests a reviewer finding the code does not settle), `options` (the Architect's reply carries a `CONTESTED:` line: two viable designs that differ materially in cost or are hard to undo) and `user` (`/devteam:ask debate <question>`). Two or three roles take part, the Architect always. Round 1 is independent: a statement already on hand (an engineer's objection, the design's own choice) goes in free with `--source reply`, the others are started in one foreground message and speak in parallel. Round 2 happens only when they split and can add something; there is no third. A statement is at most 150 words and a position names an option or `NEW`.
- The Architect's final position decides. A participant who ends elsewhere is logged as dissent in their own words (`decide --dissent "<who>: <words>"` adds one from a person who never took part), and the outcome is an ADR in `.devteam/adr/` (options, decision, reasons, dissent) beside a readable record in `.devteam/discussions/<id>.md`. Engineers are writers, so they speak only through a reply already on hand.
- **The caps are in the script, not the prompt**: participant set, trigger, word cap, rounds, two discussions per goal (`discussions.max_per_goal` in `config.json`), the spawn budget, and no discussion in the tiny lane. State is `.devteam/discussions.json`, which agents cannot write. `dt close` refuses while one is open (`decide`, or `cancel --reason`). `dt status` shows an open one.
- The ledger records open, every statement and close; the closure report prints each discussion's decision, dissent and the spawns and tokens spent between its open and close.
- `/devteam:ask debate <question>`; the Architect's reply format gains the `CONTESTED:` line; `orchestrate` names the three triggers and what a discussion is never for (a security FIX, a criterion or scope change, the tiny lane).
- 119 new tests (967 in all): every refusal, the caps, consensus short-circuit, split and round 2, dissent kept in the ADR and the record, ADR numbering, the ledger window, the close guard, agent authority, and the written parts.
### Fixed
- **A one-off consult with no goal was refused.** The spawn guard denied every `devteam:*` agent while the status was IDLE before it looked at the `adhoc` flag that `/devteam:ask` sets for exactly this case, so `/devteam:ask <role> <question>` outside a goal never started an agent. Seen live (three refusals, the PM cancelled the discussion and reported it); now an `adhoc` consult starts, and clearing the flag closes it again.
- **A recorded view from outside the participants was lost.** A debate where the user quoted an engineer's objection produced "Dissent: none", and the PM hand-edited the ADR and the record to put it back. `decide --dissent` keeps it, and the skill says an on-record view is a participant (`fullstack-engineer`, `--source reply`) or a `--dissent`, never a hand edit.
- ADR file names end on a whole word (at most 48 characters).
### Confirmed live (Claude Code 2.1.296, headless, scratch repositories)
- A user-requested debate (JSON file or SQLite, Architect and Reviewer): both started in one message, both chose the JSON file, no second round, an ADR with the options and the Architect's reasons; the goal closed `verified` in 8 agents. The discussion cost 2 spawns (out=810, cache_write=14173).
- The Architect and the Security Engineer on where a service token lives: both chose an environment variable (the config file is one `git add` from a commit, the keychain is macOS only); 2 spawns, 7 agents in the goal.
- `/devteam:ask debate` with no goal active (after the guard fix): the PM set `adhoc`, the Architect and the Reviewer ran side by side, both chose the file, an ADR was written and `adhoc` was cleared; the whole session cost about $0.19.
- A debate where the user quoted an engineer's objection (after the skill fix): the PM added `fullstack-engineer` as a participant with `--source reply`, the split was reported by position (A: Architect and Reviewer; B: the engineer), the Architect's position stood without a second round, and the engineer's dissent is in the ADR, the record and the closure line in their own words.
- Control: a goal with no trigger left no discussion state, no ADR and no closure line. A goal that named a 50-to-500,000 notes uncertainty did not make the Architect flag `CONTESTED:` ("nothing here is seriously contested"), and no discussion ran.
### Notes
- Not seen live: the `dispute` trigger from a real DONE_WITH_CONCERNS, an Architect `CONTESTED:` line, and a round 2 (every discussion among spawned roles ended in agreement after round 1; the one split was an engineer's recorded view). What a second round changes is untested. Whether a discussion improves decisions at all is a G3 (evals) question; the closure line is there to price it.
- Agent teams' direct peer messaging was not used: it is experimental, interactive only and off by default, so it is unavailable headless, and it would bypass the spawn cap and the ledger.

## [0.2.13] - 2026-10-13
Review gate (gap G6): the review is as big as the risk, and a script decides which one applies. Two older defects found by the live pass are fixed.
### Added
- **`dt risk` ends with the review that applies**: `review: gate` when it lists a trigger, `review: single pass` when it lists none. `--goal-risk high|regulated|normal` adds the goal's own stated risk as a trigger (`dt risk --goal-risk high`, with or without the word `diff`). A change adding more than 400 lines is a trigger too (`large-diff`, a `size` row in `risk.tsv`; new files count). A project's own `.devteam/risk.tsv` is read after the plugin's.
- **The review gate.** With `review: gate` the PM spawns, in one message and each with `run_in_background: false`, the Security Engineer (`diff` mode) and two Reviewers, `lens: correctness` and `lens: design`; they run side by side and all three replies come back together. The PM merges them into one list: a finding two lenses report at the same file and lines counts once (highest severity kept, both lenses named), HIGH before MEDIUM, at most five NITs, findings the diff did not introduce (`PRE`) listed apart and never blocking. An engineer fixes the blocking list; the next round re-checks only the lenses that had blocking findings, each given its findings and the fix diff. At most three rounds, then an exception stop. With `review: single pass` it is one Reviewer with no lens, as before; its `RISKY: yes` still starts the Security Engineer. A security FIX is still never dismissed.
- The Reviewer's reply carries severities (HIGH, MEDIUM, NIT, PRE) and a `RECHECK:` line; the Security Engineer has the same re-check mode.
- The closure report prints a `review:` line: review passes per role and their `in`, `out`, `cache_read` and `cache_write` tokens, so the gate's price is next to its findings.
- 51 new tests (848 in all): the gate and single-pass decision, goal risk, the size trigger and the project override, the agents' lens and re-check text, the orchestrate text, the closure line, final-usage counting and non-ASCII round trips.
### Fixed
- **Token counts were far too low.** Claude Code writes one transcript line per content block of a message and the output count grows block by block (2, then 1391 for one message); the ledger took the first line (21 tokens for a 324-token reply). A message is now counted at its final value, and a message split across two reads adds only the growth of its output.
- **Non-ASCII text was stored twice-encoded.** A criterion, goal title or note holding `…`, `é` or any non-ASCII character was written to `.devteam` as `â¦`, and the check command that ran later received garbage, so the criterion could never pass. Seen in two of three live runs (the PM had to repair the check by hand). Strings now stay UTF-8 bytes end to end in `dt` and the hooks (hook input too, so a path with a non-ASCII name matches what git and the shell use).
- **The Reviewer and the Security Engineer are told to read uncommitted work and new files** (`git diff <base>` and `git status --short`). The Reviewer's wording was `git diff <base>..HEAD`, which shows nothing until the work is committed.
### Confirmed live (Claude Code 2.1.296, headless, scratch repositories)
- A normal goal took the single pass: one Reviewer, no lens, `RISKY: no`; closed `verified` with 4 agents.
- The same goal stated as high risk took the gate: the Security Engineer and both lenses ran in parallel (their stops landed within seconds of each other), all clear with NITs only; `verified`, 5 agents.
- An uncommitted `export.py` with seeded defects (SQL injection, no authorization check, an off-by-one, unquoted CSV, a duplicated helper, SQL outside `repo.py`) went through the gate: every seeded defect was found by at least two lenses, the Security lens alone found spreadsheet formula injection, and the merged list reached the engineer. Round 2 re-checked all three lenses and found one new MEDIUM (a huge `page` overflowed SQLite); round 3 re-checked the two lenses that still had findings. Closed `verified`.
### Notes
- The lens split gave little unique coverage on a one-file change: the correctness and design Reviewers also reported security findings and each other's, although told not to. The merge rule absorbed it; the gate buys independent confirmation more than separate territory. Whether it is worth three agents on small risky changes is a G3 (evals) question.
- A risky goal with two fix rounds used all 10 standard spawns and the PM stopped to ask (the cap held). The spawn cap is unchanged.
- Text with non-ASCII characters written by an earlier version stays garbled in old `.devteam` data; re-enter it.
- The orchestrate skill grew by one step's worth of text; the always-on footprint was not re-measured in this release.

## [0.2.12] - 2026-10-12
All eight lifecycles (gap G17): DevOps, V-model, Spiral and Prototype, with done-checks that are really enforced.
### Added
- `lifecycles/devops.md`, `v-model.md`, `spiral.md`, `prototype.md` (17 to 18 lines each). `dt lifecycle suggest` never recommends a missing profile now, and a test checks every selector row has a file.
- Done-checks as criteria. Lines `- cmd: TEXT :: COMMAND`, `- judgement: TEXT` and `- manual: TEXT` under `## Extra done-checks` become criteria `L1`, `L2`, ... when a goal is confirmed. Before this, a profile's extra done-checks were prose no code read. `{dt}` and `{goaldir}` are filled in; the tiny lane, which runs no agents, turns a judgement check into a manual one. Prose lines are ignored, so existing and custom profiles keep working; `agile-scrum` now enforces its full-gate check.
- `dt lifecycle checks NAME`, and `dt lifecycle set` swaps the open done-checks of the old profile for the new one's (checks that passed stay).
- `dt gate run --full --require`: fails when no gate is configured, so a "green pipeline" check cannot pass by default.
- The closure report prints who confirmed each manual or judgement criterion and what they said.
- **A security close gate.** `dt close` now refuses, and tells the PM to ask you, when `dt risk` lists triggers in the change and no Security Engineer reviewed the goal (the tiny lane cannot spawn one). You either have it reviewed (`dt state transition ACTIVE`, `dt goal lane standard`, then the security pass) or accept it with `dt close --accept-risk --by user`; the acceptance is written into the closure report. Settled a suspect another session recorded for 0.2.11: the step lived in skill text and was skipped in one run, and in a repeat run the PM never ran `dt risk` at all.
- 106 new tests (797 in all): every profile's shape and length, 54 signal combinations never recommending a missing profile, confirm, swap, tiny lane, custom profile, verify, closure, and the security close gate.
### Fixed
- **The selector matched a signal that was not given to any row.** A call without `--ops` was met by the `devops` row. The missing profiles had hidden it by falling back; it surfaced as soon as `devops` existed.
- **A blanket "yes to everything" was accepted for a check that asks for a decision** (the prototype's keep, rebuild or discard). The close-out now records the owner's words as the note and asks once more when they have not said which.
### Confirmed live (Claude Code 2.1.296, headless, scratch repositories)
- A goal under each new lifecycle closed `verified`: `devops` (8 of 10 agents, three done-checks, the pipeline gate check passing only with a gate configured), `v-model` (QA wrote the test plan before the Architect, the verifier judged coverage, 9 agents), `spiral` (a register of risks, mitigations and outcomes per loop, 7 agents), `prototype` (2 agents, the file opening with `PROTOTYPE: disposable`). About $1.70 each at list prices, $0.70 for the prototype.
### Notes
- Not yet seen: a lifecycle changed mid-goal through `/devteam:lifecycle`, and the interactive question showing the done-checks before the user picks.

## [0.2.11] - 2026-10-12
Fourth live pass (gap G1): documentation of what ran and what is still owed. No code change.
### Confirmed live (Claude Code 2.1.296, headless, scratch repositories)
- A login and search goal closed `verified` (3 of 3 criteria, 5 agents, about $0.53). The Security Engineer's diff pass returned `CLEAR` with three real NOTEs: the existing `get_user` SQL injection outside the diff, a plaintext password returned by `SELECT *`, and a NULL password raising instead of returning `None`.
- `dt engage` refused to engage when another session's transcript was in the working directory (`ENGAGE NEEDS A CHOICE (nothing changed)`).
### Open
- **Tiny lane did not offer the standard lane (suspect, one run).** For a `get_user` change the PM chose the tiny lane and edited `app.py` itself; `dt risk` listed `sql-concat`, but the close-out did not offer `dt goal lane standard`, which the `orchestrate` skill says to offer so a Security Engineer can review. Needs a repeat before it is called a defect.
- Still not seen live: a Security `FIX` on a diff and the fix loop that follows; the interactive question prompts; the quality loop (researcher, designer, screenshots); several engineers and worktrees.

## [0.2.10] - 2026-10-12
DevOps Engineer (gap G9, second role) and a guard that keeps deploys with the user.
### Added
- `devops-engineer` agent (`devteam:devops-engineer`): writes pipeline, container and infrastructure files as code inside a task's allowed files; verifies with the project's own static checks and tests, never installs a tool and says which check could not run; never deploys. Its reply carries CHECKS and DEPLOY FACTS (what a deploy would run, where, which secrets by name, the rollback).
- `orchestrate` routes a task whose planned files list a `pipeline:` entry in `dt risk planned` to this role instead of `fullstack-engineer`, and shows any DEPLOY FACTS in the close-out question; the deploy is the user's to run.
- `git-guard` refuses, for every subagent, commands that change something outside the working tree: `terraform`/`tofu` apply and destroy, `kubectl` and `helm` mutations (a client-side dry run is allowed), `docker` push and login, `npm`/`yarn`/`pnpm`/`cargo`/`twine`/`gem`/`mvn` publish and deploy, `serverless`/`cdk`/`sam` deploys, `pulumi up`, and any `aws`, `gcloud`, `az`, `vercel`, `netlify`, `fly` call; also inside `sh -c`, after `sudo`/`env`, and in `&&` chains. A wrapper script (`make deploy`) is not seen.
- Self-test: Probe A also tries `terraform apply`, recorded as `deploy-guard-live`.
- 69 new tests (691 in all): the agent contract, the routing text, 22 refused and 20 allowed commands, and a mutation check showing the guard tests fail when the guard is off.
### Fixed
- **A Security FIX could be dismissed.** In a live run the PM sided with the reviewer against the Security Engineer and closed the goal, then told the user. A security FIX is now fixed or put to the user before `dt close`, and a security requirement that contradicts `design.md` is an exception stop.
### Confirmed live (Claude Code 2.1.296, headless, scratch repositories)
- Self-test: 14 confirmed, none refuted; the engineer probe's `terraform apply` was refused ("changes something outside the working tree").
- A CI-workflow goal ran twice through research, design, a Security Engineer design pass, the DevOps Engineer, QA verify, a Security diff pass, review and the verifier, and closed `verified` both times (7 and 8 of 10 agents, about $1.10 each at list prices). The DevOps Engineer reported `actionlint` and a YAML parser as not run rather than installing them, and its rollback.
- The pinned `actions/checkout` and `actions/setup-python` SHAs the agents wrote match the upstream tags (checked against the GitHub tags API).
### Notes
- The two runs differed: SHA pins in one, floating `@v7` tags in the other. Both disclosed what was unverified; the Security Engineer accepted both. Consistency is a G3 (evals) question.
- Not yet seen live: the DevOps Engineer on a real deploy script or infrastructure-as-code repository, and a DEPLOY FACTS block with something in it.

## [0.2.9] - 2026-10-12
Second live pass (gap G1): the self-test and a whole goal ran headlessly against the current plugin. Four defects found and fixed.
### Fixed
- **The finish gate blocked the QA Engineer.** Acceptance tests are red by design, and in verify mode QA must not fix code, so with a test gate configured every standard goal stopped at its first step: QA was sent back three times and the goal went BLOCKED. QA is no longer gated; `dt verify` and `dt close` decide.
- **A normal risky goal overran the standard spawn cap.** With the design and diff security passes it needs nine spawns, and the PM skipped QA's verify pass to fit under seven. The standard cap is now 10, and QA verification is added to the steps that are never skipped to stay under a cap.
- **`dt risk` missed the first real login function** (`def login`, `hashlib.scrypt`, `hmac.compare_digest`): new `auth-code` and `crypto-api` line triggers. Seen live: the tiny lane now reports both and offers the standard lane before closing.
- **The agent tool returns at once by default** in current Claude Code ("Async agent launched"). `orchestrate` and `/devteam:selftest` now spawn with `run_in_background: false`.
- **Self-test verdicts.** An agent declining a probe was recorded as `refuted`; it is now `unseen` with the reason (a refusal by the agent is not the hook's decision). The commit probes say they are sanctioned tests. `dt-on-path` now checks that the `dt` found is this plugin's own: a stale 0.2.3 earlier on PATH was "confirmed" in a contaminated first attempt.
- `dt trace report` decides `finish-gate-blocked` from evidence: confirmed when the same agent stopped again after a block.
### Confirmed live (Claude Code 2.1.296, headless, `--plugin-dir`, scratch repositories)
- The self-test: 13 checks confirmed, none refuted. The reviewer's commit was refused by the hook ("role 'devteam:reviewer' may not write to git"); `agent_type` `devteam:security-engineer` reaches the hooks; its tool list has no write tool.
- The finish gate blocks a `SubagentStop` and the agent carries on: three blocks, a new stop after each, then BLOCKED.
- A second session's hook events reach the team and its writes are attributed to it; `SessionStart` sources `startup`, `resume` and `compact`.
- PM mode through setup, onboarding, intake, orchestration and close. A standard goal closed `verified` (5 of 5 criteria, 7 agents, about $1.50 at list prices) with a Security Engineer design pass (6 requirements, and it flagged an out-of-scope overwrite in `create_user`) and diff pass (CLEAR, with its coverage stated).
### Notes
- Not yet seen live: the interactive prompts (headless has no `AskUserQuestion`), the user-facing quality loop, several engineers and worktrees, and a Security Engineer diff with real findings.
- Agents commit with a `Co-Authored-By` trailer because Claude Code's own attribution setting asks for one; the plugin neither adds nor removes it.
- 9 new tests (622 in all).

## [0.2.8] - 2026-10-12
Security Engineer (gap G9, first role): risky changes get a read-only security review, decided by a script.
### Added
- `security-engineer` agent (`devteam:security-engineer`): read-only (no `Write` or `Edit`), two modes. `design` applies STRIDE to the trust boundaries in `design.md` and returns at most six testable requirements. `diff` reviews only what the change adds against the OWASP Top 10 categories it can reach, checks a new or changed dependency's publisher and advisories, and reports only findings it can state as attacker, boundary, impact and why controls fail. A committed credential is `STOP` and is never printed. Its reply says what it did not read.
- `dt risk` and `plugins/devteam/risk.tsv`: `dt risk planned <path>...` checks planned file paths, and `dt risk [diff [--base REF]]` checks the finished change (paths, and the lines the change adds; new files whole) against editable triggers: authentication, payments, crypto, uploads and webhooks, secrets, pipelines, dependency manifests, migrations, `eval` and shell calls, unsafe deserialization, DOM injection, string-built SQL, disabled TLS checks. It makes no model call. A match means "look", never "finding".
- The PM flow (`orchestrate`) spawns the Security Engineer in `design` mode after the Architect and in `diff` mode before the Reviewer when `dt risk` finds a trigger or the goal's risk is high or regulated; a Reviewer's `RISKY: yes` also triggers it; `STOP` is an exception stop; a tiny-lane change that trips a trigger is offered the standard lane.
- `/devteam:selftest` probe D and the manual check `security-engineer-live` (no write tools, cannot commit).
- 53 tests: `tests/risk.t` and a hook test that the role cannot commit even with the grant on a devteam branch.
### Changed
- README token figures were stale (about 600 always-on, `orchestrate` 1.6k); measured now with `claude plugin details`: 899 before this change, 932 after (the new agent's description), `orchestrate` 3.2k to 3.5k when loaded, about 1.1k per Security Engineer spawn.
### Notes
- Tested offline only. The agent has not been run live and has no eval case yet (that needs G3). DevOps, the next role in G9, is not in this release.
- Design sources are in `docs/DESIGN.md` (Claude Code's `security-guidance` plugin and `/security-review`, shinpr/claude-code-workflows, metaswarm, gstack).

## [0.2.7] - 2026-10-12
### Fixed
- Token accounting overstated usage about threefold. Claude Code writes an assistant message's usage once per content block (a real session had 1,054 usage lines for 393 messages; a subagent had 43 for 11) and the ledger counted every line. It also counted history a forked session inherits, and the first Stop after engaging swept the whole transcript in. Usage is now counted once per message and request, only for this session, from a baseline `dt engage` takes. Checked on a real 19 MB transcript against an independent implementation: identical figures. Totals recorded by earlier versions stay inflated.
### Changed
- The tests no longer read the machine's real Claude session registry or transcripts.
### Notes
- Found while looking at gap G11 (cost report), which the owner dropped; no report or budget was built.

## [0.2.6] - 2026-10-10
Concurrent sessions (gap G16): another Claude session in the same repository no longer goes unnoticed.
### Added
- `dt sessions` (list, `ack`, `check`, `probe`): other live sessions that share this working tree. Liveness comes from Claude Code's session registry, trusted only when it lists the asking session; otherwise recent transcripts and what the hooks observed.
- A lease on the team (`.devteam/session.lock`, heartbeat from the owner's hooks). `dt engage` exits 2 and changes nothing when another live session holds the team (`--take-over`) or other live sessions share the tree (`--accept-others`); a holder that has gone, or is missing from a trusted registry (a cleared session), is replaced with a note.
- The spawn guard refuses a spawn while a live session is unacknowledged for the goal (the PM asks you once), and refuses `devteam:*` agents from a session that does not own the team.
- `dt scope start|check|accept`: a task's allowed files, and a report of every change outside them (committed, staged, unstaged or untracked) since the task started, attributed to another session when a hook saw it write. `dt close` and `dt scope start` refuse while any is unresolved; only the user keeps one.
- `dt status` shows other live sessions and scope state; `dt trace report` gains `other-session-events`.
- `/devteam:selftest` checks the registry (`sessions-registry`) and that a subagent cannot run `dt close` (`dt-authority-live`).
### Notes
- Detects and warns; it cannot prevent a write. The documented prevention is a worktree per session (`claude --worktree <name>`), described in the README.

## [0.2.5] - 2026-10-10
Honest endings (gap G8): a goal that mostly works can now say so, instead of being stuck or hand-forced shut.
### Added
- Four recorded outcomes: `verified`, `partial`, `failed`, `blocked`, written to `closure.md`, the ledger (`goal_closed`) and `dt status`.
- `dt close --accept-partial`: with no other flags it lists every unmet criterion and records nothing; with `--reason TEXT --by user` it closes as `partial`. It requires at least one passing criterion and at least one open one, and the report keeps the reason and every open criterion.
- The PM's close-out offers "accept as partial" with the unmet criteria shown (`orchestrate`), and `amend` points to it instead of removing a criterion to make a goal pass.
- Stopping a confirmed goal records `failed`, or `blocked` when it was waiting on you.
### Fixed
- A lock violation, a hand-edited protected file or a moved branch is refused for every outcome. `dt close` and `dt verify` previously re-sealed a tampered `criteria.json` as a side effect, so a second `dt close` could pass; they now refuse until you review and run `dt resync`.
- A subagent could run `dt criteria confirm --by user` or `dt close` through Bash. The git-guard hook now denies every state-changing `dt` command from a subagent; screenshots, `dt gate run` and read-only commands still work.
- `dt` options: a boolean flag followed by another `--option` (for example `--full --cwd DIR`) lost its name.
- `dt verify` no longer prints an uninitialised-value warning when no criterion passes.

## [0.2.4] - 2026-10-10
First results from `/devteam:selftest` (gap G1): nine checks confirmed, one defect found and fixed.
### Fixed
- A bare skill name can resolve to another installed plugin's skill: the researcher's preloaded `research` skill loaded a different plugin's text. The preloaded skills are renamed `devteam-craft`, `devteam-research` and `devteam-design-quality`, and a test fails if an agent preloads anything without the `devteam-` prefix.
- PM mode no longer preloads `orchestrate` and `goal` by bare name; it invokes `devteam:orchestrate` and `devteam:goal` through the Skill tool.
### Confirmed live
- `dt` on PATH; `Agent` input fields (`subagent_type`, `model`, `effort`, `isolation`); `agent_id` and `devteam:`-prefixed `agent_type` on subagent hook calls; live denial of subagent state writes, pushes and commits; spawn guard refusing an untyped agent and an ungranted worktree; model override; subagent token usage in the ledger.

## [0.2.3] - 2026-10-10
Live verification (gap G1): a way to settle what Claude Code really does, from a real run.
### Added
- Tracing: `dt trace on|off|status|show|clear|note|report`, or `DT_TRACE=1`. Every hook records its raw input (truncated) and its decision to `.devteam/trace.jsonl`; a `SubagentStart` and a `SessionStart` trace-only handler capture events nothing else listens to. Off by default, and the trace-only handler does not even start Perl while it is off.
- `dt trace report`: a verdict per assumption (agent input fields, `agent_id` on subagent calls, `agent_type` format, subagent start and stop fields, model and effort passed, compact `SessionStart`, finish-gate blocks, token usage in the ledger) plus recorded manual checks.
- `/devteam:selftest`: a live self-test for a scratch repo. It starts three probe agents, attempts actions that must be refused, and records verdicts for skill preloading, the model override, state protection, the git guard, the spawn guard and `dt` on PATH.
- A structural test that fails if `dt` declares file-level data after its dispatcher's `exit` (the cause of two earlier bugs).

## [0.2.2] - 2026-10-10
### Added
- CI (`.github/workflows/ci.yml`): the offline test suite on Ubuntu and macOS, and `claude plugin validate --strict` for the marketplace, plugin, skills and agents, on every push to `main` and every pull request. README badge added.
### Changed
- `scripts/release` now refuses a commit whose CI run is missing or not green, and waits for a run that is still in progress.

## [0.2.1] - 2026-10-10
### Added
- Workflow diagrams in the README and `docs/images/`: the end-to-end flow with the three points where you decide, the goal state machine, the team and enforcement architecture, and the git permission tiers. SVG sources plus 2x PNG exports.
- `docs/images/generate.py` and `scripts/diagrams` regenerate them, so they can follow the workflow as it changes.

## [0.2.0] - 2026-10-10
Quality and currency. A first end-to-end project passed every check and still looked like a wireframe: all criteria were structural, nothing researched what current work looks like, nobody looked at the result, and the size budget acted as a ceiling.
### Added
- **Research Analyst** (`researcher`): establishes what is current (verified versions, idioms, how leading examples are built) and writes a cited `reference.md`; topics cached in `.devteam/knowledge/` for 30 days (`dt knowledge [--stale DAYS]`).
- **UX Designer** (`ux-designer`): writes a design spec (art direction, tokens, layout, real content, imagery plan, motion, states) and critiques screenshots against a rubric.
- `dt shot [--serve DIR] [--widths 390,768,1280]`: headless-Chrome screenshots into the goal's evidence, so agents look at what they built.
- Skills `research` and `design-quality` (principles and the scoring rubric); the Architect, designer and researcher can use `WebSearch`/`WebFetch`, engineers `WebFetch`.
- Intake adds a **quality criterion** for user-facing goals and asks for 1-3 live references.
### Changed
- The PM flow: research, design spec, build with self-review of screenshots, QA screenshots, designer critique and up to two polish rounds, then code and product-quality review. Quality is never traded for spawns.
- Every agent has an explicit "how you think" process; the craft charter now says minimal means no waste, not low ambition, and the Architect's complexity budget is sized from the quality bar.
- Defaults: engineers and reviewer at high effort, verifier medium, lane caps standard 7 and large 20.
- The reviewer scores product quality from screenshots as a second lens; the verifier judges rubric criteria only from opened screenshots.
- Always-on footprint rose from about 441 to about 596 tokens per session (measured with `claude plugin details`); hooks still cost none.
- Subagents may write `reference.md`, `design-spec.md`, `knowledge/` and `evidence/shots/` (still not state or criteria).

## [0.1.5] - 2026-10-10
### Changed
- Team names are now generated at runtime instead of being fixed: each role's name is drawn at random from `names.txt` when the team is first needed, kept for the engagement, never repeated within a team, and dropped when the team is stood down. Titles and role ids stay fixed. This replaces the fixed names shipped in 0.1.4.
- Agent descriptions lead with the title only; the PM puts the person's name and title at the start of each brief (`dt who <role>`).
### Added
- `dt team --reroll` draws a new team; `dt disengage` (used by `/devteam:stop`) stands the team down.
- Tests (235) check that no person is hardcoded in any agent, skill or script, and that names are random, unique, stable and resettable.

## [0.1.4] - 2026-10-10
### Added
- Team personas: every role is a fixed fictional person with a name and title (Priya Raman, Software Architect; Marcus Lindqvist, Full-Stack Engineer; Aisha Rahman, QA Engineer; Tomas Herrera, Staff Engineer; Elena Petrova, Acceptance Verifier; Daniel Reyes, PM; Maya Okafor, Product Owner), kept in `plugins/devteam/team.tsv`.
- `dt team [--all]` and `dt who <role|name> [--role]`; `dt models show` lists the person, and `dt models set`/`get` accept first names.
- The PM announces who is working and uses names in the board; `/devteam:ask` and `/devteam:changemodels` accept names; `/devteam:start` shows the team.
### Changed
- Agent descriptions and prompts introduce the person (descriptions stay within 15 words). Role ids are unchanged.
### Fixed
- `dt` no longer clobbers the global `$_` when reading data files.

## [0.1.3] - 2026-10-10
### Added
- `CHANGELOG.md` and `scripts/release`: every published change now bumps the version and gets a GitHub release whose notes come from this file, with the commit, test count and validation result attached.

## [0.1.2] - 2026-10-10
### Fixed
- `/devteam:goal` could start intake before one-time setup was done, probing missing files with a shell command and showing "Exit code 1".
### Changed
- New `setup` skill (model choice plus project scan). `/devteam:start` and the goal flow both use it, so setup cannot be skipped.
- `dt status` ends with `setup: complete` or lists what is missing.
- `goal` and `architect-intake` read files with the Read tool, and `architect-intake` asks nothing when the profile is missing.

## [0.1.1] - 2026-10-10
### Fixed
- `/devteam:start` could not hand off to `changemodels` because it was user-only; it is now model-invocable.
- `dt gitignore` left the tracked `.gitignore` modified and the tree dirty, which made `dt branch start` refuse. It now writes `.git/info/exclude`, and the clean-tree checks ignore `.devteam/`, `.claude/worktrees/` and `.claude/settings.local.json`.
- The initial commit could sweep in `.DS_Store` and `.claude/`; `start` now shows the file list, proposes exclusions and commits only what you approve.

## [0.1.0] - 2026-10-10
### Added
- Core loop: `dt` CLI (goal state machine, hash-locked criteria, verification, tree-hash gate cache, close gate, lifecycle selector, model and effort settings, git permissions, preflight) and hooks (spawn guard, state and test-lock protection, tiered git guard, finish gate with retries, routing, turn count, compact digest, usage ledger).
- Skills: `start`, `goal`, `onboard`, `architect-intake`, `orchestrate`, `amend`, `status`, `pause`, `stop`, `changemodels`, `lifecycle`, `ask`, `craft`.
- Agents: `architect`, `fullstack-engineer`, `qa-engineer`, `reviewer`, `goal-verifier`, `project-manager`.
- Lifecycles: `direct`, `agile-kanban`, `agile-scrum`, `waterfall`.
- MIT license, design document, install and usage README, 186 tests.
