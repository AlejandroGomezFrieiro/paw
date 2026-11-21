# Options

<!-- tags: options paw.opt -->

An option is a value in `paw.opt` that changes how paw works. Set it in
`init.lua` (`paw.opt.zoom = 4`), or with `:set` (see
[The command line](cmdline.md#options)). The options belong to the
instance: every frontend attached to it shares them.

An option takes values of the type of its default. A number must be in the
range of the option. paw refuses a value that is not correct, shows an
error that says what the option takes, and keeps the old value. A change
emits the event `option.changed`. `<Space>fo` chooses an option from a list.

An extension adds options of its own with `paw.option.define(name, default, spec)`.
`paw.option.list()` gives every option with its default.

## Keys

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.leader` | `" "` | What `<leader>` means in a key: the space bar. It starts the keys that mean the same in every view (`<Space>mm` the mixer, `<Space><Space>` play and stop). A change moves every key on the leader. |
| `paw.opt.localleader` | `"\\"` | What `<localleader>` means: the leader of the keys of one view (the notation popovers, `\d`). |
| `paw.opt.timeoutlen` | `800` | The time in ms to wait for the next keys of a sequence, 0 to 10000. |
| `paw.opt.hints` | `true` | Lists the keys that can come after a key sequence that is not complete. |
| `paw.opt.hint_delay` | `500` | The time in ms before that list shows, 0 to 10000. |
| `paw.opt.keybar` | `true` | Shows the most important keys of the view and mode on the bottom line. |
| `paw.opt.keys` | `"default"` | `"classic"` gives the keys that the views had before the [key rule](key-rule.md#the-classic-keys). |

## Edit

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.grid` | `1` | The step and snap of the arrange cursor, in beats. |
| `paw.opt.note_grid` | `0.25` | The step and snap of the piano roll, in beats. |
| `paw.opt.note_snap` | `true` | Notes drawn with the pointer go on the grid of the piano roll. |
| `paw.opt.ripple` | `false` | When `true`, to delete time closes the gap, and to paste moves the music after it. |
| `paw.opt.clip_length` | `4` | The length of a new MIDI clip, in beats. |
| `paw.opt.velocity` | `100` | The velocity of notes entered by hand, 1 to 127. |
| `paw.opt.octave` | `4` | The octave where note entry starts, -1 to 9. |
| `paw.opt.roll_insert` | `"draw"` | How `i` and `a` enter notes in the piano roll: `"draw"` with the cursor, or `"keys"` with the keyboard as a piano. |
| `paw.opt.gdefault` | `false` | When `true`, `:s` changes every match without the flag `g`, and only the first match of each bar with it. |
| `paw.opt.copy_imports` | `false` | An import copies the sound file into the `media` folder of the project. |
| `paw.opt.send_level` | `-12` | The level of a new send, in dB, -150 to 24. |
| `paw.opt.learn_pickup` | `true` | A MIDI controller moves a learned parameter only after it reaches the value of the parameter. |
| `paw.opt.editor_on_add` | `true` | A plugin added by hand opens its own window. |

## Undo and safety

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.undo_steps` | `1000` | The number of steps that the undo history keeps, 10 to 1000000. |
| `paw.opt.undo_memory` | `1024` | About how many megabytes of changes the undo history keeps, from 16. |
| `paw.opt.autosave` | `60` | The seconds between safety copies of unsaved work. `0` gives no copies. It is `0` under `--clean`. |
| `paw.opt.reopen_last` | `false` | A start with no project opens the newest recent project. |
| `paw.opt.lua_limit` | `2000` | The time in ms after which paw stops Lua code that does not return. `0` gives no limit. |
| `paw.opt.clip_kind_limit` | `50` | The time in ms that a function of a kind of clip (for example `compile` or `serialize`) can run. `0` gives no limit. |

When the undo history has more steps than `undo_steps` or more data than
`undo_memory`, paw removes the oldest steps and shows a message one time.
A step keeps about what it changed. paw keeps the notes of a clip in runs
of a few hundred, and the steps share the runs. So one note changed in a
clip of 200,000 notes keeps a copy of its run (about 30 kB), not of the
clip. `:set undo_steps=200` removes the oldest steps at once.

## Play and record

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.follow` | `true` | The view scrolls to keep the playhead in view. |
| `paw.opt.count_in` | `0` | The bars that the metronome counts before a recording from a stop, 0 to 16. |
| `paw.opt.pre_roll` | `0` | The bars that play before a punch in, when you record from a stop, 0 to 64. |
| `paw.opt.pre_roll_seconds` | `0` | The seconds that play before those bars, 0 to 60. |
| `paw.opt.click_level` | `0` | The level of the metronome in dB, -60 to 12. `:click level=-6` sets it. |
| `paw.opt.click_accent` | `true` | The metronome plays a higher click on the first beat of a bar. |
| `paw.opt.click_output` | `0` | The first output channel of the pair that the metronome plays on, 1 to 63. `0` plays it with the song. |
| `paw.opt.midi_follows_selection` | `true` | The selected track plays the MIDI keyboard when no track is armed. `false`: only armed and monitored tracks play it. |
| `paw.opt.midi_record` | `"new"` | A MIDI take over a clip: `"new"` makes a clip of its own, `"merge"` joins its notes into the clip under it (overdub). |
| `paw.opt.threads` | `0` | The threads that process tracks. `0` gives one for each core. |
| `paw.opt.device_sleep` | `true` | A device at rest sleeps through silence: a reverb after its tail, a synth with no note that sounds. This saves processor time. The sound is the same with `false`. |
| `paw.opt.audio_reconnect` | `true` | paw opens an audio device again when it returns. |
| `paw.opt.scope_rest` | `"play"` | What the other tracks do in a narrowed tab: `"play"`, `"mute"` or `"frozen"`. |

## Media and render

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.media_stream` | `64` | A sound file with more decoded audio than this, in megabytes, plays from the disk. `0` keeps every file in memory. |
| `paw.opt.media_cache` | `16` | The gigabytes that each cache keeps between runs: the decoded sound of long files, and the bakes (`~/.cache/paw/bakes`). |
| `paw.opt.ffmpeg` | `"ffmpeg"` | The program that renders MP3, Ogg and Opus: a name on the `PATH`, or a path. |
| `paw.opt.render_loudest` | `-9` | A render louder than this, in LUFS, goes into the quickfix list. |
| `paw.opt.loudness_target` | `-14` | The loudness in LUFS that a mix server aims at. |
| `paw.opt.true_peak_target` | `-1` | The true peak in dBTP that a mix must stay below, for a mix server. |

## Screen

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.zoom` | `2` | The columns for each beat in the arrange view. |
| `paw.opt.note_zoom` | `8` | The columns for each beat in the piano roll. |
| `paw.opt.track_height` | `"auto"` | The rows for each track in the arrange view, 1 to 12. `"auto"` gives 3 to 4 rows, to fit the tracks on the screen. |
| `paw.opt.header_width` | `"auto"` | The columns of the track headers, 8 to 60. `"auto"` gives 26, 22, 18 or 12 columns, by the width of the screen. The track column at their left is not in these columns. |
| `paw.opt.number` (`nu`) | `true` | Shows the number of each track in the track column of the arrange view. |
| `paw.opt.relativenumber` (`rnu`) | `false` | Shows how many `j` or `k` go to each track. The track of the cursor keeps its number. |
| `paw.opt.trackcolumn` | `number,signs,fold` | The parts of the track column that show. See [The track column](trackcolumn.md). |
| `paw.opt.relativebar` (`rbar`) | `false` | Shows on the ruler how many `W` or `B` go to each bar. The bar of the cursor keeps its number. |
| `paw.opt.barlabel` | `number` | The parts of the label of each bar on the ruler. |
| `paw.opt.insertkeys` | `m,a,r,',f` | The keys of insert mode in the arrange view, in the order of its box of keys. See [Insert mode](insert-mode.md). |
| `paw.opt.devices_width` | `36` | The columns of the device panel. |
| `paw.opt.mixer_height` | `12` | The rows of the mixer. |
| `paw.opt.pianoroll_height` | `0` | The rows of the piano roll. `0` shares the space. |
| `paw.opt.qf_height` | `10` | The rows of the window that `:copen` opens. |
| `paw.opt.fps` | `60` | The most frames a second that the terminal draws while something moves, from 1 to 240. paw sends a frame only when a cell changes. While the song plays, it draws only the parts that move: the playhead, the meters and the status line. |
| `paw.opt.message_time` | `4000` | The time in ms that a message stays on the command line. |
| `paw.opt.termcolors` | `"auto"` | `"true"` for 24-bit color, `"256"` for 256 colors, or `"auto"`. |
| `paw.opt.ascii` | `false` | Draws with ASCII characters only. It has priority over `curve_glyphs` and `braille`. |
| `paw.opt.curve_glyphs` | `"sextant"` | How curves show in cells: `"sextant"`, `"braille"` or `"line"`. |
| `paw.opt.braille` | `true` | When `false`, curves show as `"line"`, whatever `curve_glyphs` is. |
| `paw.opt.wave_scale` | `"linear"` | The scale of audio waveforms in cells: `"linear"` shows hits, `"db"` shows quiet sound too. |
| `paw.opt.graphics` | `true` | Views that paint show pixels where the terminal can show images. When `false`, they use cells. |
| `paw.opt.mouse` | `true` | The terminal sends the pointer to paw. When `false`, the terminal keeps the pointer for its own selection. |
| `paw.opt.chords` | `"names"` | The chord symbols over the piano roll: `"names"`, `"roman"`, `"both"` or `false`. |
| `paw.opt.harmony_step` | `0.5` | In beats: the shortest chord that the harmony reading finds is about two times this. |
| `paw.opt.roll_context` | `"all"` | The tracks whose notes show behind the clip in the piano roll: `"all"`, `"group"`, `"none"`, or a list of track ids. Drum tracks are not in `"all"` and `"group"`. |
| `paw.opt.roll_context_max` | `4000` | The maximum number of notes that show behind the clip. |
| `paw.opt.native_dialogs` | `true` | The graphical window opens the file dialogs of the desktop, not the list of the kernel. |
| `paw.opt.window_cache` | `"auto"` | The graphical window draws a frame again only where it changed, and shows no frame when nothing changed. With `false`, it draws each frame in full. `true`, `false`, or `"auto"`, which is the same as `true`. |
| `paw.opt.window_fps` | `"auto"` | The frames a second that the graphical window draws while the song plays, from 1 to 60. `"auto"` is 30 on a graphics card and 15 on the processor. Keys, the pointer and edits show at once. |

For `termcolors = "auto"`, paw uses 24-bit color when `COLORTERM` is
`truecolor` or `24bit`, or when `TERM` ends in `-direct`. Else it uses the
nearest of 256 colors.

The curve glyphs:

- `"sextant"`: a connected line of sextant characters, two columns by three rows in a cell. Steep slopes are filled, so the line has no gaps.
- `"braille"`: dots, two columns by four rows in a cell.
- `"line"`: lines at three heights in a row.

## Windows and layouts

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.splitright` | `true` | A new window from a vertical split goes to the right. When `false`, to the left. |
| `paw.opt.splitbelow` | `true` | A new window from a horizontal split goes below. When `false`, above. |
| `paw.opt.layout` | `""` | The name of a layout in `paw.layouts` to start with. See [Windows, buffers and tabs](windows.md#layouts). |

### Options of a window

`:setlocal` sets these options for the current window only.

| Option | Effect |
| --- | --- |
| `:setlocal timebind` | Binds the time of this window to the other bound windows. `:setlocal notimebind` removes the bind. |

## Pickers, files and the quickfix list

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.audition_delay` | `150` | The time in ms that the selection stays on an item before you hear it. |
| `paw.opt.audition_level` | `-12` | The level in dB of a sound file heard in a picker. |
| `paw.opt.files_hidden` | `false` | A files buffer shows the files whose names start with a dot. |
| `paw.opt.files_hear` | `false` | A files buffer plays the sound file under the cursor after the cursor stops on it. |
| `paw.opt.qf_diagnostics` | `"warning"` | The diagnostics that go into the Problems list: this severity and worse. `"hint"` gives all, `"off"` none. |

## Completion and devices

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.complete_auto` | `true` | paw asks the completion sources for a suggestion after a pause in the edits. |
| `paw.opt.complete_idle_ms` | `1200` | The time in ms without an edit before paw asks. |
| `paw.opt.complete_deadline_ms` | `300` | The time in ms that a request waits before it shows the suggestions that arrived. |
| `paw.opt.complete_audition` | `false` | paw plays each alternative that it shows through the track. |
| `paw.opt.lua_devices_watch` | `1000` | The time in ms between checks of the files of Lua devices. `0` gives no checks. |
