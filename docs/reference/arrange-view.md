# The arrange view

<!-- tags: arrange -->

The arrange view shows the tracks as rows and the time as columns, and it is the first view you see when paw starts. The keys that it shares with the piano roll are in [Motions, operators and modes](grammar.md).

## What the view shows

- A rule between the track headers and the timeline.
- The ruler, with bar numbers and beat ticks. The playback loop shows as a bright band on the ruler and a shade over the lanes while looping is on. With looping off, the band stays on the ruler in dim colors (`RulerLoopOff`), so that you see the range that `gL` brings back.
- A thin amber playhead. Over the body of a clip, the playhead shades its column instead, so the notes or the waveform under it stay in view.
- The track headers. Each has the chips `M` `S` `R` `I` (mute, solo, arm, monitor). If there are enough rows, a header also shows the level and volume and the pan. It can also show the devices, the output (`→ Bus`), the sends (`↗ Reverb -9`) and the input.
- A letter before the name of a track of a kind that an extension defines.
- A muted clip has `⊘` before its name (`x` with `paw.opt.ascii`) and a faint body, as in `⊘ riff`.
- The master track, pinned at the bottom. Its header is like the others, with the levels of both sides in one row, and the timeline beside it shows its volume automation if it has any. `j` on the last track goes to the master, and `/master` finds it. On the master, `+` `-` `grv` change its volume and `a` adds a device to it. It has no clips, and `dd` does not remove it.

The tracks share the rows of the window, and each track gets one to three rows, the most that let every track fit (`paw.opt.track_height`). `Ctrl-=` and `Ctrl--` make the tracks of the window taller or shorter, and `Ctrl-0` fits them to the window again (see [Vertical zoom](#vertical-zoom)). The headers are 26, 22, 18 or 12 columns wide, depending on the width of the screen (`paw.opt.header_width`). The track column and the bar numbers of the ruler are described in [The track column](#the-track-column) and [Relative bars](#relative-bars).

A clip has a name row and a darker body that shows its notes or waveform in the color of its track. Each column of the body shows the notes or the sound of its own stretch of time, from the first column on, so a note on the first beat of a clip fills the first column. A thin line at the left end of the name row marks where the clip starts. The clip under the cursor shows in the full color, and the track of the cursor has a brighter header and a tinted lane.

## Keys

| Keys | Effect |
| --- | --- |
| `x` | Deletes the clip. |
| `D` `C` `Y` | Deletes, changes, copies to the end of the track. |
| `o` `O` | Adds a track below or above. On a track of a group, the new track goes into the group and plays into it. Below the row of an open group, it goes first into that group. |
| `grn` | Renames the track. |
| `Alt-j` `Alt-k` | Moves the track down or up. A count gives the places: `3 Alt-j`. |
| `:track.new` | Adds a track of a kind chosen from a list (a vocal track, a drum track: kinds that extensions define). |
| `:track.add vocal` | Adds a track of the named kind. |
| `M` `s` `r` | Mutes, solos, arms the track. |
| `+` `-`, `Ctrl-a` `Ctrl-x` | Changes the volume of the track. A count first gives the dB. |
| `]` `[` | Changes the pan of the track. |
| `grv` `grp` | Types the volume (dB) or the pan (`L30`, `R25`, `C`, -100 to 100). |
| `grt` | Types the tempo. |
| `I` | Selects the next input (audio, MIDI port and channel). |
| `Alt-i` | Monitors the input. |
| `R` | Records from the cursor, or stops the recording. While the song plays, the recording starts at the playhead. |
| `&` `S` `J` `~` | Repeats, splits, joins, mutes the clip. `J` joins the clip with the MIDI clips over it (a take over it), or else with the next clip. A count before `&` gives the copies: `4&`. |
| `grc` | Renames the clip. |
| `H` `L` | Moves the clip. |
| `Alt-h` `Alt-l` | Shortens and lengthens the clip. |
| `vic` `Ctrl-a` | Transposes the clip. On a selection, `Ctrl-a` `Ctrl-x` `+` `-` move only the notes that start in the selection, so `vib12Ctrl-a` moves one bar up an octave and leaves the rest of the clip. A count gives the semitones. The message says how many notes moved, how far and in which clips, for example `moved 4 notes up 12 semitones in Keys`. With the [classic keys](key-rule.md#the-classic-keys), `Ctrl-a` with no selection transposes the whole clip at the cursor. |
| `gw` `gW` | Puts a warp marker on the audio clip at the cursor. Removes the warp marker nearest to the cursor. |
| `<Space>cl` | Puts a linked copy after the MIDI clip, as `&` puts a plain copy. See [Linked clips](#linked-clips). |
| `<Space>cu` | Takes the clip out of its link, so that it is a plain copy again. |
| `<Space>cf`, `\ff` | Types the fade in and fade out of the audio clip, in beats (`1 2`, or one length for both). |
| `\fi` `\fo` | Fades the audio clip in from its start to the cursor. Fades it out from the cursor to its end. A count gives the beats: `2\fo`. |
| `\fx` | Crossfades the audio clip into the next clip, over a grid step. A count gives the beats. |
| `grC` | Chooses the color of the track from the colors of the theme. |
| `Enter` | Edits the notes of the clip in the piano roll. |
| `i` | Starts insert mode. Then `m` inserts a MIDI clip at the cursor, `a` an automation point, `r` a region, `'` a marker, `f` a file. `Enter` opens what you inserted. `i` `Enter` enters notes at the cursor. See [Insert mode](insert-mode.md). |
| `K` | Describes what is under the cursor in a float under the cursor, at most 72 columns wide and half the window high. The next key closes the float and does what it always does. `K` again moves the keys into the float, where `j` and `k` scroll and `q` or `Esc` close it. `:info` shows all of it in a page. A kind of track also says what it is. |
| `a` | Adds a device. The list shows instruments first on a track with no instrument, else effects first. |
| `ge` | Shows the window of the plugin. |
| `<Space>dd` `<Space>mm` `<Space>vp` `<Space>vs` | Shows the device panel, the mixer, the piano roll, the session view (with the clip launcher extension). |
| `A` | Adds a volume automation point at the cursor. |
| `<Space>at` `<Space>ax` | Turns the lane off or on (read or bypass). Clears the lane. |
| `<Space>al` | Chooses what to automate (volume, pan, a device parameter), and shows its lane. |
| `<Space>aa` `<Space>aA` | Shows or hides the lanes of the track as rows. Shows the lanes of every track. |
| `<Space>am` | Sets the automation mode of the track: read, touch, latch, write, off, in turn. |
| `<Space><Space>` | Plays from the cursor, or stops. The cursor does not move, and the playhead stays where the song stopped. A playhead that you put with `gs`, `gp` or the ruler is where play starts, until the cursor moves or you open another project. `paw.opt.play_from = "playhead"` plays from the playhead. |
| `gs` `gp` | Moves the playhead to the start, to the cursor. |
| `gL` `gm` | Turns the playback loop on or off, and keeps its range. Turns the metronome on or off. |
| `gl` | Sets the playback loop to the selection or to what the motion covers, and turns looping on. The message says the bars, for example `loop: bars 5 to 8, on`. |
| `Shift-Enter` | Plays from the playhead. With `play_from = "playhead"`, it plays from the cursor. |
| `gM` | Counts a bar in before a recording, or not. |
| `gI` | Turns punch recording on or off. On a selection, punches over it. |
| `:preroll 2` | Plays two bars (`3s`: seconds) before the punch in, when you record from a stop. |
| `:click level=-6` | Sets the level, the accent (`accent=off`) and the output (`output=3`) of the metronome. |
| `zt` | Shows or hides the take lanes of the track. |
| `zT` | Shows or hides the tempo lane under the ruler. |
| `:tempo.move 9` | Moves the tempo change at the cursor to bar 9. |
| `]t` `[t` | Selects the next or the previous take of the clip. |
| `zi` `zo` | Zooms in and out. |
| `Ctrl-=` `Ctrl--` `Ctrl-0`, `z+` `z-` `z=` | Taller rows, shorter rows, rows that fit the window again. See [Vertical zoom](#vertical-zoom). |
| `zs` `zz` `ze` | Puts the cursor at the left, in the middle or at the right of the timeline. |
| `zh` `zl` | Scrolls a bar left or right. |
| `[g` `]g` | Makes the grid finer or coarser. |
| `zn{motion}` `znn` `zw` `zW` `]z` `[z` | Enter a scope in this window (`znag` the group, `znar` the region, `znn` the innermost at the cursor). Go up one level, up to the song. Go to the scope beside. See [Scopes](narrowing.md). |
| `<Space>tv` | Makes a VCA over the selected tracks. |
| `<Space>ta` | Puts the selected tracks under a VCA. |
| `<Space>tr` | Removes the selected tracks from their VCAs. |
| `<Space>tx` | Removes the VCA at the cursor. |
| `<Space>tl` | Links the faders of a group. |
| `Tab`, `Ctrl-w w` | Goes to the next window. |
| `Ctrl-w <` `Ctrl-w >` | With the arrange view the only window: narrower or wider track headers. |
| `ZZ` `ZQ` | Saves and quits. Quits. |

For the keys of windows, see [Windows, buffers and tabs](windows.md).

## Vertical zoom

`Ctrl-=` (or `Ctrl-+`) makes the rows of the arrange view a row taller, `Ctrl--` makes them a row shorter, and `Ctrl-0` gives them the height of `paw.opt.track_height` again, which is "auto" and fits the tracks to the window unless your configuration sets a number. Most terminals don't send `Ctrl` with `=`, `-` or `0` to a program, so `z+`, `z-` and `z=` do the same in every terminal and in the graphical window.

| Keys | Effect |
| --- | --- |
| `Ctrl-=` `z+` | Makes every track a row taller, up to 12 rows. On a selection of tracks (`Vj`), or with a count (`3z+`), only those tracks. With the cursor on an automation lane, the lanes get a row more, up to 8. |
| `Ctrl--` `z-` | Makes the rows shorter: a track down to 1 row, a lane down to 2. |
| `Ctrl-0` `z=` | Gives every track the height of the option again, and the lanes 2 rows. On a selection or with a count, those tracks get the height of the others. |
| `Alt` and the wheel | The same as `z+` and `z-`. `Ctrl` and the wheel over the track headers does the same, and over the timeline it zooms in time. |

The message line says what changed, for example `track height 5`. The zoom belongs to the window, as its folds do. A split starts with the zoom of the window that it comes from, a change of zoom is not an undo step, and the project keeps the zoom of each window in its `screen.json`. The piano roll has its own vertical zoom (see [The piano roll](piano-roll.md#vertical-zoom)).

## The track column

In paw a track works like a line of text, so `5j` goes down five tracks, `5G` goes to track 5, and `dd` deletes a track. For this reason the left edge of the track headers has a column that corresponds to the number column and the `statuscolumn` of Neovim. The numbers are not part of the header width (`paw.opt.header_width`), so the timeline is narrower by their width. The signs and the tree of groups come and go with the project, so they take their columns from the track headers, and the timeline starts in the same column with and without groups. In a narrow window, where the headers are 12 columns wide, they take their columns from the timeline. The column has three parts, from the left:

- `number`: the number of each track. With `:set relativenumber`
  (`:set rnu`), each track shows how many `j` or `k` go to it. The track
  of the cursor shows its own number, or `0` when `:set nonumber`. The
  master has no number.
- `signs`: one character for each track that has one. The diagnostics of language servers show here, and the sign gives the worst diagnostic of the track, its devices and its clips.
- `fold`: the groups as a tree. An open group has `▾` on its row and a line down its members, with `╰` on its last member. A folded group has `▸`, and its name tells how many tracks it holds (`Strings +3`). Each level of groups inside groups takes one more column. A fold of tracks (`zf`) has `▸` on its row too. A click on `▾` or `▸` folds or opens the group or the fold, like `za`.

```text
 2   ▌ Drums
 1 ▾ ▌ Strings
 3 │ █ Violins
 1 │▾▌ Low
 2 ││▌ Cellos
 3 ╰╰▌ Violas
 4   ▌ Bass
```

The numbers count the way the motions count. A folded group is one row, like a fold in Neovim, so `4j` goes to the track that shows `4`. The automation lanes of a track can show as rows (`<Space>aa`), and in normal mode `j` and `k` then go onto the lane rows, which have relative numbers too. In visual mode and after an operator, only tracks count.

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.number` (`nu`) | `true` | Shows the number of each track. |
| `paw.opt.relativenumber` (`rnu`) | `false` | Shows how many `j` or `k` go to each track. |
| `paw.opt.trackcolumn` | `number,signs,fold` | The parts of the column that show. An extension that adds a part puts its name here. |

An extension adds its own parts and signs with `paw.trackcolumn`, which [The track column and the bar labels](trackcolumn.md) describes. The highlight groups are `TrackNr`, `TrackNrCursor`, `TrackFold`, `TrackSign`,
`TrackColumn` and `TrackColumnCursor`.

## Relative bars

`:set relativebar` (`:set rbar`) shows on the ruler how many `W` or `B` go to each bar, in the same way that `relativenumber` does for tracks. The bar of the cursor keeps its own number, in the accent color, so `4W` goes to the bar that shows `4`, and `4B` goes to the bar behind it that shows `4`. From inside a bar, the first `B` goes to the start of that bar, so the bars behind it count from 2. `17|` and `:17` still go to bar 17.

The option is separate from `relativenumber`, because commands such as `17|` and `:tempo 96 at 17` take the number of a bar. So you can keep the bar numbers on the ruler while you count tracks.

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.relativebar` (`rbar`) | `false` | Shows how many `W` or `B` go to each bar. |
| `paw.opt.barlabel` | `number` | The parts of the label of each bar. An extension that adds a part puts its name here. |

The highlight groups are `RulerBarCursor` and `RulerBarRelative`.

## Audio waveforms

An audio clip draws its sound under its name. Each cell column shows the lowest to the highest sample of its part of the clip, around the middle of the rows, with eighth blocks. A block that grows from the top shows in reverse video, and a clip of three rows has about twenty levels in each direction.

- The scale is linear: a kick shows higher than a hat. `paw.opt.wave_scale = "db"` also shows quiet sound, but the hits are less clear.
- A column that reaches full scale after the gain of the clip shows in red.
- `zi` and `zo` draw the waveform again from the peaks that the kernel keeps, not from the file.

Waveforms are cells, also in a terminal that shows pictures. A terminal that shows images also gets a waveform in pixels, which [Pictures in the terminal](pictures.md) describes.

## Automation lanes as rows

`<Space>aa` shows the automation lanes of a track as rows under it, two rows for each lane, and `<Space>aa` again hides them. (`za`, `zM` and `zR` fold groups and tracks, not lanes.) `<Space>al` chooses a lane to make or show, which can be the volume, the pan, or a parameter of a device of the track.

A lane header gives what the lane moves, its value at the cursor, and if the lane is read or bypassed. The curve and its points (`◆`) show along the timeline, and `j` and `k` go onto lane rows in the same way as onto tracks.

When the lanes are closed, the track of the cursor draws its volume curve in the empty parts of its row, and not over clips. It draws the curve in sextants (`paw.opt.curve_glyphs`). If your terminal font has no sextants, `:checkhealth terminal` shows it, and `:set curve_glyphs=braille` draws the curves in braille dots. The other tracks show an `A` in their header and draw no curve, so that the notes stay clear.

| Keys | On a lane row |
| --- | --- |
| `h` `l` and the other motions | Move in time. |
| `w` `b` | Go to the next and the previous point. |
| `A` | Adds a point at the cursor, at the value of the curve. |
| `+` `-` | Raise and lower the point under the cursor: a dB, 5% of pan, or 1/100 of the range of a parameter. `Ctrl-a` `Ctrl-x` by the count. |
| `c` | Types the value of the point. |
| `x` | Removes the point. |
| `gc`, `<Space>at` | Bypasses the lane. |
| `<Space>ax` | Clears the lane. |
| `>` `<` | Move points in time, with a motion or on a selection. |
| `gC`, `Enter` | Opens the curve of the lane in the [curve editor](curve-editor.md). |

In a selection (`v`) on a lane row, `x` and `d` remove the points in it.
`H` `L` move them a grid step, and `+` `-` raise or lower them.

## The tempo lane

`zT` (or `:tempo.lane`) puts two rows under the ruler, and they show the tempo map as a curve. The curve is level where a tempo holds and slopes where it ramps (`↗`), and `◆` marks a change that holds. The header gives the tempo at the cursor. Inside a subproject with a tempo of its own, the lane shows that tempo, and a change that you make on the lane goes into that tempo. Inside a subproject that follows the song's tempo, a change goes into the song's tempo at the same place in the song.

| Command | Effect |
| --- | --- |
| `:tempo 96 at 17` | Adds a tempo change at bar 17. `here` in place of `at 17` adds it at the cursor. |
| `:tempo.ramp` | Makes the change before the cursor ramp to the next change. |
| `:tempo.move 9` | Moves the change to bar 9. |
| `:tempo.remove` | Removes the change. |

Each command is one undo step. You can also draw on the lane with the mouse, as [The mouse](mouse.md) describes.

## Linked clips

The clips of a link share their notes and their controller moves, so an edit of the notes of one clip changes every clip of the link, as one undo step. Each clip keeps its own start, length, loop and mute.

- `<Space>cl` (`:clip.link`) puts a linked copy after the clip under the cursor, and moves the cursor to it. A clip that has no link yet starts one with the name of the clip, for example `riff`. The message says the link and its number of clips.
- `<Space>cu` (`:clip.unlink`) takes the clip under the cursor out of its link. The clip keeps its notes, and later edits of it change only that clip.
- `&`, `y` and `p` make plain copies, also of a linked clip.
- `S` on a linked clip takes it out of its link, then splits it, so the other clips of the link keep their notes.
- The arrange view shows `≡` after the name of a linked clip (`=` with `paw.opt.ascii`), as in `riff ≡`.
- A MIDI clip with controller moves shows a small curve on its name row, after its name. The curve is the controller that moves most often, one eighth block for each column, and it starts at its first move. So a linked copy shows the same curve as the clip that it shares the moves with.
- `K` on a linked clip says the link and its number of clips, for example `linked: riff, 3 clips`.
- The notes of a link are in one file of the project folder, `linked/riff.midi2`. See [Project files](project-files.md#the-project-folder).

### Overrides of a clip

A MIDI clip can play its notes higher or lower, or louder or softer, without a change of its notes. Each clip of a link has its own overrides, so one copy of a riff can play it a third higher while all the copies keep one set of notes.

- `:clip.override transpose=3 velocity=-10` sets the overrides of the clip under the cursor, as one undo step. `transpose` is in semitones, and `velocity` is added to the velocity of each note, which stays in 1 to 127. Each is a whole number from -127 to 127, and you can give one of them alone.
- `:clip.override clear` removes both overrides, and `:clip.override` alone says them.
- The overrides change what plays: the sound, `:export` to a sound file or a MIDI file, and the chord names. The notes of the clip stay the same.
- A note that the transpose takes below 0 or above 127 does not play.
- The label of the clip shows the overrides after its name, as in `riff ≡ +3 v-10`, and `K` says them, for example `plays with transpose +3, velocity -10`.
- The piano roll shows the notes of the clip at the pitches they play. See [The piano roll](piano-roll.md#what-the-view-shows).
- `&`, `y`, `p` and `S` keep the overrides in the copy and in each half. `J` keeps the sound of the joined clips, because it moves the notes of a clip with other overrides than the first clip by the difference.
- The overrides are in the entry of the clip in `track.json`, as `"overrides": { "transpose": 3, "velocity": -10 }`.

## Take lanes

`zt` shows the takes of a track as lanes under its clips. Each lane is as tall as an automation lane that shows as a row: the name of the take on its first row, and the waveform or the notes of the take under it, at the same time as the clip. With the mouse you can do three things:

- A drag across lane k marks the cells from the press to the release. At the release, take k plays over that time. The clips are cut at its ends on the grid (Shift: off the grid). The pieces that then play the same take are joined. It is one undo step.
- A click without a drag (shorter than a grid step) gives the piece under it take k.
- A click on the label of a lane (`↳ take 2`) makes that take play everywhere the track has it.

The release can be anywhere on the screen, because a drag belongs to the view where it started. `:take 2` over a selection does the same from the keyboard.
