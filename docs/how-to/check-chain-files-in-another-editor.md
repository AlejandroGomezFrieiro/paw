# How to check chain files in Neovim or another editor

<!-- tags: chain-lsp chain-language language-server neovim -->

The guide shows you how to edit files of the [chain language](../reference/chain-language.md) in Neovim with `chain-lsp`, the language server of the language. The editor then shows the errors as you type, formats the file, completes the kinds and the parameters, and shows the range and the unit of a parameter. The guide assumes Neovim 0.11 or later. Another editor that speaks the Language Server Protocol takes the same command.

1. Install the server. With Nix, run `nix build github:AlejandroGomezFrieiro/custom_daw#chain-lsp` and put `result/bin` on your `PATH`. With cargo, run `cargo install --path crates/chain-lsp` in a checkout of paw.
2. Save the schema of your host in a file. The schema tells the server the kinds of device and their parameters. For paw, run the following command:

   ```sh
   mkdir -p ~/.config/chain && paw chain schema > ~/.config/chain/schema.json
   ```

   For another host, write the schema as [the schema format](../reference/chain-schema.md) describes.
3. Put the following lines in your Neovim configuration, for example in `~/.config/nvim/init.lua`:

   ```lua
   vim.filetype.add({ extension = { chain = "chain" } })
   vim.lsp.config("chain_lsp", {
     cmd = { "chain-lsp", "--schema", vim.fs.normalize("~/.config/chain/schema.json") },
     filetypes = { "chain" },
   })
   vim.lsp.enable("chain_lsp")
   ```

4. Open a file that ends in `.chain`, for example `bus.chain` with the following text:

   ```text
   chain 1
   compressor #1 ratio=4 thresh=-20dB
   ```

   Neovim marks `thresh` as an error with the code `E202`, because a compressor has no parameter of that name.
5. Use the server while you edit:
   - `K` on a kind or a parameter shows what it takes.
   - `Ctrl-x Ctrl-o` in insert mode completes a kind, a parameter or a value.
   - `Ctrl-]` on `@1` or on `#1.ratio` goes to the line with `#1`.
   - `:lua vim.lsp.buf.format()` writes the file in its one layout.

## Variations

- To check against the devices that paw has now, give the server the command in place of the file: `cmd = { "chain-lsp", "--schema-command", "paw", "chain", "schema" }`. The server then starts paw once each time that it starts.
- If the editor gives `initializationOptions`, you can give the schema there as `schemaPath`, and the command line needs no option. The [README of chain-lsp](../../crates/chain-lsp/README.md) lists each option.
- Without a schema, the server checks only the grammar, and Neovim shows a message that says so.

## See also

- [The chain language](../reference/chain-language.md): the grammar and the codes of the diagnostics.
- [The programs and their options](../reference/programs.md): the options of `chain-lsp`.
- [Language servers and diagnostics](../reference/language-servers.md): the extension `chainlsp`, which starts the same server inside paw.
