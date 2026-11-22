# Subprojects

<!-- tags: subproject subprojects nest :nest.new <Space>za nest_track :nest.list :nest.outputs :nest.promote <Space>zp :scope.write <Space>zw <Space>zW -->

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

## The return row and its blocks

The arrange view draws each block of a subproject on its return row in a
frame, with `⧉` and the name of the subproject, and under the name a small
piano roll of the notes that the subproject plays there. The graphical
window draws the same blocks.

| Keys or command | Effect |
| --- | --- |
| `za` on a return row | Show the tracks of the subproject under the row, in the time of the song, or hide them again. On one of those tracks, `za` hides them and puts the cursor on the row. |
| `K` on a block | Describe the subproject, for example `nest Ballad · 6/8 · 8 bars · follows the tempo · 2 tracks · 1 instance · live`. |
| `:nest.list` | Choose a subproject from a list of its blocks, with the subprojects that no block plays (`unused`), and go inside it. |
| `:nest.outputs stems` | On the return row of a subproject, give the subproject a row for each of its tracks, named after the track, in a group under the return row. One undo step. |
| `:nest.outputs master` | On the return row or a stem row, go back to one return row. One undo step. |

The tracks that `za` shows under a return row belong to the subproject.
The cursor finds their clips where the subproject plays them, so a key
that works on the clip at the cursor, for example `~` to mute it,
changes the subproject. The window still shows the song:
`znn` on the block goes inside the subproject. The rows that `za` opens
are not part of the project, and `u` does not
close them.

With stems, the return row is a group, and each stem row holds a block
that plays one track of the subproject. Each track plays through its own
devices into its stem row, and the stem rows play into the return row, so
the fader, the sends and the devices of each stem row act on one track,
and those of the return row on their sum. The master track of the
subproject does not play with stems: its devices and fader are skipped.

## Save a view as a subproject

| Keys or command | Effect |
| --- | --- |
| `<Space>zw`, `:scope.write [name]` | Save the view of the window as a subproject, per track. One undo step. `.` then goes to the next view beside it, as `]z` does, and saves that one too. |
| `<Space>zW`, `:scope.write! [name]` | Save the view of the window as a subproject with its own row. One undo step. |

A view is a part of the song that the window shows, for example the
region that `znar` enters (see [Narrowing](narrowing.md)). Both commands
take the clips of the view's tracks in the view's time, cut at its
edges, and move them into a new subproject. The subproject takes the name
that you type, else the name of the view or of its region.

The subproject keeps the meter of the song over that time as its own,
so the song's bars stay where they are. The markers and regions inside
the time move into the subproject. A region over the whole time stays in
the song. A view with no time takes the song from its start to the end
of the last clip of its tracks, and the subproject then follows the
meter of the song.

The message says what moved, for example `nested 2 tracks, bars 5-10, as
Bridge (6/8)`. `u` gives back the project as it was before.

Per track (`<Space>zw`), each track keeps its devices, fader, sends and
lanes. The subproject gets a track of the same name for each track that
had clips in the time, and each track gets a block over the time that
plays the clips of that track. The clips play through the devices of the
track, as before, so the song sounds the same to the sample. The window
stays in the view.

With its own row (`<Space>zW`), the tracks go into the subproject, and a
new return row plays its mix:

- A track with nothing outside the time moves in as it is, with its
  devices. A track with clips or lanes outside the time stays in the
  song with them, and a copy goes in, with copies of its devices and of
  its lanes over the time.
- The return row goes at the place of the first track, with the name of
  the subproject. It plays where the tracks played, or into the master
  when they played into different tracks.
- When the view is a group whose tracks all move in, the group track
  becomes the return row, with its devices, fader, sends and lanes.
- A group in the view becomes a group inside the subproject.
- A send to a track that stays out becomes a send of the return row at
  the same level, and the message names each one, for example `the send
  of Bass to Verb (-6 dB) is now Bridge's`.
- A VCA over a track that moves in now moves the return row, and the
  message says so.
- A side-chain from a track outside the view is refused, with the route
  named: `compressor on Bass listens to Kick: take Kick in too, or use
  <Space>zw`.
- The window goes inside the subproject, at the same place.

`<Space>zp` on a subproject saved with `<Space>zW` and then `<Space>zW`
on the view that promote leaves give back the same project, with other
ids. The same holds for `<Space>zw` and then `<Space>zp`.

## Promote a subproject to a view

| Keys or command | Effect |
| --- | --- |
| `<Space>zp`, `:nest.promote` | Promote the subproject of the block at the cursor to a view. Inside a subproject, the subproject of the block that you entered it through. One undo step. |
| `:nest.promote!` | The same, and then each subproject inside it whose row holds only its block. |

Promote makes the subproject song data again, and puts a view of it where
the subproject was, so that you keep your place:

- The tracks of the subproject become tracks of the song, in a group
  named after the subproject, at the place of its return row. Their clips
  move to the beats where the block plays them, cut at the edges of the
  block, as the song played them.
- The devices of the tracks stay on the tracks, so no plugin loads again.
  The group track gets the devices of the subproject's master track first,
  then those of the return row, the sum of their faders in dB, and the
  pan, the sends, the output and the color of the return row.
- The lanes of the master track and of the return row go to the group
  track. Two volume lanes become one, with their values added in dB, and
  the message says so. For other lanes with the same target, the lane of
  the return row stays.
- The regions of the subproject come back at their beats in the song,
  inside a region named after the subproject over the block. Promote makes
  that region if there is none.
- A subproject with its own meter writes the meter into the tempo map of
  the song over the block, and the meter of the song back after it.
- The return row, the master track and the subproject go.
- The window shows a view of the group's tracks over the time of the
  region, named after the subproject, for example `Song › Ballad`. The
  view is in the picker of scopes. When the window was inside the
  subproject, it is now inside the view, at the same place.

`u` gives back the subproject as it was. The render of the song is the same
before and after.

A subproject saved per track (`<Space>zw`) promotes otherwise: the clips
of each of its tracks go back to the track of the block that plays it,
cut at the edges of the blocks, and the blocks, the subproject and its
tracks go. The window shows a view of those tracks over the time of the
region.

Promote refuses a subproject that has more than one block, a stem row
(`:nest.outputs master` first), and a return row that holds other clips.
Per track, it refuses a subproject with blocks at two places, and a track
of the subproject that has devices, lanes, or a fader or pan of its own.
