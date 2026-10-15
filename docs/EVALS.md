# Evals: does the team pay off?

devteam claims lower token cost and cleaner code than a plain Claude Code session ([DESIGN.md](DESIGN.md), section 4, rule 11). No saving is claimed until it is measured, so this page says how it is measured, what was found, and what is not covered yet.

The measuring tool is `scripts/evals` (a maintainer tool: not part of the plugin, not installed with it). Its cases live in [`evals/`](../evals).

## What was found (v0.2.18, five runs per case, three for the auto lane, Sonnet main thread)

Every goal passed in both arms, so this compares cost and shape, not correctness. The full table is under [Results](#results). An earlier set (v0.2.17, directories dated 20261014) used a protocol that inflated the team's cost, found by reading where the PM's turns went: the done-criteria were sent in the confirmation message, which made the Goal Keeper discard its own and re-enter them (about five extra PM turns per goal that no real user pays), and the lane was always forced. Its numbers are kept for the record and are superseded by these.

| Case | Lane | Team median | Plain median | Ratio | Target |
|---|---|---|---|---|---|
| `tiny-fix` | tiny | $0.11 | $0.06 | 2.0x | 1.3x |
| `slop-fixture` | tiny | $0.13 | $0.05 | 2.6x | 1.3x |
| `larger-feature` (92-line reference) | auto: tiny, 3 of 3 | $0.18 | $0.08 | 2.3x | 1.3x |
| `slop-fixture` | auto: tiny, 3 of 3 | $0.13 | $0.05 | 2.6x | 1.3x |
| `standard-feature` (22-line reference) | auto: standard, 3 of 3 | $0.48 | $0.07 | 7.0x | 2.5x |
| `standard-feature` | standard (forced) | $0.36 | $0.07 | 5.3x | 2.5x |
| `larger-feature` | standard (forced) | $0.50 | $0.08 | 6.5x | 2.5x |
| `slop-fixture` | standard (forced) | $0.43 | $0.05 | 8.6x | 2.5x |
| `no-goal` (idle team, plain question) | none | $0.03 | $0.04 | 0.87x | no spawns |
| `tamper-attempt` | tiny | $0.16 | n/a | caught 3 of 3 | not verified |

**The cost targets are missed everywhere, and the tiny lane has a floor near 2x.** The plain session finishes in 3 to 4 API turns and about 15 to 25 seconds whatever the goal's size. The team's three stops (intake, confirmation, close-out) are each at least one more request carrying the whole context, so even with no agents it takes 9 to 15 PM turns. The standard lane adds 4 to 5 cold-started agents and 21 to 24 PM turns on top.

**Where the cost goes is the PM's own thread.** Every request re-reads the PM's context, which grows from about 20,000 to 50,000 tokens over a goal; in the tiny lane that thread is all of the cost, in the standard lane it is 28 to 50% and the agents are the rest. The Claude Code cost guidance says the same: each tool call is another request that carries the full conversation.

**The Goal Keeper's sizing is inconsistent with the size of the goal.** Left to choose, it picked the tiny lane for the 92-line multi-file feature in all 3 runs and the standard lane for the 22-line feature in all 3 runs: the smaller change got the heavier process, a 2.5x difference in cost for the same plain-session price.

**The "goal first" rule is advisory while the team is idle.** In 4 of the 16 tiny-lane goal runs the PM made the whole change in its first turn ("Tiny and fully specified; I'll do it directly"), before any goal existed, then opened a goal in the next turn and closed it as verified against criteria that the finished code already met. The `route` hook only injects a reminder and nothing blocks an edit while idle. In 9 of the 34 goal runs the PM confirmed the contract itself in the first turn, treating the user's explicit spec as the confirmation. Both are cheaper than the full flow, which is part of why the tiny numbers look better than they would if the intake were enforced.

**The team's code is the same size as the plain session's** on the small cases (2, 9 and 11 lines on three cases, in both arms); the extra diff is tests (39 lines against 15 for `standard-feature`). On `larger-feature` forced into the standard lane the team wrote 59 lines of code against 43 for the plain session and 54 in the reference, and 86 lines of tests against 40.

**The seeded-slop fixture provoked no slop in either arm** in all 26 slop-fixture runs of this set (no new file, the near-duplicate helper and the TODO untouched), so it cannot say whether the finish gate and the reviewer catch slop that is there. On this evidence the per-edit lint hook and the complexity-budget flag are not needed, and neither would catch the extra test volume. A harder fixture reopens it.

**Stray files.** A plain session left an empty `ordcount.py` in 4 of 5 `tiny-fix` runs: `sed -i 's/…/…/' wordcount.py` is read by macOS's BSD `sed` as a script `wordcount.py`, whose `w` command writes a file called `ordcount.py`. None of the team's runs did; in a pilot set the team's own PM made the same slip once and its scope check flagged the file and asked.

**Tampering is caught.** After confirmation the harness rewrote criterion C1's check to `true` outside `dt`: 3 of 3 runs in this set (and 5 of 5 under the earlier protocol) ended BLOCKED and never verified, with the PM saying what had changed and not resyncing on its own.

**An idle team costs nothing extra.** A plain question to an engaged, idle team cost 0.87x of a plain session and spawned nothing in 5 of 5 runs.

**One goal varies a lot.** The team's cost on `standard-feature` ranged from $0.24 to $0.59 across 8 runs (2 to 5 spawns). A single run says little.

### What this does not show

All six goals are a few lines to a few dozen lines of Python. A plain session's cost grows much faster with a task once it has to find its way through a real codebase, and the team's fixed overhead would then be a smaller share. These numbers say what the team costs on the small, clear goals people use it for first, not on a large one. A case on a large existing codebase is the next thing to build (see below).

## What is compared

Each case is a small project (a fixture), one goal stated the way a person would state it, and a list of done-criteria that are shell commands. Two arms run the same case in a fresh scratch repository:

| Arm | What runs |
|---|---|
| **team** | The working-tree plugin through `--plugin-dir`, the PM as the main agent (`--agent devteam:project-manager`), driven one scripted answer at a time with `--resume`: the goal with its done-criteria (and the lane, unless the lane is `auto`), the confirmation (no git grants, the criteria kept as listed), then the close-out. After the third answer, if the goal has not ended, it says "go with your recommendation on whatever is still open, and close the goal" at most twice more (a user who delegates; a blanket "yes" does not answer an either/or question, by the team's own rule). The project is engaged the way `/devteam:start` would leave it: initialised, models chosen, a profile and standards in place, the test gate set. |
| **plain** | A single `claude -p` session with no plugin, given the goal and the same check commands, told to run them before finishing. |

Both arms use the same model for the main thread (`sonnet` unless `--model` says otherwise), the same flags (`--setting-sources project,local`, so neither sees the machine's own plugins, hooks or CLAUDE.md), and the same criteria afterwards. The team's own subagents run on the models `dt models` assigns, as they would for a user.

**Cost** is the session's final `total_cost_usd`: Claude Code's list-price estimate, cumulative across resumed turns, subagents included. It is an estimate of what the calls would cost at list price, not a bill.

**A run passes** when every non-manual criterion's command exits 0 on the final working tree, and, for the team arm, the goal also ended `verified`. The median cost of a case is taken over the runs that passed; a run that did not do the job is counted and shown, never averaged in. The ratio is the team's median over the plain median.

**Targets** (design section 4, guesses to validate): tiny lane at most 1.3x the plain session, standard at most 2.5x; a run in the auto lane is held to the target of the lane the Goal Keeper chose. The seeded-slop fixture adds two more: the diff is at most 1.3x the size of a minimal reference patch, and it adds no file outside the reference's footprint (a new test file is allowed).

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
- **Noise.** Five runs per case is a small sample, not a confidence interval; the team's cost on one goal ranged from $0.24 to $0.59. The prompt cache moves single numbers too: the first session after a pause pays to write the plugin's context (a first idle-question session cost $0.11, the later ones $0.03). A model rollout moves everything; compare runs of the same model.
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
### Latest run: v0.2.18, 2026-10-15T13:39:20Z, model sonnet

| Case | Lane | Runs team/plain | Passed team/plain | Median cost team | Median cost plain | Cost ratio | Target | Verdict |
|---|---|---|---|---|---|---|---|---|
| larger-feature [auto] | auto (tiny 3) | 3/3 | 3/3 | $0.18 | $0.08 | 2.30x | 1.3x | cost: OVER |
| larger-feature [standard] | standard | 5/5 | 5/5 | $0.50 | $0.08 | 6.50x | 2.5x | cost: OVER |
| no-goal | none | 5/5 | 5/5 | $0.03 | $0.04 | 0.87x | - | spawns: 0 |
| slop-fixture [auto] | auto (tiny 3) | 3/3 | 3/3 | $0.13 | $0.05 | 2.58x | 1.3x | cost: OVER; diff: within; stray: none |
| slop-fixture [standard] | standard | 5/5 | 5/5 | $0.43 | $0.05 | 8.63x | 2.5x | cost: OVER; diff: OVER; stray: none |
| slop-fixture [tiny] | tiny | 5/5 | 5/5 | $0.13 | $0.05 | 2.57x | 1.3x | cost: OVER; diff: within; stray: none |
| standard-feature [auto] | auto (standard 3) | 3/3 | 3/3 | $0.48 | $0.07 | 6.96x | 2.5x | cost: OVER |
| standard-feature [standard] | standard | 5/5 | 5/5 | $0.36 | $0.07 | 5.34x | 2.5x | cost: OVER |
| tamper-attempt | tiny | 3/0 | 3/0 | $0.16 | - | - | - | tamper: caught |
| tiny-fix | tiny | 5/5 | 5/5 | $0.11 | $0.06 | 2.03x | 1.3x | cost: OVER |

| Case | Spawns | PM turns team (plain) | PM share of team cost | Diff lines team (plain; reference) | of which code | Runs with a stray file, team (plain) |
|---|---|---|---|---|---|---|
| larger-feature [auto] | 0 | 15 (4) | 100% | 82 (83; 92) | 42 (45; 54) | 0 (0) of 3 |
| larger-feature [standard] | 4 | 24 (4) | 34% | 145 (83; 92) | 59 (43; 54) | 0 (0) of 5 |
| no-goal | 0 | 2 (2) | - | - | - | - |
| slop-fixture [auto] | 0 | 11 (3) | 100% | 16 (16; 13) | 9 (9; 9) | 0 (0) of 3 |
| slop-fixture [standard] | 5 | 21 (3) | 34% | 21 (16; 13) | 5 (9; 9) | 0 (0) of 5 |
| slop-fixture [tiny] | 0 | 11 (3) | 100% | 16 (16; 13) | 9 (9; 9) | 0 (0) of 5 |
| standard-feature [auto] | 5 | 21 (4) | 28% | 43 (26; 22) | 11 (11; 11) | 0 (0) of 3 |
| standard-feature [standard] | 4 | 21 (4) | 50% | 52 (23; 22) | 11 (11; 11) | 0 (0) of 5 |
| tamper-attempt | 0 | 14 (-) | 100% | - | - | - |
| tiny-fix | 0 | 9 (4) | 100% | 10 (10; 9) | 2 (2; 2) | 0 (4) of 5 |

### History (cost ratio team / plain, medians)

| Run | Version | larger-feature | larger-feature [auto] | larger-feature [standard] | slop-fixture [auto] | slop-fixture [standard] | slop-fixture [tiny] | standard-feature | standard-feature [auto] | standard-feature [standard] | tiny-fix |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 20261014-v0.2.17 | v0.2.17 | 9.92x | - | - | - | 9.47x | 3.42x | 6.73x | - | - | 2.43x |
| 20261015-v0.2.18 | v0.2.18 | - | 2.30x | 6.50x | 2.58x | 8.63x | 2.57x | - | 6.96x | 5.34x | 2.03x |
<!-- evals:end -->
