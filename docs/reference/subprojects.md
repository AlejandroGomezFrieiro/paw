# Subprojects

<!-- tags: subproject subprojects nest :nest.new <Space>za nest_track :nest.list :nest.outputs :nest.promote <Space>zp :scope.write <Space>zw <Space>zW :nest.export :nest.own :nest.time :nest.meter :nest.unique kind= -->

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
4. When you typed the bars and the meter makes the section shorter or
   longer in beats, everything in the song after the section moves by the
   difference, so that the song keeps its bar numbers after it: the
   clips, the automation, the markers and regions, and the tempo and
   meter changes. For example, 8 bars of 6/8 at bar 33 of a song in 4/4
   are 8 beats shorter than 8 bars of 4/4, so the rest of the song moves 8
   beats earlier, and what started at bar 41 still starts at bar 41. The
   message says how far it moved: `the rest of the song moved 8 beats
   earlier`.
5. The window goes inside the subproject, with one empty track, and the
   cursor on that track at its first bar. A kind of subproject adds its
   own tracks in place of the empty track.

The message says what it did, for example `added the subproject Ballad
over bars 33-40 in 6/8, on its own row; inside it now`. `u` takes the
subproject, its row and the meter changes away, and puts the rest of the
song back where it was, in one step.

`:nest.new` writes `name=`, `bars=` and `meter=` too, for example
`:nest.new name=Slow part bars=4 meter=3/4`.

Two more words change what `:nest.new` does with the time of the song:

- `meter=own`, for example `:nest.new Ballad 8 6/8 meter=own`, gives the
  subproject its meter and leaves the tempo map of the song as it is. The
  song keeps its bars over the block, so the two meters run side by side,
  and nothing after the section moves. The message ends with `(the song's
  meter stays)`. Inside the subproject, the ruler, the grid and the
  status line count its meter.
- `tempo=own` gives the subproject a tempo of its own from the start, at
  the tempo of the song where the block starts. The message ends with
  `its own tempo, 120 bpm`, with the tempo it took.
- `kind=` makes a kind of subproject that an extension defines, for
  example `:nest.new Groove 2 kind=drums.pattern`. The kind adds the
  tracks and clips, and it can open a view of its own when the window goes
  inside, such as a step grid. The message names the kind, for example
  `added the subproject Groove (Drum pattern) over bars 3-4`. Without the
  extension, the subproject is a plain one: it plays, and the arrange view
  edits its tracks. See
  [Kinds of subproject](extensions.md#kinds-of-subproject).

| Option | Default | Effect |
| --- | --- | --- |
| `nest_track` | `"track"` | The track that a new subproject starts with: `"track"` for a plain track, as `o` adds, or the name of a kind of track, for example `"vocal"`. |

## Time inside a subproject

A subproject follows the tempo and the meter of the song unless you give
it its own. Its bars are then the bars of the song at the place of its
block, counted from 1, so a subproject over a 6/8 section shows bars of
6/8.

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

### Its own tempo and meter

| Command | Effect |
| --- | --- |
| `:nest.time own` | Give the subproject at the cursor a tempo of its own, the tempo of the song over its first block. The sound doesn't change at first. One undo step. |
| `:nest.time own 90` | The same, at 90 bpm throughout. |
| `:nest.time follow` | Make the subproject follow the tempo of the song again. |
| `:nest.meter 6/8` | Give the subproject a meter of its own, and leave the tempo map of the song as it is. |
| `:nest.meter follow` | Make the subproject count the bars of the song again. |

The subproject at the cursor is the one the window is in, or else the one
of the block at the cursor.

A subproject with its own tempo keeps its seconds when the song's tempo
changes. A ritardando of the song over the block leaves its notes where
they were in time, and each block keeps its start in the song and lasts
as long as the subproject plays at its own tempo, so its length in beats
of the song follows. The devices inside the subproject get its tempo and
its bars, so a delay synced to the tempo follows the subproject.

Inside a subproject with its own tempo, the ruler counts its own bars at
its own tempo, and with `scopebars=both` the row under it shows the
song's bars where they fall. `:tempo` then changes the tempo of the
subproject and not the song's, and the message says so, for example
`90 bpm: the subproject's own tempo`. The status line shows `own tempo`,
and `K` on a block says `own tempo` where it otherwise says `follows the
tempo`.

The tempo lane (`zT`) shows the tempo of the subproject. A tempo change
that you make inside it goes into the tempo of the subproject at its own
beat, and the song's tempo stays as it was. You can make the change with
`:tempo.ramp`, `:tempo.remove`, `:tempo.tap` or `:tempo.move`, on the
lane with the mouse or `grt`, with a tempo flag on the ruler, or in the
curve editor of `paw://tempo`. A signature change (`:timesig`,
`:timesig.remove`, or a signature flag on the ruler) goes into the meter
of the subproject. If the subproject counted the song's meter, it gets a
meter of its own, the meter that it showed, with the change in it.

Inside a subproject that follows the song's tempo, the tempo lane shows
the song's tempo from the start of the block. A change that you make on
the lane goes into the song's tempo at the same place in the song. For
example, in 4/4 with the block at bar 5, a change at bar 3 of the
subproject is a change at bar 7 of the song. The tempo flags and the
signature flags on the ruler, and the curve editor of `paw://tempo`, work
the same way.

A subproject with its own meter and no tempo of its own counts its own
bars from the start of its block, in its meter, while the song keeps its
bars. Inside it, `:timesig`, `:timesig.remove` and the signature flags on
the ruler change its own meter, and a tempo change goes into the song's
tempo at the same place in the song.

## The return row and its blocks

The arrange view draws each block of a subproject on its return row in a
frame, with `⧉` and the name of the subproject, and under the name a small
piano roll of the notes that the subproject plays there. A kind of
subproject puts its letter after `⧉`, for example `⧉D Groove`. The graphical
window draws the same blocks.

| Keys or command | Effect |
| --- | --- |
| `za` on a return row | Show the tracks of the subproject under the row, in the time of the song, or hide them again. On one of those tracks, `za` hides them and puts the cursor on the row. |
| `K` on a block | Describe the subproject, for example `nest Ballad · 6/8 · 8 bars · follows the tempo · 2 tracks · 1 instance · live`. The count of instances is the number of places where the song plays the subproject. A kind of subproject adds its name and its own words after the name, for example `nest Groove (Drum pattern: 16 steps)`. |
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

## One subproject in several places

A copy of a block plays the same subproject, so the song can play one
section in several places. For example, `yic` on the block at bar 9 and
`p` at bar 97 give a second block of the same subproject. An edit inside
the subproject, through either block, changes what both blocks play, and
`K` on either block says `2 instances`.

| Command | Effect |
| --- | --- |
| `:nest.unique` | Make the block at the cursor a subproject of its own, a copy named `Ballad 2` that only this block plays. The other blocks keep the subproject. One undo step. |

The message names the copy and the places of the others, for example
`Ballad 2: the block at bar 97 is a subproject of its own; Ballad still
plays at bar 9`. When the window is inside the subproject through that
block, it goes inside the copy.

## Freeze a block

A frozen block plays a rendered file of what it plays into its return
row, and the devices of the subproject rest while no block plays it live.
The rules are the rules of a frozen track, in
[Frozen tracks](freezing.md#frozen-blocks-of-subprojects).

| Command | Effect |
| --- | --- |
| `:freeze` on a block | Render what the block plays into its row, and play the file from now on. On a stale block, render it again. One undo step. |
| `:freeze tail=4` on a block | Render 4 seconds after the end of the block (default: 2). |
| `:unfreeze` on a block | Play the subproject live again. One undo step. |

`K` on a frozen block ends its first line with `frozen` in place of
`live`, and the next line says if the file is up to date, for example
`frozen, stale: Ballad changed since: clips` after an edit inside the
subproject. While a frozen block is stale, the status line says
`stale: Ballad`.

## Save a view as a subproject

| Keys or command | Effect |
| --- | --- |
| `<Space>zw`, `:scope.write [name]` | Save the view of the window as a subproject, per track. One undo step. `.` then goes to the next view beside it, as `]z` does, and saves that one too. |
| `<Space>zW`, `:scope.write! [name]` | Save the view of the window as a subproject with its own row. One undo step. |

A view is a part of the song that the window shows, for example the
region that `znar` enters (see [Narrowing](narrowing.md)). Both commands
take the clips of the view's tracks in the view's time, cut at its
edges, and move them into a new subproject. The subproject takes the name
that you type, else the name of the view or of its region. A name has no
`/`. A word with a slash, such as `~/lib/bridge`, is a path to a folder,
and `:scope.write` then writes the view as a project of its own there
(see [Write a subproject or a view as a project](#write-a-subproject-or-a-view-as-a-project)).
`:scope.write!` refuses a path.

The subproject keeps the meter of the song over that time as its own,
so the song's bars stay where they are. Inside a subproject with a meter
of its own, a view saves that meter instead: a view of a 6/8 subproject
gives a subproject in 6/8. The markers and regions inside
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

## Write a subproject or a view as a project

| Command | Effect |
| --- | --- |
| `:nest.export <folder>` | Write the subproject at the cursor as a project folder of its own. Inside a subproject, that subproject. |
| `:scope.write <folder>` | Write the view of the window as a project folder of its own. Inside a subproject, the subproject, as `:nest.export` writes it. |

Both commands make a copy, so nothing in the song changes and there is
no undo step. The folder must be new or empty, because paw never writes
over files there. `~/` at the start of the folder is your home folder.
You can open the new project with `:e` and the folder, and it plays
without the song.

`:nest.export` writes the subproject as the song plays it:

- The tracks of the subproject become the tracks of the project, and its
  master track becomes the master, with its devices, fader and lanes.
- A subproject that follows the tempo or the meter of the song gets the
  tempo and the meter of the song over its first block. A subproject with
  its own tempo or meter keeps it.
- Its markers, regions and key become those of the project.
- The subprojects inside it stay subprojects of the new project.

`:scope.write <folder>` writes the view of the window:

- The project gets a copy of each track of the view, with its devices,
  and its clips and lanes in the time of the view, cut at the edges and
  moved to start at beat 0. An audio clip or a looped clip over an edge
  is refused, as for `<Space>zw`.
- The project gets the tempo and the meter of the song over that time,
  the markers and regions that fit in it, and a master track with no
  devices.
- A route to a track outside the view goes. A track that played into
  such a track plays into the master. The message names each route that
  goes, for example `the send of Bass to Verb is left out`.

Both commands copy the sound files that the clips play into `media/` of
the new folder, one copy for each set of equal bytes, and write their
`media.json`. A sound file that is missing stays missing, and the message
says how many. The message names the folder and what it has, for example
`wrote the subproject Ballad to ~/lib/Ballad: 2 tracks, 1 media file; the
song did not change`.

## Bring a project into the song as a subproject

| Keys or command | Effect |
| --- | --- |
| `:import <folder>` | Make a project folder a subproject of the song, with a return row below the track at the cursor and one block from the bar of the cursor. The subproject refers to the folder. |
| `:nest.own` | Make the subproject at the cursor, which refers to a folder, the song's own copy now. Inside a subproject, that subproject. |
| `:e <song>/nests/<name>` | Open the song and go inside its subproject `<name>`. When the song is open already, go inside the subproject. |

`:import` takes a project folder, or its `project.toml`, for example
`:import ~/lib/Ballad`, which `:nest.export` wrote. The subproject plays
at once, and the command with its row and block is one undo step. The
message names the folder and the number of tracks, for example
`imported the subproject Ballad from ~/lib/Ballad at bar 1, on its own
row: 2 tracks; it refers to the folder until you edit it`. The
subproject gets the project's parts in these ways:

- The tracks of the project become the tracks of the subproject, and the
  master track of the project becomes its master. The subprojects inside
  the project come with it.
- Its markers, regions and data come from the project, and so does its
  key when the key is not the song's.
- It keeps the meter of the project as its own. It plays at the tempo of
  the song, and keeps the tempo of the project for `:nest.time own`. When
  the two tempos are not the same, the message says so and gives the
  command, for example `:nest.time own 90`.
- Its length goes to the end of the bar where the last clip, marker or
  region of the project ends.

A subproject that refers to a folder has no copy in the song. paw reads
the folder again each time it opens the song, so a change in the folder
comes into the song. When the folder is not there, the song opens, the
subproject plays nothing, and a message says which folder is missing.

The first edit inside the subproject makes it the song's own copy, with
the subprojects that came with it, in the same undo step as the edit.
paw says so once, for example `the subproject Ballad is now the song's
own copy (was ~/lib/Ballad)`, and the subproject keeps the folder as its
`origin`. To move the block, to change the return row or to play the
subproject is no edit of it. `:nest.own` makes the copy at once, as one
undo step, so `u` makes the subproject refer to the folder again.
`:nest.own` on a subproject that is the song's own already gives an
error.

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
- A subproject with its own tempo writes its tempo into the tempo map of
  the song over the block, and the tempo of the song back after it, so the
  render stays the same. The block then lasts its beats of the
  subproject, and the song after it moves by the difference in beats. The
  message says so, for example `its own tempo, 90 bpm, in the song's map
  over bars 5-8, and 120 bpm back after it`.
- When other blocks play the subproject too, promote works on a copy that
  only this block plays, as `:nest.unique` makes. The other blocks keep
  the subproject, and the message says where it still plays, for example
  `Ballad still plays at bar 97`.
- A subproject with a key of its own, in its `meta.key` (for example
  `"D minor"`), gives that key to the region named after it, when the key
  differs from the key of the song. The region is then a key over its
  time for harmony, as a region with a `key` is, and the message says so.
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

Promote refuses a stem row (`:nest.outputs master` first), and a return
row that holds clips that aren't blocks.
Per track, it refuses a subproject with blocks at two places, and a track
of the subproject that has devices, lanes, or a fader or pan of its own.
