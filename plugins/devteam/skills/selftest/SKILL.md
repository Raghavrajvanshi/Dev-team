---
name: selftest
description: Live self-test in a scratch repo: settles the plugin's assumptions about hooks, agents and skills.
disable-model-invocation: true
---
# selftest

Run this only in a **scratch git repo**, never in a real project. It starts three cheap probe agents and attempts a few actions that must be refused. Its output is a checklist of what Claude Code really does, which is used to fix wrong assumptions. Keep every probe reply as you receive it; do not tidy it.

1. **Setup.** `dt preflight` must pass (if the scratch repo has no commit, offer to make an empty one). Then `dt init`, `dt engage ${CLAUDE_SESSION_ID}`, `dt models choose`, `dt trace clear`, `dt trace on`. Create a throwaway goal without questions: `dt goal new "selftest"`, `dt criteria add --id C1 --text "WHEN the selftest runs THEN it exits 0" --check true`, `dt goal confirm --lane standard --lifecycle direct`.
2. **PATH.** Run `command -v dt`. `dt trace note dt-on-path confirmed "<the path>"`, or `refuted` if it printed nothing.
3. **Guard probes.** Each of these spawns must be **refused**; the refusal is the pass:
   a. the Agent tool with `subagent_type: general-purpose`;
   b. the Agent tool with `subagent_type: devteam:fullstack-engineer` and `isolation: worktree` (no git grant exists).
   Note `guard-live` as `confirmed` only if both were refused with a devteam message; otherwise `refuted` with what happened.
4. **Probe A.** Spawn `devteam:fullstack-engineer`, passing `model: haiku` and `effort: low`, with this brief: *"Selftest probe. Build nothing. Answer each item in one line. (1) The model you are running as, exactly as your system prompt names it. (2) Quote the first six words of rule 1 of the craft charter if it is in your context, else write NOT LOADED. (3) Run the Bash command `git status --short`; did it run? (4) Try to Write the file `.devteam/selftest-probe.txt` containing x; was it denied or allowed, and quote any message. (5) Try the Bash command `git push --dry-run origin main`; was it denied or allowed? Finish with STATUS: DONE."*
5. **Probe B.** Spawn `devteam:reviewer` (no overrides): *"Selftest probe. (1) Quote the first six words of rule 1 of the craft charter if it is in your context, else NOT LOADED. (2) Quote the first three words of the Rubric section of the devteam-design-quality skill if loaded, else NOT LOADED. (3) Try the Bash command `git commit --allow-empty -m probe`; denied or allowed? Finish with STATUS: DONE."*
6. **Probe C.** Spawn `devteam:researcher`: *"Selftest probe. Do not search the web. Quote the first three words of rule 1 of the devteam-research skill if it is in your context, else NOT LOADED. Finish with STATUS: DONE."*
7. **Record verdicts** with `dt trace note <id> confirmed|refuted "<evidence>"`:
   - `skills-preload`: confirmed only if the craft quote is "Smallest change that meets a" in A and B, the Rubric quote is present in B, and C quotes "Reuse before searching"; otherwise refuted, naming what said NOT LOADED.
   - `model-override`: confirmed if A reports a haiku model, else refuted with what it said.
   - `state-protect-live`: confirmed if A's write was denied, refuted if it was allowed.
   - `git-guard-live`: confirmed if A's push and B's commit were both denied.
8. **Report and clean up.** Run `dt trace report` and show it to the user unedited. Then `rm -f .devteam/selftest-probe*.txt`, `dt state transition STOPPED`, `dt state transition IDLE`, `dt disengage`.
9. Tell the user to send you that report, and optionally `dt trace show --tail 60`. Mention one check this skill cannot do: relaunch with `claude --agent devteam:project-manager`, say hello, then run `dt trace note pm-mode confirmed|refuted "<what happened>"`.
