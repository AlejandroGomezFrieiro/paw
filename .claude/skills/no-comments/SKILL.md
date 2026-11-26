---
name: no-comments
description: "Delete the comments that an edit adds, except doc comments. Use it when the no-comments hook reports comments, and when a change adds or edits comments."
---

# No comments

paw code has no comments except doc comments. After each edit and write,
`tools/comment-hook.py` runs the ast-grep rules of
`tools/ast-grep/comments` on the lines that the edit added. The rules
cover Rust, Teal, Lua, Nix, shell, Python and TypeScript. The hook
reports each comment as `L<n>: <comment>`. Claude Code runs it from `.claude/settings.json`,
and pi from `.pi/extensions/paw.ts`.

## What stays

- A doc comment of an item or a module: `///`, `//!` and `/** */` in
  Rust, `---` in Lua and Teal, `/** */` in Nix and TypeScript.
- The usage header at the top of a script (shell, Python).
- A `// SAFETY:` note above an `unsafe` block.
- A tool directive (`shellcheck`, `luacheck:`, `stylua:`, `rustfmt::`,
  `noqa`, `eslint-`, `@ts-`) and a license line.

## The steps

1. Delete each reported comment.
2. If a reader needs the reason, put it in the doc comment of the item,
   in one sentence that tells why.
3. A doc comment must be useful: it tells the contract or the reason,
   not what the name already says. Check a claimed constraint against
   the code or the dependency.
