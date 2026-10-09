# Changelog

All notable changes to the `devteam` plugin. The version is the one in `plugins/devteam/.claude-plugin/plugin.json`, and every version is a GitHub release (created with `scripts/release`).

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
