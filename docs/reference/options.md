# Options

<!-- tags: options paw.opt -->

An option is a value in `paw.opt` that changes how paw works. You set it in `init.lua` (`paw.opt.zoom = 4`), or with `:set` (see [The command line](cmdline.md#options)). The options belong to the instance, so every frontend attached to it shares them.

An option takes values of the type of its default, and a number must be in the range of the option. paw refuses a value that is not correct, shows an error that says what the option takes, and keeps the old value. A change emits the event `option.changed`, and `<Space>fo` chooses an option from a list.

An extension adds options of its own with `paw.option.define(name, default, spec)`, and `paw.option.list()` gives every option with its default.

## Keys

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.leader` | `" "` | What `<leader>` means in a key, which is the space bar. It starts the keys that mean the same in every view (`<Space>mm` for the mixer, `<Space><Space>` for play and stop), and a change moves every key on the leader. |
| `paw.opt.localleader` | `"\\"` | What `<localleader>` means, which is the leader of the keys of one view (the notation popovers, `\d`). |
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
| `paw.opt.phrase_rest` | `0.5` | A rest in the piano roll longer than this, in beats, ends a phrase, which sets the phrase that `ip`, `ap`, `(` and `)` use. |
| `paw.opt.note_snap` | `true` | Notes drawn with the pointer go on the grid of the piano roll. |
| `paw.opt.ripple` | `false` | When `true`, deleting time closes the gap, and pasting moves the music after it. |
| `paw.opt.clip_length` | `4` | The length of a new MIDI clip, in beats. |
| `paw.opt.velocity` | `100` | The velocity of notes entered by hand, 1 to 127. |
| `paw.opt.step_velocity` | `"key"` | The velocity of the notes that step input enters in the piano roll: `"key"`, the velocity of each key, or a number from 1 to 127. |
| `paw.opt.bend_step` | `1` | The semitones that each `k` or `j` bends the note that you draw in the piano roll. |
| `paw.opt.strum` | `0.0625` | The beats between the notes of a chord that `C` strums in the piano roll, which is a 64th note by default. |
| `paw.opt.strum_dir` | `"up"` | Which way `C` strums: `"up"` from the lowest note, `"down"` from the highest, or `"updown"`, which rises through the first, third and fifth note and so on, and falls through the others. The picker of `C` can say it for one strum. |
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
| `paw.opt.undofile` | `true` | After each save of a project folder, paw keeps the undo history in the undo file, so you can undo past the save when you open the project again. It is `false` under `--clean`. See [Files that paw keeps](state-files.md#the-undo-file). |
| `paw.opt.undofile_mb` | `256` | About how many megabytes the undo file of one project takes, from 1. Past it, paw removes the oldest states. |
| `paw.opt.shada` | `true` | paw keeps the prompt histories, the last search, the registers and, for each project, the marks and the last cursor across restarts. See [Files that paw keeps](state-files.md#editing-history). |
| `paw.opt.history` | `200` | The number of lines that each prompt history keeps, 1 to 100000. |
| `paw.opt.autosave` | `60` | The seconds between safety copies of unsaved work. `0` gives no copies. It is `0` under `--clean`. |
| `paw.opt.reopen_last` | `false` | A start with no project opens the newest recent project. |
| `paw.opt.lua_limit` | `2000` | The time in ms after which paw stops Lua code that does not return. `0` gives no limit. |
| `paw.opt.check_stamps` | `false` | Draw each window that paw keeps by its view's `stamp` anyway, and log each window that drew other cells with the same stamp. The test suite turns it on. See [A stamp for each window](lua-views.md#a-stamp-for-each-window). |
| `paw.opt.budget_ms` | `0` | The time in ms that a key, an event handler, a timer or the drawing of the screen should take. A callback that takes longer writes one warning to `:messages`. `0` turns the check off. See [The budget of a callback](lua-other.md#the-budget-of-a-callback). |
| `paw.opt.clip_kind_limit` | `50` | The time in ms that a function of a kind of clip (e.g., `compile` or `serialize`) can run. `0` gives no limit. |

When the undo history has more steps than `undo_steps` or more data than `undo_memory`, paw removes the oldest steps and shows a message one time. A step keeps about what it changed, because paw keeps the notes of a clip in runs of a few hundred and the steps share the runs. One note changed in a clip of 200,000 notes therefore keeps a copy of its run (about 30 kB), not of the clip. `:set undo_steps=200` removes the oldest steps at once.

## Play and record

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.follow` | `true` | The view scrolls to keep the playhead in view. |
| `paw.opt.jumpview` | `"left"` | Where a jump puts its target when the target is off screen or in the last quarter of the view. Jumps are `]'`, `]r`, `n`, `*`, `'` marks, `G`, `gg` and `@19\|`. `"left"` puts the target near the left edge, so what follows reads to its right. `"center"` puts it in the middle. A step with `h` `l` `w` `b` or `e` scrolls only as far as it needs. |
| `paw.opt.jumpmargin` | `6` | The columns between the left edge and the target of a jump when `jumpview` is `"left"`. |
| `paw.opt.count_in` | `0` | The bars that the metronome counts before a recording from a stop, 0 to 16. |
| `paw.opt.pre_roll` | `0` | The bars that play before a punch in, when you record from a stop, 0 to 64. |
| `paw.opt.pre_roll_seconds` | `0` | The seconds that play before those bars, 0 to 60. |
| `paw.opt.click_level` | `0` | The level of the metronome in dB, -60 to 12. `:click level=-6` sets it. |
| `paw.opt.click_accent` | `true` | The metronome plays a higher click on the first beat of a bar. |
| `paw.opt.click_output` | `0` | The first output channel of the pair that the metronome plays on, 1 to 63. `0` plays it with the song. |
| `paw.opt.midi_follows_selection` | `true` | The selected track plays the MIDI keyboard when no track is armed. With `false`, only armed and monitored tracks play it. |
| `paw.opt.play_from` | `"cursor"` | Where play and record start from a stop. `"cursor"` is the cursor of the view that has the keys, wherever the playhead is, and `"playhead"` is the old way, where `<Space><Space>` plays from the playhead and `<S-CR>` from the cursor. |
| `paw.opt.midi_record` | `"new"` | What a MIDI take over a clip does. `"new"` makes a clip of its own, and `"merge"` joins its notes into the clip under it (overdub). |
| `paw.opt.threads` | `0` | The threads that process tracks. `0` gives one for each core. |
| `paw.opt.device_sleep` | `true` | A device at rest sleeps through silence, e.g., a reverb after its tail or a synth with no note that sounds, which saves processor time. When the song is stopped and nothing sounds, the whole engine rests (see [The engine at rest](engine.md#the-engine-at-rest)). The sound is the same with `false`. |
| `paw.opt.quality` | `"full"` | `"edit"` lowers the costly settings of the built-in devices while paw plays live, for example the oversampling of a `saturation`, and the status line shows `edit q`. A render, an export, stems, a bounce and a freeze always play at `"full"`. See [Edit quality](engine.md#edit-quality). |
| `paw.opt.audio_reconnect` | `true` | paw opens an audio device again when it returns. |
| `paw.opt.scope_rest` | `"play"` | What the tracks outside the scope do while a narrowed window is in front: `"play"`, `"mute"` or `"frozen"`. |
| `paw.opt.scopebars` | `"local"` | The bar numbers in a scope with time: `"local"` (from 1 at its start) or `"song"`. |
| `paw.opt.scopeloop` | `true` | Loops the time of a scope while its window is in front. |

## Media and render

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.media_stream` | `64` | A sound file with more decoded audio than this, in megabytes, plays from the disk. `0` keeps every file in memory. |
| `paw.opt.media_cache` | `16` | The gigabytes that each cache keeps between runs, which are the decoded sound of long files and the bakes (`~/.cache/paw/bakes`). |
| `paw.opt.ffmpeg` | `"ffmpeg"` | The program that renders MP3, Ogg and Opus, as a name on the `PATH` or a path. |
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
| `paw.opt.regionlevels` | `3` | The rows of the lane of regions under the ruler: a row for each level of regions. Deeper regions are on the last row. |
| `paw.opt.insertkeys` | `m,a,r,',f` | The keys of insert mode in the arrange view, in the order of its box of keys. See [Insert mode](insert-mode.md). |
| `paw.opt.devices_width` | `36` | The columns of the device panel. |
| `paw.opt.mixer_height` | `12` | The rows of the mixer. |
| `paw.opt.pianoroll_height` | `0` | The rows of the piano roll. `0` shares the space. |
| `paw.opt.qf_height` | `10` | The rows of the window that `:copen` opens. |
| `paw.opt.fps` | `60` | The most frames a second that the terminal draws while something moves, from 1 to 240. paw sends a frame only when a cell changes, and while the song plays it draws only the parts that move, which are the playhead, the meters and the status line. After paw plays a note with the song stopped, the frames go on until the meters are at rest. |
| `paw.opt.message_time` | `4000` | The time in ms that a message stays on the command line. |
| `paw.opt.termcolors` | `"auto"` | `"true"` for 24-bit color, `"256"` for 256 colors, or `"auto"`. |
| `paw.opt.ascii` | `false` | Draws with ASCII characters only, and this has priority over `curve_glyphs` and `braille`. |
| `paw.opt.curve_glyphs` | `"sextant"` | How curves show in cells: `"sextant"`, `"braille"` or `"line"`. |
| `paw.opt.braille` | `true` | When `false`, curves show as `"line"`, whatever `curve_glyphs` is. |
| `paw.opt.wave_scale` | `"linear"` | The scale of audio waveforms in cells. `"linear"` shows hits, and `"db"` shows quiet sound too. |
| `paw.opt.graphics` | `true` | Views that paint show pixels where the terminal can show images. When `false`, they use cells. |
| `paw.opt.mouse` | `true` | The terminal sends the pointer to paw, and with `false` the terminal keeps the pointer for its own selection. |
| `paw.opt.chords` | `"names"` | The chord symbols over the piano roll: `"names"`, `"roman"`, `"both"` or `false`. |
| `paw.opt.harmony_step` | `0.5` | In beats, and the shortest chord that the harmony reading finds is about two times this value. |
| `paw.opt.roll_context` | `"all"` | The tracks whose notes show behind the clip in the piano roll: `"all"`, `"group"`, `"none"`, or a list of track ids. Drum tracks are not in `"all"` and `"group"`. |
| `paw.opt.roll_context_max` | `4000` | The maximum number of notes that show behind the clip. |
| `paw.opt.native_dialogs` | `true` | The graphical window opens the file dialogs of the desktop, not the list of the kernel. |
| `paw.opt.window_cache` | `"auto"` | The graphical window draws a frame again only where it changed, and shows no frame when nothing changed. With `false`, it draws each frame in full, and `"auto"` is the same as `true`. |
| `paw.opt.window_fps` | `"auto"` | The frames a second that the graphical window draws while the song plays, from 1 to 60. `"auto"` is 30 on a graphics card and 15 on the processor, and keys, the pointer and edits show at once. |

For `termcolors = "auto"`, paw uses 24-bit color when `COLORTERM` is `truecolor` or `24bit`, or when `TERM` ends in `-direct`, and otherwise it uses the nearest of 256 colors.

The curve glyphs are as follows.

- `"sextant"` draws a connected line of sextant characters, two columns by three rows in a cell, and steep slopes are filled, so the line has no gaps.
- `"braille"` draws dots, two columns by four rows in a cell.
- `"line"` draws lines at three heights in a row.

## Windows and layouts

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.splitright` | `true` | A new window from a vertical split goes to the right, and with `false` it goes to the left. |
| `paw.opt.splitbelow` | `true` | A new window from a horizontal split goes below, and with `false` it goes above. |
| `paw.opt.layout` | `""` | The name of a layout in `paw.layouts` to start with. See [Windows, buffers and tabs](windows.md#layouts). |

### Options of a window

`:setlocal` sets these options for the current window only.

| Option | Effect |
| --- | --- |
| `:setlocal timebind` | Binds the time of this window to the other bound windows, and `:setlocal notimebind` removes the bind. |

## Pickers, files and the quickfix list

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.audition_delay` | `150` | The time in ms that the selection stays on an item before you hear it. |
| `paw.opt.audition_level` | `-12` | The level in dB of a sound file heard in a picker. |
| `paw.opt.files_hidden` | `false` | A files buffer shows the files whose names start with a dot. |
| `paw.opt.files_limit` | `20000` | The files picker (`<leader>ff`) reads at most this many directory entries, 100 or more, and the query line says so when the picker stops there. |
| `paw.opt.files_depth` | `8` | The files picker goes this many folders deep, 1 to 64, and the query line says so when the picker stops there. |
| `paw.opt.files_skip` | `{ "target", "node_modules", "result", "build", "dist", "__pycache__", "vendor" }` | The folder names that the files picker does not enter. The picker also leaves out hidden folders (`.git`, `.direnv`) and the plain names in the `.gitignore` of the working directory. |
| `paw.opt.files_hear` | `false` | A files buffer plays the sound file under the cursor after the cursor stops on it. |
| `paw.opt.qf_diagnostics` | `"warning"` | The diagnostics that go into the Problems list, which are this severity and worse. `"hint"` gives all and `"off"` gives none. |

## Completion and devices

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.complete_auto` | `true` | paw asks the completion sources for a suggestion after a pause in the edits. |
| `paw.opt.complete_idle_ms` | `1200` | The time in ms without an edit before paw asks. |
| `paw.opt.complete_deadline_ms` | `300` | The time in ms that a request waits before it shows the suggestions that arrived. |
| `paw.opt.complete_audition` | `false` | paw plays each alternative that it shows through the track. |
| `paw.opt.lua_devices_watch` | `1000` | The time in ms between checks of the files of Lua devices. `0` gives no checks. |
