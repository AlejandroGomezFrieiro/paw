# Articulations

An articulation is how a note is played, for example sustain, staccato,
pizzicato or a trill. The extension writes it on the note and sends it to
the instrument of the track. The instrument can be a sampler that reads MIDI
2.0, or any MIDI 1.0 instrument through its keyswitches, controllers or
programs.

```lua
paw.ext.load("/path/to/paw/extensions/articulations")
```

![The demo song's melody under the example violin map: :%art sus tags every note and the band above names the run, \a on a note makes it staccato (each articulation heard as the highlight rests on it), three notes made pizzicato in visual mode, and K shows how paw tells the instrument](images/tui-articulations.gif)

## Try it

1. Type `:ext.load articulations`. Open a clip of a violin track in the
   piano roll.
2. Type `:art.map examples/violin-section`. The keyswitch rows on the
   keyboard edge now have names, and a band `art` is above the ruler.
3. Type `:%art sus`. Each note shows the tag `sus`.
4. Put the cursor on a note, and press `\a`. A numbered list of
   articulations opens. When the highlight stays on one, you hear the note
   with it.
5. Select "Staccato" and press Enter. The note shows `stc`. Press `K`. paw
   tells you that the note is sent as `ks=D1`.

## How to

### How to give notes an articulation

- For the note under the cursor, press `\a` and choose.
- For a selection, select the notes in visual mode, then press `\a`.
- For a range, type `:'<,'>art stc`, `:5,8art pizz` or `:%art sus`.
- To give new notes an articulation, press `\a` in insert mode, or type
  `:art.pen name`.
- For the note that you draw in the piano roll, press `a` in insert mode
  and type the name. The names of the map of the track complete.

### How to make a map for a library

1. Put the cursor on the track of the instrument.
2. Type `:art.generate` with the path of an `.sfz`, a `.dspreset`, a
   `.dslibrary` or a folder of samples. With no path, paw asks a device that
   describes its instrument, for example the sampler.
3. paw writes the map to `~/.local/share/paw/articulations/generated/` and
   binds it to the track.
4. To change names or controllers, edit the `.art.toml` file. paw reads it
   again.

### How to use Reaticulate banks

- To import, type `:art.import file.reabank`. Each bank becomes a map in
  `~/.config/paw/articulations/reaticulate`.
- To export the map of the track, type `:art.export reabank [file]`.

### How to use a plugin instrument

1. Add the plugin to a track. When a map names the plugin in its `match`,
   paw binds the map to the track, as one undo step. A message tells you
   so. `paw.opt.art_auto_map = false` stops this.
2. If the keyswitches of the plugin are on other keys than those of the
   map, type `:art.shift -1oct` (or `-12`, `+2`). `:art.shift 0` puts them
   back.

See [How to use articulations with a plugin
instrument](../../docs/how-to/use-articulations-with-a-plugin-instrument.md).

### How to make notes sound on the beat

1. Bind the map of the instrument to the track.
2. Type `:art.measure`. paw renders one note of each articulation and shows
   the delays that it finds.
3. Type `:art.measure!`. paw writes the delays into the map and sends them
   to the track.

### How to draw dynamics on several controllers at once

1. Add a `[linked]` entry to the map (generated maps have one).
2. Press `\c` in the piano roll, or type `:art.lane dynamics`. The linked
   controllers open as one curve.

### How to find problems

Type `:art.check`. The problems of the notes go to the quickfix list.

## Reference

### Where the data is

- The articulation is the MIDI 2.0 attribute of the note (`note.attr =
  { type, data }`). It is a code of the MIDI 2.0 Note-On Orchestral
  Articulation Profile (M2-123): `11.0` staccato, `11.A` pizzicato, `13.2`
  a whole-step trill. See [Project objects in
  Lua](../../docs/reference/lua-objects.md#note-attributes-noteattr).
- A map gives the names of the codes on one instrument, and how to send
  them to it. Each instrument has one `.art.toml` file.
- When you bind a map to a track, the track keeps the binding
  (`track.meta.articulations`). The extension gives the core the downgrade
  map of the track (`track.attr_map`), which sends the keyswitch, controller
  or program of each note before the note, to an instrument that does not
  take the attribute.
- The core does not use the map, and the extension reads the TOML of the map
  with `paw.toml`. The extension also reads an attribute in `note.meta.art`,
  where older versions kept it.

### A map

```toml
# Violin section of VSCO 2 CE, played by a keyswitched SFZ.
format = 1
name = "Violin section"
match = ["sfz:Violin Section KS.sfz"]  # what instrument it is for
range = "G3-A7"                       # the roll shades outside it
comfortable = "G3-E7"                 # and lightly outside this
keyswitches = "C1-A1"                 # rows labelled with articulations
default = "sustain"                   # what a note with no articulation plays
send = "change"                       # keyswitch only when it changes ("every": before every note)
chase = [1, 11, 64]

[art]
sustain    = { m2 = "10.0", out = "ks=C1",  tag = "sus", name = "Sustain",   class = "long" }
staccato   = { m2 = "11.0", out = "ks=D1",  tag = "stc", name = "Staccato",  class = "short", mark = "staccato" }
pizzicato  = { m2 = "11.A", out = "ks=E1",  tag = "pz",  name = "Pizzicato", class = "short-light", text = "pizz.", range = "G3-E7" }
harmonics  = { m2 = "14.0", out = "ks=A1 cc1=96", tag = "hrm", name = "Harmonics", class = "long-light", text = "harm." }

[mod]
con-sord   = { m2 = "mute=straight", out = "cc20=127", off = "cc20=0", text = "con sord." }
```

The full example is in the folder of this extension, at
`articulations/examples/violin-section.art.toml` (from the top of the
source of paw:
`extensions/articulations/articulations/examples/violin-section.art.toml`),
and `:art.map examples/violin-section` binds it.

Each articulation is one inline table on one line, in the order that the
popover numbers them.

| Field | Value |
| --- | --- |
| `m2` | the code of M2-123 |
| `out` | a line of events: `ks=D1` a keyswitch note that the instrument latches (`ks=D1:127` with a velocity), `hold=D1` held while the articulation continues, `cc32=40`, `cc58=0-15` a value from a range (paw sends the middle), `pc=12` (`pc=12/258` with a bank), `ch=2` the note on another channel, `bend=0.5`, `attr` the attribute alone. Two keyswitches go in one line: `ks=C#0 hold=G0` |
| `tag` | the short name on the notes |
| `name` | the name in lists |
| `class` | a color: the classes of Reaticulate (`long`, `short`, `legato`, `fx`, `textured`, each `-light` or `-dark`) or `#rrggbb` |
| `mark` | what the score shows: `staccato`, `staccatissimo`, `accent`, `tenuto`, `marcato` |
| `text` | the text in the score: `pizz.` |
| `range` | the range of this articulation |
| `delay` | how much earlier its notes play: `"-80ms"` |

Key names are as paw names them: middle C is C4, 60. For a vendor whose
chart calls key 60 `C3`, put `middle_c = "C3"` at the top of the map, and
the keys of the map are then as the chart writes them, while paw sends them
as paw names them.

Other fields at the top of a map:

| Field | Value |
| --- | --- |
| `match` | the instruments that the map is for. `sfz:File.sfz`, `dspreset:`, `describe:` name a library. `vst3:MODO BASS 2`, `clap:<id>`, `lv2:`, `vst:` name a plugin in that format, by its id, its name or a part of its name. `plugin:Name` names it in any format |
| `middle_c` | the name of key 60 in the map: `"C4"` (the default) or `"C3"` |
| `checked` | how far the map was checked: `"from the manual, not checked with the plugin"` |

### Maps of plugins

The extension has the following maps, in `articulations/plugins/<vendor>/`.
Each one comes from the documentation of its vendor, which the top of the
file names, and paw did not check them with the plugins.

| Map | Instrument |
| --- | --- |
| `modo-bass-2` | MODO BASS 2: finger, pick (down, up), slap, harmonics, ghost notes, hammer-on, legato slide; mute and plucking position as modifiers. Set its keys in the Control tab first: the top of the file tells how |
| `sine-keyswitch` | SINE Player in key switch mode, a template. It binds itself to SINE Player |
| `sine-cc`, `sine-channel`, `sine-program` | SINE Player in its other modes: a controller divided in ranges, a channel for each articulation, program changes |

Drum plugins have no articulations, and the `drums` extension names their
notes (`:drums.map mt-powerdrumkit`).

paw looks for maps in the following places, and the first map with an id
wins.

1. `~/.config/paw/articulations/**`
2. beside a library (`Violins.art.toml` next to `Violins.sfz`)
3. `articulations/` in any loaded extension
4. `~/.local/share/paw/articulations/generated/`

The id of a map is its path there without `.art.toml`
(`examples/violin-section`). `:art.map` takes an id, the end of an id, a
name or a file.

### Delays

Many libraries start the sound of an articulation late (the attack of a
legato sample, the start of a bow). `delay = "-80ms"` on an articulation,
or on the full instrument at the top of its map, plays those notes that
much earlier, so they sound on the grid.

- The delay goes into the downgrade map of the track
  (`attr_map.arts[code].delay`, and `attr_map.delay` for the instrument).
  The kernel applies it.
- `K` on a note tells its delay.
- `:art.measure` renders one note of each articulation offline through the
  instrument of the track, after the keyswitch, controllers, program and
  attribute. It finds where each sound starts, and shows the delays.
- `:art.measure!` writes them into the map of the instrument (on the line
  of each articulation, with comments kept) and sends them to the track, as
  one undo step.
- The start of the sound is the first 1 ms block whose peak is within
  20 dB of the loudest block. paw looks at the first two seconds of the
  note.

### Linked controllers

An instrument often plays one gesture from several controllers: dynamics
on CC1 and CC11, a vibrato on CC21 and CC1. The map links them:

```toml
[linked]
dynamics = { cc = [1, 11], curve = ["linear", "0:0.4 1:1"], default = 0.7, name = "Dynamics" }
```

- `\c` in the piano roll (or `:art.lane dynamics`) opens them as one
  curve in the curve view. Its keys and the pointer edit it, in the
  terminal and in the graphical window.
- Each point writes every controller of the link through its own curve
  (`linear`, `exp`, `log`, `s`, or points `"x:y x:y"`), in one edit.
- With no moves, the lane is at the `default` of the instrument. A drawing
  that starts after the start of the clip starts at that value.
- The controllers are ordinary moves of the clip. Any instrument plays
  them.

### In the piano roll

With a map bound, the piano roll changes as follows:

- Rows outside the range are dark. Rows outside the comfortable range are
  dimmer.
- The keyboard edge names the keyswitch rows by their articulations.
- Each note with an articulation has its color, and its tag (`stc`) in
  place of its pitch.
- A band above the ruler, `art`, shows the articulation of the top line of
  the clip in time, with the pen at its right.
- `K` on a note tells "Pizzicato (11.A), sent as ks=E1", or which
  articulation the fallback of the profile plays.

| Keys | Effect |
| --- | --- |
| `\a` | the articulation of the note under the cursor, or of the selection (visual mode): a numbered list. You hear each on those notes when the highlight stays on it. Enter writes it as `:art <name>`. Esc leaves no change |
| `\A` | a modifier of the map (`con sord.`) over the note or the selection: its controllers at the start, `off` at the end |
| `\a` in insert mode | the pen: the articulation of the notes that you enter after this |
| `ia` `aa` | the run of notes with the articulation under the cursor (`aa` with the gap after it): `dia`, `yaa`, `v` `ia` |
| `\c` | the linked controllers of the instrument (dynamics), as one curve |

Notes entered with the keys, in insert mode or by a click take the pen.

### Commands

| Command | Effect |
| --- | --- |
| `:art name` | sets the articulation of the note under the cursor. With a range, of its notes: `:'<,'>art stc`, `:5,8art pizz`, `:%art sus`, `:g/art=pz/art arco`. `none` removes it. Alone, the popover |
| `:art.default name` | what the notes of the track with no articulation play |
| `:art.pen name` | the articulation of new notes (`none`) |
| `:art.mod name` | a modifier over the range or the note |
| `:art.map [name]`, `:art.unmap`, `:art.maps` | binds a map (alone: the map whose `match` names a device of the track, else a list), removes it, lists all maps |
| `:art.generate [library]` | makes a map from an `.sfz`, a `.dspreset` or `.dslibrary`, a folder of samples named by articulation, or (alone) a device that describes its instrument, and binds it |
| `:art.import file.reabank` | makes a map of each bank of a Reaticulate file, in `~/.config/paw/articulations/reaticulate` |
| `:art.export reabank [file]` | writes the map of the track as a Reaticulate bank |
| `:art.new name` | a map to fill |
| `:art.from-keyswitches` | changes keyswitch notes and the controller moves that switch articulations into the articulations of the notes after them: CC32 (UACC), and a controller that two articulations set to other values (not one that the map chases or links) |
| `:art.shift [keys]` | moves the keyswitches of the map of the track: `-12`, `+2`, `-1oct`. `0` puts them back. Alone, tells where they are |
| `:art.check` | the problems of the notes of bound tracks, in the quickfix list |
| `:art.measure`, `:art.measure!` | measures how late each articulation sounds. With `!`, writes it into the map |
| `:art.lane [name]` | a linked lane of controllers as one curve |

The `art` field matches and sets the articulation of a note in patterns:
`:g/art=pz/`, `:s/art=stc/art=spc/`.

### Diagnostics

| Problem | Severity and fix |
| --- | --- |
| a note outside the range (of the map, or of its articulation) | warning. Fix: move it an octave |
| a note on a keyswitch row | warning. Fix: make the keyswitches the articulation of the notes after them |
| an articulation that the map does not have | it plays by the fallback of the profile, and says so. Fixes: make it that articulation, or remove it |
| a chord of two articulations on a keyswitched instrument | warning, because the last keyswitch wins |

### Maps from a library

| Source | What paw reads |
| --- | --- |
| SFZ | `sw_last` (and `sw_down`, held), `sw_label`, `label_keyN`, `sw_lokey` `sw_hikey`, `sw_default`, the keys of the regions of each switch. Through `#define` and `#include` |
| Decent Sampler | `<midi><note>` whose bindings enable groups: the key, and the names of the groups that it enables. The keys of the samples of the groups |
| A folder | its folders with samples are articulations. The notes in the names of the files are their ranges (the layout of VSCO 2 CE). The attribute alone plays them |
| A sampler device | the answer of `device_call(id, "describe")`: its articulations, keyswitches and range |
| Reaticulate | every bank of a `.reabank`: names, colors, icons, program numbers, `chase`, outputs (`cc`, `note`, `note-hold`, `program`, `pitch`, channels) |

- Names get their codes from the words that libraries use, icons first
  (`trill m2` and `trill M2` differ only by case).
- Of the 1426 articulations of the 218 factory banks of Reaticulate, 1283
  get a code (90 %), 120 of them from the icon alone.
- Most of the rest are what the profile makes a controller (`sul pont`,
  `con sord`), or a word of one library. Those get a code of the library
  (classification 1A and up), and two articulations with one code get two
  variations of it, so you can choose each articulation.
- What the library does not say comes from the profile. Each coded
  articulation gets the tag of the profile (`stc`, `pz`, the tags that
  `:g/art=pz/` finds) and a class for its color. Where the profile has one,
  it also gets the mark (`staccato`) or text (`pizz.`, `trem.`, `harm.`) of
  the score.
- Each generated map links dynamics on CC1 and CC11 (`[linked]`), so `\c`
  works on it at once. Edit the file when the library uses other
  controllers.

### With notation

When the notation extension is loaded too, the following changes apply:

- The articulation of a note shows in the score as its `mark` (a staccato
  dot).
- A run of notes starts with its `text` (`pizz.`), with `ord.` where the
  default returns.
- A mark in the score (`g'` a staccato) or a technique (`\p pizz.`, `arco`)
  sets the attribute of the notes, when the map of the track has an
  articulation with that mark or text. `paw.opt.art_from_notation = false`
  turns this off.

### Options

| Option | Default | Effect |
| --- | --- | --- |
| `art_auto_map` | `true` | a plugin added to a track with no map binds the map whose `match` names it |
| `art_from_notation` | `true` | a mark or technique written in the score sets the articulation of the notes |

### Events

| Event | Payload | When |
| --- | --- | --- |
| `articulations.bound` | `{ track, map }` | a map was bound to a track. With no `map`, the binding was taken away |

### Limits

- The articulations have no menu of their own in the graphical window.
- The keyswitch rows have labels and shades, but they do not fold.
- The score draws the mark of an articulation in the same ink as a written
  mark.
- A modifier writes its MIDI 1.0 controllers, not the registered
  controllers of the profile. A modifier does not send keyswitches.
- A map cannot switch an articulation with a parameter of the plugin. Use
  a keyswitch or a controller that the plugin learns.
- A project that opens does not bind maps to its plugins. Only a plugin
  that you add does.

## About

The articulation is MIDI and not data of the extension, so paw copies,
moves, undoes and saves it with the note, and it plays when the extension is
not loaded. A part moved to another instrument keeps its meaning. An
instrument that does not have that exact articulation plays the nearest
one that the profile names, which is another variation, then the same
family, then sustain.
