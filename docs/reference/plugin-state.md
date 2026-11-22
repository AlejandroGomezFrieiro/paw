# The saved state of plugins

The [plugstate](../../extensions/plugstate/README.md) extension reads the
saved state of a plugin as a tree and writes it back, and a reader for each
framework finds the form of the state from its bytes. The reference describes the
forms that plugstate reads, the trees that it makes from them, and the module
`plugstate.frameworks`. For the layers of JUCE, see
[The state of JUCE plugins](juce-plugin-state.md).

## The readers

plugstate asks the readers in the order below, and the first reader that knows
the bytes opens the state.

| Reader | Detected by | Root of the tree | Parameters |
| --- | --- | --- | --- |
| `dpf` | `__dpf_` at the start of the data | `DPF` | `/DPF/Parameters`, by symbol |
| `lsp` | `LSP ` (CLAP) or `LSPS` (VST3) at the start | `LSP` | `/LSP/Parameters`, by port id |
| `dplug` | the magic `0B 20 BA 92` | `Dplug` | `/Dplug/Parameters`, by the names of the host |
| `iplug2` | a string `###...###` first, or the hint `iplug2` | `IPlug` | `/IPlug/Parameters`, by the names of the host |
| `juce` | a layer of JUCE (see [The state of JUCE plugins](juce-plugin-state.md)) | the type of the ValueTree | the `PARAM` nodes |
| `json` | text that starts with `{` or `[` | `state` | nih-plug: `/state/params`. Vital: `/state/settings` |
| `lv2` | the Turtle text of an LV2 state | `DPF`, `LSP` or `LV2` | `/<root>/Parameters`, the ports by symbol |
| `binary` | each other state | `State` | the floats in `/State/Floats`, when the bytes look like floats |

- `doc.framework` is the name of the reader, or a name that the reader
  finds: `nih-plug` and `vital` (`json`), `dpf` and `lsp` (`lv2`), `hise`
  (`juce`, with the hint `hise`).
- When nothing changes, `doc:write()` gives the same bytes as the state
  that was opened, because a reader writes each unchanged value with its
  original bytes or text.
- A VST3 state has a component part and a controller part. The readers read
  the component part, and the controller part does not change.

## The forms

### DPF

`DistrhoPluginVST3.cpp` (`getState`, line 1169) and `DistrhoPluginCLAP.cpp`
(`stateSave`, line 1456) of DPF write the same text, where each string ends
with a zero byte, and a byte `0xFE` followed by a zero byte ends the state.

| Part | Content |
| --- | --- |
| `__dpf_program__`, then a number | the program, if the plugin has programs |
| `__dpf_state_begin__` ... `__dpf_state_end__` | the state keys and their values |
| `__dpf_parameters_begin__` ... `__dpf_parameters_end__` | each parameter that is not an output: its symbol, then its value as text |

The tree is `/DPF@program`, `/DPF/State@<key>` and
`/DPF/Parameters@<symbol>`. `DistrhoPluginLV2.cpp` (`lv2_save`, line 912)
keeps the state keys as `urn:distrho:<key>`, and the parameters are ports.
The `lv2` reader gives the keys and ports the same paths, so a preset of path
edits works in each format of a DPF plugin.

### LSP

The CLAP wrapper of lsp-plugin-fw (`wrap/clap/impl/wrapper.h`,
`save_state_work`, line 1334) writes `LSP ` and a 32-bit version. The VST3
wrapper (`wrap/vst3/impl/wrapper.h`, `save_state`, line 1296) writes
`LSPS` and a 16-bit version. Then each record follows.

| Record | Content |
| --- | --- |
| a port | its id (a varint length, the bytes), a type (`f` a 32-bit float, `s` a string), the value |
| `!preset_settings`, `!preset_state` | a varint size, then the bytes |
| a KVT entry (its name starts with `/`) | a flags byte, a type (`i u I U f F s B`), the value |

The tree is `/LSP/Parameters@<port id>` and `/LSP/State@<name>`. The
name of a KVT entry has no first `/`, and `_` replaces each other `/`.
The LV2 state of an LSP plugin has the ports as LV2 ports, so
`/LSP/Parameters@<id>` is the same path in CLAP, VST3 and LV2.

### iPlug2

`IPluginBase::SerializeParams` (`IPlugPluginBase.cpp`, line 109) writes the
value of each parameter as a 64-bit float, in the order of the parameters. A
plugin that has its own `SerializeState` often writes strings first
(`IByteChunk::PutStr` writes a 32-bit length and then the bytes), and it can
write its own data after the parameters. The VST3 wrapper
(`IPlugVST3_Common.h`, `GetState`, line 25) adds a 32-bit bypass flag at
the end. The CLAP wrapper (`IPlugCLAP.cpp`, `stateSave`, line 407) writes
the chunk alone.

- The reader finds the parameters with the list of parameters of the host.
  The plugin's own parameters have the ids 0 to n-1.
- It tries each place after the strings at the start. It takes the place
  where most of the n values are plausible numbers.
- The tree is `/IPlug/Chunk@string1` (and the other strings),
  `/IPlug/Chunk@data` (the data after the parameters),
  `/IPlug/Parameters@<key>` and, in VST3, `/IPlug@bypass`.
- Without the list of the host, the reader gives the strings and the data
  only.

### Dplug

`writeStateChunk` in `dplug/client/preset.d` writes the form below, little
endian after the magic.

| Bytes | Content |
| --- | --- |
| 4 | the magic `0x0B20BA92`, big endian |
| 4, 4 | the major and the minor version of the format |
| 4 | the version of the plugin |
| 4 | the current preset |
| 4, then 4 for each | the count of the parameters, then each normalized value as a 32-bit float |
| 4, then the bytes | from major version 1: the size of the plugin's own data (`saveState`), then the data |

The tree is `/Dplug@preset`, `/Dplug/Parameters@<key>` and
`/Dplug/State@data`.

### nih-plug

`PluginState` in `src/wrapper/state.rs` (line 31) is `version`, `params`
and `fields`. `serialize_json` (line 134) writes it as JSON. With the
feature `zstd` of nih-plug, it compresses the JSON with Zstandard.
plugstate does not read a compressed state, so it opens as a `binary` state.

- A parameter is its plain value (not normalized) as `{"f32": 0.5}`, `{"i32": 3}`,
  `{"bool": true}` or `{"string": "<id>"}`.
- A field of `fields` is a string that holds JSON.
- `doc:params()` gives each parameter by its id with its value.
  `doc:set_param(id, value)` changes the value in its object.

### Vital

`SynthPlugin::getStateInformation` (`src/plugin/synth_plugin.cpp`, line 189)
writes the JSON of the preset with `MemoryOutputStream::writeString`,
so a zero byte ends the text. The `json` reader names it `vital` when
the object has `synth_version`, or `settings` and `author`.
`/state/settings` holds the parameters.

### JSON

The `json` reader gives each object as a node. Its numbers, strings and
booleans are properties, and its objects and arrays are children. An item
of an array is an `item` node. A key that has `/`, `@`, a bracket or a
space gets `_` in its place, and the node keeps the key in `@key`.

- Only values change. A new key or a key that is taken away is an error.
- A changed value is written in its place in the text. The rest of the
  text stays as it was.

### LV2

paw keeps the state of an LV2 plugin as Turtle text, as
`lilv_state_to_string` writes it.

- Each port (`lv2:symbol`, `pset:value`) is a property of `Parameters`.
- Each key of `state:state` is a property of `State`. Its name is the end
  of the URI of the key, after its last `#`, `/` or `:`.
- A string, a typed literal (`"0.5"^^xsd:float`), a URI (`<file://...>`
  gives the path) and a block (`[ ... ]`, as text) are values.
- `/<root>@plugin` is the URI of the plugin.
- A changed value is written in its place in the text.

### HISE and Cabbage

HISE and Cabbage make JUCE plugins. plugstate reads their state with the
JUCE layer.

- The binary of a HISE plugin has the marker `N4hise` (the type names of
  its classes). Then `doc.framework` is `hise`.
- The state of a HISE plugin is a ValueTree `ControlData`. Its controls are
  nodes with `id` and `value` under `/ControlData/InterfaceData/Content`,
  and `doc:params()` gives them.
- Circvit Bass (HISE, Windows, through yabridge) was tested. Its state
  has the `vstw` layer (see
  [The state of JUCE plugins](juce-plugin-state.md#the-layers-of-a-state)).
- No Cabbage plugin was tested.

### Windows plugins through yabridge

A Windows plugin through yabridge is a VST3 or CLAP plugin for paw, and its
state is the state of the Windows plugin, so the readers read it like the
state of any other plugin. plugstate does not read the binary of a Windows
plugin, so no hint comes from its markers.

### The VST3 SDK and VSTGUI

The VST3 SDK has no common form of state, because each plugin writes its own
bytes with `IBStreamer`, and the `binary` reader keeps them as `/State@data`.

- When at least 9 in 10 of the 32-bit words are plausible floats, the
  reader adds `/State/Floats`. Each float has the name `at<n>`, with `n`
  the place of its first byte. Such a list is a guess.
- A change to a float writes its 4 bytes only.
- The `sfizz` adapter knows the state of sfizz (see
  [plugstate](../../extensions/plugstate/README.md#adapters)).

## Hints from the binary of the plugin

`frameworks.binary_of(plugin)` finds the binary of a plugin in the plugin
folders (`CLAP_PATH`, `VST3_PATH`, `LV2_PATH`, else the usual folders).
`frameworks.markers(path)` reads the binary once and gives the name of a
framework and the version of JUCE. paw does not run the binary, and it does
not read the bridge of Windows plugins (`yabridge`).

| Marker | Framework |
| --- | --- |
| `N4hise` | `hise` |
| `JucePlugin_`, `JUCE v` | `juce`, with the version after `JUCE v` |
| `DISTRHO` | `dpf` |
| `lsp-plug.in` | `lsp` |
| `nih_plug` | `nih-plug` |
| `Dplug` | `dplug` |
| `iPlug2` | `iplug2` |
| `VSTGUI` | `vstgui` |

The hint `iplug2` lets the `iplug2` reader open a state without a string
`###...###`, and the hint `hise` makes a JUCE state report the framework
`hise`.

## The module

`require("plugstate.frameworks")` gives the functions below.

| Function | Result |
| --- | --- |
| `open(state, format, opts)` | the document of a state (paw's base64). `opts`: `hint`, `param_info` (as `paw.api.device_get` gives it), `desc` (a description of a JUCE plugin), `framework` (only that reader) |
| `open_device(id, state)` | the document of a device, with its hints. Without `state`, the state now |
| `generate(preset, format, current, opts)` | the state of a preset for a device of `format`: the base of the preset, else `current`, with the edits |
| `reader(def)` | adds a reader: `{ name, title, detect(data, format, ctx), open(data, format, ctx) }`. A reader added later is asked first |
| `binary_of(plugin)`, `markers(path)` | the binary of a plugin, and the framework that its markers name |

A document has the functions of the JUCE document: `get`, `query`, `set`,
`remove`, `insert`, `params`, `param`, `set_param`, `dump`, `diff`,
`write`, `write_as` and `layer_names`. A document also has the fields below.

| Field | Content |
| --- | --- |
| `doc.framework` | the name of the framework |
| `doc.title` | the name of the framework for a person |
| `doc.root` | the tree |
| `doc.notes` | what the reader could not find, for example the parameters of an iPlug2 state without the list of the host |

`doc:write_as(format, template)` gives the data in another format. Only CLAP
and VST3 hold the same data, because an LV2 state is Turtle text and the data
of CLAP or VST3 does not go into it.

## Limits

- A reader knows the form of the state, not the meaning of each value.
  A description gives names to the paths of a JUCE plugin.
- A plugin can refuse a state or ignore a value in it. Some VST3 plugins
  take a state from paw, and then their controller restores the earlier
  parameters (VoLum).
- A nih-plug state that Zstandard compresses opens as a `binary` state.
- The JSON reader and the LV2 reader change values only. They do not add
  or remove keys.
