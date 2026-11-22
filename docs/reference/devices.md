# Devices

<!-- tags: built-in-devices devices -->

A device is an instrument or an effect on a track. paw has built-in devices, hosts plugins (see [Plugins](plugins.md)), and runs devices written in Lua (see [Lua devices](lua-devices.md)), and all kinds have parameters, presets, a wet/dry mix and an output gain.

## Built-in devices

| Kind | Parameters and behavior |
| --- | --- |
| `synth` | `wave` (sine, saw, square, triangle), `attack`, `decay`, `sustain`, `release`, `cutoff`, `resonance`, `gain` |
| `drums` | `gain`, `kick_tune`, `decay`. A synthesized kit on the General MIDI drum notes: kick (35, 36), rim (37), snare (38, 40), clap (39), closed, pedal and open hat (42, 44, 46: the closed and pedal hats stop the open hat), six toms (41 to 50), crashes, china and splash (49, 57, 52, 55), ride (51, 59), ride bell (53), tambourine (54), cowbell (56). Output pairs: Kit, Kick, Snare, Hats, Toms, Cymbals and Percussion (see [Routing](routing.md#instruments-with-several-outputs)). |
| `sampler` | `gain`. One sound file for each note, each with a level, pan, tuning and choke group. The kit is the state of the device: text lines `note level pan tune group path`, set with `paw.api.device_set(id, "state", base64)`. paw reads the files off the audio thread. `extensions/drums` makes kits from folders. |
| `gain` | `gain` |
| `delay` | Echoes: `time` (ms), or `sync` to a note length at the current tempo (`1/8.`, `1/4T`, and other values), `feedback`, `mix` (the level of the echoes, the dry sound stays at full level), `mode` (stereo or ping-pong), `low_cut` and `high_cut` on the repeats (off at the ends of their ranges), `width`. A new time glides, like the time of a tape delay. |
| `chorus` | Doubles and widens a guitar or a pad: `rate` or `sync`, `depth`, `delay`, `feedback`, `spread` (the right LFO behind the left LFO), `mix`, `voices`. |
| `flanger` | A sweeping, jet-like effect with `rate` or `sync`, `depth`, `delay`, `feedback` (negative for the hollow sound), `spread`, `mix`. |
| `phaser` | `rate` or `sync`, `depth` (up to three octaves each way), `center`, `stages` (2 to 12), `feedback`, `spread`, `mix`. |
| `tremolo` | `mode` (tremolo, or auto-pan at equal power), `rate` or `sync`, `depth`, `shape` (sine, triangle, a soft square). A synced LFO locks to the position of the song while it plays. |
| `limiter` | The last device on the master: `ceiling` (default -1 dB), `gain` (drive into it), `release`, `true_peak` (on by default: the peaks between samples also stay below the ceiling, as a BS.1770 meter reads them, with 0.2 dB of margin). It looks 5 ms ahead, so no sample goes above the ceiling. The rest of the mix waits for it. `paw.params.read(l, "meters")` gives `gr` and `input` in dB. |
| `eq` | A parametric equalizer: eight bands, each with `bN_on`, `bN_type` (low cut 12 or 24 dB/oct, low shelf, bell, high shelf, high cut 12 or 24, notch, band pass), `bN_freq`, `bN_gain`, `bN_q`, and `output`. Flat until a band moves. Settings glide without clicks. `paw.params.read(eq, "curve", n)` gives its response in dB at `n` frequencies from 20 Hz to 20 kHz on a log scale. |
| `compressor` | For a vocal, a drum bus, or parallel compression (`mix` below 100 %): `threshold`, `ratio` (the top of its range is a limit), `knee`, `attack`, `release`, `auto_release` (a fast release after short peaks, a slow release after long compression), `makeup`, `auto_makeup` (gives back half of what a 0 dB peak loses), `lookahead` (reported as latency), `detector_hp` (so that the kick does not drive it), `detect` (peak or RMS), `mix`, `link`, `listen` (play the side-chain as the detector hears it). With a side-chain (see [Routing](routing.md#side-chains)), the detector hears that track instead of its input. `paw.params.read(c, "meters")` gives `gr`, `input` and `output` in dB. `"curve"` gives the static curve. |
| `reverb` | Rooms and plates: an eight-line feedback delay network whose lines drift slowly, so that it does not ring. `size`, `decay` (seconds to fall 60 dB), `predelay`, `damp_high` and `damp_low` (where the highs and lows decay sooner, off at the ends of their ranges), `diffusion`, `early` (early reflections against the tail), `width`, `mix` (the dry sound stays at full level up to 50 %, and the wet sound reaches full level there). |
| `utility` | Level and stereo: `gain`, `pan` (a balance: the far side fades out), `width` (0 % is mono, 200 % is two times as wide), `mono_below` (no sides below this frequency, off at 20 Hz), `invert_l`, `invert_r`, `swap`, `dc` (a 5 Hz high-pass). |
| `saturation` | Warmth or grit: `drive`, `curve` (tape: soft and symmetric, tube: biased, adds even harmonics, hard clip), `oversample` (2x or 4x, so that the harmonics do not fold back as noise), `tone` (a high shelf after the curve), `mix`, `output`. Quiet audio passes at its own level. 31 samples late (0.65 ms at 48 kHz), reported as latency. |
| `meter` | Measures the audio and lets it through with no change. `paw.params.read(m, "meters")` gives `momentary`, `short_term` and `integrated` loudness (LUFS, EBU R 128 with its gates), `true_peak` (dBTP) and `sample_peak` held since `paw.params.read(m, "reset")` (or for 3 s with `hold`), and `rms_l`, `rms_r` and `correlation` over 300 ms. `"spectrum", n` gives dB in `n` bands from 20 Hz to 20 kHz. A value that is not ready is -200. |
| `tuner` | Tunes a guitar or a bass: `paw.params.read(t, "pitch")` gives `freq`, `note` (`E2`), `midi`, `cents` and `confidence`, from the last 85 ms (YIN). `reference` sets A4. `mute` silences the track while you tune. |
| `gate` | Removes the spill between hits on a drum track, or the noise between phrases: `mode` (gate or expander), `threshold`, `range`, `ratio` (expander), `attack`, `hold`, `release`, `hysteresis`, `lookahead`, `detector_hp`, `detect`, `link`, `listen`. A side-chain can key it, as for the compressor. The same meters as the compressor. |

### Displays and windows

- In the device panel, some devices show a display below their names. The `eq` shows its curve, the `compressor`, `gate` and `limiter` show their gain reduction, the `meter` shows its loudness, and the `tuner` shows a needle.
- `:eq` and `:tuner` show the equalizer or the tuner of the track, and add one if the track has none. `:loudness` shows the meter of the master.
- In the graphical window, each of these opens a window of its own, also from the track menu, and from the timeline menu for the meter.
- In the window of the equalizer, drag the dot of a band to move it, and use the wheel over a dot to change its Q. A double click on a dot disables the band, and a double click on empty space enables a band there as a bell.

### Cost

The cost of one instance on one core at 48 kHz (`bench/devices.lua`):

| Device | CPU |
| --- | --- |
| `reverb` | 1.0 % |
| `saturation` | 0.7 % at 2x (about two times that at 4x) |
| `limiter` | 0.5 % |
| `chorus`, `meter`, `phaser` | 0.3 % |
| `eq` (all bands on), `flanger` | 0.2 % |
| `compressor` | 0.1 % |
| `gate`, `delay`, `tremolo`, `utility`, `tuner` | less than 0.1 % |

### Built-in device functions

| Function | Result |
| --- | --- |
| `paw.params.presets(kind)` | The built-in settings of a device: vocal high-pass and presence, drum bus glue, plate, room and others. They are in [device_presets.lua](../../runtime/lua/paw/device_presets.lua). |
| `paw.params.apply(device, name)` | Apply one of the built-in settings. |
| `paw.params.format(param, value)` | A value in its unit: `2.5 kHz`, `-18.0 dB`, `4:1`, `1/8.`. |
| `paw.params.read(device, what, ...)` | The meters, curves and readings of a device (see the table above). |

Frequencies, times and ratios move on a log scale from the keyboard and on sliders.

A new built-in device implements the `Device` trait in `paw-engine`, and it is added to the registry in [devices/mod.rs](../../crates/paw-engine/src/devices/mod.rs).

## Wet/dry mix and output gain

Each device, built-in or plugin, has two parameters from paw after its own parameters.

| Parameter | Range | Effect |
| --- | --- | --- |
| `fx_wet` | Wet, 0 to 100 % | The part of the processed sound. The dry part is the input of the device, delayed by the latency of the device so that the two align. |
| `fx_gain` | Output, -24 to +24 dB | The output level of the device. |

- You set, automate, bind and save them in presets like any other parameter. In Lua, `paw.fx.set_wet(device, 50)` sets the mix.
- The card of a device in the graphical window shows both, below the preset.
- The device panel shows `wet 50%` on the line of the device when the mix is not 100 %, and `+` and `-` on that line change it. Both parameters are the last rows of the device.
- A bypass, the end of a bypass, and any change of the mix fade over 5 ms, with no click. A bypassed device adds no delay.

## Presets

A preset is the settings of a device, saved with a name. You can load it into the same kind of device in any project, and a load is one undo step.

| Command | Key (device panel) | Effect |
| --- | --- | --- |
| `:preset` | `c` on a device | Select a preset in a picker: your presets first, then the presets of the device. |
| `:preset Warm` | | Load a preset by name, or by a part of the name. |
| `:preset.next`, `:preset.prev` | `]p` `[p` | The next or previous preset. |
| `:preset.save Warm` | `<Space>dw` | Save the device as a preset. |
| `:preset.default` | `<Space>dW`, or `Ctrl-s` in the picker | New devices of this kind that you add by hand start from the loaded preset. `:preset.default none` stops this. |
| `:preset.delete` | | Delete a preset. |

In the graphical window, the card of a device shows its preset between `◀` and `▶`, and a click on the name opens a menu of the presets, with "Save as a preset…".

The presets of a device are the presets that its format lists, as the table below shows.

| Format | Presets |
| --- | --- |
| CLAP | CLAP preset discovery (for example, the patches of Surge XT) |
| VST3 | `.vstpreset` files in `~/.vst3/presets/<vendor>/<plugin>`, `/usr/share/vst3/presets`, `$VST3_PRESET_PATH` and the bundle of the plugin |
| LV2 | the presets that lilv knows |
| built-in | the tables in `runtime/lua/paw/device_presets.lua` |

Your presets are JSON files in `~/.local/share/paw/presets/<kind>/` (`paw.opt.presets_dir` sets a different directory). Each file holds the state of the plugin and the value of each parameter, and `defaults.json` in the same directory names the default preset of each kind.

| Function | Effect |
| --- | --- |
| `paw.fx.save(device, name)` | Save a preset. |
| `paw.fx.load(device, name)` | Load a preset. |
| `paw.fx.presets(device)` | The list of presets. |
| `paw.fx.step(device, 1)` | The next preset. |
| `paw.fx.set_default(kind, name)` | Set the default preset of a kind. |
