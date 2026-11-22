# The arrange view

<!-- tags: arrange -->

The arrange view shows the tracks as rows and the time as columns, and it is the first view you see when paw starts. The keys that it shares with the piano roll are in [Motions, operators and modes](grammar.md).

## What the view shows

- A rule between the track headers and the timeline.
- The ruler, with bar numbers and beat ticks. The loop shows as a band on the ruler and a shade over the lanes.
- A thin amber playhead.
- The track headers. Each has the chips `M` `S` `R` `I` (mute, solo, arm, monitor). If there are enough rows, a header also shows the level and volume and the pan. It can also show the devices, the output (`→ Bus`), the sends (`↗ Reverb -9`) and the input.
- A letter before the name of a track of a kind that an extension defines.
- The master track, pinned at the bottom. Its header is like the others, with the levels of both sides in one row, and the timeline beside it shows its volume automation if it has any. `j` on the last track goes to the master, and `/master` finds it. On the master, `+` `-` `grv` change its volume and `a` adds a device to it. It has no clips, and `dd` does not remove it.

The tracks share the rows of the window, and each track gets three to four rows (`paw.opt.track_height`). The headers are 26, 22, 18 or 12 columns wide, depending on the width of the screen (`paw.opt.header_width`). The track column and the bar numbers of the ruler are described in [The track column](#the-track-column) and [Relative bars](#relative-bars).

A clip has a name row and a darker body that shows its notes or waveform in the color of its track. The clip under the cursor shows in the full color, and the track of the cursor has a brighter header and a tinted lane.

## Keys

| Keys | Effect |
| --- | --- |
| `x` | Deletes the clip. |
| `D` `C` `Y` | Deletes, changes, copies to the end of the track. |
| `o` `O` | Adds a track below or above. |
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
| `vic` `Ctrl-a` | Transposes the clip. On a selection, `Ctrl-a` `Ctrl-x` change the pitch of the clips. |
| `gw` `gW` | Puts a warp marker on the audio clip at the cursor. Removes the warp marker nearest to the cursor. |
| `<Space>cf`, `\ff` | Types the fade in and fade out of the audio clip, in beats (`1 2`, or one length for both). |
| `\fi` `\fo` | Fades the audio clip in from its start to the cursor. Fades it out from the cursor to its end. A count gives the beats: `2\fo`. |
| `\fx` | Crossfades the audio clip into the next clip, over a grid step. A count gives the beats. |
| `grC` | Chooses the color of the track from the colors of the theme. |
| `Enter` | Edits the notes of the clip in the piano roll. |
| `i` | Starts insert mode. Then `m` inserts a MIDI clip at the cursor, `a` an automation point, `r` a region, `'` a marker, `f` a file. `Enter` opens what you inserted. `i` `Enter` enters notes at the cursor. See [Insert mode](insert-mode.md). |
| `K` | Describes what is under the cursor. A kind of track also says what it is. |
| `a` | Adds a device. The list shows instruments first on a track with no instrument, else effects first. |
| `ge` | Shows the window of the plugin. |
| `<Space>dd` `<Space>mm` `<Space>vp` `<Space>vs` | Shows the device panel, the mixer, the piano roll, the session view (with the clip launcher extension). |
| `A` | Adds a volume automation point at the cursor. |
| `<Space>at` `<Space>ax` | Turns the lane off or on (read or bypass). Clears the lane. |
| `<Space>al` | Chooses what to automate (volume, pan, a device parameter), and shows its lane. |
| `<Space>aa` `<Space>aA` | Shows or hides the lanes of the track as rows. Shows the lanes of every track. |
| `<Space>am` | Sets the automation mode of the track: read, touch, latch, write, off, in turn. |
| `<Space><Space>` | Plays from the cursor, or stops. The cursor does not move, and the playhead stays where the song stopped. A playhead that you put with `gs`, `gp` or the ruler is where play starts, until the cursor moves. `paw.opt.play_from = "playhead"` plays from the playhead. |
| `gs` `gp` | Moves the playhead to the start, to the cursor. |
| `gL` `gm` | Turns the loop on or off. Turns the metronome on or off. |
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
| `zz` `zh` `zl` | Puts the cursor in the center. Scrolls left and right. |
| `[g` `]g` | Makes the grid finer or coarser. |
| `zn` `zw` | Narrows to the group at the cursor, in a tab of its own. Widens again. |
| `<Space>tv` | Makes a VCA over the selected tracks. |
| `<Space>ta` | Puts the selected tracks under a VCA. |
| `<Space>tr` | Removes the selected tracks from their VCAs. |
| `<Space>tx` | Removes the VCA at the cursor. |
| `<Space>tl` | Links the faders of a group. |
| `Tab`, `Ctrl-w w` | Goes to the next window. |
| `Ctrl-w +` `Ctrl-w -` | With the arrange view the only window: taller or shorter tracks. |
| `Ctrl-w =` | With the arrange view the only window: the height of the tracks is automatic again. |
| `Ctrl-w <` `Ctrl-w >` | With the arrange view the only window: narrower or wider track headers. |
| `ZZ` `ZQ` | Saves and quits. Quits. |

For the keys of windows, see [Windows, buffers and tabs](windows.md).

## The track column

In paw a track works like a line of text, so `5j` goes down five tracks, `5G` goes to track 5, and `dd` deletes a track. For this reason the left edge of the track headers has a column that corresponds to the number column and the `statuscolumn` of Neovim. The column is not part of the header width (`paw.opt.header_width`), so the headers keep their width and the timeline is narrower by the width of the column. The column has three parts, from the left:

- `number`: the number of each track. With `:set relativenumber`
  (`:set rnu`), each track shows how many `j` or `k` go to it. The track
  of the cursor shows its own number, or `0` when `:set nonumber`. The
  master has no number.
- `signs`: one character for each track that has one. The diagnostics of language servers show here, and the sign gives the worst diagnostic of the track, its devices and its clips.
- `fold`: the groups as a tree. An open group has `▾` on its row and a line down its members, with `╰` on its last member. A folded group has `▸`, and its name tells how many tracks it holds (`Strings +3`). Each level of groups inside groups takes one more column. A click on `▾` or `▸` folds or opens the group, like `za`.

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

`<Space>aa` shows the automation lanes of a track as rows under it, two rows for each lane, and `<Space>aa` again hides them. (`za`, `zM` and `zR` fold groups, not lanes.) `<Space>al` chooses a lane to make or show, which can be the volume, the pan, or a parameter of a device of the track.

A lane header gives what the lane moves, its value at the cursor, and if the lane is read or bypassed. The curve and its points (`◆`) show along the timeline, and `j` and `k` go onto lane rows in the same way as onto tracks.

When the lanes are closed, the track of the cursor draws its volume curve in the empty parts of its row, and not over clips. It draws the curve in sextants (`paw.opt.curve_glyphs`). The other tracks show an `A` in their header and draw no curve, so that the notes stay clear.

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

`zT` (or `:tempo.lane`) puts two rows under the ruler, and they show the tempo map as a curve. The curve is level where a tempo holds and slopes where it ramps (`↗`), and `◆` marks a change that holds. The header gives the tempo at the cursor.

| Command | Effect |
| --- | --- |
| `:tempo 96 at 17` | Adds a tempo change at bar 17. `here` in place of `at 17` adds it at the cursor. |
| `:tempo.ramp` | Makes the change before the cursor ramp to the next change. |
| `:tempo.move 9` | Moves the change to bar 9. |
| `:tempo.remove` | Removes the change. |

Each command is one undo step. You can also draw on the lane with the mouse, as [The mouse](mouse.md) describes.

## Take lanes

`zt` shows the takes of a track as lanes under its clips, with one row for each take. With the mouse you can do three things:

- A drag across lane k marks the cells from the press to the release. At the release, take k plays over that time. The clips are cut at its ends on the grid (Shift: off the grid). The pieces that then play the same take are joined. It is one undo step.
- A click without a drag (shorter than a grid step) gives the piece under it take k.
- A click on the label of a lane (`↳ take 2`) makes that take play everywhere the track has it.

The release can be anywhere on the screen, because a drag belongs to the view where it started. `:take 2` over a selection does the same from the keyboard.
