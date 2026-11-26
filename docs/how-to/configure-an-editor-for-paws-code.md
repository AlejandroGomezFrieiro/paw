# How to configure an editor for paw's code

<!-- tags: extending teal lua editor language-server -->

You can get completion, types and errors in your editor for paw's Teal and
Lua. They help when you change paw or write an extension in the source
tree. The dev shell of the flake has the two language servers that you
need:

- `teal-language-server`, for `.tl` files. It reads `tlconfig.lua`, which
  tells it where the types of paw are (`runtime/types`).
- `lua-language-server`, for `.lua` files. It reads `.luarc.json`, which
  tells it about LuaJIT and the global `paw`, and gives it the file of
  types that `tools/apidoc.lua` makes (`runtime/types/paw.lua`).

1. In the checkout, run `nix develop`, and start your editor from the
   same shell so that it finds the two servers.
2. Tell the editor to use the servers. In Neovim with the plugin
   nvim-lspconfig, put the following line in your configuration:

   ```lua
   vim.lsp.enable({ "teal_ls", "lua_ls" })
   ```

3. Open a file of the source tree, for example
   `extensions/rulerplus/init.tl`, and type `paw.` on a new line. The
   editor shows the fields of `paw`.

The language server of Lua reads the whole tree when it starts, which
takes about half a minute. Until it has read the tree, it gives no
completion.

## Variations

- The types of `paw` come from the source of paw. When you change a
  function or its doc comment, run `tools/apidoc.lua` (see
  [the teal skill](../../.claude/skills/teal/SKILL.md)), and the servers
  show the new types.
- To check all of the Teal files at once, run `tools/tlcheck.sh`. It
  shows each problem with its file and line. It runs the paw of
  `tests/tools/run.sh`, which builds paw when your checkout has none.

## See also

- [How to write an extension in Teal](write-an-extension-in-teal.md).
- [About Teal in paw](../explanation/about-teal.md): the tools for Teal
  and Lua, and why paw uses each one.
- [How to build and run paw from the source](build-paw-from-source.md).
