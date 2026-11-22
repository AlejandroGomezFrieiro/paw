# The plain-writing skill in paw

This note is paw's. SKILL.md is the upstream skill without changes (see
SOURCE).

paw has two kinds of text. Each kind has its own style:

| Kind | Files | Style |
|---|---|---|
| External | `README.md`, `docs/**`, `extensions/*/README.md`, `extensions/*/doc/**`, `crates/*/README.md` | plain-writing (this skill) |
| Internal | `AGENTS.md`, `.claude/**`, `bench/**`, Backlog tickets, design documents, code comments, commit messages, replies in chat | ASD-STE100 Simplified Technical English |

The skill's description names commit messages and PR descriptions. In paw
these are internal: they use STE, not this skill.

Diátaxis applies to both kinds (see `.claude/skills/diataxis-docs`).

Rules for external pages in paw:

- Apply SKILL.md to the prose only. Code spans, fenced code, key names and
  screen captures stay as paw shows them, for example `NORMAL·mixer`.
- A table cell can keep a short label with a middle dot when the label is
  what paw shows. Prose uses a comma or "and".
- Keep paw's names for things (the glossary in
  `.claude/skills/diataxis-docs/SKILL.md`): one name for one thing, as rule 4
  says.
- Vale checks the rules that a pattern can find, in the style
  `.vale/styles/Plain`. `.vale.ini` gives each path its styles. Run
  `nix develop -c tools/vale.sh <files>`.
