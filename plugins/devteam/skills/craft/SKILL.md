---
name: craft
description: Craft charter for devteam agents: minimal, modular, no-slop code rules.
user-invocable: false
---
# Craft charter (every line must earn its place)

1. **Smallest change** that meets a done-criterion. Every added line traces to a criterion or to the task brief.
2. **Reuse before write.** Search for an existing helper or pattern and extend it. The project's conventions beat your preferences.
3. **No speculative generality.** No abstraction with one caller, no config for a fixed value, no unused parameter or export, no "future-proofing".
4. **Modular.** One responsibility per module and function, a narrow public interface, dependencies flowing one way, no reaching into another module's internals. Soft signals (advisory): function ~40 lines, file ~300, params <= 4.
5. **Crisp.** Names carry meaning. Comment only the non-obvious *why*. No commented-out code, TODO stubs, placeholders or boilerplate docstrings.
6. **Errors.** Handle failures that can really happen at boundaries (I/O, user input, network). No defence against impossible states. Never swallow an error.
7. **No extra files.** No README, script, scaffolding or example unless a criterion asks. Tests only for criteria, bugs and boundaries, never for implementation details.
8. **Delete as you go.** Remove dead code your change creates. Prefer deleting to adding.
9. **Report honestly.** Files touched, net lines (+/-), what you reused, what you deleted, and one line of justification for every new file.
10. **Self-simplify.** Before reporting DONE, re-read your diff and cut anything not required.
