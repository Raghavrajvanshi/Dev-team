# Dev-team

A goal-gated, token-lean software development team for Claude Code, packaged as the plugin **`devteam`**. It works in any git project.

- A **Goal Keeper** asks you to define the goal first. Nothing is built until you confirm it, and the team stops when the done-criteria are verified by script.
- A **PM**, an **Architect**, engineers, **QA** and a **Reviewer** are started one at a time, only when a step needs them.
- The PM suggests the best-fit **lifecycle** (Agile Scrum/Kanban, Waterfall, and more) and you choose.
- **You are the highest authority.** Amend, pause, stop or change models at any time. Git writes happen only after you grant them; push, PR and deploy are asked every time.
- Code quality is enforced, not requested: every agent loads a short craft charter (minimal, modular, no slop), and scope, locked tests and a close gate are checked by scripts.

> **Status: v0.1 (core loop).** Unit and CLI tests pass (225) and the plugin installs cleanly from this repo, and a first live run confirmed the plugin loads and `/devteam:start` works through preflight, init and engage. The rest of the flow has not yet been exercised end to end. See [Status and known limits](#status-and-known-limits).

## Requirements

| Needed | Check with | Notes |
|---|---|---|
| Claude Code **2.1.295 or newer** | `claude --version` | Older versions lack the hook failure setting the plugin relies on. Update with `claude update`. |
| `git` | `git --version` | The project must be a git repo with at least one commit. |
| Perl 5 with core modules | `perl -MJSON::PP -MDigest::SHA -e1` (prints nothing when fine) | Preinstalled on macOS and most Linux. Windows is not supported yet. |

## Install

Run these two commands in a terminal:

```bash
claude plugin marketplace add Raghavrajvanshi/Dev-team
claude plugin install devteam@devteam-marketplace
```

Or, from inside a Claude Code session:

```
/plugin marketplace add Raghavrajvanshi/Dev-team
/plugin install devteam@devteam-marketplace
```

Then restart Claude Code (or run `/reload-plugins`) and check it:

```bash
claude plugin list        # devteam@devteam-marketplace  Version 0.1.4  enabled
```

In a session, typing `/devteam:` should list the commands below.

By default the plugin installs for you (`--scope user`) and is available in every project, but it stays **idle until you run `/devteam:start`** in a project. Use `--scope project` to enable it for everyone on one repository.

**Try it without installing:**

```bash
git clone https://github.com/Raghavrajvanshi/Dev-team.git
cd your-project && claude --plugin-dir ../Dev-team/plugins/devteam
```

**Update, disable, uninstall:**

```bash
claude plugin marketplace update devteam-marketplace
claude plugin update devteam@devteam-marketplace     # restart Claude Code to apply
claude plugin disable devteam@devteam-marketplace    # switches every hook off
claude plugin uninstall devteam@devteam-marketplace
```

## Use it

Open Claude Code in your project and follow these steps.

**1. Start the team: `/devteam:start`** (once per project)
It checks your setup (Claude Code version, git repo with a commit, clean working tree) and offers a fix for anything missing, never applying it without your yes. The first time, it asks **one question: use the recommended models, or customise?** (recommended is pre-selected). It then scans the project cheaply into `.devteam/profile.md`, records the project's test and lint commands, and offers an allow-list so the team does not stop at every command. You approve each of these.

**2. Describe a goal in plain words**
For example: *"Add a /health endpoint that returns {status: ok}, with a test."* (or `/devteam:goal <text>`). If you skipped the one-time setup (model choice, project scan), the goal flow finishes it first instead of failing. The Goal Keeper asks only what it cannot infer (the Architect adds up to three technical questions), each with a recommended answer, so "go with your recommendations" works. Then you get **one combined confirmation**:

| You confirm | Examples |
|---|---|
| The contract | Objective, scope, non-goals, and done-criteria like *WHEN GET /health THEN 200 and `{"status":"ok"}`* |
| The lane | *tiny* (inline, no agents), *standard*, or *large* |
| The lifecycle | The PM's suggestion with its reasons, the runner-up, "show all", or type any name |
| Git permissions | Whether the team may create `devteam/<goal>`, commit on it, merge into it, and switch back |

**3. The team works.** You see short summaries. You are asked again only for **exceptions** (a cap is reached, tests keep failing, a command is not allow-listed, anything that would push or deploy) and **once at close-out**: open manual criteria, whether to commit, and whether to open a PR (the exact commands are shown).

**4. It stops.** When every criterion is verified by script, the goal closes with a short report in `.devteam/goals/<id>/closure.md`, your original branch is restored, and nothing keeps running. Your next message starts a new goal.

### Commands

| Command | Use it to |
|---|---|
| `/devteam:start` | Engage the team in this project; resume a paused or blocked goal |
| `/devteam:goal [text]` | Define and confirm a new goal (a plain message does this too once engaged) |
| `/devteam:amend <change>` | Change criteria, scope, lane, lifecycle or git permissions mid-goal |
| `/devteam:status` | See state, board, criteria, spawns and usage |
| `/devteam:pause` | Pause (a running agent finishes its step; nothing new starts) |
| `/devteam:stop` | Stop now, clean up and disengage |
| `/devteam:changemodels` | Pick team members, then set their model and effort |
| `/devteam:lifecycle [name]` | Show or change the process lifecycle |
| `/devteam:ask <role> <question>` | One-off consult with a role (read-only) |

### The team

Each member is a fictional person with a fixed name and title, so you can talk to them naturally (`/devteam:ask priya ...`, `/devteam:changemodels` accepts first names). The technical role ids (`devteam:architect`, ...) are unchanged. Run `dt team` (or `/devteam:start`, which shows it) for the live list.

| Person | Title | Role id | Runs as |
|---|---|---|---|
| Maya Okafor | Product Owner (Goal Keeper) | `goal-keeper` | intake, in your session |
| Daniel Reyes | Project Manager and Scrum Master | `project-manager` | the PM, in your session |
| Priya Raman | Software Architect | `architect` | agent |
| Marcus Lindqvist | Full-Stack Engineer | `fullstack-engineer` | agent |
| Aisha Rahman | QA Engineer | `qa-engineer` | agent |
| Tomas Herrera | Staff Engineer (code review) | `reviewer` | agent |
| Elena Petrova | Acceptance Verifier | `goal-verifier` | agent |

Planned: Wei Chen (Backend), Sofia Marini (Frontend), Kenji Watanabe (Mobile), Hannah Becker (DevOps), Idris Bello (Security), Lucia Fernandes (UX), Oliver Grant (Technical Writer), Nadia Haddad (Research). Names are invented; any resemblance to real people is coincidental.

### Lanes and lifecycles

- **Lane** is how big the work is: *tiny* (one file or a small fix, **zero agents**), *standard* (a feature in existing code), *large* (several modules). Each lane caps how many agents may start.
- **Lifecycle** is the process shape, chosen by you from the PM's suggestion: `direct`, `agile-kanban`, `agile-scrum`, `waterfall` today. Each is a short file in [`plugins/devteam/lifecycles/`](plugins/devteam/lifecycles); add your own in `.devteam/lifecycles/<name>.md`, starting from `_template.md`.

### What it creates in your project

- `.devteam/` (it offers to hide it from `git status` through `.git/info/exclude`; your tracked `.gitignore` is never touched): state, config, `profile.md`, `standards.md`, and `goals/G-001/{goal.md, criteria.json, board.md, closure.md}`. Safe to read, and you may edit `goal.md` freely. Changes to `criteria.json`, `state.json` or `config.json` made outside the team's tools are detected and block the goal; ask Claude to run `dt resync` to accept a deliberate edit.
- A git branch `devteam/G-001`, only if you grant it. Your own branch is restored at the end and its tip is verified unchanged.

## Cost

`claude plugin details devteam` reports the plugin's footprint: about **441 tokens added to every session**; hooks cost no model tokens. Skills and agents cost tokens only when they run (for example `goal` about 1k, `orchestrate` about 1.2k). Gate results are cached by exact code state so an identical tree is never tested twice, and hooks take about 2–4 ms when the team is not engaged. Savings versus a plain session are not claimed until you measure them; the usage ledger (`/devteam:status`) records spawns and tokens by model.

## Troubleshooting

| Symptom | What to do |
|---|---|
| Preflight says `FAIL claude-version` | `claude update`, then restart |
| `FAIL git` or `FAIL clean-tree` | Make an initial commit; commit or stash your changes, then rerun `/devteam:start` |
| `dt: command not found` | Restart Claude Code or `/reload-plugins`. If it persists, tell Claude to run `dt` by its full path inside the installed plugin folder (`claude plugin list` shows where), and report it |
| Goal is `BLOCKED` | `/devteam:status` shows why. Resolve it and run `/devteam:start` to resume, or `/devteam:stop` |
| The team is in the way of normal work | `/devteam:stop`, or `claude plugin disable devteam@devteam-marketplace` |

## Status and known limits

**Tested** (`prove tests/`): the `dt` CLI (state machine, goals, hash-locked criteria, verification, tree-hash gate cache, close gate, lifecycle selector, model/effort settings, git grants), the git command classifier, and every hook. `claude plugin validate --strict` passes for the marketplace, plugin, skills and agents, and a fresh install from this repo works.

**Confirmed in a first live run:** the plugin loads from the marketplace, `/devteam:start` runs, preflight, `dt init` and `dt engage ${CLAUDE_SESSION_ID}` work, and `dt` resolves. Live runs also found and fixed four bugs: `changemodels` was user-only so `start` could not use it, `.gitignore` edits left the tree dirty (now `.git/info/exclude`), the first commit could sweep in `.DS_Store` and `.claude/` (now it shows the file list and asks), and `/devteam:goal` ran before setup was finished (it now completes setup first via the `setup` skill).

**Not yet verified inside a live session** (each has a documented fallback; please report what you see): the exact `Agent` tool input fields, `agent_id`/`agent_type` on subagent hook calls, preloading the `craft` skill into agents by bare name, the `model`/`effort` override on spawn, `SubagentStop` blocking from a plugin, and PM mode (`claude --agent devteam:project-manager`).

**v0.1 limits:** engineers run one at a time (no worktrees or parallelism yet); onboarding is an inline scan; backend/frontend/mobile/DevOps/Security/UX/Writer roles and the DevOps, V-model, Spiral and Prototype lifecycles are planned. macOS and Linux only.

## Develop

```bash
prove tests/                                        # 225 tests
claude plugin validate .                            # marketplace
claude plugin validate plugins/devteam --strict     # plugin
claude plugin validate plugins/devteam/skills --strict
claude plugin validate plugins/devteam/agents --strict
```

### Releasing

Every published change is a new version and a GitHub release ([releases](https://github.com/Raghavrajvanshi/Dev-team/releases), [CHANGELOG](CHANGELOG.md)):

1. Bump `version` in `plugins/devteam/.claude-plugin/plugin.json` and add a `## [x.y.z]` entry to `CHANGELOG.md`.
2. Commit and push to `main`.
3. Run `scripts/release`. It refuses unless the commit is on `origin/main`, the version is new and has a changelog entry, and the tree is clean, `prove tests/` passes and `claude plugin validate --strict` is clean. The release notes are the changelog entry plus the commit, test count and install/update commands.

Layout: `plugins/devteam/{bin/dt, lib/, hooks/, skills/, agents/, lifecycles/, templates/}`. The full design and the reasoning behind it: [docs/DESIGN.md](docs/DESIGN.md).

## License

[MIT](LICENSE)
