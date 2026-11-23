# The schema of the chain language

A schema tells the check of the [chain language](chain-language.md) the kinds that a host has: its devices, its splits and its modulators, and the parameters of each one. The language itself knows no kind, so a chain text is only as correct as the schema that it is checked against. A schema is a JSON file, and each host writes its own. paw writes its schema with `paw chain schema`.

## An example

```json
{
  "chain_schema": 1,
  "host": "example",
  "devices": [
    {
      "kind": "compressor",
      "name": "Compressor",
      "params": [
        { "key": "threshold", "type": "number", "unit": "dB", "min": -60, "max": 0, "default": -18 },
        { "key": "ratio", "type": "number", "label": ":1", "min": 1, "max": 20, "default": 4 },
        { "key": "detect", "type": "choice", "choices": ["peak", "rms"], "default": "peak" },
        { "key": "key", "type": "source" }
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
  "open_prefixes": ["clap:", "vst3:"]
}
```

## The schema

| Field | Value | Meaning |
| --- | --- | --- |
| `chain_schema` | A number | The version of the format. The version that this reference describes is `1`. A reader refuses a version that it does not know. |
| `host` | A text | The host that wrote the schema, for people. The check does not read it. |
| `devices` | A list of kinds | The kinds of device. |
| `splits` | A list of split kinds | The kinds of split: containers that split the signal into branches. |
| `modulators` | A list of kinds | The kinds of modulator, which go in a `mods` block. |
| `open_prefixes` | A list of texts | Prefixes of kinds that may be missing from the schema, such as the plugins of a format that are not installed. A missing kind with one of these prefixes gives the warning `W301`, and its fields are not checked. A missing kind without one gives the error `E201`. |

Each field but `chain_schema` can be left out, and it is then empty.

## A kind

A kind of device and a kind of modulator have the same fields.

| Field | Value | Meaning |
| --- | --- | --- |
| `kind` | A text | The kind as a chain text writes it, such as `compressor` or `clap:com.example.amp`. Any text can be a kind. |
| `name` | A text | The name to show to people. |
| `params` | A list of parameters | The parameters, in the order that the formatter writes the fields. |
| `open_params` | `true` or `false` | The host knows the parameters of this kind only for each instance, as with some plugins. Any key is then allowed, and its value is not checked. The default is `false`. |

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
| `source` | `@id`, `@in`, or a word or quoted text that the host gives a meaning to, such as the name of a track | None. |

A `unit` is one of `dB`, `Hz`, `kHz`, `ms`, `s`, `%` and `st`. The check accepts a value in another unit of the same measure, so a parameter in `Hz` takes `2.5kHz`.

## Defaults and the formatter

With a schema, the formatter leaves out each field at the `default` of its parameter, and a host reads a missing field as its default. A parameter with no `default` is always written. A `list` and a `source` have no default.

## Versions

A new version of the format gets a new number in `chain_schema`. A reader of version 1 refuses a schema of version 2, with a message that names both versions, and it does not guess.
