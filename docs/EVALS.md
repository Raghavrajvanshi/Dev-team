# Evals: does the team pay off?

devteam claims lower token cost and cleaner code than a plain Claude Code session ([DESIGN.md](DESIGN.md), section 4, rule 11). No saving is claimed until it is measured, so this page says how it is measured, what was found, and what is not covered yet.

The measuring tool is `scripts/evals` (a maintainer tool: not part of the plugin, not installed with it). Its cases live in [`evals/`](../evals).

## What is compared

Each case is a small project (a fixture), one goal stated the way a person would state it, and a list of done-criteria that are shell commands. Two arms run the same case in a fresh scratch repository:

| Arm | What runs |
|---|---|
| **team** | The working-tree plugin through `--plugin-dir`, the PM as the main agent (`--agent devteam:project-manager`), driven one scripted answer at a time with `--resume`: the goal, the confirmation (lane, no git grants, the exact criteria), then the close-out. After the third answer it says "Continue." at most twice more. The project is engaged the way `/devteam:start` would leave it: initialised, models chosen, a profile and standards in place, the test gate set. |
| **plain** | A single `claude -p` session with no plugin, given the goal and the same check commands, told to run them before finishing. |

Both arms use the same model for the main thread (`sonnet` unless `--model` says otherwise), the same flags (`--setting-sources project,local`, so neither sees the machine's own plugins, hooks or CLAUDE.md), and the same criteria afterwards. The team's own subagents run on the models `dt models` assigns, as they would for a user.

**Cost** is the session's final `total_cost_usd`: Claude Code's list-price estimate, cumulative across resumed turns, subagents included. It is an estimate of what the calls would cost at list price, not a bill.

**A run passes** when every non-manual criterion's command exits 0 on the final working tree, and, for the team arm, the goal also ended `verified`. The median cost of a case is taken over the runs that passed; a run that did not do the job is counted and shown, never averaged in. The ratio is the team's median over the plain median.

**Targets** (design section 4): tiny lane at most 1.3x the plain session, standard at most 2.5x. The seeded-slop fixture adds two more: the diff is at most 1.3x the size of a minimal reference patch, and it adds no file outside the reference's footprint (a new test file is allowed).

Diff size is lines added plus lines deleted against the starting commit, with `.devteam/`, `.claude/` and interpreter droppings left out.

## The cases

| Case | Kind | Lane | What it tests |
|---|---|---|---|
| `tiny-fix` | goal | tiny | A one-line bug fix with a test. The cheapest honest comparison: the team's tiny lane spawns nothing. |
| `standard-feature` | goal | standard | A new CLI command across two modules and their tests. |
| `slop-fixture` | goal | standard | One small addition where a ready helper exists, a near-duplicate helper sits beside it, and a TODO invites scope creep. Measures how far the diff strays from the smallest correct change. |
| `no-goal` | inert | none | The team is engaged and idle, the user asks a plain question. Nothing may be spawned or started; the cost gap against the plain session is the plugin's always-on price. |
| `tamper-attempt` | tamper | tiny | After the goal is confirmed, a criterion's check is rewritten to `true` outside `dt`. The team has to notice, and the goal must not close as verified. Team arm only. |

`scripts/evals check` proves, without any model call, that every case can fail and can pass: each non-regression criterion fails on the fixture, every criterion passes once the reference patch is applied, and the patch touches nothing outside its own footprint. A criterion that cannot fail is refused. (It caught one while this was being written: an empty-output check that passed when the command did not exist.) The same check runs in the offline suite (`tests/evals.t`, which also exercises the runner against a fake `claude`).

## Running it

```bash
scripts/evals list
scripts/evals check                                  # offline, free
scripts/evals run all --runs 3 --budget 40 --yes     # real sessions on your account
scripts/evals report                                 # the latest results directory
scripts/evals report --write docs/EVALS.md           # rewrite the results block below
```

`run` refuses without `--yes` and never starts a session past `--budget` (checked between runs; one call is capped at $8). A whole default set is 3 runs of 5 cases in both arms, tens of dollars at list price. Results go to `evals/results/<timestamp>-v<version>/`, one small JSON file per run plus `summary.json`; the raw transcripts and ledgers stay in a temporary directory whose path is printed.

`report DIR_OLD DIR_NEW` prints the change in cost ratio per case between two runs and flags a worsening of more than 10%, which is how a release can be compared with the last before it ships.

## What it adopts from `claude plugin eval`, and what it does not

Claude Code ships `claude plugin eval` (v2.1.269 and later), which runs a plugin's `evals/` cases in isolated non-interactive sessions, repeats them with no plugin loaded, scores them with `regex`, `tool_used`, `tool_order`, `file_exists`, `llm` and `baseline` graders, and exits non-zero under a threshold. Adopted from it: runs repeated three times by default and compared with a no-plugin baseline, a versioned JSON result per run, a cost ceiling, a threshold exit code, and the advice to pin the model.

It is not the runner here because a case there is one prompt in an empty workspace with no way to answer a question mid-run, and a devteam goal is a conversation (intake, confirmation, close-out), driven as the PM agent, whose cost includes subagents. Its isolation (`--setting-sources`-style cleanliness) is reproduced with flags. A natural next use of it is a skill-trigger suite (does `/devteam:goal` fire on natural phrasing), which is a different question from this page's.

## Reading the results with care

- **Small tasks, one stack.** Every case is a few lines of Python. The ratios say what the team costs on goals this size; they do not say what it costs on a large codebase, where a plain session also pays more.
- **Steady state.** The one-time onboarding scan is excluded (the profile and standards are written in advance); the team's first goal in a project costs more than a later one.
- **Noise.** Three runs per case is the minimum the plan asks for, not a confidence interval. A model rollout moves the numbers; compare runs of the same model.
- **List-price estimates**, from Claude Code's own accounting.
- **The team arm is scripted.** A person answering interactively asks and answers differently; only the three answers are held constant.

## Not covered yet

- A user-facing page scored on the design-quality rubric (needs a neutral judge for both arms and a screenshot capture; the register keeps it owed).
- The large lane, and goals long enough to hit the compaction path.
- Interactive use and Windows: the harness is a maintainer tool for macOS and Linux.
- Whether a bounded discussion or the three-lens review gate improves outcomes: these need cases built around a contested decision and a risky diff (the closure report already prices both).

## Results

<!-- evals:begin -->
No runs are recorded yet. `scripts/evals run all --runs 3 --yes` writes them, and `scripts/evals report --write docs/EVALS.md` fills this block.
<!-- evals:end -->
