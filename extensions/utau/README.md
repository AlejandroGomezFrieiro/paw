# utau: singing synthesis

Vocal tracks whose notes and lyrics the engines of OpenUtau sing: classic
UTAU voicebanks, DiffSinger, ENUNU, Vogen, VOICEVOX. They sing through the
own engine of the extension, `paw-utau-engine`. The extension also has its
own vocal editor.

```lua
local vocal = paw.track_kinds.add("vocal", { name = "Vocal", ask = false })
require("utau").configure(vocal.id, { singer = "Kitane sno act5 VCV" })
vocal:add_clip({ start = 0, length = 4, notes = {
  { pitch = "A3", start = 0, length = 1, meta = { lyric = "- あ" } },
  { pitch = "C4", start = 1, length = 1, meta = { lyric = "- い" } },
} })
paw.render("vocal.wav")   -- waits until every phrase is sung at final quality
```

![A vocal track added to the demo song with :track.add vocal, its singer chosen with \Vs and its phonemizer with :utau.phonemizer, the melody pasted in, lyrics typed in romaji with :utau.lyrics and made kana with :utau.batch. The phrases turn green as the engine sings them](images/tui-utau.gif)

![The vocal editor on the sung melody: the phonemes under the notes, ~ puts a vibrato on the long note, \]e and } raise its dynamics, r sings it again, and Space pressed twice plays it](images/tui-utau-editor.gif)

## Try it

1. Start paw with the extension (see [How to enable the
   extension](#how-to-enable-the-extension)). Install a voicebank for
   OpenUtau.
2. Type `:track.add vocal`. A vocal track appears, with `V` before its name.
3. Press `\Vs` and choose a singer.
4. Put the cursor on an empty part of the track. Press `i` to make a clip,
   and press Enter. The vocal editor opens.
5. Press `i` to add a note, then `c`, type `a` and press Enter. The phrase
   in the ruler turns green when the engine has sung it. Press Space two
   times to hear it.

## How to

### How to enable the extension

In a Nix configuration, take paw with the extension in it. The engine,
OpenUtau and the Lua come with it. You install nothing more.

```nix
# home-manager, with the flake of this repository as `paw`:
imports = [ paw.homeManagerModules.default ];
programs.paw = { enable = true; extensions = [ "utau" ]; };

# or a package of your own:
paw.packages.${system}.default.withExtensions (exts: [ exts.utau ])
```

- To run it from the source tree, type `nix run .#paw-utau`. `nix run .`
  has no .NET in it.
- The package loads the extension at startup, whatever `init.lua` says.

Also install **voicebanks** for OpenUtau, in
`~/.local/share/OpenUtau/Singers`. `:utau.install` can do it.

### How to work on the extension without Nix packages

1. Link the extension into `~/.config/paw/extensions/utau`, or add
   `paw.ext.load("/path/to/paw/extensions/utau")` to `init.lua`. The device
   is Lua and needs no build.
2. Build the engine alone with `nix build .#utau-engine`, or with `dotnet`
   (see `engine/README.md`).
3. To try a change of the engine, point `utau_engine` at
   `result/bin/paw-utau-engine`.
4. Run the tests with `tests/tools/suite.sh only utau`. The tests that sing
   need the engine, and `PAW_UTAU_OPENUTAU_DIR` set to the OpenUtau folder
   that has the test voicebank (`PAW_UTAU_TEST_SINGER` names another
   voicebank). Without them, they say that they were skipped. The tests
   are in `tests.lua` and `tests_singing.lua`.

When the file of the device changes, paw loads it again
(`:device.reload`).

### How to type lyrics

- For one note, press `c` in the vocal editor and type the lyric. `Tab`
  goes to the next note.
- For many notes, type `:utau.lyrics` and the words, from the cursor on.
  Or paste several words at `c`.
- From a text file, type `:utau.lyrics_file <path>`.
- To change romaji to kana, type `:utau.batch romaji_to_hiragana`.

### How to shape the voice

- To switch vibrato on a note, press `~`.
- To choose the curve under the notes, press `]e` or `[e`. To raise or
  lower it at the cursor, press `}` or `{`.
- To apply a tuning preset, type `:utau.preset` and choose one.

### How to add a harmony or a double

- Type `:utau.harmony 3up`. A track under this one sings a third up, in the
  key.
- Type `:utau.double`. A track under this one doubles the voice.

### How to open the tracks in OpenUtau

Type `:utau.openutau`. paw writes the vocal tracks to a `.ustx` file and
starts OpenUtau on it. To read changes back, save in OpenUtau and type
`:utau.import <file>`.

### How to make a vocal track into audio

Type `:utau.freeze`. To sing it again, type `:utau.unfreeze`.

## Reference

### Vocal tracks

A vocal track is a kind of track (`paw.track_kinds`).

- `:track.add vocal [singer]`, `<localleader>Vt` (`:utau.track [singer]`) or
  `:track.new` adds one. The graphical window offers "New vocal track"
  where it makes a track.
- `<localleader>Vs` (`:utau.singer`) chooses its singer from a list.
- The header shows `V` before the name of the track. `K` and the header in
  the graphical window tell who sings.
- Enter on a clip of a vocal track opens the vocal editor, not the piano
  roll.
- Without the extension, a vocal track is an ordinary MIDI track.

### Keys after the leader

These keys work from every view. They are in the domain `<Space>u` (utau).

| Keys | Command | Effect |
| --- | --- | --- |
| `<Space>ut` | `utau.track` | adds a vocal track |
| `<Space>uv` | `utau.voice` | makes the track at the cursor a vocal track |
| `<Space>us` | `utau.singer` | chooses the singer of the vocal track |
| `<Space>ue` | `utau.edit` | opens the clip under the cursor in the vocal editor |
| `<Space>ul` | `utau.sheet` | shows or hides the lyric sheet |
| `<Space>ur` | `utau.render` | renders the vocal track again |
| `<Space>uf` `<Space>uF` | `utau.freeze`, `utau.unfreeze` | freezes the vocal track, sings it again |
| `<Space>uo` | `utau.openutau` | opens the vocal tracks in OpenUtau |
| `<Space>ui` | `utau.status` | tells what the singing engine does |

### The vocal editor

| Keys | Effect |
| --- | --- |
| `h` `j` `k` `l`, `<C-d>` `<C-u>` | move the cursor a grid step or a semitone, an octave |
| `w` `b`, `Tab` `S-Tab`, `0` `$`, `W` `B` | the next and previous note, the start and end of the clip, the next and previous bar |
| `d` `y` `>` `<` `gl` with a motion, `in` `ib` `ic`, or a selection (`v` `V` `<C-v>`) | delete, yank, move or loop notes, as in the piano roll. The notes keep their lyrics and tuning |
| `p` `P` | paste after the note, or at the cursor |
| `/` | finds a note by its lyric. `n` and `N` continue |
| `i` `x` | add a note, remove the note (`x` and `Del` remove the selected notes, if any) |
| `c`, `Enter` | type the lyric of the note: the first key replaces it, `Tab` keeps it and goes to the next note, `S-Tab` to the previous note, `Enter` keeps it, `Esc` drops it. Several pasted words fill the notes from this note on |
| `+` `-` (`C-a` `C-x` with a count), `A-l` `A-h`, `H` `L` | up, down a semitone. Longer, shorter. Move. The selected notes, else the note under the cursor |
| `gA`, `ip` `ap` | select every note. The phrase as a text object (`yip`, `vap`) |
| `<C-c>`, `d` `x` | copy the selected notes (or the note), cut them. `p` `P` paste, with their pitches |
| `]e` `[e`, `:utau.curve <abbr>` | the curve under the notes: next, previous, by name |
| `}` `{` | raise or lower that curve at the cursor (the pitch by 10 cents, the others by their own step. A count multiplies) |
| `=` | an operator: reset that curve to its default over what it covers. `=in` under the note, `==` in the full clip, `=` on a selection |
| `[p` `]p` | choose the previous or next phoneme (in the phoneme row and the bottom line) |
| `[` `]` | that phoneme starts 5 ticks earlier or later |
| `grp`, `gR` | type the phoneme to sing in its place. Restore it from the voicebank |
| `~`, `:utau.note key=value ...` | vibrato on or off. Set properties of the selected notes: `tuning`, `vibrato=on`, `length` `period` `depth` `in` `out` `shift` `drift` `vol_link`, `po` (phonemizer, `default` for the track's), `transition=default`, and any expression (`vel=120`) |
| `<Space><Space>`, `gh` | play from the cursor or stop. Hear the note under the cursor |
| `S`, `s`, `r` | choose the singer, show the lyric sheet, render again |
| `Esc`, `<C-w>p`, `<C-w>c` | forget the selection (the editor stays). Return to the window before. Close the editor |

- The selection is the same in both frontends: the notes in a visual
  selection while there is one, else the notes chosen with the pointer.
  Each key above that says "selected" acts on it, or on the note under the
  cursor when nothing is selected.
- When the engine runs and the track has a singer, you hear notes when you
  place or click them, with the voice of the track. Else you hear a soft
  tone. `paw.opt.utau_audition = false` stops this.
- While the transport plays, the editor turns the page to keep the
  playhead in view.

The editor shows:

- the lyric of each note
- in the row under it, the phonemes that the engine made (red when the
  voicebank does not have one, orange when changed here)
- the state of each phrase in the ruler: gray pending, yellow rendering,
  blue draft, green final, red error
- the sung pitch as a white line across the rows (`▔`, `─` and `▁` for the
  upper, middle and lower third of a semitone)
- the bends that you drew, as orange dots
- under the notes, the chosen curve in cells (`paw.opt.curve_glyphs`), with
  its value at the cursor

In a terminal that shows pictures (`buf:strip`, see [Pictures in the
terminal](../../docs/reference/pictures.md)), these are lines in pixels
under the notes. Orange is the pitch of each note: its transition from the
note before, its vibrato (a vibrato of 25 cents shows), and your bends.
White is the pitch that the engine sang. The curve has the area under it.
The notes, lyrics, cursor and playhead stay cells over them. `:set
graphics!` returns to cells.

The lyric sheet (`s`, `:utau.sheet`) shows the lyrics of the clip, one
line for each phrase, with the sung note lit. `c` types a line again, and
the words go to its notes in order. `K` splits Japanese into one kana for
each note.

### Commands of the voice

| Command | Effect |
| --- | --- |
| `utau.track [singer]`, `utau.voice` | adds a vocal track. Makes the cursor track a vocal track |
| `utau.singer [name]`, `utau.phonemizer`, `utau.renderer`, `utau.resampler`, `utau.color` | the voice of the track |
| `utau.edit`, `utau.sheet` | opens the vocal editor, the lyric sheet |
| `utau.lyric <text>`, `utau.lyrics <words...>`, `utau.lyrics_file <path>` | the lyric of a note. Of the notes from the cursor on. From a text file |
| `utau.vibrato`, `utau.tuning <cents>`, `utau.bend <cents>`, `utau.flatten` | properties and pitch of each note |
| `utau.batch [name]` | batch edits: `romaji_to_hiragana`, `kana_to_romaji`, `vcv_to_cv`, `remove_tone_suffix`, `remove_hint`, `dash_to_plus`, `lowercase`, `replace find=a replace=b`, `reset_pitch`, `clear_vibrato`, `vibrato_long`, `reset_exp`, `reset_phonemes`, `reset_po`, `reset_all`, `fix_overlap`, `fill_gaps`. `note=1` for the note under the cursor only |
| `utau.preset [name]` | tuning presets: breath at phrase starts, soft endings, swells, tension on high notes, overshoot and preparation on leaps, crisp consonants, vibrato styles, raspy, scream, growl, vocal fry, reset |
| `utau.import <file>` | an OpenUtau `.ustx`, UTAU `.ust`, VOCALOID `.vsqx`, Synthesizer V `.svp`, MIDI or MusicXML file as vocal tracks, read by the code of OpenUtau |
| `utau.render`, `utau.restart`, `utau.status` | renders a track again, starts the engine again, shows what it does |
| `utau.inspector` | shows or hides the note inspector in the window of the vocal editor |

### Commands of tracks, files and the engine

| Command | Effect |
| --- | --- |
| `utau.export <file> [all=1] [clip=1]` | writes the vocal track (every vocal track, the clip under the cursor) to the `.ustx` of OpenUtau, the `.ust` of UTAU, or MIDI with lyrics (`.mid`), by the extension of the file. A `.ust` holds one part: more parts go to `name-2.ust` and on |
| `utau.openutau` | writes the vocal tracks to `<project>.ustx` beside the project file (`~/.local/share/paw/utau/openutau/` for a project that is not saved), and starts OpenUtau on it: `paw.opt.utau_openutau`, else `$PAW_UTAU_OPENUTAU`, else `OpenUtau` |
| `utau.freeze`, `utau.unfreeze` | renders the vocal track to audio on a track below it, "Vocal (frozen)", mutes it and stops its voice. Sings it again and removes the audio |
| `utau.singer_save <name>`, `utau.singer_preset [name]`, `utau.singer_delete <name>` | saves the voice of the track as a singer preset. Gives a track a preset (with no name, from a list). Deletes one |
| `utau.install <archive or folder>`, `utau.singers` | installs a voicebank (zip, rar, 7z, uar, a folder), a Vogen singer (`.vogeon`) or a dependency package (`.oudep`). Lists the installed singers, to choose one for the track |
| `utau.harmony [3up\|3down\|5up\|4down\|6down\|8up\|8down] [key=Dm] [preset=name]`, `utau.double [take=2]` | a track under this one that sings a harmony in the key, or doubles it |
| `utau.ai_pitch [on\|off]` | AI pitch: the pitch model of the renderer sings, and paw adds the drawn pitch to it |
| `utau.retake [new\|prev\|next\|info] [kind=timbre] [note=1] [whole=1]` | a new AI pitch (or timbre) take of the phrases of the clip, or of the note under the cursor of the editor. Steps between takes |
| `utau.timing [take]` | a timing take: the starts of the notes humanized by up to 18 ticks, the same for the same take. `0` removes it |
| `utau.curve [abbr] [off=1]` | shows a curve under the notes of the editor. A curve of the renderer (energy, voice color blends, and other) first gets the lane of a device slot `x1` to `x8`. With no name, lists them |
| `utau.unison <voices> [spacing= pitch= timing= level=]`, `utau.shift <semitones> [cents=]` | sings with several voices. Sings higher or lower without a move of the notes |

- **Export and import** go through the engine. `paw-utau-engine --export`
  makes the OpenUtau project from the description that the engine sings,
  and saves it with the writers of OpenUtau. `--convert` reads it back with
  the readers of OpenUtau. A `.ustx` returns with the same notes,
  lyrics, note properties, singer and curves (on the whole-number grid of
  OpenUtau). OpenUtau gives its default pitch points to notes that have
  none.
- **Freeze** is the bounce of the core (`paw.bounce`), after the engine
  sang every phrase at final quality. The frozen track keeps its notes,
  curves and voice. The bounced file is in the media folder of the project.
- **Singer presets** are JSON files in `~/.local/share/paw/utau/presets`
  (`paw.opt.utau_presets_dir`). A preset holds the singer, phonemizer,
  renderer, resampler, wavtool and voice color. It also holds the options
  of the engine (AI pitch, unison, shifts) and the value of each curve with
  no lane. A
  preset replaces the full voice of the track.
- **Install** runs `paw-utau-engine --install`. It finds the type of the
  singer and the encoding of the file names. A folder is copied into
  `Singers`. The singers go into the folder of OpenUtau
  (`~/.local/share/OpenUtau`, or `utau_openutau_dir`), and the engine finds
  singers again.
- **A harmony** is a copy of the track (voice, curves, lyrics and note
  properties), 3 dB quieter and panned 0.3 to one side. Its notes move by
  scale degrees in the key. That is the key of the project when the
  `musicops` extension has one, else the key of the melody
  (Krumhansl-Schmuckler).
- **A double** keeps the notes. It moves the start of each note by up to 18
  ticks and its pitch by up to 8 cents. The same take gives the same
  result.
- **AI pitch, retakes and the curves of the renderer** belong to the
  engine. Its cache keeps the takes across sessions. You hear them with
  DiffSinger and other renderers that have a pitch model or such curves. A
  classic UTAU voicebank sings the same with or without them.

### In the graphical window

A double click on a clip of a vocal track opens the vocal editor in a
window of its own. The extension paints it (`lua/utau/gui.lua` and the
`gui_*.lua` panels beside it), through `paw.canvas`.

| Where | With the pointer |
| --- | --- |
| Toolbar | the name of the singer opens the list of singers. `Notes`, `Select` and `Pitch` choose the tool. `Curves` and `Inspector` show or hide those panels. Then the grid and the zoom |
| Ruler | a click moves the playhead. The colored line shows how far each phrase is rendered |
| Notes tool | a drag on empty space draws a note. A click on a note selects it. Shift+click adds or removes it. Ctrl+drag on empty space selects the notes in a box. A drag on a note moves the selection, a drag on its right edge stretches it. A double click types the lyric (Tab goes to the next note). A double click on empty space selects the phrase there. A right click removes the note, or its selection |
| Select tool | as the Notes tool, but a drag on empty space always draws a box |
| Pitch tool | draw over the notes to bend the pitch (orange). A right click on a note restores its pitch. You drag the transition points of each note (green). A double click on a note adds one, a right click removes one. Ctrl+click changes how the line leaves it (circle: ease in and out, diamond: straight, triangles: ease in, ease out). Ctrl+click on a note switches its vibrato. On the selected note, you drag its handles (start, fade in, fade out, depth, period, shift, drift). The white line is the sung pitch |
| Phoneme row | drag the start of a phoneme (the line on its left) to move it, with Shift for single ticks. A double click types the phoneme to sing in its place. A right click restores it |
| Curve panel | the tabs choose the curve (a dot marks curves with a lane). A drag draws it. A right drag restores its default. A double click restores it under a note |
| Inspector | lyric, tuning, phonemizer, vibrato and its numbers, transition, expressions of each note, and the phonemes of the note, for the selected notes (else the note under the cursor). Drag a value to the side (Shift for small steps), or click it and type. A right click restores it. Several words typed as the lyric go to the notes in order |
| Wheel | scrolls. With Shift, to the side. With Ctrl, it zooms. With Ctrl and Shift, the rows grow or shrink |
| Keys | every key of the editor in the terminal. `Ctrl+V` pastes at the cursor here (in the terminal, it selects a block) |

### Where the data is

All the data is ordinary project data. So the project saves it, and undo
applies to it.

| Data | Where |
| --- | --- |
| Notes | the notes of the clip. The lyric of a note is `note.meta.lyric`. A note without one sings `paw.opt.utau_default_lyric` (`a`). `R` is a rest |
| Note properties (tuning, vibrato, pitch transitions, phoneme overrides, expressions, phonemizer override) | `note.meta.utau`, in the shape that `paw-utau-engine --convert` writes (see `lua/utau/payload.lua`) |
| Curves (pitch deviation `pitd`, dynamics `dyn`, tension, breathiness, gender, voicing, tone shift, growl, cross synthesis) | the parameters of the `utau` device (`lua:utau`). An automation lane on a parameter is that curve. A parameter with no lane holds the curve at its value |
| The kind | `track.meta.kind = "vocal"`. A track with the device and no kind (made before kinds of track) is a vocal track too. A project saved when the device was part of the program (kind `utau`) gets the device in Lua |
| The voice (singer, phonemizer, renderer, resampler, wavtool, voice color, other options of the engine) | `device.meta.utau`. Also the curve of the renderer that each slot `x1` to `x8` draws (`curves`), and for a frozen track, its audio track (`frozen`) |
| The id of a vocal clip | `clip.meta.utau_clip`. A copy knows its original by it |
| The voice that a device plays | the `voice` parameter of the device. The extension numbers the voices |

- **Curves follow their clip.** When you move a vocal clip, on its track or
  to another vocal track, its curves go with it. A copy, a duplicate or a
  paste gets a copy of them. A delete removes them, and a paste brings them
  back. A split or a trim leaves them in place. This occurs in the same
  undo step as the edit.
- paw does not save the rendered audio. The engine keeps it in a cache. A
  project that opens again is sung again from that cache.

### Files

| Path | Contents |
| --- | --- |
| `~/.local/share/OpenUtau/Singers` | the voicebanks. `utau_openutau_dir` or `$PAW_UTAU_OPENUTAU_DIR` names another folder |
| `~/.local/share/paw/utau/openutau-data` | the data of the engine. `utau_data_dir` names another folder |
| `~/.cache/paw/utau` | the render cache, with the AI pitch takes. `utau_cache_dir` names another folder |
| `~/.cache/paw/utau-voices/<pid>` | the rendered phrases as files. paw removes them when it stops |

paw finds the engine through the `utau_engine` option, `$PAW_UTAU_ENGINE`,
`bin/paw-utau-engine` beside the extension (where the package puts it), or
`paw-utau-engine` on the `PATH`. Without the engine, the device and the
editor work, but nothing sings, and an offline render tells you.

| Option | Default | Effect |
| --- | --- | --- |
| `utau_drafts` | `true` | sings a quick draft of each DiffSinger phrase before the final quality |
| `utau_final_delay` | `1500` | the milliseconds without an edit before the engine sings the final quality |
| `utau_render_timeout` | `600` | the seconds that an offline render waits for the singing |
| `utau_log_level` | `info` | the log level of the engine (`--log-level`) |

### How it works

```
 Lua: extensions/utau                       paw-utau-engine (.NET, OpenUtau.Core)
   project ── snapshot/diff ── msgpack ─────▶ phonemize, render phrases
   editor  ◀── phonemes, sung pitch ────────
   phrase files, device_post("voice.N") ◀── PhraseAudio ─
          │
   devices/utau.lua (lua:utau) maps the files and plays each phrase at its time
```

- The extension starts `paw-utau-engine --socket <path>` with
  `paw.api.proc_spawn`, and listens on that socket with
  `paw.api.sock_listen`. The engine connects. The two send msgpack frames
  (`lua/utau/proto.lua` and `msgpack.lua` on this side,
  `engine/PawUtau.Protocol` on the other side). After each edit, the
  extension compares the vocal tracks with what it sent last, and sends
  the difference.
- Rendered phrases return as audio, with their place in seconds. The
  extension writes each to a file of 32-bit floats, and posts the list of
  files of a voice to every `utau` device (`paw.api.device_post(kind,
  "voice.<n>", list)`, `lua/utau/voices.lua`).
- Each device maps the files (`dsp.map`) in its own process, and plays the
  phrases of its voice under the playhead. The sound is in memory one
  time, in the files. paw drops old phrases, but an old phrase plays until
  its replacement arrives.
- A device made later, also the device of an offline render, gets the same
  lists before its first block. So it plays the same phrases.
- The device places phrases by whole frames of the song. So live playback and a
  render agree bit for bit (`tests.lua` checks it). A block of 512 frames
  with four phrases costs about 16 µs of its 10.7 ms.
- `paw.render` sends `render.before`. The extension then waits until every
  phrase of every vocal track is final, before the render starts. So
  offline renders are deterministic.
- A device that crashes stops alone, as any device in Lua.
  `:device.restart` starts it again with its voice.
- The engine runs only while there is a vocal track, or a command of the
  editor needs it. It stops with paw.
- Curves follow clips: the extension answers each edit of a clip with
  edits of lanes in the same turn. So the core puts both in one undo step.
  It only notes changes that the core marks `restored` (undo, redo, an
  opened project) (`lua/utau/follow.lua`).

### Limits

- No expression pad, and no panel for curves that only one renderer has.
- The sung pitch does not become pitch points.
- In the terminal: no keys to move pitch points and vibrato (you drag them
  in the graphical window), and no inspector panel (`:utau.note` and the
  bottom line do its work).
- No expression graphs and their macro lanes.
- paw cannot take a track back from OpenUtau over the DAW protocol of
  OpenUtau. `:utau.openutau` writes the file and starts OpenUtau, and
  `:utau.import` reads back what you saved there.
- One clip is one part. A clip cannot hold several parts.
- No clips that loop or play at another rate.
- Tempo ramps in OpenUtau: the engine and the `.ustx` export change a ramp
  into steps of a quarter beat. An
  import away from the start of the song keeps the tempo map of the song.
- Curves do not follow a clip through a ripple delete
  (`paw.opt.ripple`). The pieces after the cut move without their curves.
- Curves do not go with a part of a clip. When you yank and paste a time
  that cuts a clip, the paste has its notes but not its curves.

## About

The extension owns all its parts. The core of paw has no code for
sung notes. See [About the core and
extensions](../../docs/explanation/about-core-and-extensions.md).

```
extensions/utau/
  init.lua, lua/utau/   the vocal editor, the commands, the talk with the engine
  devices/utau.lua      the device that plays the voice (a device written in Lua)
  engine/               the C# source of the engine, on OpenUtau.Core (engine/README.md)
  nix/                  how the engine and the extension are built and packaged
```

The window of the vocal editor is the example of how an extension makes a
painted window.
