# chain-lsp

chain-lsp is a language server for the chain language, which is a text form of a chain of audio devices with parallel branches. It works in any editor that speaks the Language Server Protocol, and it knows no host: the kinds of device, split and modulator, with their parameters, come from the schema that you give it. All of the language is in the crate [chain-syntax](../chain-syntax/README.md), so the server and the other tools of the language give the same diagnostics.

```text
chain 1 "Gtr bus"
eq #2 hp=90Hz lp=9kHz
compressor #5 ratio=4 threshold=-20dB key=@2
```

## What the server does

- **Diagnostics.** Each time a text opens or changes, the server sends the errors of the grammar and, with a schema, the errors of the check: an unknown kind or parameter, a value of the wrong type, unit or range, and the other codes of the [reference page](https://github.com/AlejandroGomezFrieiro/custom_daw/blob/main/docs/reference/chain-language.md).
- **Formatting.** The server writes the text in its one layout, with the fields in the order of the schema and no field at its default. It keeps the comments, and it leaves a text with an error as it is.
- **Completion.** At the start of a line, the server offers the kinds of the schema. After a kind, it offers the parameters that the line does not have yet, and after `=`, the choices of a parameter or `on` and `off`.
- **Hover.** On a kind, the server shows its parameters. On a parameter, it shows the type, the unit, the range and the default.
- **Go to definition.** From a reference `@5` or a link target `#5.ratio`, the server goes to the line with `#5`.

## Install it

With Nix, run `nix build github:AlejandroGomezFrieiro/custom_daw#chain-lsp`. With cargo, run `cargo install --path crates/chain-lsp` in a checkout of the repository.

## Give it the schema of your host

The server reads the [schema](https://github.com/AlejandroGomezFrieiro/custom_daw/blob/main/docs/reference/chain-schema.md) of the host from the first of these places that you give:

1. the `initializationOptions` of the editor, as `schema` (the JSON itself, as an object or as text), `schemaPath` (a file) or `schemaCommand` (a program and its arguments, as a list)
2. the command line, as `--schema <file>` or `--schema-command <program> [args...]`

```json
{ "schemaPath": "/path/to/schema.json" }
```

paw prints its schema with `paw chain schema`, so `chain-lsp --schema-command paw chain schema` checks against the devices that paw has. Without a schema, the server says so in a message and checks only the grammar.

A host can also give a context of its own, as `chainContext` in the `initializationOptions` or with the notification `chain/context`. The server keeps it for a later version of the language and reads nothing in it yet.

## Use it

- [How to check chain files in Neovim or another editor](https://github.com/AlejandroGomezFrieiro/custom_daw/blob/main/docs/how-to/check-chain-files-in-another-editor.md)
- In paw, the extension [chainlsp](https://github.com/AlejandroGomezFrieiro/custom_daw/blob/main/extensions/chainlsp/README.md) starts the server with paw's schema.

The crate comes from [paw](https://github.com/AlejandroGomezFrieiro/custom_daw), a personal audio workstation. It depends on no other crate of paw.

## License

The crate is under the MIT license or the Apache License 2.0, at your choice: see `LICENSE-MIT` and `LICENSE-APACHE`.
