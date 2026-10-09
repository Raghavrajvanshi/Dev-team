# devteam: design

A goal-gated, token-lean, slop-free software team as a Claude Code plugin.

> **How to read this.** This is the design brief the plugin is built from. "You" means the person using the team (the project owner), who is the highest authority. Sections 1-14 describe the **target design**; the section below records where the **v0.1 build** differs from it. Behaviours the docs did not settle are listed as spike items in section 11 and are not assumed.

## As built (v0.1) versus this design
- **Language:** the deterministic parts (`dt` CLI and hooks) are Perl 5 using only core modules, not POSIX `sh` plus `awk`. JSON parsing in plain `sh` was too fragile, and Perl ships on macOS and mainstream Linux. `hooks/hook.sh` is still a dependency-free fast path that exits in a few milliseconds when the team is not engaged.
- **Fail-closed:** `onFailure: "block"` is set only on the spawn guard. The state-protect and git-guard hooks are defence in depth and fail open; the close gate and the seal catch what they miss.
- **Onboarding** is an inline main-thread scan; the `researcher` agent and approved skill packs arrive in v0.3.
- **Seal:** `state.json`, `config.json` and the current goal's `criteria.json` are sealed; a mismatch during a goal sets BLOCKED, and `dt resync` accepts a deliberate hand edit.
- **Engagement** persists through IDLE (so the next message starts a new goal) and ends with `/devteam:stop`.
- **Engineers** run one at a time and commit on the integration branch; worktrees and parallelism are v0.2.
- **Ignoring local state:** `dt gitignore` writes `.git/info/exclude` (not the tracked `.gitignore`) for `.devteam/`, `.claude/worktrees/` and `.claude/settings.local.json`, and the clean-tree checks ignore those paths, so the team's own files never dirty the tree.
- **Personas:** every role has a fixed title in `plugins/devteam/team.tsv`, and a name drawn at random from `plugins/devteam/names.txt` the first time the team is needed. Names are kept in `.devteam/team.json` for the engagement, never repeat within a team, and are dropped on `/devteam:stop`. Role ids stay the technical key for hooks, config and spawning; the PM passes the person's name and title in each agent's brief, so no name is written into an agent file.
- **Setup is a shared skill:** the one-time model choice and project scan live in the `setup` skill. `start` invokes it, and `goal` invokes it first if `dt status` reports `setup: incomplete`, so skipping `/devteam:start` cannot leave intake without a profile.
- **Initial commit:** `start` shows the file list and proposes exclusions (`.DS_Store`, `.env*`, `node_modules/`, `.claude/`) instead of committing everything.
- **`changemodels` is model-invocable** (it only changes anything after an explicit confirmation), because `start` and `amend` hand off to it. `start`, `stop`, `pause` and `ask` stay user-only.
- **Confirmed live (first run):** the plugin loads, `/devteam:start` runs, preflight, init and engage work, `${CLAUDE_SESSION_ID}` is substituted, and `dt` resolves.
- **Not yet verified inside a live session:** section 11 items (a)-(p) not listed above, notably the `Agent` input fields, `agent_id` on subagent hooks, bare-name `skills:` preload, and the `model`/`effort` override on spawn.

## Context
The goal is a reusable dev team of agents (Architect, engineers, PM/Scrum Master, plus extras) packaged as a Claude Code plugin for any project. The rules it is built on:

1. **Lazy activation.** Never start all agents; spawn only what the current step needs.
2. **Token optimisation everywhere.**
3. **You are the highest authority.** You can change anything, any time.
4. **Goal Keeper.** Asks you to define the goal first; no work until you confirm it; stops when the goal is achieved; the next prompt starts a new goal.
5. **No slop.** Code is modular, crisp, clean, minimal. A core value of the Architect and every engineer.
6. **Technically correct.** Checked against the current Claude Code docs in two review rounds. Anything the docs don't settle goes to the spike (section 11), not into the design as fact.
7. **All lifecycle types accommodated.** The PM suggests the best-fit process for your goal (Agile, DevOps, Waterfall, V-model, Spiral, Prototype, or your own) and asks you which one you want (section 3a).

Requires Claude Code 2.1.295 or newer (older versions lack `onFailure` for hooks). Agent teams mode is not used.

## Decisions locked
| # | Decision |
|---|---|
| Q1 | **Minimum stops (revised):** intake questions → ONE combined confirmation (contract + lane + git grant) → ONE close-out question (manual criteria, commit, PR). The Architect brief is shown but the run does not wait for it; you can `/devteam:pause` or `/devteam:amend` while it runs. No per-task merge gate. Push, PR and deploy still prompt (section 6a). Exceptions stop the run (section 2b). |
| Q2 | Greenfield and existing repos; first run does `onboard` → compact project profile. |
| Q3 | Hybrid roster: curated core + runtime stack "skill refresh" (web research, you approve each pack). |
| Q4 | Core: Goal Keeper/PO, QA, Reviewer, DevOps, Security. Conditional: UX, Writer, Mobile. v2: Data/ML, DBA. |
| Q5 | State in `.devteam/` inside each repo. |
| Q6 | Model tiering; ≤2 discussion rounds; Architect breaks ties, dissent logged. |
| Q7 | Engineers in worktrees/branches; local commits; PRs only after approval; never force-push or push to main. |
| Q8 | Marketplace-shaped repo, plugin `devteam`. |
| Q9 | Bounded discussion via a shared file. **Now PM-mediated** (no peer `SendMessage` for engineers/QA/reviewer). |
| Q10 | PM orchestrates; Architect holds technical authority; every role addressable. |
| Q11 | Deterministic gates, 3-retry cap, escalate. **Refined in section 6** (hard gate at close, not on every edit). |
| Q12 | **Recommended models are the default; custom models are an opt-in.** Asked **once** at the first start in a project (recommended pre-selected, section 2a); entering your own models is never required. You can change them any time with `/devteam:changemodels`, which lets you choose which team members to change and set their model and effort. |
| Q13 | **Git is prompt-first and role-limited** (section 6a): read for those who need it; local writes only after a goal-scoped grant you approve in the combined confirmation and only for the roles that write files; push, PR, deploy and destructive git prompt you every time; nobody commits to your original or default branch. |
| Q14 | **Every lifecycle is accommodated** (section 3a): lifecycles are small data profiles (Agile Scrum/Kanban, DevOps/DevSecOps, Waterfall, V-model, Spiral, Prototype, or your own). The PM suggests the best fit from your goal by a deterministic table and then asks which lifecycle you want (recommendation pre-selected, or type any), as one question in the combined confirmation; you can change it any time with `/devteam:lifecycle`. |

## 1. Design principles (what the two reviews changed)
- **Interactive roles are skills; isolated roles are agents.** Subagents can't ask you questions, so Goal Keeper intake and the PM run in the main thread. Agents never spawn agents except the Architect's consults, never hold `SendMessage`, and carry no `memory` on read-only roles.
- **Hooks only distinguish subagent calls (they carry `agent_id`) from main-thread calls.** Your instructions and the PM's decisions are both main-thread. So:
  - In the main thread, gates **report, never block**.
  - The hard block is **at close**: the script that writes `ACHIEVED` refuses until format, typecheck, tests and acceptance checks pass, unless you waive a rule with `/devteam:amend`.
  - Subagents are hard-gated when they finish (`SubagentStop`).
- **The grader can't be changed by the graded.** Acceptance tests are written before the build (at intake or by QA) and their file hashes are recorded in `criteria.json`. A change by any other role fails verification. Criteria that a machine can't judge use a `manual` check (you confirm) or a `judgement` check (the verifier agent reads the evidence).
- **Detect what can't be prevented.** Shell commands can write anywhere and hook matching on Bash is best-effort, so scripts checksum protected files after each legitimate write; a mismatch sets `BLOCKED`.
- **Single writer for state.** Only the PM and scripts write `state.json`, `criteria.json`, `board.md` (subagent writes denied by `agent_id`). Isolated worktree subagents can't write to the main checkout anyway.
- **Anything the PM needs is in the agent's reply.** A worktree with no tracked changes is auto-removed, taking its files with it. A missing or invalid status code counts as `BLOCKED`: the PM resumes the agent once, then asks you.
- **Hard denies belong in permission rules; hooks are defence in depth.** Push is `ask` (you approve each time), so approved PRs still work. Hooks hard-block push/deploy only for calls carrying an `agent_id`.
- **Fail visible, not open, without breaking other sessions.** Plugin hooks run in every session where the plugin is enabled, so `onFailure: "block"` is used **only** on hooks narrowed by the `if` field (state-protect launches only for `.devteam/` paths, git-guard only for git/gh commands), which also saves a process launch on ordinary edits. Every script's first step is a dependency-free "is this session engaged?" check in plain `sh`. Scripts are POSIX `sh` with no runtime dependencies, referenced via `${CLAUDE_PLUGIN_ROOT}`. `/devteam:start` runs a **self-test** of every script (version ≥2.1.295, `git`, scripts present and executable) and refuses to engage if anything fails. A documented kill-switch (disable the plugin) exists. macOS/Linux first; Windows deferred.
- **Untrusted by default:** web-researched skill packs, and any pre-existing `.devteam/` files in a repo (see section 7).
- **Grow only on evidence.** MVP first, full roster as roadmap. The plugin itself obeys the no-slop rule.

## 2. Goal lifecycle (`.devteam/state.json`)
```
(none) ─first /devteam:start→ preflight → MODEL CHOICE (2a, asked once) → ONBOARDING (Researcher read-only) → IDLE
IDLE ─prompt→ INTAKE ─you confirm contract+lane→ ACTIVE ⇄ PAUSED
                                                  │ ⇄ BLOCKED (waiting on you / budget / stall / tamper)
                                                  └ criteria pass→ VERIFYING ─pass→ ACHIEVED → IDLE
                                                                    └ fail→ ACTIVE (max 2 returns, then ask you)
any state ─/devteam:stop→ STOPPED (cleanup) → IDLE
```
- **Contract:** `goals/G-00N/goal.md` (objective, scope, non-goals, constraints, **proposed lane and lifecycle (3a), which you confirm**) + `criteria.json`: EARS-style criteria, each with a `check` command or a `manual`/`judgement` type, and a `passes` flag only the verifier script flips.
- **Intake:** main-thread skill, ≤5 questions (1–3 if the prompt is specific). No agent is spawned until you confirm.
- **Single terminator:** only the Goal Keeper declares done, from fresh script evidence. The `goal-verifier` agent is spawned **only** for `manual`/`judgement` criteria.
- **Session ownership:** `state.json` stores the owning `session_id`. Other sessions in the same repo (or days later) are ignored by every hook until you run `/devteam:start` there.
- **Routing:** the team is opt-in. In **IDLE** a `UserPromptSubmit` hook adds a one-line hint that a plain prompt is a new goal (skipping non-user turns such as agent reports, scheduled runs and cross-session messages; exact detection verified in the spike). In **ACTIVE** the already-loaded PM skill classifies messages as *amend*, *question* or *new goal*. A new goal is **queued**; one goal at a time. A queued **tiny** goal may interrupt at the next task boundary (the tree is clean after a merge): the PM asks you once, pauses the running goal, does the fix on its own branch from your original branch, then resumes (v0.2; in v0.1 a tiny goal simply waits).
- **Recovery:** the board holds per-task status, branch and worktree path, so `/devteam:start` resumes after a crash, pause or stop.
- **Loop exits:** VERIFYING→ACTIVE max 2 returns, then the PM asks whether the criteria were wrong. A task that outgrows the **tiny** lane is upgraded to standard (announced); never silently downgraded.
- **Spawn guard:** in ONBOARDING/INTAKE/PAUSED/STOPPED/BLOCKED only `devteam:researcher` (onboarding) and user-invoked one-offs (`/devteam:ask`) may spawn. While engaged, forks (on by default, they inherit the whole conversation) and `general-purpose` are denied. The guard also counts spawns for the caps.

### 2a. Model choice: asked once, changeable any time (main-thread skill)
**The default is the recommended tiering; custom models are an opt-in, never required.** The first `/devteam:start` in a project asks **one question, once**; the first, pre-selected option is "go with the recommended models", so continuing takes a single keystroke and nobody has to type or pick a model:
1. **Use recommended models (default):** Architect `opus`; engineers, QA, Reviewer, Security, DevOps, verifier `sonnet`; Researcher, Writer `haiku`.
2. **Customise (opt-in):** only if chosen, it runs the same guided flow as `/devteam:changemodels` below.

The answer is saved to `.devteam/config.json` (`models`, `effort`) and **never asked again** at later starts or during a goal. The prompt shows a relative price hint from the editable price table in `config.json`, so a heavier choice's cost is visible.
- **The PM's model:** in a normal session the PM (main thread) runs on your session model, which a plugin can't change (`/model` does), and orchestration is a lot of reading replies, merging and running scripts. If that model is `opus` or another top tier, the start prompt offers **PM mode**: relaunch with `claude --agent devteam:project-manager`, where the main thread uses the PM agent's own model (recommended `sonnet`) and effort. Trade-off: that agent's prompt **replaces** the default Claude Code system prompt, so the PM prompt must stand on its own. It is an option, never forced; `changemodels` shows the relaunch command when you pick it.
- **Recommended effort** (initial values, tuned after measurement): Architect `high`; Security `high`; engineers, QA, Reviewer, DevOps `medium`; Researcher, Writer, verifier `low`.
- **`/devteam:changemodels`** (your authority, any time, any state) is a guided flow:
  1. It shows the current table (member · model · effort).
  2. **Pick which team members to change** (multi-select). Members are grouped to fit the prompt's 4-option limit (Architect · Engineers · QA/Reviewer/Security/DevOps · Researcher/Writer/Verifier/UX), with a drill-down to individual members. Only agents that exist in the installed release are listed.
  3. **Pick the model** (`opus`, `sonnet`, `haiku`, `inherit` = your session model, or `recommended`) and **the effort** (`low`, `medium`, `high`, `xhigh`, `max`, or `recommended`) for the selection. Offer "fine-tune each member separately" if you want different values.
  4. It shows an old → new table and the relative price hint, asks you to confirm, saves, and applies from the **next spawn**. It never interrupts a running agent. The ledger records model and effort per spawn.
- **Mechanism:** agent files keep the recommended `model:` and `effort:` as defaults; only for changed members does the PM pass a different `model`/`effort` on spawn, which overrides the frontmatter (confirmed in the spike). Settings stay fixed per role between changes so prompt caches are shared.
- **Reviewer escalation** to a stronger model for risky diffs uses `models.escalation`; with a single-model choice there is none.
- A new project asks once again (settings are per project, in `.devteam/config.json`).

### 2b. Where the team stops for you (minimum stops)
**Planned stops (a standard goal has three):**
1. **Intake questions**, one batch: ≤5 from the Goal Keeper (1–3 if your prompt is specific) **plus ≤3 technical questions from the Architect** in standard/large lanes (2c).
2. **One combined confirmation:** the contract and done-criteria, the proposed lane, the **lifecycle choice**: the PM's recommendation with reasons, and you pick (3a), and the git grant (6a), in a single prompt batch.
3. **One close-out question:** every `manual` criterion at once, whether to commit, and whether to open the PR (this prompt shows the exact command, so approving it also covers that push/PR).

**Not gates:** the Architect brief (it is written to `design.md` and summarised to you as soon as it exists, and the run continues; pause or amend if you disagree), per-task merges into the integration branch (reversible; the merge script and gates are the check), and routine gate retries.

**Exception stops (the run pauses as BLOCKED and asks):** the design changes scope, non-goals or a criterion; the complexity budget or a lane cap is exceeded; a stall is detected; protected-file tampering; gates still failing after 3 retries; a command outside the allow-list; any push, PR, deploy or destructive git; new skill pack; a risky diff the Reviewer flags. With `--autonomous` the PM first tries one cheap recovery (e.g. a retry with the escalation model) before asking; it never skips the combined confirmation or an outward action.

### 2c. The Architect asks you questions back (without adding stops)
A subagent can't ask you anything (no `AskUserQuestion`), so the Architect's questions always travel through the main thread. Two layers:
1. **At your input (layer 1, standard/large lanes):** an `architect-intake` step runs **in the main thread with the Architect persona and playbook**, reading only the profile (≤150 lines) and the draft contract. It asks **≤3 technical questions** that would change the design: scale and non-functional needs, data and integrations, constraints, reuse of existing patterns. They are **merged into the same intake batch** as the Goal Keeper's questions, so there is no extra stop and **no agent is spawned** (the "no spawn before confirmation" rule holds). It runs on the PM's model (the Architect's `opus` setting applies to the design agent, not to this step). The tiny lane skips it unless the fix is design-ambiguous. The same step runs on a `/devteam:amend` that touches the design.
2. **Mid-design (layer 2):** if the Architect agent hits a **blocking** ambiguity after reading the code, it returns `NEEDS_CONTEXT` with ≤3 questions. The PM raises one exception stop with a single batched prompt, then resumes the same Architect agent with your answers (a resume keeps its context; it is not a new spawn).

**Rules that keep it cheap and non-annoying**
- Only questions that change the design. Everything else becomes a labelled **assumption** in the brief (visible, amendable), never a question.
- ≤3 questions per round; layer 1 once per input, layer 2 at most once per goal (a second would set BLOCKED and say why).
- Every question carries a **recommended answer**; "go with your recommendations" answers all of them in one keystroke, and "skip, use your judgement" logs the assumptions to the ADR.
- Your answers are written by the PM into `goal.md` under **Clarifications**, and any that change a criterion go through the normal contract confirmation.
- `--autonomous`: the Architect proceeds on its recommended answers and logs them as assumptions.

## 3. Lanes (the PM proposes, you confirm with the contract)
| Lane | When | Flow | Initial caps (tune after measuring) |
|---|---|---|---|
| Tiny | one file / small fix | intake → inline edit → gates report → close gate | 0 spawns; main-thread turns counted by a `Stop` hook, warn at 15 |
| Standard | a feature in known code | Architect brief (shown, no wait) → engineers **one at a time in v0.1** → QA → one Reviewer pass → close | ≤5 spawns; `maxTurns` architect 15, engineer 30, QA 20, reviewer 12; fix rounds ≤3 |
| Large | multi-module / new system | onboard → Architect design + module map (shown, no wait) → parallel engineers (v0.2+, ≤3, disjoint files) → QA, Reviewer, conditional Security/DevOps/UX/Writer | ≤12 spawns; PM asks before exceeding |

The lane table fixes who is spawned. The ~30–50k-token delegation rule applies only to **optional** consults inside the large lane (e.g. Security, Researcher). Quality bar is identical in every lane; only ceremony shrinks.

### 3a. Lifecycle: the PM suggests the best fit, you choose, every methodology is accommodated
Two independent axes: **lane** = how big the work is (caps, who is spawned); **lifecycle** = the process shape (phases, cadence, artifacts, extra definition-of-done). Tiny goals always run `direct` (no ceremony).

**Lifecycles are data.** One ≤40-line markdown profile per methodology in `lifecycles/`, so any new methodology is a new file, not new code. Schema: `phases` (ordered, entry/exit criteria, artifacts) · `cadence` (none, or *iteration* = a bounded batch of N tasks ending in an integrated, verified increment, or continuous with a WIP limit) · `roles_early` (roles pulled forward, e.g. DevOps from phase 1, a QA test plan per phase) · `dod_extra` (added done-checks) · `ceremonies` (what the PM writes) · `extends` (hybrids).

| Profile | Shape | Best for | Notable effects |
|---|---|---|---|
| `direct` | none | tiny fixes | no ceremony |
| `agile-kanban` | continuous flow, WIP limit 1–3, pull from the backlog | maintenance, bug streams, steady feature flow | smallest overhead |
| `agile-scrum` | backlog → iteration of N tasks → review → retro | evolving requirements, product features, greenfield products | each iteration ends in a verified increment |
| `devops` (DevSecOps) | pipeline-first: CI/CD, IaC, observability in phase 1; small frequent releases; rollback plan | infra, deployment, platform, ops-heavy goals | DevOps (and Security) pulled forward; DoD adds green pipeline, staging deploy, tested rollback |
| `waterfall` | requirements → design → build → verify → release | fixed, well-understood, contractual scope | full upfront spec; DoD adds a requirement→test traceability matrix |
| `v-model` | waterfall with a test plan written for each phase | safety-critical, regulated, audit trail | QA pulled forward; acceptance/integration/unit plans per phase |
| `spiral` | repeat: identify risks → spike/prototype → evaluate → plan next | high uncertainty or high technical risk | risk register updated each loop |
| `prototype` (RAD) | quick throwaway build for feedback, then rebuild properly or discard | unclear UX or requirements | prototype code is marked disposable |
| custom | copy the template to `.devteam/lifecycles/<name>.md` | Shape Up, XP, Lean, any hybrid via `extends` | no code change |

**Selection is a deterministic table in the PM skill (≤30 lines), not free-form.** It scores the contract and profile on: requirements clarity and stability · risk and compliance · delivery model (one-off project, continuous product, maintenance) · whether infra/CI-CD/ops is central · size. Mapping: regulated or audit-trailed → `v-model`; fixed spec and low change → `waterfall`; infra/pipeline/deploy central → `devops`; high uncertainty or risk → `spiral`; unclear UX wanting fast feedback → `prototype`; maintenance or bug stream → `agile-kanban`; evolving product work → `agile-scrum` (large) or `agile-kanban` (standard). **Your stated preference always wins.** The PM **suggests the best-fit lifecycle with the reasons from your goal, then asks you to choose which one you want.** It is one question in the same prompt batch as the combined confirmation (no extra stop): the options are *the recommendation (pre-selected, with why)*, *the runner-up*, and *show all lifecycles*; "Other" lets you type any lifecycle name, including a custom profile. Accepting the recommendation is one keystroke. If your own prompt already names a lifecycle, the question is skipped and the choice is just echoed back. With `--autonomous` the recommendation is used. `/devteam:lifecycle` views or changes it any time; changing it mid-goal re-plans only the remaining tasks.

**Agents have no calendars,** so sprints, WIP and cadence are counted in tasks and budget, not days. Ceremonies are cheap bookkeeping, never multi-agent meetings: planning = the task breakdown on the board; standup = a board snapshot; review = the close-out summary; retro = ≤10 lessons appended to `profile.md` at close.

**What a lifecycle may and may not change.** It shapes phases, cadence, early roles and extra done-checks. It does **not** change the three planned stops, the craft charter, the spawn/token caps or the git rules. Regulated flows that need sign-off at each phase can opt in with `lifecycle.phaseStops: true` (adds a stop at each phase boundary); by default boundaries are report-only checkpoints. **Token cost:** the PM loads only the chosen profile and never reads the others.

## 4. Token and cost rules
1. Cold by default plus lanes. Typed named agents only, never forks.
2. Cheap standing context: agent `description` ≤15 words, SKILL.md <150 lines, agent files ≤60 lines. Playbooks are preloaded via `skills:` for agents that need them; engineers/QA/reviewer get no `Skill` tool.
3. Handoff by brief: ≤15-line task brief in; reply ≤150 words + status (`DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED`). Fresh context per task; workers never re-plan or expand scope.
4. `omitClaudeMd: true` on brief-driven agents. **`standards.md` (≤60 lines) is derived from `CLAUDE.md` and refreshed at goal start whenever CLAUDE.md's hash changes**, then shown to you in the combined confirmation.
5. Models via aliases, fixed per role (shared caches). **Recommended defaults** (you can override at every start, section 2a): `opus` = Architect; `sonnet` = engineers, QA, Reviewer, Security, DevOps, verifier; `haiku` = Researcher, Writer. Reviewer escalates to the escalation model only for risky diffs (auth, payments, migrations, large diff). The main-thread (PM) model is yours, recorded in the ledger. A custom choice may cost more; that is your call and the cost targets below apply to the recommended tiering only.
6. Profile ≤150 lines. **Gate results are cached by git tree hash** in `goals/G-N/evidence/`: a gate whose exact tree already passed is skipped, and later phases (QA, close) cite the receipt instead of re-running. At a subagent's finish only the **affected tests** run (via the profile's related-tests command; full suite if none exists); the **full suite runs once, before close**, and is itself skipped if that tree already passed in full. A 5-minute suite then runs about twice per goal instead of eight times.
7. **Prompt-cache life:** sequential engineers spaced more than the default 5-minute cache lifetime pay full cache writes again. The spike tests `experimental.cacheTtl: 1h` on engineer agents; the ledger decides whether the dearer 1-hour write is worth it.
8. Hook output only failures (≤40 lines). Deterministic checks cost zero LLM tokens.
9. Discussion is the exception: contested cross-role decisions, 2–3 participants, ≤150 words each, ≤2 rounds, PM-mediated through one file, Architect decides.
10. **Ledger** `.devteam/log.jsonl` (append-only): spawns, turns, tokens **by model**, cache-read fraction, net LOC. A small editable price table in `config.json` converts to cost.
11. **Measurement (from milestone M1, not last):** compare **cost**, not raw tokens, over ≥3 runs per lane (medians) against a plain single-session baseline that must pass the same `criteria.json`. Initial targets to validate: tiny ≤1.3×, standard ≤2.5× baseline cost; large reported only. No saving is claimed until measured.

## 5. Craft charter — the no-slop principle
`playbooks/craft.md` (≤40 lines) is preloaded by the Architect, engineers, Reviewer and QA:
1. **Smallest change** that meets a criterion; every line traces to a criterion or the brief.
2. **Reuse before write;** existing project conventions beat personal style.
3. **No speculative generality:** no one-caller abstractions, config for fixed values, unused params/exports.
4. **Modular:** one responsibility per module/function, narrow public interface, one-way dependencies, no reach-in. Soft signals from config (function ~40 lines, file ~300, params ≤4), advisory.
5. **Crisp:** meaningful names; comments only for non-obvious *why*; no commented-out code, TODO stubs, boilerplate docstrings.
6. **Errors:** handle failures that can occur at boundaries; none for impossible states; never swallow errors.
7. **No extra files** (docs, scripts, scaffolding, examples) unless a criterion asks; tests only for criteria, bugs, boundaries, never implementation details.
8. **Delete as you go;** prefer deleting over adding.
9. **Report:** files touched, net LOC, reused/deleted, one line justifying each new file.
10. **Self-simplify** the diff before reporting DONE.

**Architect owns design simplicity:** each brief has a *module map* (modules, responsibility, public interface, allowed dependencies), a *reuse list*, per-task *allowed files*, a *complexity budget*; simplest design that satisfies the criteria; ADR names at most one rejected alternative. The module map also makes parallel work safe.

| Enforcement | Mechanism | Blocks? |
|---|---|---|
| After each edit | lint **that file only**, ≤10 lines of output | No (report) |
| When a subagent finishes | format, typecheck, **affected tests**; skipped if this tree hash already passed; **only these count as retries** (cap 3) | Yes (SubagentStop) |
| At merge | PM's merge script compares each task branch's diff to the task's allowed files | Yes |
| At merge | unused code/exports check where project tooling exists | Yes |
| During run | diff size vs complexity budget (>1.5×) | No (flags PM) |
| Reviewer (read-only) | charter checklist; findings are specific deletions/merges; ≤3 rounds | Counts as a fix round |
| QA | each test maps to a criterion or bug id; acceptance tests hash-locked | Yes at close |
| At close | the `ACHIEVED` transition script checks receipts for the **final tree hash**, runs only what is missing (the full suite once), and refuses otherwise | **Yes (unless waived)** |

## 6. Git, worktrees and environment
- **Prerequisites (preflight asks before fixing):** git repo with ≥1 commit (offers `git init` + initial commit); working tree clean **ignoring `.devteam/` and `.claude/worktrees/`**; `gh` auth only at PR time.
- **`.devteam/` is fully gitignored by default** (local state, so writes never dirty the tree). Optional archive-on-close commits goal summaries/ADRs if you opt in. Onboarding adds the gitignore entries.
- **Branches (needs the 6a grant):** the PM records your original branch, creates `devteam/G-00N`, and **restores your branch at close**. The integration branch is left with a summary; a PR opens only on your yes.
- **Worktrees (v0.2+):** engineers use `isolation: worktree`; onboarding proposes (you approve) `worktree.baseRef: "head"` and a `.worktreeinclude`. Dependent tasks run sequentially (merge task N, run gates, then spawn N+1). Parallel only for disjoint files from the module map.
- **Merging:** PM merges in dependency order and runs the merge script (scope + unused-code + gates). Conflicts go back to the owning engineer as `NEEDS_CONTEXT` or to the Architect; never auto-resolved silently.
- **Cleanup:** on close/stop the PM removes merged worktrees; unmerged work is merged or discarded only with your OK.
- **Environment in the profile:** dependency install command (per worktree), test prerequisites (DB/services/secrets), gate commands. Greenfield with no gates yet: the first Architect task scaffolds minimal tooling; gates report "not configured" instead of passing falsely.
- **Permissions (before the first goal, not only before parallel work):** a background subagent's prompts surface in your main session, so any command not on the allow-list stops the goal until you return, and `--autonomous` doesn't help. Onboarding therefore proposes the allow-list (the profile's test/lint/typecheck/install commands, read-only git, task-branch commits) plus `ask` rules for `git push`, `gh pr create`, deploy commands, **before the first goal starts**; you approve it once. `/devteam:status` shows `unattended-ready: yes/no`. Without the allow-list the PM warns that the goal will stop at each unlisted command, and parallelism stays at 1.

### 6a. Git permissions: members touch git only after you've been prompted
**Three tiers**
1. **Read** (status, diff, log, show, blame): any role that needs it; no prompt.
2. **Local write** (create the integration branch, task branches and worktrees; commit on them; merge task branches into the integration branch; restore your branch): needs a **goal-scoped grant that you approve in the combined confirmation (2b)**. In the tiny lane nothing is requested: changes stay uncommitted in your working tree until you approve a commit at close.
3. **Remote and destructive** (push, PR create/merge, deploy, `reset --hard`, `clean`, `branch -D`, force flags, removing a worktree that has changes): a **prompt every time** showing the exact command. A grant never covers these.

**Who may use which tier**
| Role | Read | Local write | Remote / destructive |
|---|---|---|---|
| PM (main thread) | yes | branches, worktrees, merges, restore (with grant) | prompts you each time |
| Engineers, QA, Writer (roles that write files) | yes | commit on their **own task branch** only (with grant) | no; the PM asks you |
| Architect, Reviewer, Security, Researcher, verifier, UX | yes | none | none |

- **The grant:** in the combined confirmation the PM shows a short checklist of the local-write categories it needs (integration branch + switching to it, task branches/worktrees + commits, merges, restoring your branch). It is stored in `state.json` (`git_grants`, PM-written), shown in `/devteam:status`, revocable or extendable with `/devteam:amend`, and **expires at ACHIEVED or STOPPED**. If you would rather be prompted for each local write, set `git.localWrites: "per-action"`.
- **Never, even with a grant:** any role committing to your original branch or the default branch. The original branch's tip SHA is recorded at start and verified at close; a mismatch sets BLOCKED.
- **Enforcement:** the `git-guard` hook (PreToolUse on `Bash` calls that carry an `agent_id`; role from `agent_type`) classifies each command into a tier and denies anything the role or grant doesn't allow. The spawn guard refuses an `isolation: worktree` engineer spawn without the worktree grant. In the main thread the PM follows the same matrix by instruction, and native `permissions.ask` rules (offered at onboarding) force a real prompt for remote and destructive git, because hooks can't tell the PM from you and Bash matching is best-effort.

## 7. Your authority and trust
- **Commands:** `/devteam:start`, `goal`, `amend <change>`, `status`, `pause`, `stop`, `ask <role> <q>`, `onboard`, `changemodels`, `lifecycle`.
- **Amend** edits the contract and re-plans only affected tasks; it is also how you waive a rule.
- **Files are the source of truth:** hand-edit `goal.md`, `criteria.json`, `plan.md`; the PM re-reads next step.
- **Override:** your instruction beats Architect/PM decisions; one line of risk, then comply; logged to the ADR. **Gates never block your own commands, they block a goal from closing.** `/devteam:stop` is honoured immediately.
- **Outward actions** (push, PR, deploy, external sends) always need your explicit yes each time. **Git writes follow section 6a: a prompt first, then only the roles the matrix allows.**
- **Trust:** skill packs (facts + source URLs, ≤60 lines, never executed) need your approval before first use. On the first `/devteam:start` in a repo where `.devteam/` or `standards.md`/`profile.md`/`check` commands already exist (e.g. committed by someone else), they are shown to you and their hashes recorded; changes re-trigger approval.

## 8. Roster
Agents are `devteam:*`; contracts list scope, non-goals, inputs, outputs, tools, done/fail. The model shown is the **recommended default**, overridable at start (2a).

| Agent / skill | Kind · model | Competencies (web research) |
|---|---|---|
| Goal Keeper intake + `orchestrate` (PM) | skills, main thread | Intake, EARS criteria, lanes, lifecycle selection, gates, budget, merge control, status |
| `goal-verifier` | agent · sonnet | Judgement/manual criteria from evidence only |
| `architect` (+ `architect-intake` step in the main thread) | agent · opus | Design, stack, standards, module map, ADRs, tie-breaks, simplicity; asks ≤3 clarifying questions back via the PM (2c) |
| `fullstack-engineer` | sonnet | Default for small cross-layer tasks |
| `backend-engineer` | sonnet | Contract-first APIs (REST/gRPC, cursor pagination, versioning, RFC 9457, rate limits), DB modelling and safe online migrations, transactions/indexing, caching, retries/idempotency/outbox, OpenTelemetry |
| `frontend-engineer` | sonnet | Strict TypeScript, one framework, a11y/ARIA, Core Web Vitals (LCP/INP/CLS), forms/async state, XSS and token safety, component + E2E tests |
| `qa-engineer` | sonnet | Test pyramid, acceptance tests before build, contract tests (Pact/OpenAPI), property-based tests for logic-heavy code, mutation testing on critical modules, Playwright (role locators, web-first assertions), flake control |
| `reviewer` | sonnet (opus if risky), read-only | Diff review against the craft charter |
| `security-engineer` | sonnet, read-only | STRIDE at design, OWASP Top 10/ASVS, SAST/SCA/secrets, authN/Z |
| `devops-engineer`, `mobile-engineer`, `ux-designer`, `tech-writer` | sonnet / haiku | Conditional |
| `researcher` | haiku, read-only | Onboarding scan; stack skill refresh |

Playbook content is **written fresh for the plugin** (inspired by, not copied from, tools installed on your machine, since those won't exist elsewhere and licences vary). The built-in `/simplify` is not used: it spawns its own parallel agents and would break the caps.

## 9. Hooks (every script exits fast unless this session owns an engaged `.devteam/`)
| Hook | Event | Blocks? | Purpose |
|---|---|---|---|
| guard | PreToolUse `Agent|Task` | Yes | spawn rules, fork/general-purpose denial, spawn count |
| state-protect | PreToolUse `Edit|Write` with `agent_id` | Yes | subagents can't write state/criteria/board |
| git-guard | PreToolUse `Bash` with `agent_id` | Yes | classifies git commands by tier; enforces role matrix and goal grant (6a); no push/deploy from subagents |
| route | UserPromptSubmit | No | IDLE-only new-goal hint |
| lint-file | PostToolUse `Edit|Write` | No | per-file lint report |
| finish-gate | SubagentStop | Yes | format, typecheck, tests; retry count |
| turn-count | Stop | No | main-thread turns vs lane cap |
| compact-reinject | SessionStart `compact` | No | ≤20-line state digest |
| ledger | SubagentStop / Stop | No | usage log |
| checksum | all hooks | Sets BLOCKED | detects tampering with protected files |

Scoping rules: each hook uses `if` or a tight matcher so it never launches for unrelated tool calls; the first line of every script is the engaged-session check; only `if`-narrowed hooks use `onFailure: "block"`. The broad `guard` (all `Agent` spawns) is self-tested at engage time rather than fail-closed, so a broken install can't block spawns in sessions that never engaged the team.

## 10. What we adopt from comparable open-source projects
Research agents read READMEs/docs of ~25 projects. Star counts and vendor benchmarks are unverified; the design relies on **mechanisms**, not popularity.

| Adopt | From |
|---|---|
| Brief + report files, status codes, fresh context per task, bounded fix rounds, orchestrator never fixes code | obra/superpowers |
| Outcome + exclusions contract; approvals at design/plan/scope; reviewers read docs not chat; Lite mode | shinpr/claude-code-workflows |
| Independent verification, hook-enforced gates, escalate after 3 failures, durable on-disk state | dsifry/metaswarm |
| Evidence receipts reused by later stages | garrytan/gstack |
| Single-owner files, ≤4 parallel, plan-first approval | wshobson/agents |
| Artifact-per-role; test-retry cap of 3 | MetaGPT |
| One terminating authority | ChatDev + MAST |
| Append-only event log; stuck detection; confirm only risky actions | OpenHands |
| Progress ledger with stall/reset caps | Microsoft Magentic |
| Abort failing runs early; simplicity | SWE-agent / mini-swe-agent |
| Strong planner + cheaper editor | Aider |
| EARS criteria; archive each goal | Kiro, Spec Kit, OpenSpec |
| Script-decided done, distinct exit states, turn caps; JSON criteria with agent-writable `passes` only | Ralph critique, `/goal`, Anthropic harness post |
| Subagent returns ~1–2k tokens max; just-in-time loading | Anthropic context-engineering posts |

**Avoid:** full ceremony on small goals (BMAD, Spec Kit, Kiro); LLM-managed routing (CrewAI, LangGraph); peer-messaging agent teams by default (~7× tokens); self-declared "done" and unbounded loops; build+review on every task and review ping-pong (≈59% of ChatDev tokens); persona/skill sprawl and unmeasured savings claims (VoltAgent, ruflo, SuperClaude); parallel agents with implicit conflicting decisions (Cognition); unvetted hooks/repos.

## 11. Release plan, acceptance and spike
**Spike first (throwaway repo; verify rather than assume):**
(a) `PreToolUse` on `Agent`: real input shape (subagent type, fork, general-purpose). (b) `UserPromptSubmit`: `additionalContext`, `session_id`, and how agent reports/scheduled/cross-session turns look. (c) `SessionStart` `compact` re-inject. (d) `agent_id` on a subagent's `Edit` to `state.json`. (e) `baseRef: "head"` worktree contents; isolated write to the main checkout blocked. (f) plugin `hooks.json` fires `SubagentStop`. (g) plugin-agent `memory` location, including inside worktrees. (h) empty-worktree auto-removal and what survives. (i) hook start-up time on macOS and `onFailure: "block"` behaviour. (j) plain-session baseline ×3. (k) the Agent tool's `model` and `effort` parameters override a plugin agent's frontmatter `model` and `effort`, and which model aliases and effort levels your account offers. (l) `agent_type` and `agent_id` in `PreToolUse` `Bash` input from a subagent, and whether agent `tools` accept command patterns such as `Bash(git diff *)`. (m) `experimental.cacheTtl: 1h` on engineer agents (ledger decides if worth it). (n) the hook `if` field for narrowing, and `onFailure: "block"` behaviour when a script is missing or non-executable. (o) PM mode (`claude --agent devteam:project-manager`): the system-prompt replacement, preloaded skills, tool access, and that the main thread uses the agent's model and effort. (p) `SendMessage` to a completed Architect resumes it with its context intact and reports back to the main thread, for the layer-2 answer path.

**v0.1 Core loop** — manifest, state machine, session ownership, guard/protect/finish/turn-count/compact hooks, `start` (with the one-time model-choice prompt)/`goal/status/pause/stop/amend/changemodels`, `criteria.json` + hash-locked acceptance tests + close-gate script, `orchestrate` (tiny + standard lanes, **engineers one at a time**), the **lifecycle schema + selector table + `direct`, `agile-kanban`, `agile-scrum`, `waterfall` profiles** (they only reshape phases and PM bookkeeping, so need no new roles), Architect (brief only), `fullstack-engineer`, QA, Reviewer, preflight and trust prompts.
*Acceptance:* (1) no goal → zero spawns; a forced spawn is blocked. (2) tiny fix → 0 spawns, close gate passes, restored branch. (3) standard goal → exactly three planned stops (intake, combined confirmation, close-out); the Architect brief is shown without waiting, and `/devteam:pause` or `/devteam:amend` during the run works; each exception stop in 2b triggers when forced. (4) failing tests → ≤3 retries then BLOCKED and asks you. (5) criteria pass by script → IDLE, nothing running, next prompt = new goal. (6) subagent can't write `state.json`; a Bash tamper is detected. (7) engineer weakening an acceptance test fails verification. (8) a second session in the same repo is not routed. (9) hooks exit fast when not engaged (measured). (10) cost ratios measured on ≥3 runs per lane. (11) seeded-slop fixture: net LOC ≤1.3× a minimal reference diff and stray files are caught at merge. (12) the model prompt appears only on the first start in a project with "recommended" pre-selected; accepting it needs no model input; later starts and goals never re-ask; `/devteam:changemodels` works in any state, lets you select members, then set model and effort, shows an old → new table before saving, and applies from the next spawn without interrupting a running agent; recommended and custom choices each produce the matching `model` and `effort` on every spawn in the ledger. (13) with no grant, an engineer's `git commit` is denied and the PM asks you; a Reviewer/Architect/Security agent can never write to git; commits to your original branch are impossible; remote and destructive git always prompt with the exact command; the original branch SHA is unchanged at close; the tiny lane leaves changes uncommitted until you approve a commit. (14) a gate whose exact tree hash already passed is skipped (the ledger shows the cache hit) and the full suite runs once before close. (15) after onboarding approves the allow-list, a standard goal runs to close without stopping on any listed command. (16) with the plugin installed but never engaged, hooks add no measurable delay and a missing script doesn't block unrelated sessions. (17) for a standard goal with an ambiguous non-functional requirement, ≤3 Architect questions appear in the intake batch each with a recommended answer and cause no extra stop and no spawn; "go with your recommendations" proceeds; a blocking mid-design ambiguity produces exactly one extra batched prompt and the Architect resumes with the answers; skipping logs assumptions to the ADR. (18) on five fixture goals (unclear greenfield product, fixed regulated spec, pipeline/deploy goal, bug stream, high-risk research-like change) the PM suggests the expected lifecycle with reasons and asks you to choose (recommendation pre-selected, runner-up, "show all", or type any name) as one question in the combined confirmation, your choice is honoured, a lifecycle named in your prompt skips the question, and the ledger shows only the chosen profile was read; a custom profile file works with no code change; `/devteam:lifecycle` mid-goal re-plans only the remaining tasks; no lifecycle adds a planned stop unless `lifecycle.phaseStops` is on.

**v0.2 Parallel build** — worktrees, integration branch, merge script, tiny-goal interrupt, backend/frontend engineers, Security (conditional). (The allow-list onboarding moves to v0.1.) *Acceptance:* two disjoint tasks merge cleanly in order; conflict path works; stop leaves no orphan worktrees; prompts bounded.

**v0.3 Intelligence** — `onboard` + Researcher + approved skill packs, `discuss`, agent memory (non-read-only roles), DevOps/UX/Writer/Mobile, and the remaining lifecycles (`devops`, `v-model`, `spiral`, `prototype`) plus custom profiles via `.devteam/lifecycles/`. *Acceptance:* a contested decision ends in ≤2 rounds with an ADR; an unapproved pack is never loaded.

**v1.0 Hardening** — `claude plugin validate`, `claude plugin eval`, README documenting every hook, optional publish. Add roles only when the ledger shows they pay off.

## 12. Plugin layout (new repo at `Dev-team/`)
```
Dev-team/
├─ .claude-plugin/marketplace.json
└─ plugins/devteam/
   ├─ .claude-plugin/plugin.json      # name, version, min Claude Code version, userConfig (models, caps, soft limits)
   ├─ agents/*.md                     # ≤60 lines; model, effort, tools allowlist, maxTurns, omitClaudeMd, skills (preload), isolation (engineers)
   ├─ skills/  start goal amend status pause stop ask onboard changemodels lifecycle architect-intake orchestrate discuss refresh-skills
   │           playbooks/ craft.md + <role>.md
   ├─ hooks/hooks.json + scripts/     # section 9
   ├─ lifecycles/                     # one ≤40-line profile per methodology (3a)
   ├─ templates/                      # goal.md, criteria.json, plan.md, board.md, adr.md, discussion.md, profile.md
   └─ README.md
```
Per project (gitignored): `.devteam/{config.json,state.json,log.jsonl,profile.md,standards.md,trust.json,skills/,goals/G-00N/{goal.md,criteria.json,plan.md,board.md,evidence/},adr/,discussions/,reports/}`.

## 13. Risks and open questions
- Plugin agents ignore `permissionMode`/`hooks`/`mcpServers`; your permission mode governs. Permission rules, not hooks, are the hard deny.
- Nesting-depth default changed across versions; design needs depth ≤2.
- Agent-teams mode is experimental and interactive-only; deferred.
- Multi-agent costs far more than a single session (Anthropic: ~15× vs chat) and is weakest on tightly coupled coding. No controlled benchmark of Claude Code subagents on/off exists, so we measure ourselves.
- `/goal` overlap: optional transcript-only backstop for `--autonomous`, never the verifier.
- Several behaviours (section 11 spike a–i) are unverified; the design is deliberately arranged so each has a documented fallback.

## 14. Decisions confirmed at review
1. MVP-first release plan instead of building the whole roster at once.
2. PM-mediated discussion (no peer messaging between engineers/QA/reviewer).
3. Opt-in engagement via `/devteam:start`; one goal at a time; others queued.
4. Onboarding may propose project-settings edits (`worktree.baseRef`, allow/ask rules), always with your approval.
5. Requires Claude Code ≥2.1.295 (you'd update from 2.1.289), macOS/Linux first.
6. `.devteam/` is gitignored by default; optional archive commit.
7. Git repo with a commit and a clean tree (ignoring `.devteam/`) at goal start.
8. Model prompt asked once per project at the first start (recommended pre-selected, custom opt-in), plus `/devteam:changemodels` any time (choose members, then model and effort), as you asked. If "once" should instead mean once per user across all projects, say so and the choice moves to a user-level setting.
9. Git local writes are granted **once per goal in the combined confirmation** (default) rather than prompted per command; set `git.localWrites: "per-action"` for a prompt on every commit/branch/merge. Remote and destructive git always prompt each time.
10. Gates reduced to three planned stops (you chose "minimum stops"): the Architect brief no longer waits for approval, so a poor design can run until you notice or an exception stop fires. The brief is summarised to you immediately and the exception list (2b) is the safety net.
11. PM mode (`claude --agent devteam:project-manager`) is offered, not forced, when your session model is a top tier; the PM prompt then has to stand on its own because it replaces the default system prompt.
12. Architect questions at intake run in the main thread on the PM's model (cheap, no spawn) rather than via a spawned Architect on `opus`; only a mid-design blocking question resumes the real Architect. If you want every Architect question to come from the `opus` agent, it costs one spawn before you confirm the contract.
13. The lifecycle is suggested by a fixed selector table and chosen by you as an explicit question (no free-form LLM choice), and ceremonies are task- and budget-based bookkeeping rather than calendar sprints or multi-agent meetings. Phase boundaries are report-only unless you turn on `lifecycle.phaseStops` for sign-off flows.

## Sources
- Claude Code docs (code.claude.com/docs/en/): hooks, sub-agents, worktrees, agent-teams, plugins/components, manifest-reference, goal, costs
- Anthropic engineering: multi-agent-research-system, effective-context-engineering-for-ai-agents, writing-tools-for-agents, effective-harnesses-for-long-running-agents
- arxiv.org/abs/2503.13657 (MAST), 2308.00352 (MetaGPT), 2405.15793 (SWE-agent)
- GitHub: obra/superpowers, shinpr/claude-code-workflows, dsifry/metaswarm, garrytan/gstack, wshobson/agents, bmad-code-org/BMAD-METHOD, github/spec-kit, Fission-AI/OpenSpec, OpenHands/OpenHands, FoundationAgents/MetaGPT, OpenBMB/ChatDev, crewAIInc/crewAI, Aider-AI/aider
- Role-skill sources are practitioner/training sites (guidance, not standards).
