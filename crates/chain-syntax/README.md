# The chain-syntax crate

chain-syntax reads, writes, formats and checks the chain language, a text form of the graph of one part of a project. A text names the nodes of the part, such as strips, buses, sends and producers, and the wires that join them to each other and to lanes. A strip holds its inserts, which are a chain of devices in series, splits with parallel branches, modulators with links to parameters, and checks of the sound. People and programs can both edit the text, and the crate tells them when a text is wrong and where.

The crate names no host. A program that hosts devices, such as a digital audio workstation or a plugin host, gives the crate a schema in JSON. The schema names its kinds of stream, device, split, modulator and producer, with their parameters and ports. The host can also give a context for one text, which names the lanes that the text can reach. The crate has no audio code.

## A part

```chain
chain 2 "Violin I"
strip #1 "Violin I" gain=-3dB
  synth #2 voices=4
  eq #3 hp=120Hz
  compressor #4 ratio=3 key=@"Drums/Kick"
producer midi-keys #5 smooth=20ms
"Notes" -> #1
#1 -> @"Strings/Bus"
"Notes" -> #5
#5 => "Keys"
```

Each line is one node line or one wire, and two spaces of indent go one level in, under the strip that holds the inserts. `#2` is an id, and `120Hz` is a number with its unit. `->` is a live wire, and `=>` stores its result in a lane. `"Notes"` is a lane of the part, and `@"Strings/Bus"` is a node of another part.

A text of version 1, with the header `chain 1`, is the chain of inserts of one strip. A reader of version 2 reads it too.

## Use it

Add the crate to `Cargo.toml`:

```toml
[dependencies]
chain-syntax = "0.1"
```

Parse a text, check it against your schema, and print the diagnostics:

```rust
let schema = chain_syntax::Schema::from_json(r#"{
    "chain_schema": 3,
    "devices": [
        { "kind": "compressor", "params": [
            { "key": "ratio", "type": "number", "minimum": 1, "maximum": 20, "default": 4 }
        ] }
    ]
}"#)?;
let parsed = chain_syntax::check_text("chain 1\ncompressor #1 ratio=40\n", &schema, None);
let messages: Vec<String> = parsed.diagnostics.iter().map(ToString::to_string).collect();
assert_eq!(messages, ["2:15: error E205: `ratio` goes from 1 to 20, so `40` is out of range"]);

// The formatter writes the one layout of a chain.
let text = chain_syntax::format("chain 1\ncompressor   #1  ratio=4\n").expect("a chain with no error");
assert_eq!(text, "chain 1\ncompressor #1 ratio=4\n");
# Ok::<(), chain_syntax::SchemaError>(())
```

The crate gives you these functions:

- `parse` reads a text into a tree. It goes on after each error, so it finds each error of the text, and each diagnostic has a line and a column.
- `check` and `check_text` check a tree against a schema and an optional context. They find unknown kinds and parameters (with a "did you mean"), values of the wrong type, unit or range, ids used twice, and references to later nodes. They also find links out of their container, splits with the wrong number of branches, and wires between ports whose streams do not meet.
- `print` writes a tree as text. A parse of the printed text gives the same tree.
- `format` writes a text in its one layout and keeps the comments. `format_with` also writes the fields in the order of the schema and leaves out the fields at their defaults.
- `complete`, `hover` and `definition` answer an editor about a place in a text.

## The schema of a host

A schema lists the kinds of stream of a host, and its kinds of device, split, modulator, producer and input or output. It gives the parameters of each kind, with their types, units, ranges and defaults, and the ports of each kind, with their streams. A kind is any text, so a host can name the kinds of its plugins and of its extensions as it wants. A schema can also let the kinds of a plugin format be missing, for plugins that are not installed. The check then gives a warning and does not check their fields.

## Documentation

- [The chain language](https://github.com/AlejandroGomezFrieiro/custom_daw/blob/main/docs/reference/chain-language.md): the grammar, an example of each rule, the units and the codes of the diagnostics.
- [The schema of the chain language](https://github.com/AlejandroGomezFrieiro/custom_daw/blob/main/docs/reference/chain-schema.md): each field of the JSON of a schema and of a context.

The crate comes from [paw](https://github.com/AlejandroGomezFrieiro/custom_daw), a personal audio workstation. paw writes its schema with `paw chain schema`.

## License

The crate is under the MIT license or the Apache License 2.0, at your choice: see `LICENSE-MIT` and `LICENSE-APACHE`.
