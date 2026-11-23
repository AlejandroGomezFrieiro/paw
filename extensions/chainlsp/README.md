# chainlsp

chainlsp adds chain-lsp, the language server of the [chain language](../../docs/reference/chain-language.md), as an entry of `paw.lsp`. The server is a program of its own that knows nothing of paw, and it works in other editors too ([How to check chain files in Neovim or another editor](../../docs/how-to/check-chain-files-in-another-editor.md)). The extension tells paw where the server is, starts it with paw's schema of the language, and shows it each chain file of the project. paw works the same without the extension.

```lua
paw.ext.load("/path/to/paw/extensions/chainlsp")
```

## Try it

1. Install the server, `chain-lsp`, on the `PATH`. The Nix package of paw has it, and `cargo install --path crates/chain-lsp` in a checkout of paw builds it.
2. Save the project, so that it has a folder.
3. In the folder of the project, make the file `racks/glue.chain` with the following text:

   ```text
   chain 1
   compressor ratio=80
   ```

4. Type `:ext.load chainlsp`, then `:chainlsp`. paw shows where the server is and lists `racks/glue.chain`.
5. Type `:diagnostics`. The list has the error of the file, which starts with `2:12` and gives the range of `ratio`.
6. Change the file in another editor, and type `:chainlsp check`. paw reads the chain files again and the list follows.

## Reference

| Command | Keys | Effect |
| --- | --- | --- |
| `:chainlsp` | | shows where the server is, the chain files that it checks, and how each server runs. `:chainlsp start`, `:chainlsp stop` |
| `:chainlsp check` | | reads the chain files of the project again and sends the changed ones to the server |

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.chainlsp_cmd` | `""` | the server and its arguments. If the option is empty, paw uses `$CHAIN_LSP`, and if that is not set either, `chain-lsp` on the `PATH`. |
| `paw.opt.chainlsp_autostart` | `true` | starts the server when the extension loads, if paw finds it |

- The chain files are the files that end in `.chain` in the folder of the project and in its folders, three levels deep. paw leaves out the folders whose names start with a dot.
- paw gives the server its schema of the language when the server starts, with the plugins and the Lua devices that it has then. `paw chain schema` prints the same schema.
- `:diagnostics` lists the diagnostics of the chain files with those of the other servers, and each one starts with its line and column in the file. [Language servers and diagnostics](../../docs/reference/language-servers.md) describes the list.

## What it does not do yet

- paw has no buffer for a chain file, so you edit the files in another editor, and paw shows no completion or hover for them.
- paw keeps the devices of a track in the project, not in a chain file, so the server does not check them. A later version of paw moves them into `devices.chain`, and then the server checks them too.
