---
name: changemodels
description: Choose which team members to change and set their model and effort.
---
# changemodels

Works in any state. The change applies from the next spawn and never interrupts a running agent.

1. Show the table: `dt models show` (member, model, effort, recommended or custom, and the person's name). The user may name members by first name (Priya, Marcus, ...); `dt models set` accepts names or role ids.
2. Ask which members to change (AskUserQuestion, multi-select): *Architect*; *Engineers* (fullstack, backend, frontend, mobile, devops); *QA, Reviewer, Security, Verifier*; *Researcher, Writer, UX*. "Other" lets the user name individual members.
3. Ask, in one call, the **model** (Recommended = restore the default, opus, sonnet, haiku; "Other" accepts `inherit`) and the **effort** (Recommended = restore the default, low, medium, high; "Other" accepts `xhigh` or `max`). If the user wants different values per member, repeat for each.
4. Show old to new for the affected members, with the price hint (`prices` in config: opus 5, sonnet 1, haiku 0.25 relative per token), and ask the user to confirm.
5. Apply: `dt models set <member,member> --model M --effort E` (use `recommended` to restore). `dt models show` to confirm.
6. Remind the user that the PM itself runs on the session model (`/model` changes it) and that `claude --agent devteam:project-manager` runs the PM on its own cheaper default.
