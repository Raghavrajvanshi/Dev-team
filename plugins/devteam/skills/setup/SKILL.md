---
name: setup
description: One-time project setup: the model choice and the project scan. Skips what is done.
---
# setup

`dt status` ends with `setup: complete`, or `setup: incomplete (...)` naming what is missing. Do only the missing parts, then return to whoever called you.

1. **Models, asked once.** If `models chosen: no`, ask one question: *Use the recommended models* (Recommended: Architect opus; engineers, QA, Reviewer sonnet; light roles haiku) or *Customise*. Recommended: `dt models choose`. Customise: invoke the `changemodels` skill with the Skill tool (do not replicate its steps by hand). Mention what the PM runs on: your own session model. If that is opus-class or another top tier, mention the cheaper option of relaunching with `claude --agent devteam:project-manager`. Never ask this again once chosen.
2. **Onboard.** If there is no project profile or standards file, invoke the `onboard` skill.
3. Run `dt status` once more and confirm `setup: complete`.
