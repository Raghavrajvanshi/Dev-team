---
name: onboard
description: Build the compact project profile, gate commands and standards, and propose the permission allow-list.
---
# onboard

Run only from IDLE. `dt state transition ONBOARDING` first; `dt state transition IDLE` when done.

1. **Scan cheaply.** List the repo root; read the manifests that exist (package.json, pyproject.toml, Cargo.toml, go.mod, Makefile, composer.json, build.gradle, ...), CI config, test config, and the first 40 lines of the README. Do not read the codebase.
2. **Write `.devteam/profile.md`** from `templates/profile.md` in the plugin (under 150 lines): stack, layout, commands, conventions, test prerequisites, notes. Use only what you saw; write "unknown" rather than guessing.
3. **Set the gates** with `dt gate set`, only for commands that really exist (for example `format="npm run lint"`, `typecheck="npx tsc --noEmit"`, `test="npm test"`, `install="npm ci"`). Set `test_affected` only when you are sure of a related-tests invocation; otherwise leave it empty and the full suite is used. A greenfield project may have none yet; say so, do not invent.
4. **Write `.devteam/standards.md`** (under 60 lines): the project's real conventions, and the rules from `CLAUDE.md` if one exists. First line: `source-hash: <sha256 of CLAUDE.md or none>` (`shasum -a 256 CLAUDE.md`). The `goal` skill regenerates this file when that hash changes.
5. **Propose permissions.** Show the user this addition to `.claude/settings.local.json` and ask before writing it (merge, never overwrite existing keys):
   - `permissions.allow`: each gate command exactly as configured, `Bash(dt *)`, and read/local git: `Bash(git status *)`, `Bash(git diff *)`, `Bash(git log *)`, `Bash(git show *)`, `Bash(git add *)`, `Bash(git commit *)`.
   - `permissions.ask`: `Bash(git push *)`, `Bash(gh pr create *)`, `Bash(gh pr merge *)`.
   Explain: without the allow-list the team stops at every unlisted command, and `/devteam:status` will show `unattended-ready: no`.
6. Report the result in five lines or fewer.
