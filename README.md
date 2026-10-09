# Dev-team

A goal-gated, token-lean software development team for Claude Code, packaged as the plugin `devteam`. It works in any git project.

- A **Goal Keeper** asks you to define the goal first. Nothing is built until you confirm it, and the team stops when the done-criteria are verified by script.
- A **PM**, an **Architect**, engineers, **QA** and a **Reviewer** are spawned one at a time, only when a step needs them.
- The PM suggests the best-fit **lifecycle** (Agile Scrum/Kanban, Waterfall, and more) and you choose.
- **You are the highest authority.** Amend, pause, stop or change models at any time. Git writes happen only after you grant them; push, PR and deploy are asked every time.
- Code quality is enforced, not requested: a short craft charter (minimal, modular, no slop) is preloaded by every agent, and scope, tests and a close gate are checked by scripts.

## Status: v0.1 (core loop), under active development

**Tested** (`prove tests/`, 179 tests, no dependencies beyond Perl 5 core): the `dt` CLI (state machine, goals, hash-locked criteria, verification, tree-hash gate cache, close gate, lifecycle selector, model/effort settings, git grants), the git command classifier, and every hook.

**Not yet verified live** inside a running Claude Code session (the plugin was built without API access to the CLI): the exact `Agent` tool input fields, `agent_id`/`agent_type` on subagent hook calls, `${CLAUDE_SESSION_ID}` substitution in skills, `skills:` preload of a plugin skill by bare name, the `model`/`effort` override on spawn, `SubagentStop` blocking from a plugin, and PM mode (`claude --agent devteam:project-manager`). Every one has a documented fallback; please report what you see.

## Requirements

Claude Code 2.1.295 or newer, `git`, and Perl 5 (macOS/Linux; Windows is not supported yet).

## Install

```
/plugin marketplace add Raghavrajvanshi/Dev-team
/plugin install devteam@devteam-marketplace
```

## Use

1. `/devteam:start` once per project: preflight, a one-time model choice (recommended models are pre-selected), a cheap project scan, and an offer to add an allow-list so the team does not stop at every command.
2. Describe a goal. The Goal Keeper asks a few questions (the Architect adds up to three technical ones), then shows one combined confirmation: the contract and done-criteria, the lane, the lifecycle, and the git permissions.
3. The team works. You are asked again only for exceptions and once at close-out (open manual criteria, commit, PR).
4. When every criterion is verified, the goal closes and nothing keeps running. Your next message starts a new goal.

| Command | What it does |
|---|---|
| `/devteam:start` | Engage the team; resume a paused or blocked goal |
| `/devteam:goal [text]` | Define and confirm a goal |
| `/devteam:amend <change>` | Change criteria, scope, lane, lifecycle, git permissions |
| `/devteam:status` | State, board, criteria, usage |
| `/devteam:pause`, `/devteam:stop` | Pause, or stop and clean up |
| `/devteam:changemodels` | Pick team members, then set their model and effort |
| `/devteam:lifecycle [name]` | Show or change the process lifecycle |
| `/devteam:ask <role> <q>` | One-off consult with a role |

## The team (v0.1)

`architect` (opus) · `fullstack-engineer`, `qa-engineer`, `reviewer`, `goal-verifier` (sonnet) · the PM and Goal Keeper intake run in your session as skills. Models and effort are recommended defaults you can change. Backend/frontend/mobile/DevOps/Security/UX/Writer roles, parallel worktrees and more lifecycles (DevOps, V-model, Spiral, Prototype) are planned.

Lanes decide who runs: **tiny** (no agents, you and the PM inline), **standard**, **large**. Lifecycles decide the process shape and are small data files in `plugins/devteam/lifecycles/`; add your own in `.devteam/lifecycles/`.

## How it stays cheap and safe

- Cold by default: no agent starts before a confirmed goal, one at a time, within a per-lane spawn cap.
- Handoffs are short briefs and replies of at most 150 words; gate results are cached by git tree hash so an identical tree is never tested twice.
- Hooks do nothing, and start nothing, unless this session engaged the team (`.devteam/state.json`). To switch everything off, disable the plugin.
- Subagents cannot write team state or locked acceptance tests, and git is tiered: read (open), local writes (need your per-goal grant, only the right roles, never on your own branch), push/PR/deploy/destructive (always asked). Hooks are defence in depth; add the proposed `permissions.ask` rules for a hard prompt.

## Develop

```
prove tests/                              # unit and CLI tests
claude plugin validate plugins/devteam    # manifest
claude plugin validate plugins/devteam/skills --strict
claude plugin validate plugins/devteam/agents --strict
claude --plugin-dir ./plugins/devteam     # try it in a project
```

Layout: `plugins/devteam/{bin/dt, lib/, hooks/, skills/, agents/, lifecycles/, templates/}`.

## License

Not yet chosen.
