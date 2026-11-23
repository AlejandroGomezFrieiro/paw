# The chain-syntax crate

chain-syntax reads, writes, formats and checks the chain language, a text form of a chain of audio devices. A chain can have devices in series, splits with parallel branches, modulators with links to parameters, and checks of the sound. People and programs can both edit the text, and the crate tells them when a text is wrong and where.

The crate names no host. A program that hosts devices, such as a digital audio workstation or a plugin host, gives the crate its kinds of device, split and modulator as a schema in JSON. The crate has no audio code.

## A chain

```chain
chain 1 "Gtr bus"
eq #2 hp=90Hz lp=9kHz
band #8 "Tame" xover=150Hz,2.5kHz
  | Low
    compressor #5 ratio=4 threshold=-20dB
  | High gain=-1dB
    saturation #6 drive=12dB curve=tube -- a little grit
mods
  lfo #30 sync=1/4 -> #6.drive +3dB
```

Each line is one node, and two spaces of indent go one level in. A `|` line starts a branch of the split above it. `#2` is an id, and `90Hz` is a number with its unit.

## Use it

Add the crate to `Cargo.toml`:

```toml
[dependencies]
chain-syntax = "0.1"
```

Parse a text, check it against your schema, and print the diagnostics:

```rust
let schema = chain_syntax::Schema::from_json(r#"{
    "chain_schema": 1,
    "devices": [
        { "kind": "compressor", "params": [
            { "key": "ratio", "type": "number", "min": 1, "max": 20, "default": 4 }
        ] }
    ]
}"#)?;
let parsed = chain_syntax::check_text("chain 1\ncompressor #1 ratio=40\n", &schema);
let messages: Vec<String> = parsed.diagnostics.iter().map(ToString::to_string).collect();
assert_eq!(messages, ["2:15: error E205: `ratio` goes from 1 to 20, so `40` is out of range"]);

// The formatter writes the one layout of a chain.
let text = chain_syntax::format("chain 1\ncompressor   #1  ratio=4\n").expect("a chain with no error");
assert_eq!(text, "chain 1\ncompressor #1 ratio=4\n");
# Ok::<(), chain_syntax::SchemaError>(())
```

The crate gives you these functions:

- `parse` reads a text into a tree. It goes on after each error, so it finds each error of the text, and each diagnostic has a line and a column.
- `check` and `check_text` check a tree against a schema: unknown kinds and parameters (with a "did you mean"), values of the wrong type, unit or range, ids used twice, references to later nodes, links out of their container, and splits with the wrong number of branches.
- `print` writes a tree as text. A parse of the printed text gives the same tree.
- `format` writes a text in its one layout and keeps the comments. `format_with` also writes the fields in the order of the schema and leaves out the fields at their defaults.

## The schema of a host

A schema lists the kinds of device, split and modulator of a host, and the parameters of each kind, with their types, units, ranges and defaults. A kind is any text, so a host can name the kinds of its plugins and of its extensions as it wants. A schema can also let the kinds of a plugin format be missing, for plugins that are not installed: the check then gives a warning and does not check their fields.

## Documentation

- [The chain language](https://github.com/AlejandroGomezFrieiro/custom_daw/blob/main/docs/reference/chain-language.md): the grammar, an example of each rule, the units and the codes of the diagnostics.
- [The schema of the chain language](https://github.com/AlejandroGomezFrieiro/custom_daw/blob/main/docs/reference/chain-schema.md): each field of the JSON of a schema.

The crate comes from [paw](https://github.com/AlejandroGomezFrieiro/custom_daw), a personal audio workstation, which keeps the chain of each track in a file of this language. paw writes its schema with `paw chain schema`.

## License

The crate is under the MIT license or the Apache License 2.0, at your choice: see `LICENSE-MIT` and `LICENSE-APACHE`.
