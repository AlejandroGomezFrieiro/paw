# Lua devices

<!-- tags: lua-devices luadev paw.dsp -->

A device can be a Lua file with parameters and a `process` function that gets each block of sound. Its kind is `lua:<file name>`, and the device picker shows it next to the built-in devices and the plugins. You set, automate, bind and save its parameters in the project and in presets, as for any other device. The Lua module is `paw.dsp`. For the steps, see [How to write a device in Lua](../how-to/write-a-device-in-lua.md).

## Where paw finds scripts

- `~/.config/paw/devices/`
- the `devices/` directory of each extension, where an extension ships its devices
- the directories added with `paw.luadev.add_dir(dir)`.

A script in the configuration directory replaces a script of an extension with the same name. `extensions/luafx` has four examples, which are a gain and pan, a drive, a chord maker and a sine instrument. Modules next to the file are available to `require`.

## The device

The file returns its device, made with `dsp.device { ... }`.

| Field | Value |
| --- | --- |
| `name` | The name. The default is the name of the file. |
| `category` | `"effect"` (default) or `"instrument"`. |
| `vendor` | The vendor. |
| `params` | A list of `{ key, name, min, max, default, unit }`, or of choices: `{ key = "mode", choices = { "Soft", "Hard" }, default = "Soft" }`. The value of a choice is its number, from 0. |
| `midi_effect` | True means that the events that the device sends replace the events that come in (an arpeggiator, a chord maker). |
| `sidechain` | True means that the device can listen to a different track (see [Routing](routing.md#side-chains)). |

| Function | When paw calls it |
| --- | --- |
| `dev.init(sample_rate, max_block)` | One time, before the first block. |
| `dev.process(b)` | For each block. |
| `dev.sample(l, r, b)` | For each frame, if there is no `process`. Returns the new pair. |
| `dev.call(method, data)` | When a script calls the device (see below). |

`dev.values` holds the parameter values of the last block.

## The block

| Field of `b` | Value |
| --- | --- |
| `b.left`, `b.right` | The two channels: `ffi` float arrays, counted from 0, `b.frames` long. An effect changes them. An instrument adds to them. |
| `b.frames` | The number of frames. |
| `b.params` | The parameter values, by key. |
| `b.sample_rate` | The sample rate. |
| `b.playing`, `b.tempo`, `b.beat`, `b.seconds`, `b.bar`, `b.bar_start`, `b.sig_num`, `b.sig_den` | The transport. In a subproject, `b.beat`, `b.seconds` and the bars count from the start of the clip of the subproject that plays, and `b.bar` is 0 in its first bar (see [The audio engine](engine.md#the-transport-in-a-subproject)). |
| `b.key_left`, `b.key_right` | The side-chain, or nil when no track is connected. |
| `b.events`, `b.nevents` | The MIDI events (see below). |

LuaJIT compiles the loops over the arrays, and a gain costs less than one microsecond for each block.

### MIDI

`b.events[0]` to `b.events[b.nevents - 1]` are the events of the block, in order.

| Field of an event | Value |
| --- | --- |
| `frame` | The frame in the block. |
| `type` | The type (see below). |
| `channel` | 1 to 16. |
| `key` | The note, or the controller number. |
| `value` | The velocity or the value. |
| `attr` | The MIDI 2.0 attribute of a note-on, as one number: type × 65536 + data. 0 for none. `dsp.attr(e)` gives `{ type, data }` or nil. |

| Type | `key` and `value` |
| --- | --- |
| `dsp.NOTE_ON` | the note, the velocity (0 to 1) |
| `dsp.NOTE_OFF` | the note |
| `dsp.CC` | the controller, the value (0 to 1) |
| `dsp.BEND` | the value (-1 to 1) |
| `dsp.PRESSURE` | the value |
| `dsp.PROGRAM` | the program |
| `dsp.ALL_NOTES_OFF` | |
| `dsp.OTHER` | all other events (the controllers of one note, RPNs) |

| Function | Effect |
| --- | --- |
| `b:note_on(frame, key, velocity, channel, attr)` | Send a note-on to the next devices. |
| `b:note_off(frame, key, channel)` | Send a note-off. |
| `b:cc(frame, number, value, channel)` | Send a controller. |
| `b:send(frame, type, key, value, channel)` | Send any event. |
| `b:pass(e)` | Send an event that came in, with no change. |

The device can send events in any order. paw sends on the events that come in and adds the events that the device sends, except that a device with `midi_effect = true` replaces the events that come in.

## Helpers

| Function | Result |
| --- | --- |
| `dsp.gain(db)`, `dsp.db(gain)` | A gain from dB, dB from a gain. |
| `dsp.mtof(note)` | The frequency of a note. |
| `dsp.pan(p)` | Equal-power gains. |
| `dsp.clamp` | A value inside limits. |
| `dsp.saturate(x)` | A soft clip. |
| `dsp.buffer(n)` | A float array, for a delay line. |
| `dsp.onepole(hz, sr)` | A one-pole filter, with `:lowpass(x)` and `:highpass(x)`. |
| `dsp.biquad(shape, hz, q, gain_db, sr)` | A biquad filter, with `:set(...)` and `:process(x)`. Shapes: lowpass, highpass, bandpass, notch, peak, lowshelf, highshelf. |
| `dsp.smoother(ms, sr)` | A smoother, with `:next(target)` to glide to a new value. |
| `dsp.map(path)` | A file of 32-bit floats in memory (see below). |

Use one filter or smoother for each channel.

## Calls from scripts

- `dev.call(method, data)` answers `paw.api.device_call(device, method, data)` from the Lua of the kernel.
- The call runs in the state of the device, between two blocks, and a block that comes during the call waits for it, so keep the call short.
- `data` is a string, and the return value (a string, a number or nothing) is the answer. An error is an error of the caller, and the device continues to play.
- `paw.api.device_post(kind, topic, data)` calls `dev.call(topic, data)` on each device of a kind. It calls the devices that exist immediately, and it calls each device made later before its first block (the private devices of an offline render too). paw keeps the latest data of each topic for these devices, so devices made at any time agree, and `nil` removes a topic.

## Large data

Large data, e.g., the samples of a sampler or the phrases of a singer, is too big for a string on each call, so a script passes it through a file.

- The script writes the data to a file of 32-bit floats and calls the device with the path.
- The device maps the file with `dsp.map(path)`, and the result `m` has `m.data[0]` to `m.data[m.n - 1]`. paw reads the file one time, and all the devices that map the same file share it.
- Map a file in `dev.call` or `dev.init`, and not in `process`. `m:close()` releases the file.
- For new data, write a new file, and do not write over a file that a device has in memory.

`extensions/utau` plays its synthesized voice this way.

## Reload

- paw looks at the files each second (`paw.opt.lua_devices_watch`, in ms, 0 for never). When a script changes, paw loads it again, and its devices start again from the new code with their parameter values, and a new parameter starts at its default.
- `:device.reload` loads the device selected in the panel again immediately, or all the Lua devices of the track.
- `:device.scripts` lists the scripts, where they are, and why a script did not load.

## Errors

- If a script does not load (a syntax error, no `process`, a top level that runs for more than five seconds), paw reports it with the file and the line, and a device that runs an earlier version continues.
- If a script fails while it runs, only that device stops, and paw shows the device as stopped, with the error (`tilt.lua:23: attempt to index a nil value`). The track continues, so an effect lets the sound through and an instrument is silent. `:device.restart`, or a save of the file, starts the device again.

## Process

Each Lua device runs in a helper process, as a plugin does, with a LuaJIT state of its own. The engine gives the helper each block through shared memory and waits for it inside the block, so a Lua device adds no latency, and a slow script costs its own track a block of sound.

The events of that block go to the script at the start of the next block that it takes, so a note that you play at that time sounds and a note-off is not lost.

A script that hangs or crashes (`ffi` can crash) stops without an effect on other devices, also with `--plugins-in-process`. For the reason, see [About the plugin sandbox](../explanation/about-the-plugin-sandbox.md).
