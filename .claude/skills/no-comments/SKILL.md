---
name: no-comments
description: "Find and delete comments that are not a legal header, a public API contract, an external dependency or protocol constraint, a `// SAFETY:` note, or a tool directive. Use it when a change adds or edits code comments, and when a review finds narration, banners, commented-out code, or a workaround sermon."
---

# No comments

The hook in `.pi/extensions/paw.ts` reports each added comment after an
edit or a write. The hook is the first pass. This skill gives the
judgment that the hook cannot make. It never starts a subagent: the work
is a direct edit.

## The exceptions

A comment stays only for one of these reasons:

- A legal or license header.
- A doc comment that defines a public API contract (`///`, `//!`,
  `/**`, `---@` and `---` in Lua).
- A `// SAFETY:` note above an `unsafe` block (see the rules for agents).
- A constraint that an external dependency, a platform, a vendor or a
  protocol forces. Name the dependency, the protocol and its version.
- A tool directive (`prettier-ignore`, `stylua:`, `luacheck:`,
  `rustfmt::`, `eslint-`, `# shellcheck`, `# noqa`, `# type:`).

## The steps

1. Read each line of the report: `L<n>: <comment>`.
2. Delete the comment. Do not shorten it: a shorter alibi is still a
   comment.
3. For a claimed constraint, find the proof in the code or in the
   dependency. If the proof is absent, delete the comment.
4. For a workaround in our own code, delete the comment and report the
   symbol that needs a rename, an extract, a type or a design change.
5. Report the comments removed, each keep with its proof, and the
   symbols that need a change.
