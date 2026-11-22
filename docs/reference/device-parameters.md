# Device parameters

<!-- tags: device-parameters param_info parameter-ids -->

paw describes the parameters of each device in the same way, for built-in devices, Lua devices, and CLAP, VST3 and LV2 plugins. A script reads the description in `paw.api.device_get(id).param_info`, which is a list in the order of the device. The list of a plugin is known when the plugin runs.

## The fields of a parameter

| Field | Value |
| --- | --- |
| `index` | The place of the parameter in the list, from 1. |
| `key` | The name of the parameter in scripts and in the project, made from its name: `input_gain`. It is unique in the device. |
| `id` | The id that the device itself gives the parameter (see [Ids](#ids)). |
| `name` | The name to show: `Input gain`. |
| `group` | The group that the device puts the parameter in, with levels joined by `/`: `Osc 1/Pitch`. Empty when the device gives no group. |
| `min`, `max`, `default` | The range and the default value, in the units of the device. VST3 values are from 0 to 1. |
| `unit` | The unit: `dB`, `Hz`, `ms`. Empty when the device gives no unit. |
| `kind` | `continuous`, `stepped` (whole steps only), `enum` (each step is a named option) or `boolean` (off at `min`, on at `max`). |
| `steps` | For a parameter that is not continuous, the number of equal steps from `min` to `max`. 0 for a continuous parameter. |
| `choices` | The names of the steps, where paw knows them: built-in options, LV2 scale points, CLAP enumerations. |
| `automatable` | The device lets the host automate the parameter. |
| `read_only` | The device shows the value, but does not take new values. |
| `per_note` | The format lets the parameter take a different value for each note (CLAP). |
| `automated` | A lane of the track that is on moves the parameter. |

The last two parameters of each device are the wet/dry mix (`wet`) and the output gain (`gain`) of paw, which [Devices](devices.md) describes. Their `id` is their key.

## Ids

| Device | `id` | Example |
| --- | --- | --- |
| Built-in or Lua | The key | `cutoff` |
| CLAP | The CLAP parameter id, in decimal | `2683833795` |
| VST3 | The VST3 `ParamID`, in decimal | `536350147` |
| LV2 | The symbol of the control port (also the key) | `g_in` |

- A plugin keeps the id of a parameter in its new versions, also when it puts its parameters in a different order or gives them new names.
- When paw saves a project, it writes the id of each key that the project uses (a value or a lane) in `param_ids` of the device. When the plugin runs again, the parameter with that id gets that key, so the values and lanes stay on their parameters after an update of the plugin.
- paw does not list the parameters that a CLAP or VST3 plugin marks as hidden, the VST3 parameters that are read-only, and the `MIDI CC` parameters of JUCE plugins.

## The plugin

`paw.api.device_get(id).plugin` tells which plugin the device is, as the format names it, and it is `nil` for a built-in or Lua device.

| Field | Value |
| --- | --- |
| `format` | `clap`, `vst3` or `lv2` |
| `id` | The CLAP plugin id (`org.surge-synth-team.surge-xt`), the VST3 class id as 32 hexadecimal digits, or the LV2 URI |
| `name`, `vendor` | As the plugin gives them |
| `version` | As the plugin gives it. Empty for an LV2 plugin without `lv2:minorVersion`. For a plugin that paw found before it kept versions, empty until `:plugins.rescan`. |

`paw.api.device_types()` gives `id` and `version` for each kind of device too, and `features`, which are the CLAP features of a plugin (`ara:supported`) or the subcategories of a VST3 plugin. For a plugin that paw found before it kept features, the list is empty until `:plugins.rescan`.

## Values as text

- `paw.api.device_param_text(device, param, value)` writes a value as the device writes it, so a plugin gives its own text (`-6.00 dB`, `Herm Thin`). Without `value`, it writes the value now.
- `paw.api.device_param_parse(device, param, text)` gives the value that a text is. A plugin reads the text itself, and an error tells when the device cannot read the text.
- A device with no text of its own (a built-in device, an LV2 plugin) uses the text of the device panel, for example `2.5 kHz`, `-18.0 dB`, `120 ms`, the name of an option, `on` or `off`. paw reads these back, also with a unit of a different size (`2.5 kHz` for a parameter in Hz).

## Read and set a parameter

Each function finds the parameter by its key, by its `id`, or by its name (in capital or small letters), in that order.

| Function | Result |
| --- | --- |
| `paw.api.device_param(device, param)` | The fields of the parameter, with `value` (now) and `text` (that value as the device writes it). |
| `paw.api.device_set_param(device, param, value)` | Sets the value, as one undo step. The value is a number or a text (`"440 Hz"`, `"Saw"`). |

## Events

`param.touched` tells that a parameter moved. Its fields are `device`, `param` (the key), `id` (the id of the device for the parameter) and `from`. `from` is `host` when paw set the value, and it is `editor` when the value moved in the editor of the plugin, and then the event also has `value`.

## Interchange

- The [interop](../../extensions/interop/README.md) extension writes a DAWproject file with the `id` of a CLAP or VST3 parameter as `parameterID`, and the plugin `id` as `deviceID`. It writes ids of 2^31 and more as negative numbers, as other programs do.
- The same extension writes a parameter envelope of a REAPER project as `<PARMENV 5:-1611133501`, with the place from 0 and the id after the colon, as REAPER writes it. REAPER and paw find the parameter by the id first.
