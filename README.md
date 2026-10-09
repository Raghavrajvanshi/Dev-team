# Dev-team

A goal-gated, token-lean software development team for Claude Code, packaged as a plugin (`devteam`) that works in any project.

**Status: design phase.** The plugin is not built yet; nothing here is installable today.

## What it will be

- A **Goal Keeper** asks you to define the goal first. No work starts until you confirm it, and the team stops when the goal is verifiably achieved.
- A **PM / Scrum Master**, an **Architect**, specialist **engineers**, **QA**, a **Reviewer** and conditional **Security / DevOps / UX / Writer** roles, spawned lazily and only when a step needs them.
- The PM suggests the best-fit **lifecycle** (Agile Scrum/Kanban, DevOps, Waterfall, V-model, Spiral, Prototype, or your own) and you choose.
- **You are the highest authority:** amend, pause, stop or change models at any time. Git writes happen only after you have been prompted.
- Token cost and code quality are design goals: minimal, modular, no-slop code, and a usage ledger that measures cost instead of assuming savings.

## Layout (planned)

```
.claude-plugin/marketplace.json
plugins/devteam/   agents, skills, hooks, lifecycles, templates
```

## License

Not yet chosen.
