---
name: no-comments
description: "Review code comments for narration, banners and dead code. Keep comments that explain a reason the code does not show. Use it when a change adds or edits comments or the comment hook reports a candidate."
---

# No comments

The hook in `.pi/extensions/paw.ts` flags possible narration after an
edit or a write. Review its candidates against `CODING_STANDARDS.md`.
Do the review yourself.

## What to keep

Keep these comments:

- A legal or license header.
- A doc comment that defines a public API contract (`///`, `//!`,
  `/**`, `---@` and `---` in Lua).
- A `// SAFETY:` note above an `unsafe` block (see the rules for agents).
- A reason the code does not show, such as a required order of operations
  or a constraint from a dependency.
- A tool directive (`prettier-ignore`, `stylua:`, `luacheck:`,
  `rustfmt::`, `eslint-`, `# shellcheck`, `# noqa`, `# type:`).

## The steps

1. Read each line of the report: `L<n>: <comment>`.
2. Delete narration, banners, and dead code. Keep a comment that tells
   the reader why the code must work this way.
3. Check a claimed constraint against the code or the dependency. If the
   claim is false, correct or delete the comment.
