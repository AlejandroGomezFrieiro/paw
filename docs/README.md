# The paw manual

The manual has four kinds of page. Tutorials teach paw with lessons that you
do. How-to guides give the steps for one task. Reference pages describe each
part of paw. Explanation pages tell why paw works as it does. In paw,
`:help` shows the same pages under the same four headings, and a page for
each extension (`:help notation`).

The tutorials and how-to guides start with the user guide, for musicians.
The guides are in groups by task. The guides for developers and for the
writers of extensions come after them.

## Tutorials

### Make music with paw

- [Make music with paw](tutorials/make-music/README.md): five lessons that make one song, from the first note to an MP3 file
  - [Your first song](tutorials/make-music/01-first-song.md): drums, a bass and chords in a loop of four bars
  - [Play a synth from a MIDI keyboard](tutorials/make-music/02-play-a-midi-keyboard.md): play live, record over the loop, quantize
  - [Record a guitar](tutorials/make-music/03-record-a-guitar.md): an amp chain, two takes, the best parts, a fade
  - [Arrange the song](tutorials/make-music/04-arrange-the-song.md): verse and chorus, markers, the tempo, find a part
  - [Mix and render the song](tutorials/make-music/05-mix-and-render.md): levels, pan, effects, a send, automation, WAV and MP3
- [The course](tutorials/course/README.md): seventeen short lessons for your first days with paw, also inside paw as `:tutor`

## How-to guides

### Install and configure

- [How to install paw with Nix](how-to/install-paw.md): the package, without the dev shell
- [How to start paw the first time and hear sound](how-to/start-paw-and-hear-sound.md): `paw doctor`, `:checkhealth`, a test tone
- [How to choose the audio devices](how-to/choose-audio-devices.md): in paw, at the start, in `init.lua`
- [How to lower the latency](how-to/lower-the-latency.md): the block size, and what to change when the sound crackles
- [How to connect a MIDI keyboard](how-to/connect-a-midi-keyboard.md): check that paw sees it, and play an instrument
- [How to use your own plugins](how-to/use-your-own-plugins.md): CLAP, VST3, LV2, where paw looks, Windows plugins through yabridge
- [How to use an ARA plugin on a vocal or a take](how-to/use-an-ara-plugin.md): play the clips through it, edit them, MIDI from the notes it heard
- [How to map a MIDI controller](how-to/map-a-midi-controller.md)

### Tracks and instruments

- [How to add a track with a virtual instrument](how-to/add-an-instrument-track.md): the built-in synth, a plugin, a preset
- [How to add an audio track for a microphone or a guitar](how-to/add-an-audio-track.md): the input, the monitor, an amp
- [How to name, color, reorder and group tracks](how-to/organize-tracks.md): groups are folders and buses
- [How to change the sound of an instrument](how-to/change-the-sound-of-an-instrument.md): parameters, presets, the editor of the plugin
- [How to change a sound at a point in the song](how-to/change-a-sound-at-a-point-in-the-song.md): a state lane gives a plugin another preset, model or state from a point, also in a rendered file
- [How to switch amp models and presets from paw](how-to/switch-amp-models-and-presets.md): presets, models and impulse responses of TONE3000 and Soundshed Guitar, scenes, snapshots
- [How to find and change a setting inside a plugin](how-to/find-and-change-a-setting-inside-a-plugin.md): the saved state of any plugin as a tree, the paths that a change touches, a value set from paw, presets of the changes
- [How to sign in to TONE3000 from paw](how-to/sign-in-to-tone3000.md): the `client_id`, the code, where the tokens go, the live tests
- [How to play a hardware synth from a track](how-to/play-a-hardware-synth.md)
- [How to route the outputs of a drum plugin](how-to/route-the-outputs-of-a-drum-plugin.md)

### Edit and arrange

- [How to move, copy, split and trim clips](how-to/move-copy-split-and-trim-clips.md)
- [How to change the velocity, length and pitch of notes, and quantize them](how-to/edit-notes.md)
- [How to loop a part of the song while you work](how-to/loop-a-part-of-the-song.md)
- [How to change the tempo and the time signature](how-to/change-the-tempo-and-time-signature.md): also in the middle of the song
- [How to undo, and return to an earlier state](how-to/undo-and-return-to-an-earlier-state.md): the undo tree
- [How to fit audio to the tempo](how-to/fit-audio-to-the-tempo.md)
- [How to work on one group of a large project](how-to/work-on-one-group.md)
- [How to arrange your screen: windows, tabs and layouts](how-to/arrange-your-screen.md): one view full screen, two clips side by side, a layout of your own

### Find things

- [How to find a command or a key you forgot](how-to/find-a-command-or-a-key.md)
- [How to find a track, a clip or a marker by name](how-to/find-a-track-clip-or-marker.md)
- [How to search the project and go through the results](how-to/search-the-project.md): `:vimgrep`, notes, queries, the quickfix list

### Record

- [How to record a guitar or a bass](how-to/record-a-guitar-or-a-bass.md): the instrument input, the level, the tuner, a take
- [How to record vocals with a count-in and a click](how-to/record-vocals-with-a-count-in-and-a-click.md)
- [How to record MIDI from a keyboard](how-to/record-midi-from-a-keyboard.md): a take, a take merged into a clip, a take over a loop
- [How to use the metronome](how-to/use-the-metronome.md): the click, the count-in
- [How to record takes over a loop and comp them](how-to/record-takes-and-comp.md)
- [How to punch in over a part](how-to/punch-in-over-a-part.md)
- [How to set the recording offset](how-to/set-the-recording-offset.md)

### Mix

- [How to set levels and pan, and keep the master out of the red](how-to/set-levels-and-pan.md)
- [How to add an effect and change its settings](how-to/add-an-effect.md): EQ, compressor, reverb, delay, presets
- [How to send several tracks to one reverb](how-to/send-several-tracks-to-one-reverb.md)
- [How to check the mix](how-to/check-the-mix.md): meters, loudness, mono
- [How to freeze a heavy track](how-to/freeze-a-heavy-track.md)
- [How to duck a track under the kick](how-to/duck-a-track-under-the-kick.md)
- [How to write automation with the faders](how-to/write-automation-with-the-faders.md)

### Render and share

- [How to export a song as WAV, FLAC or MP3](how-to/export-a-song.md): where the file goes, tags
- [How to export part of the song or a loop](how-to/export-part-of-the-song.md)
- [How to render stems](how-to/render-stems.md)
- [How to export MIDI for another program](how-to/export-midi.md)
- [How to move a song between paw and REAPER](how-to/open-a-reaper-project.md)
- [How to move a song between paw and other DAWs](how-to/move-a-song-to-another-daw.md): Bitwig Studio, Studio One, Cubase

### Projects and files

- [How to save, back up and open projects](how-to/save-and-open-projects.md): recent projects, safety copies
- [How to import audio and MIDI files](how-to/import-audio-and-midi-files.md): commands, the file manager, a drop on the graphical window
- [How to make and use track templates](how-to/use-track-templates.md)
- [How to relink lost media](how-to/relink-missing-media.md)

### When something goes wrong

- [How to fix no sound](how-to/fix-no-sound.md)
- [How to fix crackles and dropouts](how-to/fix-crackles-and-dropouts.md)
- [How to deal with a plugin that crashes or hangs](how-to/deal-with-a-plugin-that-crashes.md)
- [How to open a project without its plugins](how-to/open-a-project-without-its-plugins.md)
- [How to fix a plugin editor that does not work](how-to/fix-a-plugin-editor.md)
- [How to recover lost work](how-to/recover-lost-work.md)

### For developers and extensions

- [How to build and run paw from the source](how-to/build-paw-from-source.md): the dev shell, the demo song, the example configuration
- [How to configure paw](how-to/configure-paw.md): `init.lua`, options, colors, commands, keys, events
- [How to change the status line](how-to/change-the-status-line.md): sections and components in `init.lua`
- [How to load an extension](how-to/load-an-extension.md): a bundled extension, your own, or one from Nix
- [How to add a picker](how-to/add-a-picker.md): a list to choose from, with a key
- [How to write a snippet](how-to/write-a-snippet.md)
- [How to write a completion source](how-to/write-a-completion-source.md)
- [How to write a device in Lua](how-to/write-a-device-in-lua.md)
- [How to write a language server](how-to/write-a-language-server.md)
- [How to give an extension an editor in the graphical window](how-to/add-an-editor-to-the-window.md)
- [How to run the graphical window without a graphics card](how-to/run-the-window-without-a-graphics-card.md)
- [How to run the graphical window against a kernel on another machine](how-to/run-the-window-against-a-remote-kernel.md)
- [How to run the tests](how-to/run-the-tests.md): the Lua suite, the Rust tests, the tests of the graphical window
- [How to drive paw from an agent](how-to/drive-paw-from-an-agent.md): let an agent that writes code, or an assistant, edit a project
- [How to work on paw from another computer](how-to/work-from-another-computer.md): attach over the network or SSH, send files, hear the sound

## Reference

- [Keys, by idea](reference/keys.md): all the keys on one page, to keep near the keyboard
- [Motions, operators and modes](reference/grammar.md): the keys that the arrange view and the piano roll share
- [The key rule](reference/key-rule.md): the meaning of each key in every view, the leaders, the classic keys
- [The arrange view](reference/arrange-view.md): its keys, waveforms, lanes as rows, the tempo lane, take lanes
- [The piano roll](reference/piano-roll.md): its keys, insert mode, several clips, suggestions
- [The device panel](reference/device-panel.md): its keys
- [The mixer](reference/mixer-view.md): its strips and keys
- [The curve editor](reference/curve-editor.md): lanes, parameters, controllers and the tempo map as curves
- [The command line](reference/cmdline.md): completion, `:set`, unsaved work, messages
- [Ex commands](reference/ex.md): ranges, `:s` and `:g`
- [Windows, buffers and tabs](reference/windows.md): splits, tabs, layouts, narrowed tabs
- [Lists edited as text](reference/lists-edited-as-text.md): `paw://tracks`, `paw://sends`, devices, markers
- [The file manager](reference/file-manager.md): folders as text and as a tree
- [The quickfix list](reference/quickfix.md): Problems, location lists, `:cdo`
- [Pickers](reference/pickers.md): every picker, its keys, matching, audition, the Lua API
- [Search the text of the project](reference/grep.md): `:vimgrep`, `paw.grep`
- [Structural queries](reference/queries.md): `:select`, `:query`, `paw.query`
- [Help](reference/help.md): `:help`, tags, `:helpgrep`
- [The mouse](reference/mouse.md): each gesture in the terminal
- [The terminal screen](reference/screen.md): the parts of the screen, the bottom line, colors
- [Pictures in the terminal](reference/pictures.md): pixels in terminals that show images
- [The status line](reference/status-line.md): sections, components, `paw.statusline`
- [Options](reference/options.md): every option of `paw.opt`
- [The graphical window](reference/window.md): its command line, each gesture, the panes and the views in windows of their own
- [The graphical window in Lua](reference/window-lua.md): `paw.frontend.act`, menus, bands, panes, views that paint
- [The programs and their options](reference/programs.md): `paw`, `paw-gui`, `paw-mcp`, environment variables
- [Files that paw keeps](reference/state-files.md): configuration, state, cache, recent projects
- [The Nix package](reference/nix-package.md): the outputs of the flake and the checks
- [Audio devices](reference/audio-devices.md): the input and output devices, PipeWire, latency, a lost device, test backends
- [Recording](reference/recording.md): track inputs, monitoring, count-in, punch, pre-roll, files, import
- [Takes](reference/takes.md): takes, comping, take lanes
- [MIDI](reference/midi.md): controller moves, the event list, MIDI input and output, MPE, MIDI files
- [The audio engine](reference/engine.md): threads, the state of the engine, delay compensation, failed devices
- [Tempo and time signatures](reference/tempo.md): the tempo map, its commands, the timebase of audio clips
- [Routing: groups, VCAs, sends and side-chains](reference/routing.md): groups, linked faders, VCAs, outputs, sends, side-chains, output pairs
- [Narrowed tabs](reference/narrowing.md): a tab of one group, the rest of the song
- [Frozen tracks](reference/freezing.md): frozen and held tracks
- [Automation](reference/automation.md): automation modes, how the controls write automation
- [Stretched and looped clips](reference/stretch.md): stretch, pitch, warp markers, tempo, loops
- [Markers and regions](reference/markers.md): markers, regions, their keys and commands
- [Render](reference/render.md): `:render`, formats, tags, stems, bounce
- [Media files and audio clips](reference/media.md): paths, relink, sample rates, long files, fades, clip operations
- [Project files](reference/project-files.md): the project folder, `:w` and `:wa`, MIDI clip files, files from outside, changes from outside, safety copies, `:recover`
- [Devices](reference/devices.md): the built-in devices, wet/dry and output gain, presets
- [Plugins](reference/plugins.md): formats, scan, editors, processes, status, offline devices
- [Attachments](reference/attachments.md): native libraries that take a plugin, the clips and files they get (`paw_attach.h`)
- [Lua devices](reference/lua-devices.md): the fields of a device in Lua, the block, MIDI, helpers, reload
- [Device parameters](reference/device-parameters.md): the fields of each parameter, the ids of plugins, values as text, the plugin itself
- [The saved state of plugins](reference/plugin-state.md): the readers of each framework (JUCE, DPF, LSP, iPlug2, Dplug, nih-plug, Vital, LV2), their forms and trees, hints from the binary
- [The state of JUCE plugins](reference/juce-plugin-state.md): the layers of a state, paths, parameters, differences, descriptions of plugins, presets
- [MIDI controllers](reference/learn.md): bind knobs, faders and pads to controls
- [Harmony](reference/harmony.md): the chords and keys that paw reads, providers, theory functions, voicings, ranges
- [Snippets](reference/snippets.md): keys, the first set, the fields of a snippet
- [Completion](reference/completion.md): suggestions, their keys and options, the fields of a source
- [Several clips in the piano roll](reference/roll-clips.md): context notes, edit many clips, `paw.roll_clips`, layers
- [Language servers and diagnostics](reference/language-servers.md): keys, addresses, subjects, server configs, the protocol, MIDI LSP
- [The Lua interface](reference/scripting.md): the `paw` module, its layers and units, and the pages below
- [Project objects in Lua](reference/lua-objects.md): tracks, devices, clips, notes, attributes, the transport, tempo, automation
- [Commands, keys and options in Lua](reference/lua-commands.md): `paw.command`, ranges, `paw.ex`, `paw.keymap`, `paw.option`
- [Views and buffers in Lua](reference/lua-views.md): views, roles, buffer types, text buffers, the pointer, curves, layers
- [Addresses, diagnostics and lists in Lua](reference/lua-addresses.md): `paw.address`, `paw.diagnostic`, `paw.qf`, `paw.lsp`, queries
- [Timers, programs and other modules in Lua](reference/lua-other.md): timers, helper programs, seats
- [Events](reference/events.md): every event and its payload
- [Scripts and `paw ctl`](reference/ctl.md): `paw -l`, `paw ctl`, `paw attach`, `paw doctor`
- [Extensions](reference/extensions.md): the bundled extensions, files, how to load them, manifests, what an extension owns, health checks
- [Pictures in the terminal](reference/pictures.md): strips, `paw.plot`, and what a frontend does with strips
- [Lua API reference](reference/api.md): each function, made from the code
- [The control protocol](reference/protocol.md): the messages of the socket, scenes, seats, files and sound
- [Limits: what paw does not do yet](reference/limits.md): what paw does not do, and the known limits of what it does

## Explanation

- [About the architecture](explanation/about-the-architecture.md): the crates, the threads, the kernel and its frontends
- [About the key rule](explanation/about-the-key-rule.md): why a key means the same in every view
- [About seats](explanation/about-seats.md): many frontends on one instance, and a safe network connection
- [About the look of paw](explanation/about-the-look.md): color for attention, the color of a track, cells first
- [About the Nix build](explanation/about-the-nix-build.md): two layers, and why crane
- [About scenes: one view, two frontends](explanation/about-scenes.md): why the graphical window has no views of its own
- [About the audio engine](explanation/about-the-audio-engine.md): many cores and one result, delay compensation, failed devices, long files
- [About time and tempo](explanation/about-time-and-tempo.md): the tempo map, and which clock each thing keeps
- [About groups and VCAs](explanation/about-groups-and-vcas.md): why groups and VCAs are usual tracks, narrowing, freezing
- [About time stretch](explanation/about-stretching.md): the two methods, formants, why paw stretches a file one time
- [About project files](explanation/about-project-files.md): why a project is a folder of files, MIDI clip files, `unused`, files from outside, safety copies
- [About cues](explanation/about-cues.md): clips off the timeline played from a beat, why the engine times a cue, and why a render plays only the timeline
- [About language servers](explanation/about-language-servers.md): the four layers, addresses with ids, subjects, LSP
- [About the harmony reading](explanation/about-the-harmony-reading.md): how paw finds chords and keys, and why providers can replace it
- [About MIDI 2.0 in paw](explanation/about-midi-2.md): fractions, controllers for each note, ports, MPE
- [About the plugin sandbox](explanation/about-the-plugin-sandbox.md): one process for each plugin, and what it costs
- [About ARA plugins](explanation/about-ara.md): plugins that read whole clips, how paw hosts them, and what Windows plugins need
- [About state lanes](explanation/about-state-lanes.md): a lane of presets, models and states, and where each kind of change lands
- [About the core and extensions](explanation/about-core-and-extensions.md): where the line is, why, and how far an extension goes
- [About MIDI as the truth](explanation/about-midi-as-the-truth.md): why the notes are the truth, and where extensions keep their data
- [About seats](explanation/about-seats.md): many people in one instance, and the state of each
