# The audio engine

<!-- tags: engine threads latency xruns sleep -->

The engine plays the project on the audio thread and on a pool of worker threads. [About the audio engine](../explanation/about-the-audio-engine.md) describes the design.

## Commands

| Command | Effect |
| --- | --- |
| `:engine` | Show the backend, the device, the sample rate, the threads and the xruns. |
| `:engine pipewire rate=48000 buffer=256` | Restart the engine with a backend, a sample rate and a block size. |
| `:engine threads=4` | Set the number of threads (`paw.opt.threads`). |
| `:engine.status` | Show the problems while the song played, in one line: CPU, xruns, late plugin blocks, dropped MIDI events, lost recorded frames, stopped devices. |

## Threads

Playback and renders use one thread for each core.

| Way | Effect |
| --- | --- |
| `paw.opt.threads = 4`, `:engine threads=4` | Use four threads. |
| `paw.opt.threads = 1` | Use the audio thread only. |
| `paw.opt.threads = 0` | Default: one thread for each core. |
| the `threads` option of a render | The number of threads for one render: `paw.render(path, { threads = 1 })`. |

- `paw.api.engine_get().threads` gives the number of threads in use.
- When the audio thread has real-time priority, the worker threads get the same priority, and if the system refuses this priority, the engine uses only the audio thread.
- A render is the same to the bit with any number of threads.
- Live, the engine uses the worker threads only when one thread needs a quarter or more of the time of a block, so a small project plays on the audio thread only and the worker threads sleep. After a stop, the engine remembers how much work the song needed.
- A render shares a group of tracks between the threads when that group has enough work, because less work finishes sooner on one thread.
- Between blocks, the worker threads sleep.

## Devices at rest

A device at rest sleeps through silence, which means that the engine does not run it. Skipping the device saves processor time while the song stops and in the silent parts of a song.

| Device | At rest |
| --- | --- |
| `synth`, `drums`, `sampler` | No note sounds. |
| `reverb`, `delay`, `chorus`, `flanger`, `phaser` | The input is silent and the tail is below -120 dB. The device then clears its tail. |
| `eq`, `utility`, `tremolo`, `gain` | The input is silent and the settings do not change. |
| A CLAP plugin | The plugin says that it can sleep, or that its tail is complete. |
| A VST3 plugin | Its tail is complete, and its output is silent. |
| `compressor`, `gate`, `limiter`, `meter`, `tuner`, `saturation`, LV2 plugins | Never. |

- A note, a sound at the input, or a change of a parameter wakes the device.
- The sound is the same to the bit when devices sleep and when they do not.
- `paw.opt.device_sleep = false` makes each device run on each block, and the `sleep` option of a render does the same for one render.

## Edit quality

`paw.opt.quality = "edit"` (`:set quality=edit`) lowers the costly settings of the built-in devices while paw plays live, so that a large project costs less processor time while you edit it. The change takes effect at the next block, with no click of yours and no restart. `:set quality=full` gives back the full sound, and `"full"` is the default.

| Device | In edit quality |
| --- | --- |
| `saturation` | No oversampling, whatever `oversample` says. The curve shapes each sample at the rate of the project, so loud high notes add some aliasing. The latency stays the same. |
| Other built-in devices | No change. |

- A render, an export, stems, a bounce and a freeze always play at full quality, whatever the option says (see [Export](export.md#behavior)).
- The status line shows `edit q` while the option is `"edit"` (see [Status line](status-line.md)).
- Plugins and Lua devices play as they always do.
- The `reverb`, `chorus` and `compressor` keep their sound in edit quality. Each costs less than a `saturation` at 4x, and they have no setting that paw can lower without a change that you would hear in the mix.
- If you switch back to full quality while the song plays, the first 31 samples of each `saturation` can have a short click.

## The engine at rest

When the song is stopped and nothing sounds, the whole engine rests. It then writes silence for each block and does no other work: it does not clear the buffers of the tracks, add them up or measure them.

The engine rests after 8 blocks in a row in which all of these are true:

- The transport is stopped, and no count-in runs.
- No clip of the clip launcher waits to start.
- No track hears an audio input: no track is monitored or armed with an audio input.
- No sound file plays on its own (a preview or an audition).
- Each device sleeps (see [Devices at rest](#devices-at-rest)), and the output is silent. A reverb that still rings, or a device that never sleeps, such as a `compressor` or a CLAP plugin that never says that it can sleep, keeps the engine awake.
- The meters of the tracks have fallen below -100 dB, and the delay of each path (see [Delay compensation](#delay-compensation)) holds only silence.

A message from the kernel, such as a note that you play, a change of a parameter or the start of the transport, wakes the engine in the same block. A MIDI input event does the same. A plugin that asks paw to run it, for example after you move a knob in its own window or after it asks for a restart, wakes the engine in the next block, and so does a state or a preset that you load into a device. So the first sound comes in the same block as when the engine does not rest. When the engine starts to rest, it sets the meters of the tracks to zero.

- `paw.api.engine_get().engine_rests` counts the blocks in which the engine rested. In these blocks each device sleeps, so `device_sleeps` counts them too.
- `paw.opt.device_sleep = false` stops the rest too, because it is one switch for both.
- A render never rests, so a render is the same to the bit with `sleep` on and off.

## State of the engine

`paw.api.engine_get()` gives a table, and `paw.frontend.state()` gives the same values to the graphical window and the status line.

| Field | Value |
| --- | --- |
| `backend`, `device`, `input_device` | The backend and the devices. |
| `sample_rate`, `block` | The sample rate and the block size. |
| `input_latency`, `output_latency` | The latencies, in ms (see [Audio devices](audio-devices.md#latency)). |
| `latency` | How far the output is behind the transport, in ms, with delay compensation. |
| `threads` | The number of threads in use. |
| `shared_groups` | The groups of tracks that the engine shared between threads, since it started. |
| `device_sleep` | True when devices at rest sleep (`paw.opt.device_sleep`). |
| `device_runs`, `device_sleeps` | The blocks that devices ran, and the blocks that devices at rest slept through, since the engine started. |
| `engine_rests` | The blocks in which the whole engine rested, since it started (see [The engine at rest](#the-engine-at-rest)). |
| `lost` | The name of a lost device, or nil. |
| `xruns` | The number of xruns. |
| `late_blocks` | The number of blocks that plugins did not give in time. |
| `midi_dropped` | The number of MIDI events dropped because a queue was full, or because a slow plugin or Lua device was late for more events than paw keeps for it. |
| `record_dropped` | The number of frames of a take lost because the disk was slow. |
| `devices_stopped` | The number of stopped devices. |

## Delay compensation

- A device that looks ahead reports the delay of its output. CLAP, VST3 and LV2 plugins report it, and of the built-in devices the `limiter`, the `saturation`, and the `compressor` and `gate` with `lookahead` report it.
- paw delays each other path to the same place by the difference, through buses and sends, so that all the sound arrives together.
- A render removes the delay from the start of the file.
- paw does not delay the clips of a track to match the sound that is routed into the track.

## The transport in a subproject

The devices on the tracks of a subproject see the bars of the subproject in
their transport. Bar 1, beat 0, is the start of the clip of the subproject
that plays, and the tempo is the tempo of the song at that place. The
devices on the tracks of the song see the bars of the song. For example, a
clip of a subproject at bar 33 of the song gives bar 1 to a delay inside
the subproject, and bar 33 to a delay on a track of the song.

- CLAP plugins get these bars in `clap_event_transport`, VST3 plugins in
  `ProcessContext`, LV2 plugins in their time position, and Lua devices
  in their block (see [Lua devices](lua-devices.md#the-block)).
- The built-in devices that follow the tempo, for example the LFO of the
  modulation devices, follow the same transport.
- Before the first clip of the subproject, and between its clips, the
  devices see the time of the clip before, or of the first clip.
- A subproject with a meter of its own gives its devices its own meter.

## A device that fails

- paw guards each device on the audio thread. A device that panics is marked failed, and the chain ignores it after that, so an instrument is silent and an effect lets its input through.
- The event `device.stopped` reports the failure, in the same way as for a plugin whose helper crashed. The device panel shows the device as stopped, and `:device.restart` makes a new device.
- paw replaces samples that come out of a device as NaN or infinity with silence at its output, so they never reach a fader, a meter or the master. The event `device.invalid` and a message report this one time.
- A panic in a function of `paw.api` doesn't stop paw. The call gives an error that names the function, for example `paw.api.clip_get stopped on a bug in paw: index out of bounds`, and paw shows it as a message. Save your work and report the bug.
- A panic in any other part of paw writes a safety copy of the work that is not saved, before paw stops. paw then restores the terminal and says where the copy is, and `:recover` offers it at the next start (see [Project files](project-files.md#safety-copies)).

## Memory

paw releases decoded audio that the project and the undo steps do not use, when another project opens and at intervals while you edit. So a long session does not keep each file that it played.

## Scripts and the engine

| Function | Effect |
| --- | --- |
| `paw.api.engine_restart(spec)` | Restart the engine. With no `backend` in `spec`, the engine keeps the backend that runs (see [Audio devices](audio-devices.md#test-backends)). |
| `paw.api.engine_audible(ids)` | Play only these tracks, and what their sound goes through. `scope_rest=mute` uses it (see [Scopes](narrowing.md)). |
| `paw.api.engine_hold(track, file)` | Play a file instead of a track. `scope_rest=frozen` uses it. |
| `paw.wait(ms)` | Let time pass, with timers and events. `paw.api.sleep` does not run timers or events. A script run with `-l` is otherwise one long turn. |
