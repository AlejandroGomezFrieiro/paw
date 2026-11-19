# The state of JUCE plugins

Most commercial plugins use the JUCE library. The
[plugstate](../../extensions/plugstate/README.md) extension reads the saved
state of a JUCE plugin as a tree, and writes it back. This page describes
the forms that it reads, the paths, the descriptions of plugins and the
presets. The modules are `plugstate.jucestate` (the layer),
`plugstate.juce` (trees and paths) and `plugstate.jucexml` (XML). For the
other frameworks, see [The saved state of plugins](plugin-state.md).

## The layers of a state

`jucestate.open(state, format)` takes a state as `paw.api.device_state`
gives it, and finds these layers by themselves, from the outside in.

| Layer | Where | What the layer does |
| --- | --- | --- |
| `vst3` | each VST3 state | splits the part of the component from the part of the controller |
| `juce-private` | the end of the VST3 component | removes the private data of the JUCE VST3 wrapper (`JUCEPrivateData`, for example `Bypass`) |
| `lv2` | each LV2 state | reads the JUCE base64 text of `<uri>:StateString` from the Turtle text |
| `vstw` | `VstW` at the start of the VST3 component | the VST3 wrapper with `JUCE_VST3_CAN_REPLACE_VST2`: the data in an FXB bank (`FBCh`) or FXP program (`FPCh`) chunk, with big-endian sizes. The private data of JUCE stays in the chunk |
| `header` | a description gives it | a header of the plugin with the size of the data in it, for example `sub3` of Surge XT |
| `vc2` | `VC2!` at the start | `AudioProcessor::copyXmlToBinary`: the magic, the size, the XML, a zero byte |
| `gzip`, `zlib` | the magic bytes of the data | `GZIPCompressorOutputStream` and zlib data |
| `base64` | `<size>.<characters>` | `MemoryBlock::toBase64Encoding` |
| `xml` | text that starts with `<` | XML text, as `ValueTree::createXml` writes it |
| `prefix` | four letters with a digit, or the `prefix` of a description | a magic before a tree, for example `T3KB` of TONE3000 |
| `valuetree` | a type, then counts | `ValueTree::writeToStream` |

- `doc:layer_names()` gives the layers that the layer found, for example
  `vst3 juce-private vc2 xml`.
- When nothing changes, `doc:write()` gives the same bytes as the state
  that was opened. Each layer keeps the bytes of the parts that do not
  change, also the text between the elements of XML.
- A changed XML element is written as JUCE writes it on one line. Changed
  gzip and zlib data is compressed again (deflate, `paw.api.deflate`).
- A CLAP state is the data of the plugin as it is. A JUCE plugin gives
  the same data in each format.

## The tree

A node is `{ type, props = { { name, raw }, ... }, children }`. `raw` is
the stored `var`: a kind byte, then the data. An XML element is a node,
and its attributes are text properties.

| Kind | Value in Lua |
| --- | --- |
| `int`, `int64`, `double` | a number |
| `bool` | `true` or `false` |
| `string` | a string |
| `binary` | `{ binary = <bytes> }` |
| `array` | `{ array = { value, ... } }` |

`juce.set(node, name, value, kind)` keeps the kind of an `int` or `int64`
property when the number is whole. Give `kind` to write another kind.

## Paths

A path names nodes, and with `@name` at its end a property.

| Part | Meaning |
| --- | --- |
| `/Root` | the first step is the root |
| `/Node` | the children of that type |
| `*` | a child of any type |
| `[2]` | the second of the nodes found in this step |
| `[id=gain]` | the nodes whose property `id` has the value `gain` |
| `@name` | the property `name` of each node found |

Examples:
`/TONE3000State/ChainSnapshot/ChainBlocks/ChainBlock[3]@activeModelId`,
`/patch/parameters/a_octave@value`, `/Plugin/PARAMETERS/PARAM[id=gain]@value`.

| Function | Result |
| --- | --- |
| `doc:get(path)` | the value of the property, or the first node |
| `doc:query(path)` | each match as `{ node, parent, index }`, and the name of the property |
| `doc:set(path, value, kind, { make = true })` | sets the property in each node found. With `make`, the layer makes the nodes that are not there |
| `doc:insert(path, tree, index)` | puts a tree into the node found |
| `doc:remove(path)` | removes the nodes, or the property of each node |
| `doc:dump({ depth, max })` | the tree as lines of text |
| `juce.walk(root)` | each node and property with its path |

In the paths that paw writes, a node is `Type` when it is the only one of
its type. Else it is `Type[id=<id>]` when its `id` is unique, and else
`Type[n]`.

## Parameters of AudioProcessorValueTreeState

| Function | Result |
| --- | --- |
| `doc:params()` | `{ { id, value }, ... }` of the `PARAM` nodes |
| `doc:param(id)` | the value of one parameter |
| `doc:set_param(id, value)` | sets a parameter. A parameter that is not there is added, also one that the host does not see as a parameter. Returns `true` when it is added |

The node of the parameters is the `params` path of the description. Else
it is the first node with a `PARAM` child. Else it is the first node with
children that have an `id` and a `value`, for example the `Control` nodes of
HISE.

## Differences

`doc:diff(other)` and `juce.diff(a, b)` give the changes from one tree to
the other: `{ op, path, before, after }`. `op` is `set` (a property changed),
`add` or `remove` (a property, or a node with all that it holds).
`juce.diff_text(changes)` gives them as lines:

```
set    /patch/parameters/a_octave@value: "0" → "1"
add    /Plugin/PARAMETERS/PARAM[id=hidden] = <PARAM>
remove /Plugin/Slot[2] (was <Slot>)
```

## Descriptions of plugins

`jucestate.plugin(desc)` adds a description. A description has these fields.

| Field | Meaning |
| --- | --- |
| `name` | the name of the description, for example `surge-xt` |
| `title` | the name of the plugin for a person |
| `ids` | `{ clap = <id>, lv2 = <uri>, vst3 = <name> }` |
| `root` | the type of the root. Another root is an error |
| `prefix` | four letters before the tree |
| `header` | `{ magic, size, skip }`: the data starts after `skip` bytes, and its size is the 32-bit number at byte `size` |
| `paths` | names for paths: `doc:get("name")` reads the path of `name` |
| `params` | the path of the node of the parameters |
| `slots` | `{ key, label, path }`: values that the `juce` adapter of plugstate shows and sets |
| `ignore` | the start of paths that `:plugstate.changes` does not list, for example the state of the window |

`jucestate.plugin_of(device)` gives the description of a device. The
extension describes these plugins:

| Name | Plugin | Formats | Data | Slots |
| --- | --- | --- | --- | --- |
| `tone3000` | TONE3000 | CLAP, VST3, LV2 | `T3KB`, a ValueTree | none (the `tone3000` adapter) |
| `surge-xt` | Surge XT | CLAP, VST3, LV2 | `sub3` header, XML of the patch, wavetables | `name`, `octave` |
| `musio` | Musio | VST3 | `VC2!`, XML (`PluginState`) | `reverb`, `room`, `reverb_amount` |
| `decent-sampler` | DecentSampler | VST3 | `VC2!`, XML (`DecentSampler`) | none. Paths: `preset_name`, `sample_path`, `library_url`, `tuning` |

## Presets

A preset is a base state and a list of edits:
`{ plugin, name, base, format, edits }`. Without `base`, the edits apply
to the state of the device. An edit is one of these:

| Edit | Effect |
| --- | --- |
| `{ path, value, kind, make }` | sets a property |
| `{ path, remove = true }` | removes nodes or a property |
| `{ path, insert = tree, index }` | puts a tree into a node |
| `{ param = id, value }` | sets a parameter (`set_param`) |

| Function | Result |
| --- | --- |
| `jucestate.generate(preset, format, current)` | the state for a device of `format`. `current` is the state of the device: it gives what is around the data |
| `jucestate.convert(state, from, to, template)` | a state of one format as a state of another format |
| `doc:write_as(format, template, { uri })` | the same for an open document. Without a template, an LV2 state needs the URI of the plugin |
| `jucestate.write_preset(file, preset)`, `jucestate.read_preset(file)` | a preset as a `.jucepreset` file (JSON) |

## Limits

- The layer reads the state that the plugin saves. It does not know what
  each value means. A description gives names to the paths.
- Surge XT as a VST3 plugin does not take a state from paw, also a state
  that it saved. The state of Surge XT in CLAP and LV2 loads.
- Musio keeps its instrument in `MusioFile`. Without a login, Musio has no
  instrument, and that node is empty.
