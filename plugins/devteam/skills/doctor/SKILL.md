---
name: doctor
description: Check that devteam is installed and working (files, hooks, PATH, versions, project) and say how to fix what is not.
argument-hint: [--offline]
---
# doctor

Run `dt doctor` (add `--offline` to skip its one request to GitHub for the latest release number). It changes nothing in the user's installation. Show its output as it is, then for each `FAIL` or `warn` say in one plain sentence what it means and give its `fix:` line.

- Never run an install, update, uninstall or disable command yourself: show it, and run it only when the user says yes. A change takes effect after Claude Code is restarted.
- `dt` not found: the plugin's `bin/` is not on PATH yet. Restart Claude Code or run `/reload-plugins`; until then run it by its full path (`claude plugin list` shows where the plugin is installed).
- Every check passed but something is still wrong: ask for the output of `/devteam:selftest` in a scratch repository.
