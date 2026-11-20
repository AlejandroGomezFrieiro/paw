# The paw manual

The manual has four kinds of page. Tutorials are lessons that you do.
How-to guides give the steps for one task. Reference pages describe each
part of paw. Explanation pages tell why paw works as it does. In paw,
`:help` shows the same pages under the same four headings, and a page for
each extension (`:help notation`).

## Start here

- [How to start paw the first time and hear sound](how-to/start-paw-and-hear-sound.md): `paw doctor`, `:checkhealth`, a test tone
- [Make music with paw](tutorials/make-music/README.md): five lessons that make one song
- [Keys, by idea](reference/keys.md): all the keys on one page, to keep near the keyboard
- [How to configure paw](how-to/configure-paw.md): your `init.lua`
- [Limits: what paw does not do yet](reference/limits.md)

## Tutorials

- [Make music with paw](tutorials/make-music/README.md): five lessons that make one song, from the first note to an MP3 file
  - [Your first song](tutorials/make-music/01-first-song.md): drums, a bass and chords in a loop of four bars
  - [Play a synth from a MIDI keyboard](tutorials/make-music/02-play-a-midi-keyboard.md): play live, record over the loop, quantize
  - [Record a guitar](tutorials/make-music/03-record-a-guitar.md): an amp chain, two takes, the best parts, a fade
  - [Arrange the song](tutorials/make-music/04-arrange-the-song.md): verse and chorus, markers, the tempo, find a part
  - [Mix and render the song](tutorials/make-music/05-mix-and-render.md): levels, pan, effects, a send, automation, WAV and MP3
- [The course](tutorials/course/README.md): seventeen short lessons for your first days with paw, also inside paw as `:tutor`

## How-to guides

The guides of an extension are on the page of the extension. The groups
below link the main ones.

### Install and configure

- [How to install paw with Nix](how-to/install-paw.md): the package, without the dev shell
- [How to start paw the first time and hear sound](how-to/start-paw-and-hear-sound.md): `paw doctor`, `:checkhealth`, a test tone
- [How to choose the audio devices](how-to/choose-audio-devices.md): in paw, at the start, in `init.lua`
- [How to lower the latency](how-to/lower-the-latency.md): the block size, and what to change when the sound crackles
- [How to connect a MIDI keyboard](how-to/connect-a-midi-keyboard.md): check that paw sees it, and play an instrument
- [How to map a MIDI controller](how-to/map-a-midi-controller.md)
- [How to use your own plugins](how-to/use-your-own-plugins.md): CLAP, VST3, LV2, where paw looks, Windows plugins through yabridge
- [How to configure paw](how-to/configure-paw.md): `init.lua`, options, colors, commands, keys, events
- [How to change the status line](how-to/change-the-status-line.md): sections and components in `init.lua`
- [How to load an extension](how-to/load-an-extension.md): a bundled extension, your own, or one from Nix
- [How to check all the hardware](../extensions/doctor/README.md#how-to-check-all-the-hardware): the doctor's guided check and its report

### Tracks and instruments

- [How to add a track with a virtual instrument](how-to/add-an-instrument-track.md): the built-in synth, a plugin, a preset
- [How to add an audio track for a microphone or a guitar](how-to/add-an-audio-track.md): the input, the monitor, an amp
- [How to name, color, reorder and group tracks](how-to/organize-tracks.md): groups are folders and buses
- [How to change the sound of an instrument](how-to/change-the-sound-of-an-instrument.md): parameters, presets, the editor of the plugin
- [How to change a sound at a point in the song](how-to/change-a-sound-at-a-point-in-the-song.md): a state lane gives a plugin another preset, model or state from a point
- [How to switch amp models and presets from paw](how-to/switch-amp-models-and-presets.md): TONE3000 and Soundshed Guitar, scenes, snapshots
- [How to find and change a setting inside a plugin](how-to/find-and-change-a-setting-inside-a-plugin.md): the saved state of any plugin as a tree
- [How to sign in to TONE3000 from paw](how-to/sign-in-to-tone3000.md): the `client_id`, the code, where the tokens go
- [How to play a hardware synth from a track](how-to/play-a-hardware-synth.md)
- [How to route the outputs of a drum plugin](how-to/route-the-outputs-of-a-drum-plugin.md)
- [How to make a drum track](../extensions/drums/README.md#how-to-make-a-drum-track): a kit, a plugin or a folder of samples, and a grid
- [How to add a sampler track](../extensions/sampler/README.md#how-to-add-a-sampler-track): SFZ and Decent Sampler instruments
- [How to use articulations with a plugin instrument](how-to/use-articulations-with-a-plugin-instrument.md): MODO BASS 2, SINE Player, maps of your own
- [How to give notes an articulation](../extensions/articulations/README.md#how-to-give-notes-an-articulation): staccato, legato and other articulations for each note
- [How to type lyrics for a vocal track](../extensions/utau/README.md#how-to-type-lyrics): a voice that sings, with OpenUtau's voicebanks
- [How to play an instrument from the guitar](../extensions/vinput/README.md#how-to-play-an-instrument-from-the-guitar): a guitar heard as MIDI

### Write and edit music

- [How to move, copy, split and trim clips](how-to/move-copy-split-and-trim-clips.md)
- [How to change the velocity, length and pitch of notes, and quantize them](how-to/edit-notes.md)
- [How to humanize a phrase](../extensions/musicops/README.md#how-to-humanize-a-phrase): and strum, arpeggiate, keep notes in a key
- [How to enter notes in a score](../extensions/notation/README.md#how-to-enter-notes): a clip as notation, also printed and as MusicXML
- [How to change a beat while the song plays](../extensions/pattern/README.md#how-to-change-a-beat-while-the-song-plays): clips written as a line of text
- [How to use the suggestions](../extensions/continue/README.md#how-to-use-the-suggestions): how a phrase continues, in the piano roll
- [How to use a snippet](../extensions/snippets/README.md#how-to-use-a-snippet): chords that lead to the next chord, parts and voices, by name
- [How to loop a part of the song while you work](how-to/loop-a-part-of-the-song.md)
- [How to change the tempo and the time signature](how-to/change-the-tempo-and-time-signature.md): also in the middle of the song
- [How to fit audio to the tempo](how-to/fit-audio-to-the-tempo.md)
- [How to use an ARA plugin on a vocal or a take](how-to/use-an-ara-plugin.md): play the clips through it, edit them, MIDI from the notes it heard

### Arrange and organize

- [How to move a section](../extensions/sections/README.md#how-to-move-a-section): intro, verse and chorus as named parts
- [How to undo, and return to an earlier state](how-to/undo-and-return-to-an-earlier-state.md): the undo tree
- [How to compare two versions by ear](../extensions/undotree/README.md#how-to-compare-two-versions-by-ear)
- [How to work on one group of a large project](how-to/work-on-one-group.md)
- [How to arrange your screen: windows, tabs and layouts](how-to/arrange-your-screen.md): one view full screen, two clips side by side, a layout of your own

### Find things

- [How to find a command or a key you forgot](how-to/find-a-command-or-a-key.md)
- [How to find a track, a clip or a marker by name](how-to/find-a-track-clip-or-marker.md)
- [How to search the project and go through the results](how-to/search-the-project.md): `:vimgrep`, notes, queries, the quickfix list

### Record and play live

- [How to record a guitar or a bass](how-to/record-a-guitar-or-a-bass.md): the instrument input, the level, the tuner, a take
- [How to record vocals with a count-in and a click](how-to/record-vocals-with-a-count-in-and-a-click.md)
- [How to record MIDI from a keyboard](how-to/record-midi-from-a-keyboard.md): a take, a take merged into a clip, a take over a loop
- [How to use the metronome](how-to/use-the-metronome.md): the click, the count-in
- [How to record takes over a loop and comp them](how-to/record-takes-and-comp.md)
- [How to punch in over a part](how-to/punch-in-over-a-part.md)
- [How to set the recording offset](how-to/set-the-recording-offset.md)
- [How to record a performance into the timeline](../extensions/launcher/README.md#how-to-record-a-performance-into-the-timeline): the clip launcher

### Mix

- [How to set levels and pan, and keep the master out of the red](how-to/set-levels-and-pan.md)
- [How to add an effect and change its settings](how-to/add-an-effect.md): EQ, compressor, reverb, delay, presets
- [How to send several tracks to one reverb](how-to/send-several-tracks-to-one-reverb.md)
- [How to check the mix](how-to/check-the-mix.md): meters, loudness, mono
- [How to check a mix before delivery](../extensions/mixdiag/README.md#how-to-check-a-mix-before-delivery): loudness, true peak, phase and the problems in the mix
- [How to freeze a heavy track](how-to/freeze-a-heavy-track.md)
- [How to duck a track under the kick](how-to/duck-a-track-under-the-kick.md)
- [How to write automation with the faders](how-to/write-automation-with-the-faders.md)

### Render and share

- [How to export a song as WAV, FLAC or MP3](how-to/export-a-song.md): where the file goes, tags
- [How to export part of the song or a loop](how-to/export-part-of-the-song.md)
- [How to render stems](how-to/render-stems.md)
- [How to export MIDI for another program](how-to/export-midi.md)
- [How to print a part or the score](../extensions/notation/README.md#how-to-print-a-part-or-the-score)
- [How to move a song between paw and REAPER](how-to/open-a-reaper-project.md)
- [How to move a song between paw and other DAWs](how-to/move-a-song-to-another-daw.md): Bitwig Studio, Studio One, Cubase

### Projects and files

- [How to save, back up and open projects](how-to/save-and-open-projects.md): recent projects, safety copies
- [How to import audio and MIDI files](how-to/import-audio-and-midi-files.md): commands, the file manager, a drop on the graphical window
- [How to make and use track templates](how-to/use-track-templates.md)
- [How to relink lost media](how-to/relink-missing-media.md)
- [How to diff and merge projects with git](../extensions/projdiff/README.md#how-to-diff-and-merge-projects-with-git)
- [How to work on paw from another computer](how-to/work-from-another-computer.md): attach over the network or SSH, send files, hear the sound

### When something goes wrong

- [How to fix no sound](how-to/fix-no-sound.md)
- [How to fix crackles and dropouts](how-to/fix-crackles-and-dropouts.md)
- [How to deal with a plugin that crashes or hangs](how-to/deal-with-a-plugin-that-crashes.md)
- [How to open a project without its plugins](how-to/open-a-project-without-its-plugins.md)
- [How to fix a plugin editor that does not work](how-to/fix-a-plugin-editor.md)
- [How to recover lost work](how-to/recover-lost-work.md)

### Extend paw

- [How to add a picker](how-to/add-a-picker.md): a list to choose from, with a key
- [How to write a snippet](how-to/write-a-snippet.md)
- [How to write a completion source](how-to/write-a-completion-source.md)
- [How to write a device in Lua](how-to/write-a-device-in-lua.md)
- [How to write a language server](how-to/write-a-language-server.md)
- [How to write an importer or exporter](how-to/write-an-importer-or-exporter.md): open and write the files of another program with `:import`, `:open` and `:export`
- [How to give an extension an editor in the graphical window](how-to/add-an-editor-to-the-window.md)
- [How to drive paw from an agent](how-to/drive-paw-from-an-agent.md): let an agent that writes code, or an assistant, edit a project

### Work on paw

- [How to build and run paw from the source](how-to/build-paw-from-source.md): the dev shell, the demo song, the example configuration
- [How to run the tests](how-to/run-the-tests.md): the Lua suite, the Rust tests, the documentation checks
- [How to run the graphical window without a graphics card](how-to/run-the-window-without-a-graphics-card.md)
- [How to run the graphical window against a kernel on another machine](how-to/run-the-window-against-a-remote-kernel.md)

## Reference

### Keys and commands

- [Keys, by idea](reference/keys.md): all the keys on one page, to keep near the keyboard
- [Motions, operators and modes](reference/grammar.md): the keys that the arrange view and the piano roll share
- [The key rule](reference/key-rule.md): the meaning of each key in every view, the leaders, the classic keys
- [The command line](reference/cmdline.md): completion, `:set`, unsaved work, messages
- [Ex commands](reference/ex.md): ranges, `:s` and `:g`
- [The mouse](reference/mouse.md): each gesture in the terminal
- [Completion](reference/completion.md): suggestions, their keys and options, the fields of a source
- [Snippets](reference/snippets.md): keys, the first set, the fields of a snippet
- [Options](reference/options.md): every option of `paw.opt`
- [Help](reference/help.md): `:help`, tags, `:helpgrep`

### Views and the screen

- [The arrange view](reference/arrange-view.md): its keys, waveforms, lanes as rows, the tempo lane, take lanes
- [The piano roll](reference/piano-roll.md): its keys, insert mode, several clips, suggestions
- [Several clips in the piano roll](reference/roll-clips.md): context notes, edit many clips, `paw.roll_clips`, layers
- [The device panel](reference/device-panel.md): its keys
- [The mixer](reference/mixer-view.md): its strips and keys
- [The curve editor](reference/curve-editor.md): lanes, parameters, controllers and the tempo map as curves
- [Windows, buffers and tabs](reference/windows.md): splits, tabs, layouts, narrowed tabs
- [Lists edited as text](reference/lists-edited-as-text.md): `paw://tracks`, `paw://sends`, devices, markers
- [The file manager](reference/file-manager.md): folders as text and as a tree
- [The terminal screen](reference/screen.md): the parts of the screen, the bottom line, colors
- [Pictures in the terminal](reference/pictures.md): pixels in terminals that show images, strips, `paw.plot`
- [The status line](reference/status-line.md): sections, components, `paw.statusline`
- [The graphical window](reference/window.md): its command line, each gesture, the panes and the views in windows of their own

### Find

- [Pickers](reference/pickers.md): every picker, its keys, matching, audition, the Lua API
- [Search the text of the project](reference/grep.md): `:vimgrep`, `paw.grep`
- [Structural queries](reference/queries.md): `:select`, `:query`, `paw.query`
- [The quickfix list](reference/quickfix.md): Problems, location lists, `:cdo`
- [Language servers and diagnostics](reference/language-servers.md): keys, addresses, subjects, server configs, the protocol, MIDI LSP

### Time, recording and clips

- [Tempo and time signatures](reference/tempo.md): the tempo map, its commands, the timebase of audio clips
- [Markers and regions](reference/markers.md): markers, regions, their keys and commands
- [Recording](reference/recording.md): track inputs, monitoring, count-in, punch, pre-roll, files, import
- [Takes](reference/takes.md): takes, comping, take lanes
- [MIDI](reference/midi.md): controller moves, the event list, MIDI input and output, MPE, MIDI files
- [MIDI controllers](reference/learn.md): bind knobs, faders and pads to controls
- [Media files and audio clips](reference/media.md): paths, relink, sample rates, long files, fades, clip operations
- [Stretched and looped clips](reference/stretch.md): stretch, pitch, warp markers, tempo, loops
- [Harmony](reference/harmony.md): the chords and keys that paw reads, providers, theory functions, voicings, ranges

### Mix, devices and plugins

- [Routing: groups, VCAs, sends and side-chains](reference/routing.md): groups, linked faders, VCAs, outputs, sends, side-chains, output pairs
- [Automation](reference/automation.md): automation modes, how the controls write automation
- [Narrowed tabs](reference/narrowing.md): a tab of one group, the rest of the song
- [Frozen tracks](reference/freezing.md): frozen and held tracks
- [Devices](reference/devices.md): the built-in devices, wet/dry and output gain, presets
- [Device parameters](reference/device-parameters.md): the fields of each parameter, the ids of plugins, values as text
- [Plugins](reference/plugins.md): formats, scan, editors, processes, status, offline devices
- [The saved state of plugins](reference/plugin-state.md): the readers of each framework, their forms and trees, hints from the binary
- [The state of JUCE plugins](reference/juce-plugin-state.md): the layers of a state, paths, parameters, differences, presets
- [Attachments](reference/attachments.md): native libraries that take a plugin, the clips and files they get (`paw_attach.h`)
- [Audio devices](reference/audio-devices.md): the input and output devices, PipeWire, latency, a lost device, test backends
- [The audio engine](reference/engine.md): threads, the state of the engine, delay compensation, failed devices

### Projects, files and programs

- [Project files](reference/project-files.md): the project folder, `:w` and `:wa`, MIDI clip files, safety copies, `:recover`
- [Render](reference/render.md): `:render`, formats, tags, stems, bounce
- [Files that paw keeps](reference/state-files.md): configuration, state, cache, recent projects
- [The programs and their options](reference/programs.md): `paw`, `paw-gui`, `paw-mcp`, environment variables
- [Scripts and `paw ctl`](reference/ctl.md): `paw -l`, `paw ctl`, `paw attach`, `paw doctor`
- [The control protocol](reference/protocol.md): the messages of the socket, scenes, seats, files and sound
- [The Nix package](reference/nix-package.md): the outputs of the flake and the checks
- [The source tree](reference/source-tree.md): the folders and crates of the repository, and what each one holds

### Lua and extensions

- [The Lua interface](reference/scripting.md): the `paw` module, its layers and units, and the pages below
- [Project objects in Lua](reference/lua-objects.md): tracks, devices, clips, notes, attributes, the transport, tempo, automation
- [Commands, keys and options in Lua](reference/lua-commands.md): `paw.command`, ranges, `paw.ex`, `paw.keymap`, `paw.option`
- [Views and buffers in Lua](reference/lua-views.md): views, roles, buffer types, text buffers, the pointer, curves, layers
- [Addresses, diagnostics and lists in Lua](reference/lua-addresses.md): `paw.address`, `paw.diagnostic`, `paw.qf`, `paw.lsp`, queries
- [Timers, programs and other modules in Lua](reference/lua-other.md): timers, helper programs, seats
- [The graphical window in Lua](reference/window-lua.md): `paw.frontend.act`, menus, bands, panes, views that paint
- [Lua devices](reference/lua-devices.md): the fields of a device in Lua, the block, MIDI, helpers, reload
- [Events](reference/events.md): every event and its payload
- [Extensions](reference/extensions.md): the bundled extensions, files, manifests, what an extension owns, health checks
- [Lua API reference](reference/api.md): each function, made from the code

### Limits

- [Limits: what paw does not do yet](reference/limits.md): what paw does not do, and the known limits of what it does

## Explanation

- [About the architecture](explanation/about-the-architecture.md): the crates, the threads, the kernel and its frontends
- [About the core and extensions](explanation/about-core-and-extensions.md): where the line is, why, and how far an extension goes
- [About MIDI as the truth](explanation/about-midi-as-the-truth.md): why the notes are the truth, and where extensions keep their data
- [About the key rule](explanation/about-the-key-rule.md): why a key means the same in every view
- [About scenes: one view, two frontends](explanation/about-scenes.md): why the graphical window has no views of its own
- [About seats](explanation/about-seats.md): many frontends and people on one instance, the state of each, and a safe network connection
- [About the look of paw](explanation/about-the-look.md): color for attention, the color of a track, cells first
- [About the audio engine](explanation/about-the-audio-engine.md): many cores and one result, delay compensation, failed devices, long files
- [About the plugin sandbox](explanation/about-the-plugin-sandbox.md): one process for each plugin, and what it costs
- [About ARA plugins](explanation/about-ara.md): plugins that read whole clips, how paw hosts them, and what Windows plugins need
- [About state lanes](explanation/about-state-lanes.md): a lane of presets, models and states, and where each kind of change lands
- [About time and tempo](explanation/about-time-and-tempo.md): the tempo map, and which clock each thing keeps
- [About time stretch](explanation/about-stretching.md): the two methods, formants, why paw stretches a file one time
- [About cues](explanation/about-cues.md): clips off the timeline played from a beat, and why a render plays only the timeline
- [About groups and VCAs](explanation/about-groups-and-vcas.md): why groups and VCAs are usual tracks, narrowing, freezing
- [About MIDI 2.0 in paw](explanation/about-midi-2.md): fractions, controllers for each note, ports, MPE
- [About the harmony reading](explanation/about-the-harmony-reading.md): how paw finds chords and keys, and why providers can replace it
- [About language servers](explanation/about-language-servers.md): the four layers, addresses with ids, subjects, LSP
- [About project files](explanation/about-project-files.md): why a project is a folder of files, MIDI clip files, `unused`, safety copies
- [About the Nix build](explanation/about-the-nix-build.md): two layers, and why crane
