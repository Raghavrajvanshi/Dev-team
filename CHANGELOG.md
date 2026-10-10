# Changelog

All notable changes to the `devteam` plugin. The version is the one in `plugins/devteam/.claude-plugin/plugin.json`, and every version is a GitHub release (created with `scripts/release`).

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
