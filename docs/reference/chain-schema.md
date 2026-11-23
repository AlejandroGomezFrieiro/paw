# The schema of the chain language

A schema tells the check of the [chain language](chain-language.md) what a host has. It names the kinds of stream that wires and lanes carry, and the kinds of device, split, modulator, producer and input or output, with the parameters and ports of each. It also gives the parameters and ports of each role of a node line, such as `strip` and `send`. The language itself knows no kind, so a chain text is only as correct as the schema that it is checked against. A schema is a JSON file, and each host writes its own. paw writes its schema with `paw chain schema`.

A host can also give a context for one text, which is a second JSON file. The context names the lanes of the part and the lanes and nodes of other parts. See [the context](#the-context) below.

## An example

```json
{
  "chain_schema": 2,
  "host": "example",
  "streams": [
    {
      "stream": "audio",
      "name": "Audio",
      "time": "samples",
      "records": true,
      "props": [{ "key": "channels", "type": "number", "integer": true, "min": 1, "max": 64, "default": 2 }]
    },
    { "stream": "midi", "name": "MIDI", "time": "beats", "records": true },
    { "stream": "curve", "name": "Curve", "time": "beats", "records": true, "control": true }
  ],
  "default_ports": [
    { "port": "in", "stream": "audio", "main": true },
    { "port": "out", "stream": "audio", "main": true, "out": true }
  ],
  "nodes": [
    {
      "kind": "strip",
      "params": [
        { "key": "gain", "type": "number", "unit": "dB", "min": -60, "max": 12, "default": 0 },
        { "key": "pan", "type": "number", "min": -1, "max": 1, "default": 0 }
      ],
      "ports": [
        { "port": "in", "stream": "audio", "main": true },
        { "port": "notes", "stream": "midi", "main": true },
        { "port": "out", "stream": "audio", "main": true, "out": true }
      ]
    },
    { "kind": "send", "params": [{ "key": "level", "type": "number", "unit": "dB", "min": -60, "max": 12, "default": 0 }] }
  ],
  "devices": [
    {
      "kind": "compressor",
      "name": "Compressor",
      "params": [
        { "key": "threshold", "type": "number", "unit": "dB", "min": -60, "max": 0, "default": -18 },
        { "key": "ratio", "type": "number", "label": ":1", "min": 1, "max": 20, "default": 4 },
        { "key": "detect", "type": "choice", "choices": ["peak", "rms"], "default": "peak" },
        { "key": "key", "type": "source", "stream": "audio" }
      ]
    },
    {
      "kind": "synth",
      "params": [{ "key": "voices", "type": "number", "integer": true, "min": 1, "max": 32, "default": 8 }],
      "ports": [
        { "port": "notes", "stream": "midi", "main": true },
        { "port": "out", "stream": "audio", "main": true, "out": true }
      ]
    },
    { "kind": "clap:com.example.amp", "open_params": true }
  ],
  "splits": [
    {
      "kind": "band",
      "branches": { "min": 2, "max": 6 },
      "params": [
        { "key": "xover", "type": "list", "unit": "Hz", "min": 20, "max": 20000, "count": { "min": 1, "max": 5 }, "ascending": true }
      ],
      "branch_params": [
        { "key": "gain", "type": "number", "unit": "dB", "min": -60, "max": 12, "default": 0 },
        { "key": "mute", "type": "switch", "default": false }
      ]
    }
  ],
  "modulators": [
    {
      "kind": "lfo",
      "params": [
        { "key": "rate", "type": "number", "unit": "Hz", "min": 0.01, "max": 50, "default": 1 },
        { "key": "sync", "type": "note" }
      ]
    }
  ],
  "producers": [
    { "kind": "render", "tier": "bake" },
    {
      "kind": "mono",
      "converts": true,
      "ports": [
        { "port": "in", "stream": "audio", "props": { "channels": 2 }, "main": true },
        { "port": "out", "stream": "audio", "props": { "channels": 1 }, "main": true, "out": true }
      ]
    }
  ],
  "io": [
    { "kind": "midi-in", "ports": [{ "port": "out", "stream": "midi", "main": true, "out": true }] }
  ],
  "open_prefixes": ["clap:", "vst3:"]
}
```

## The schema

| Field | Value | Meaning |
| --- | --- | --- |
| `chain_schema` | A number | The version of the format. The version that this reference describes is `2`. A reader refuses a version that it does not know. |
| `host` | A text | The host that wrote the schema, for people. The check does not read it. |
| `streams` | A list of streams | The kinds of stream that ports, lanes and wires carry. With no streams, the check does not check the streams between inserts. |
| `default_ports` | A list of ports | The ports of a kind that gives no `ports` of its own. |
| `nodes` | A list of kinds | The parameters and ports of each role of a node line that has no kind of its own: `strip`, `bus`, `master`, `send` and `vca`. The `kind` of each entry is the role. |
| `devices` | A list of kinds | The kinds of device. |
| `splits` | A list of split kinds | The kinds of split: containers that split the signal into branches. |
| `modulators` | A list of kinds | The kinds of modulator, which go in a `mods` block. |
| `producers` | A list of kinds | The kinds of a `producer` line. A producer of tier `live` can also be an insert. |
| `io` | A list of kinds | The kinds of an `io` line: the inputs and outputs of the host. |
| `open_prefixes` | A list of texts | Prefixes of kinds that may be missing from the schema, such as the plugins of a format that are not installed. A missing kind with one of these prefixes gives the warning `W301`, and its fields are not checked. A missing kind without one gives the error `E201`. |

Each field but `chain_schema` can be left out, and it is then empty.

## A stream

| Field | Value | Meaning |
| --- | --- | --- |
| `stream` | A text | The word that ports and the context name the stream by, such as `audio`. |
| `name` | A text | The name to show to people. |
| `time` | `samples`, `beats` or `seconds` | What the time of the stream counts, for people and tools. It can be left out. |
| `records` | `true` or `false` | A lane of this stream can record from an input. The default is `false`. |
| `control` | `true` or `false` | The stream can move a parameter of a node, as a curve moves a gain. The default is `false`. |
| `props` | A list of parameters | The properties of the stream, such as `channels`, with their types and defaults. They have the same fields as a parameter. |

## A kind

A kind of device, modulator, producer and input or output, and a role in `nodes`, have the same fields.

| Field | Value | Meaning |
| --- | --- | --- |
| `kind` | A text | The kind as a chain text writes it, such as `compressor` or `clap:com.example.amp`. Any text can be a kind. |
| `name` | A text | The name to show to people. |
| `params` | A list of parameters | The parameters, in the order that the formatter writes the fields. |
| `open_params` | `true` or `false` | The host knows the parameters of this kind only for each instance, as with some plugins. Any key is then allowed, and its value is not checked. The default is `false`. |
| `ports` | A list of ports | The inputs and outputs. When it is left out, the kind has the `default_ports` of the schema. |
| `tier` | `live`, `kernel` or `bake` | When the kind runs: `live` as the host plays, `kernel` in the host as its source changes, or `bake` in a job whose result a lane keeps. The default is `live`. |
| `converts` | `true` or `false` | A producer with one input and one output that turns one type of stream into another. The check accepts a wire between two types that a converter joins, because the host puts the converter on the wire. The default is `false`. |

## A port

| Field | Value | Meaning |
| --- | --- | --- |
| `port` | A text | The name that a wire gives the port, as in `#3.side`. |
| `stream` | A text | The kind of stream of the port. |
| `props` | An object | The values of properties of the stream that an input needs or that an output gives, such as `{ "channels": 1 }`. An output that does not name a property gives the default of the stream. |
| `main` | `true` or `false` | The port that a wire with no port joins, and that inserts in series join. A kind has at most one main input and one main output of each stream. The default is `false`. |
| `out` | `true` or `false` | `true` for an output, and `false` for an input. The default is `false`. |

## A split kind

| Field | Value | Meaning |
| --- | --- | --- |
| `kind` | A text | The kind as a chain text writes it, such as `layer`. |
| `name` | A text | The name to show to people. |
| `branches` | `{ "min": n, "max": n }` | How many branches the split takes. A split with nodes and no `|` line has one branch. |
| `params` | A list of parameters | The parameters of the split itself. |
| `branch_params` | A list of parameters | The parameters of each branch, on its `|` line. |

## A parameter

Each parameter has a `key` and a `type`, and the type decides the other fields.

| Field | Value | Meaning |
| --- | --- | --- |
| `key` | A text | The key that a field names, such as `threshold` or `Input gain`. |
| `type` | A text | One of the types below. |
| `name` | A text | The name to show to people. |
| `label` | A text | A unit that the host shows and that the language does not have, such as `°` or `:1`. Values of the parameter have no unit. |

| Type | The value in a chain | Its fields |
| --- | --- | --- |
| `number` | A number, with a unit when `unit` is given | `unit`, `min`, `max` and `default`, all in `unit`. `integer` is `true` when the parameter takes only whole numbers. |
| `switch` | `on` or `off` | `default`: `true` for `on`. |
| `choice` | One of the choices | `choices`, a list of texts, and `default`, one of them. |
| `text` | Any word or quoted text | `default`. |
| `note` | A note value, such as `1/4` | `default`, as a chain writes it. |
| `list` | Numbers with commas between them | `unit`, `min` and `max` for each number. `count` is `{ "min": n, "max": n }`. `ascending` is `true` when each number must be greater than the one before it. |
| `source` | `@id`, `@in`, an outside end `@"path"`, or a word or quoted text that the host gives a meaning to | `stream`, the kind of stream that an outside end must give. It can be left out. |

A `unit` is one of `dB`, `Hz`, `kHz`, `ms`, `s`, `%` and `st`. The check accepts a value in another unit of the same measure, so a parameter in `Hz` takes `2.5kHz`.

## Defaults and the formatter

With a schema, the formatter leaves out each field at the `default` of its parameter, and a host reads a missing field as its default. A parameter with no `default` is always written. A `list` and a `source` have no default.

## The context

The context of a text tells the check the type of each lane and outside end that the text names. A host writes it for one part, because each part has its own lanes. The context is optional. With no context, the check gives the warning `W302` for each lane and outside end, and does not check their types.

```json
{
  "chain_context": 2,
  "lanes": [
    { "name": "Notes", "stream": "midi" },
    { "name": "Mic", "stream": "audio", "props": { "channels": 1 } }
  ],
  "outside": [
    { "path": "Drums/Kick", "stream": "audio" },
    { "path": "Strings/Bus", "node": "bus" }
  ]
}
```

| Field | Value | Meaning |
| --- | --- | --- |
| `chain_context` | A number | The version of the format, `2`. A reader refuses a version that it does not know. |
| `lanes` | A list of lanes | The lanes of the part. Each has a `name`, which a wire writes in quotes, a `stream`, and the values of the properties of the stream in `props`. |
| `outside` | A list of outside ends | The lanes and nodes of other parts. Each has a `path`, which a text writes after `@`. A lane has a `stream` and `props`. A node has `node`, its role, and `kind` for a producer or an input or output, and its ports come from the schema. |

## Versions

A new version of the format gets a new number in `chain_schema`. A reader of version 2 refuses a schema of version 1, with a message that names both versions, and it does not guess.
