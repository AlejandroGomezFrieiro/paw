# Subprojects

<!-- tags: subproject subprojects nest :nest.new <Space>za nest_track -->

A subproject is a section of the song with tracks of its own and a
timeline of its own. The song plays it from a row of its own, its return
row, where a clip of the subproject (its block) covers the time of the
section. The commands and the Lua functions call a subproject a nest. For
entering a subproject and moving around in it, see
[Narrowing](narrowing.md#a-subproject).

## Add a subproject

| Keys or command | Effect |
| --- | --- |
| `<Space>za` | Open the command line with `:nest.new ` for you to type the name, the bars and the meter, for example `Ballad 8 6/8`. Over a selection, the command line starts with `'<,'>nest.new `. |
| `:nest.new [name] [bars] [meter]` | Add a subproject and go inside it, in one undo step. |

`:nest.new` takes its time from the first of these that applies:

1. The selection, or a range that you type (`:33,40nest.new Ballad`).
2. The number of bars that you type, from the start of the bar of the
   cursor. With a meter, the bars are bars of that meter: `8 6/8` is 8 bars
   of 3 beats.
3. The region at the cursor. The subproject then takes the name of the
   region if you type none.
4. Eight bars from the start of the bar of the cursor.

`:nest.new` then does these things:

1. It adds the subproject, named as you typed or `Subproject 1`.
2. It adds the return row below the track of the cursor, with the same
   name, and one block on it over the time of the subproject.
3. With a meter, it writes the meter into the tempo map of the song at the
   start of the block, and the meter that was there back at its end. The
   bar numbers of the song then count the bars of the section, so that bar
   41 comes 8 bars after bar 33. A meter change inside that time goes away.
   The subproject keeps the meter as its own.
4. The window goes inside the subproject, with one empty track, and the
   cursor on that track at its first bar.

The message says what it did, for example `added the subproject Ballad
over bars 33-40 in 6/8, on its own row; inside it now`. `u` takes the
subproject, its row and the meter changes away in one step.

`:nest.new` writes `name=`, `bars=` and `meter=` too, for example
`:nest.new name=Slow part bars=4 meter=3/4`.

| Option | Default | Effect |
| --- | --- | --- |
| `nest_track` | `"track"` | The track that a new subproject starts with: `"track"` for a plain track, as `o` adds, or the name of a kind of track, for example `"vocal"`. |

## Time inside a subproject

A subproject follows the tempo of the song. Its bars are the bars of the
song at the place of its block, counted from 1, so a subproject over a 6/8
section shows bars of 6/8.

- `:tempo` inside a subproject changes the tempo map of the song at the
  place in the song, and the message names the bar of the song. For
  example, `:tempo 60` at the start of the subproject at bar 33 says
  `60 bpm: the song's tempo at bar 33`, and `:tempo 180 at 9` says
  `180 bpm: the song's tempo at bar 41`. Without `at`, `:tempo` sets the
  tempo where the subproject starts.
- `:timesig`, `:tempo.ramp`, `:tempo.remove` and the bar numbers that you
  type in commands work in the bars of the subproject, and change the
  tempo map of the song at that place.
- The status line, the ruler and the playhead show the song's time at the
  place of the block, as for the cursor.

See [Tempo and time signatures](tempo.md) for the commands.
