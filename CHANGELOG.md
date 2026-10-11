# Changelog

All notable changes to the `devteam` plugin. The version is the one in `plugins/devteam/.claude-plugin/plugin.json`, and every version is a GitHub release (created with `scripts/release`).

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
