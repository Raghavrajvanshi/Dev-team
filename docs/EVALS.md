# Evals: does the team pay off?

devteam claims lower token cost and cleaner code than a plain Claude Code session ([DESIGN.md](DESIGN.md), section 4, rule 11). No saving is claimed until it is measured, so this page says how it is measured, what was found, and what is not covered yet.

The measuring tool is `scripts/evals` (a maintainer tool: not part of the plugin, not installed with it). Its cases live in [`evals/`](../evals).

## What was found (v0.2.17, five runs per case, Sonnet main thread)

Every goal passed in both arms (5 of 5, every case), so this is a comparison of cost and shape, not of correctness. The full table is under [Results](#results).

| Case | Team median | Plain median | Ratio | Target |
|---|---|---|---|---|
| `tiny-fix` (tiny lane) | $0.14 | $0.06 | 2.4x | 1.3x |
| `slop-fixture` (tiny lane) | $0.17 | $0.05 | 3.4x | 1.3x |
| `standard-feature` (standard lane) | $0.47 | $0.07 | 6.7x | 2.5x |
| `larger-feature` (standard lane) | $0.78 | $0.08 | 9.9x | 2.5x |
| `slop-fixture` forced into the standard lane | $0.47 | $0.05 | 9.5x | 2.5x |
| `no-goal` (idle team, plain question) | $0.03 | $0.04 | 0.86x | no spawns |
| `tamper-attempt` | $0.19 | n/a | caught 5 of 5 | not verified |

**The cost targets are missed on every goal, and by more as the goal grows.** The plain session's cost barely moves with the size of the change ($0.06 for the one-line fix, $0.08 for the 92-line feature: it writes the code, runs the checks and stops in 3 to 5 turns). The team's cost grows with the ceremony it runs, so the ratio gets worse, not better, against a bigger goal. A plain session finished in 15 to 25 seconds; the team took 30 to 320.

**Where the cost goes is the PM's own thread.** The PM took 13 to 26 API turns on a goal where the plain session took 3 to 5, and each turn re-reads the PM's whole context (about 30,000 tokens of always-on text, skills and the conversation so far). In the tiny lane the PM is all of the cost. In the standard lane the PM is 28 to 42% of the weighted token use and the five or so spawns are the rest (each starts cold with its own context).

**The team's code is the same as the plain session's.** The smallest correct change was 11 lines of code for `standard-feature`, 9 for `slop-fixture`, 2 for `tiny-fix`; both arms wrote exactly that. What makes the team's diff larger is tests: 39 test lines against 15 in `standard-feature`, 132 against 39 in `larger-feature` (the reference has 38). The QA role writes boundary tests the plain session does not; whether they are worth their lines is a judgement the criteria cannot make.

**The seeded-slop fixture did not provoke slop in either arm.** Neither arm added a file, reused anything but the ready helper, touched the near-duplicate or acted on the TODO, in any of 20 runs. So it cannot say whether the finish gate and the reviewer would catch slop that is there. What it does say, on this evidence: nothing in the code needed a per-edit lint hook or a complexity-budget flag, and the one place the team over-produces (test volume) is not something either would catch. The decision, for now, is not to build them; a harder fixture is the way to reopen it.

**Stray files.** A plain session left an empty `ordcount.py` behind in 3 of 5 `tiny-fix` runs: `sed -i 's/…/…/' wordcount.py` is read by macOS's BSD `sed` as a script `wordcount.py`, and its `w` command writes a file named `ordcount.py`. None of the team's 5 runs did. In a pilot set that is not part of these results the team's own PM made the same slip once, its scope check flagged the file, and it stopped to ask which to do, which is the behaviour the rules ask for.

**Tampering is caught.** After confirmation the harness rewrote criterion C1's check to `true` outside `dt`. In 5 of 5 runs the next hook put the goal in BLOCKED, the PM said exactly what had changed and why it mattered, refused to run `dt resync` on its own, and the goal never closed as verified.

**An idle team costs nothing extra.** With the team engaged and no goal, a plain question cost 0.86x of the plain session (the PM agent's prompt is smaller than the default one) and spawned nothing in 5 of 5 runs.

**One goal varies a lot.** The same `standard-feature` goal cost $0.31 to $0.56 across five team runs (3 to 5 spawns). A single run says little; the medians here are over five.

### What this does not show

All six goals are a few lines to a few dozen lines of Python. A plain session's cost grows with a task much faster than shown here once it has to find its way through a real codebase; the team's fixed overhead would then be a smaller share, and the ratio better than 10x. These numbers say what the team costs on the small, clear goals people use it for first, not that it costs this much on a large one. A case with a large existing codebase is the next thing to build (see below).

## What is compared

Each case is a small project (a fixture), one goal stated the way a person would state it, and a list of done-criteria that are shell commands. Two arms run the same case in a fresh scratch repository:

| Arm | What runs |
|---|---|
| **team** | The working-tree plugin through `--plugin-dir`, the PM as the main agent (`--agent devteam:project-manager`), driven one scripted answer at a time with `--resume`: the goal, the confirmation (lane, no git grants, the exact criteria), then the close-out. After the third answer, if the goal has not ended, it says "go with your recommendation on whatever is still open, and close the goal" at most twice more (a user who delegates; a blanket "yes" does not answer an either/or question, by the team's own rule). The project is engaged the way `/devteam:start` would leave it: initialised, models chosen, a profile and standards in place, the test gate set. |
| **plain** | A single `claude -p` session with no plugin, given the goal and the same check commands, told to run them before finishing. |

Both arms use the same model for the main thread (`sonnet` unless `--model` says otherwise), the same flags (`--setting-sources project,local`, so neither sees the machine's own plugins, hooks or CLAUDE.md), and the same criteria afterwards. The team's own subagents run on the models `dt models` assigns, as they would for a user.

**Cost** is the session's final `total_cost_usd`: Claude Code's list-price estimate, cumulative across resumed turns, subagents included. It is an estimate of what the calls would cost at list price, not a bill.

**A run passes** when every non-manual criterion's command exits 0 on the final working tree, and, for the team arm, the goal also ended `verified`. The median cost of a case is taken over the runs that passed; a run that did not do the job is counted and shown, never averaged in. The ratio is the team's median over the plain median.

**Targets** (design section 4): tiny lane at most 1.3x the plain session, standard at most 2.5x. The seeded-slop fixture adds two more: the diff is at most 1.3x the size of a minimal reference patch, and it adds no file outside the reference's footprint (a new test file is allowed).

Diff size is lines added plus lines deleted against the starting commit, with `.devteam/`, `.claude/` and interpreter droppings left out, and it is split into code and tests (a path under `tests/`, a `test_*` file or a `*_test.*`/`*.test.*` file is a test) because the two behave differently: the team's code has matched the plain session's, and the extra lines have been tests.

The second table of a report shows where the team's cost goes: spawns, how many API turns the PM's own thread took against the plain session's, and the PM's share of the team's weighted token use from the ledger (input 1, output 5, cache read 0.1, cache write 2, times the model's price family). The PM re-reads its whole context on every turn, so turns, not output, dominate.

## The cases

| Case | Kind | Lane | What it tests |
|---|---|---|---|
| `tiny-fix` | goal | tiny | A one-line bug fix with a test. The cheapest honest comparison: the team's tiny lane spawns nothing. |
| `standard-feature` | goal | standard | A new CLI command across two modules and their tests (a 22-line reference patch). |
| `larger-feature` | goal | standard | CSV export and a validating import on the same project: a new module, the CLI and tests (a 92-line reference patch). Shows whether the team's fixed overhead shrinks against a larger plain-session cost. |
| `slop-fixture` | goal | standard, and again in the tiny lane | One small addition where a ready helper exists, a near-duplicate helper sits beside it, and a TODO invites scope creep. Measures how far the diff strays from the smallest correct change. It is a one-file change the Goal Keeper would size as tiny, so it is measured both ways: forced into the standard lane (what that costs on a goal too small for it) and in the tiny lane. |
| `no-goal` | inert | none | The team is engaged and idle, the user asks a plain question. Nothing may be spawned or started; the cost gap against the plain session is the plugin's always-on price. |
| `tamper-attempt` | tamper | tiny | After the goal is confirmed, a criterion's check is rewritten to `true` outside `dt`. The team has to notice, and the goal must not close as verified. Team arm only. |

`scripts/evals check` proves, without any model call, that every case can fail and can pass: each non-regression criterion fails on the fixture, every criterion passes once the reference patch is applied, and the patch touches nothing outside its own footprint. A criterion that cannot fail is refused. (It caught one while this was being written: an empty-output check that passed when the command did not exist.) The same check runs in the offline suite (`tests/evals.t`, which also exercises the runner against a fake `claude`).

## Running it

```bash
scripts/evals list
scripts/evals check                                  # offline, free
scripts/evals run all --runs 3 --budget 40 --yes     # real sessions on your account
scripts/evals run slop-fixture --lane tiny --yes     # the same case, sized as the Goal Keeper would
scripts/evals report                                 # the latest results directory
scripts/evals report DIR1 DIR2 ...                   # several directories merged into one table
scripts/evals report --write docs/EVALS.md           # rewrite the results block below
scripts/evals report --compare OLD_DIR NEW_DIR       # what changed between two runs
```

`run` refuses without `--yes` and never starts a session past `--budget` (checked between runs; one call is capped at $8). A whole default set is 3 runs of 5 cases in both arms, tens of dollars at list price. Results go to `evals/results/<timestamp>-v<version>/`, one small JSON file per run plus `summary.json`; the raw transcripts and ledgers stay in a temporary directory whose path is printed.

`report --compare OLD NEW` prints the change in cost ratio per case between two runs and flags a worsening of more than 10%, which is how a release can be compared with the last before it ships. The sessions of one set can run in parallel: start one `run` per group of cases with its own `--out`, then merge them with `report`.

## What it adopts from `claude plugin eval`, and what it does not

Claude Code ships `claude plugin eval` (v2.1.269 and later), which runs a plugin's `evals/` cases in isolated non-interactive sessions, repeats them with no plugin loaded, scores them with `regex`, `tool_used`, `tool_order`, `file_exists`, `llm` and `baseline` graders, and exits non-zero under a threshold. Adopted from it: runs repeated three times by default and compared with a no-plugin baseline, a versioned JSON result per run, a cost ceiling, a threshold exit code, and the advice to pin the model.

It is not the runner here because a case there is one prompt in an empty workspace with no way to answer a question mid-run, and a devteam goal is a conversation (intake, confirmation, close-out), driven as the PM agent, whose cost includes subagents. Its isolation (`--setting-sources`-style cleanliness) is reproduced with flags. A natural next use of it is a skill-trigger suite (does `/devteam:goal` fire on natural phrasing), which is a different question from this page's.

## Reading the results with care

- **Small tasks, one stack.** Every case is a few lines of Python. The ratios say what the team costs on goals this size; they do not say what it costs on a large codebase, where a plain session also pays more.
- **Steady state.** The one-time onboarding scan is excluded (the profile and standards are written in advance); the team's first goal in a project costs more than a later one.
- **Noise.** Five runs per case is a small sample, not a confidence interval; the team's cost on one goal ranged from $0.31 to $0.56. The prompt cache moves single numbers too: the first session after a pause pays to write the plugin's context (a first idle-question session cost $0.11, the later ones $0.03). A model rollout moves everything; compare runs of the same model.
- **Runs set aside.** A session the API refused (a usage limit, HTTP 429) or whose setup failed is marked `invalid`, left out of every count and shown as a note under the table; two such runs happened here (a usage limit hit during the last `larger-feature` pair) and that pair was run again.
- **List-price estimates**, from Claude Code's own accounting.
- **The team arm is scripted.** A person answering interactively asks and answers differently; only the three answers are held constant.

## Not covered yet

- A user-facing page scored on the design-quality rubric (needs a neutral judge for both arms and a screenshot capture; the register keeps it owed).
- A large existing codebase (the case that would show whether the ratio improves when the plain session's own cost grows), the large lane, and goals long enough to hit the compaction path.
- Interactive use and Windows: the harness is a maintainer tool for macOS and Linux.
- Whether a bounded discussion or the three-lens review gate improves outcomes: these need cases built around a contested decision and a risky diff (the closure report already prices both).

## Results

<!-- evals:begin -->
### Latest run: v0.2.17, 2026-10-14T10:28:58Z, model sonnet

| Case | Lane | Runs team/plain | Passed team/plain | Median cost team | Median cost plain | Cost ratio | Target | Verdict |
|---|---|---|---|---|---|---|---|---|
| larger-feature | standard | 5/5 | 5/5 | $0.78 | $0.08 | 9.92x | 2.5x | cost: OVER |
| no-goal | none | 5/5 | 5/5 | $0.03 | $0.04 | 0.86x | - | spawns: 0 |
| slop-fixture [standard] | standard | 5/5 | 5/5 | $0.47 | $0.05 | 9.47x | 2.5x | cost: OVER; diff: OVER; stray: none |
| slop-fixture [tiny] | tiny | 5/5 | 5/5 | $0.17 | $0.05 | 3.42x | 1.3x | cost: OVER; diff: within; stray: none |
| standard-feature | standard | 5/5 | 5/5 | $0.47 | $0.07 | 6.73x | 2.5x | cost: OVER |
| tamper-attempt | tiny | 5/0 | 5/0 | $0.19 | - | - | - | tamper: caught |
| tiny-fix | tiny | 5/5 | 5/5 | $0.14 | $0.06 | 2.43x | 1.3x | cost: OVER |

| Case | Spawns | PM turns team (plain) | PM share of team cost | Diff lines team (plain; reference) | of which code | Runs with a stray file, team (plain) |
|---|---|---|---|---|---|---|
| larger-feature | 6 | 26 (4) | 28% | 190 (84; 92) | 58 (45; 54) | 1 (0) of 5 |
| no-goal | 0 | 2 (2) | - | - | - | - |
| slop-fixture [standard] | 5 | 25 (3) | 42% | 24 (16; 13) | 9 (9; 9) | 0 (0) of 5 |
| slop-fixture [tiny] | 0 | 16 (3) | 100% | 16 (16; 13) | 9 (9; 9) | 0 (0) of 5 |
| standard-feature | 5 | 23 (4) | 42% | 50 (26; 22) | 11 (11; 11) | 0 (0) of 5 |
| tamper-attempt | 0 | 18 (-) | 100% | - | - | - |
| tiny-fix | 0 | 13 (4) | 100% | 10 (10; 9) | 2 (2; 2) | 0 (3) of 5 |

2 run(s) were set aside because their setup failed or the API refused the session (not a result for either arm).
<!-- evals:end -->
