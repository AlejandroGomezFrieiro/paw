# Audio devices

<!-- tags: audio audio-devices -->

The engine opens one output device and one input device. The devices belong to the computer and not to the project, so paw keeps the choice in `$XDG_STATE_HOME/paw/audio.json` for the next start. If a remembered device is not connected, paw uses the default device of the system and shows a message. The options of the command line (`--output`, `--input`, `--no-input`, `--audio`) are described in [How to choose the audio devices](../how-to/choose-audio-devices.md).

## Commands

| Command | Effect |
| --- | --- |
| `:audio` | List the outputs, inputs and block sizes. The top line shows the sample rate, the block size, and the input and output latency. |
| `:audio.output <name>` | Use an output device. |
| `:audio.input <name>` | Use an input device. |
| `:audio.buffer <frames>` | Set the block size. |
| `:audio.reconnect` | Try to open a lost device immediately. |

- `Tab` completes the names.
- A name that matches no device is refused, with the list of the devices.
- A part of a name selects the device with the most channels that contains it. For example, `UR22` opens the full two-channel input of a Steinberg UR22mkII, and not one of the mono halves that PipeWire also offers.
- The engine indicator in the graphical window also selects the devices.

## Lua

```lua
paw.audio.devices()      -- { outputs = { { name, id, channels, sample_rate, min_block, max_block }, ... }, inputs = {...}, output, input }
paw.audio.use({ input = "UR22" })                 -- by name, id or a part of the name; "default" for the system's
paw.audio.use({ output = "UR22mkII Stereo", buffer = 128 })   -- buffer 0: the device's own block size
paw.audio.levels()       -- the level arriving at each input channel, 0 to 1
paw.api.engine_get()     -- device, input_device, sample_rate, block, input_latency, output_latency (ms)
```

| Function | Result |
| --- | --- |
| `paw.audio.devices()` | The outputs and inputs, each with `name`, `id`, `channels`, `sample_rate`, `min_block`, `max_block`, and the devices in use. |
| `paw.audio.use(spec)` | Use an output, an input or a block size. A device by name, id or a part of the name. `"default"` for the default device of the system. `buffer = 0`: the block size of the device. |
| `paw.audio.levels()` | The level at each input channel, from 0 to 1. |
| `paw.api.engine_get()` | The state of the engine (see [The audio engine](engine.md)). |

## PipeWire

- Each device is a PipeWire node, opened by its node name.
- The list does not show the "default" entries of the system, the streams of other programs, or sinks offered again as inputs.
- The block size is a request to PipeWire, set as the latency of the node, and the graph can use a different size. `paw.api.engine_get().block` gives the size in use.

## Latency

- cpal runs input and output as two streams, and a ring buffer joins them. The ring buffer holds at most one input period plus one output block.
- When the two clocks drift, paw drops the extra frames or repeats the last frame.
- `paw.api.engine_get()` gives `input_latency` (the capture delay of the system plus the ring) and `output_latency`, in milliseconds, as the backend measures them.
- The latency of recordings is described in [Recording](recording.md#recording-offset).

## A device that goes away

When the audio device goes away, for example because a USB interface is disconnected or the sound server stops, paw behaves as follows:

- The transport stops, and a take that records is closed and kept.
- paw says which device it lost and continues without sound, so you can still edit, save and render.
- Every three seconds, paw looks for the device. When the device is back, paw opens it again with the same sample rate, block size and input, and says so. The tracks keep their inputs.
- `:audio.reconnect` tries immediately. `paw.opt.audio_reconnect = false` stops the automatic tries, and then only the command reconnects.
- The engine indicator shows `lost: UR22mkII`, and
  `paw.api.engine_get().lost` names the device.

[MIDI](midi.md#midi-input) describes MIDI ports that go away.

## Test backends

The null backend (`--audio null`) can make test input and test MIDI ports, with the fields below.

| Field | Effect |
| --- | --- |
| `test_input` | `{ frequency, level, channels }`. Input channel `n` has a sine at `n` times the frequency. The input device is `test signal`. |
| `test_midi` | A list of names: MIDI ports to show in the lists. |
| `midi = true` | Open the real MIDI ports with the null backend, to try MIDI from hardware or from a different program with no sound. |

```lua
paw.api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 }, test_midi = { "Keys A" } })
```

The `test` backend is the null backend with a test device that can go away, and it has two functions.

| Function | Effect |
| --- | --- |
| `paw.api.audio_test_device({ fail_after = 100, back_after = 2000 })` | Lose the device 100 blocks into the next stream, and bring it back two seconds later. |
| `paw.api.midi_test_ports({ "Keys A" })` | Change the MIDI ports that the null backend shows. |
