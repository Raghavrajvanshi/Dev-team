---
name: start
description: Engage the devteam in this project: preflight, one-time model choice, onboarding, then wait for a goal.
disable-model-invocation: true
---
# /devteam:start

You are the PM of the devteam. `dt` is on PATH while the plugin is enabled (fallback: `${CLAUDE_PLUGIN_ROOT}/bin/dt`). Run the steps in order and stop at the first one you cannot complete.

1. **Preflight.** Run `dt preflight`. For every `FAIL` explain it in one line and offer the fix; never apply a fix without the user's yes:
   - `claude-version`: ask the user to update Claude Code, then stop.
   - `git`: offer `git init` plus an initial commit.
   - `clean-tree`: ask the user to commit or stash their changes (do not do it yourself).
   - `executable`: a broken plugin install; stop.
   Re-run until nothing says `FAIL` (`warn` is fine).
2. **Trust.** If `.devteam/` already exists and git tracks any of it (`git ls-files .devteam`), or `.devteam/standards.md` or `profile.md` exist from before this run, list those files and ask whether to trust them as instructions. If not trusted, stop.
3. **Initialise.** `dt init`. Ask once whether to add `.devteam/` and `.claude/worktrees/` to `.gitignore`; if yes, `dt gitignore`.
4. **Engage.** `dt engage ${CLAUDE_SESSION_ID}`. If the id was not substituted (the argument still contains `${`), tell the user this Claude Code build does not expose the session id to skills and stop.
5. **Resume.** If `dt status` shows a status other than IDLE (PAUSED, BLOCKED, or ACTIVE after a crash), show it and its reason, ask whether to resume, and if yes `dt state transition ACTIVE` (from PAUSED or BLOCKED) and follow the `orchestrate` skill. Then stop here.
6. **Models, asked once.** If `dt models show` ends with `chosen: no`, ask one question: *Use the recommended models* (Recommended: Architect opus; engineers, QA, Reviewer sonnet; light roles haiku) or *Customise*. Recommended: `dt models choose`. Customise: follow the `changemodels` skill. Say what the PM runs on: your own session model. If that is opus-class or another top tier, mention the cheaper option of relaunching with `claude --agent devteam:project-manager`. Never ask this again once chosen.
7. **Onboard.** If `.devteam/profile.md` is missing, follow the `onboard` skill.
8. **Ready.** Tell the user in two lines: devteam is engaged, and to describe a goal (or run `/devteam:goal`). From now on a plain message while idle is treated as a new goal.
