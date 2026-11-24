# Time motions: positions, the grid and moves (design)

Status: accepted by the owner 2026-11-23 (Q1-Q9 as recommended). ADR 0036 accepted.
time axis) and on the axis of TASK-325.

## 0. The problem

The owner, 2026-11-23, after recording sessions:

1. "there are still problems with alignment between takes, the
   timeline ruler etc."
2. "the cursor can get out of sync with the ruler, if I move it back to
   1.1.1 and then move it, it recovers its alignment"
3. "if a clip stops recording off-the-grid and I do `w` and `b` to
   move, then the cursor becomes offset since the clip might finish
   off-the-grid, which then can build up"
4. "make a consistent good design for how to mix continuous time and
   discrete time movements properly in our architecture"

### 0.1 The case, reproduced

The probe ran on the stepped engine through the test runner (a scratch
fixture, `PAW_TEST_FIXTURE`), at 100 columns and zoom 2 (two columns a
beat). Grid 1 beat. `#` marks the cells that the cursor lights.

```text
take 1: start 0, end 5.312 (the stop key fell between two beats)
keys       cursor beat   what the user sees
w          5.312         the end of take 1 (exact, correct)
l          6.312         one grid step later: the offset stays
l          7.312         the offset stays
b          0             the start of take 1
e          5.312
h          4.312
3l         7.312
R (3.2 b)  take 2: start 7.312, end 10.512   the offset goes into the data
```

Screen after `w` (before):

```text
 Song 2.2               │1 ▏ ▏ ▏ 2 ▏▼▏ ▏ 3 ▏ ▏ ▏ 4 ▏ ▏ ▏▕5 ▏ ▏ ▏ 6 ▏ ▏ ▏ 7
 1 █ Guitar        MSRI │▏take 1    ▏    ▏       ▏       ▏       ▏       ▏
   █in ━━━━━━━━━╸── 0.0 │▂▂▂▂▂▂▂▂▂▂▂##   ▏       ▏       ▏       ▏       ▏
```

The cursor block (`##`, columns 11 and 12) covers the half of the cell
of beat 5 and the half of the cell of beat 6. It is on no ruler cell.
After `l` it is at columns 13 and 14, again over two cells.

### 0.2 The causes in the code (base 7e5a2603)

| Cause | Where |
| --- | --- |
| `h` `l` add `count * grid` to the position. An offset stays for ever. | `defaults/cursor.lua` `cursor.right` `cursor.left`; the roll `move` in `defaults/keys.lua`; utau, notation `move` |
| Positions are floats in beats. Steps of 1/3 or 1/5 add a float error (999 steps of 1/3 give 332.99999999999852). A `floor` then gives the column before. | `cursor.tl` `set_beat`; every `+ n * grid` |
| The cursor block is `floor(grid * zoom)` columns from `col(beat)`. It does not end at the next grid line. | `views/arrange.tl` lines 1203, 1311, 1860, 2303 |
| The piano roll's grid starts at the start of the active clip, not at the bars of the song. A clip that starts off the grid moves the whole grid of the roll. | `roll_clips.tl` ("Beats here are the roll's: from the start of the active clip"); `pianoroll_mouse.tl` `on_grid` |
| About 60 places do their own grid arithmetic: `util.round(x, grid)`, `math.floor(x / grid + 1e-6)`, `grid / 2` as a reach, `max(grid, ...)` as the least length. Each has its own epsilon. | `edit.tl`, `controls.lua`, `curves.tl`, `tempolane.tl`, `defaults/clips.lua`, `defaults/lanes.lua`, `markers.tl`, `frontend/act/*.tl`, `views/*_mouse.tl`, `stretch.lua`, drums `edit.lua`, notation, utau |
| The grid is a step in beats. It knows no bar, no meter change, no triplet in the arrange view, no swing, no fold. | `options.tl` `grid`, `note_grid` |
| `cursor.to_playhead` rounds to the nearest grid step. The other jumps are exact. | `defaults/cursor.lua` |

## 1. Research: what other editors do

| Tool | What it does | Copy | Do not copy |
| --- | --- | --- | --- |
| Vim | Motions and text objects. A motion is exclusive or inclusive. `w` `b` `e` go to word edges, not by a count of characters. `l` over a Tab goes over the whole Tab, and the cursor never rests inside it. `curswant` keeps the wanted column over `j` `k` when a short line clamps it. | Motions to edges, not by fixed amounts. Exclusive ranges for a continuous axis. `curswant` for clamps. An off-grid offset is like the inside of a Tab: one key goes over it. | Inclusive ranges of character cells. Time has points, not cells. |
| REAPER | Edit cursor and time selection are points in seconds. Actions "move cursor to next grid division" and "move cursor right by grid" are separate. Snap is a toggle. "Snap relative to grid" keeps the offset of an item that starts off the grid when the user moves it. Each item has a snap offset. | Grid lines as stops for the cursor. Relative snap for moves of whole items. A toggle of snap for the pointer. | Two actions that look the same and do different things. A snap offset in each item. |
| Ableton Live | Adaptive grid (follows the zoom) or fixed grid. Cmd-1 and Cmd-2 make it finer or wider, Cmd-3 triplets, Cmd-4 snap. Arrow keys move clips by the grid. A dragged note moves free up to the first grid line, then snaps. | Grid narrow and wide on keys (`[g` `]g`), triplets, adaptive grid as an option. | The "free up to the first line" magnet: it is not clear from the screen. |
| Bitwig | Adaptive and fixed grid. Snap to the grid and to objects. A relative snap option. | Same as Live. Snap to objects is our `w` `b` `e`. | |
| Logic Pro | Snap is relative by default: a region keeps its offset from the grid when it moves. "Snap Regions to Absolute Value" turns this off. | Relative moves of whole things as the default. | A menu option for the absolute case. We have `=` (quantize) for it. |
| Cubase | Snap types: Grid, Grid Relative, Events, Magnetic Cursor, Shuffle. Users report confusion between them. | Grid Relative for moves of whole things. | Many snap types. One rule for each class of edit is clearer. |
| Renoise (tracker) | The cursor is always on a row. A note that is off a row is on the row before, with a delay value in its own column. The edit step tells how far the cursor goes after an entry. | Cell views (drum grid, score, tracker) keep the cursor on cells. An off-grid event shows in its cell with a mark of its offset. | A delay column as data. MIDI stays the truth. |

Sources:

- Vim, `:help exclusive` and `:help curswant`.
- The REAPER blog, "what does snap relative to grid mean" (2014), and
  Sound On Sound on the snap offsets of REAPER.
- Apple, the Logic Pro user guide, "Snap items to the grid".
- Steinberg, the Cubase manual, "Snap Types".
- The Ableton Live 12 manual, "Arrangement View" and the chapter on MIDI.
- The Renoise user manual, the pattern editor.

## 2. The model of positions

### 2.1 The unit

- A position on the axis is an integer count of **ticks**. A tick is
  1/61440 of a beat (a quarter note). This is `TPQ` of the clip files
  (`clipfile.rs`): 2^12 x 3 x 5. Each grid of 1/1 to 1/4096, of
  triplets and of quintuplets is an integer count of ticks.
- At 120 BPM a tick is 8.1 microseconds. At 48 kHz a sample is 20.8
  microseconds. A tick is smaller than a sample at each tempo over
  47 BPM.
- In Lua and Teal a tick is an `integer` (a float with no fraction).
  LuaJIT keeps integers exact up to 2^53, which is 1.4e11 beats.
- The API keeps beats (`paw.cursor.beat`, `clip.start`) for now. The
  motion layer converts once at the boundary: `tick = floor(beat *
  TPQ + 0.5)`, `beat = tick / TPQ`. All arithmetic, compares and
  sorts in the motion layer use ticks. No epsilon is necessary.
- A grid line that is not an integer count of ticks (septuplets, a
  frame grid, a seconds grid) is rounded to the nearest tick. Each
  line is computed from the start of its bar or from zero seconds,
  never by addition of steps. So an error does not build up.

### 2.2 Musical time and absolute time

- The axis is musical: ticks. Bars, beats, grid lines, the cursor, the
  selection, marks, markers and MIDI are in ticks.
- A thing with the time base `time` (an audio clip with
  `Timebase::Time`, a video clip, a seconds lane) keeps its position in
  seconds. Its tick is computed from the tempo map on each read and is
  never written back. After a tempo change it can be off the grid. That
  is correct: it keeps its time.
- Content inside a clip has its own atom: a sample of the source file
  for audio, a frame for video, a tick for MIDI and curves. An edit of
  content rounds to the atom of the content (rule 12 of the rules below).

### 2.3 The grid

The grid is a function of the window's grid setting, the meter map, the
swing, the folds and the zoom. It gives a sorted list of lines in
ticks. A **cell** is the span from a line to the next line.

```text
grid setting  := note value [t] | "bar" | "auto" | "frame" | seconds
note value    := 1/1 1/2 1/4 1/8 1/16 1/32 1/64   ("t": triplet, 2/3 of it)
seconds       := 1s 500ms 100ms ...
swing         := 50% (none) to 75%, on every second line
```

| Input | Effect on the lines |
| --- | --- |
| Note value | A line each `step` ticks from the start of each bar. |
| Meter and meter changes | Lines start again at each bar line. A bar that is not a multiple of the step (7/8 with a 1/4 grid) has a short last cell. A bar line is always a line. |
| Triplets (`1/8t`) | The step is 2/3 of the note value. It is an integer count of ticks. |
| Swing | Each second line of a bar moves later by `(swing - 50%) * 2 * step`. The same function as `paw.notes.snap`. |
| `bar` | Only the bar lines. |
| `auto` | The note value is the finest power of two whose cell is two columns wide or more at the zoom. The setting of triplets stays. The grid then follows the zoom. Positions do not change. |
| `frame` | A line at each frame of the project's frame rate (a rational number: 30000/1001), converted through the tempo map. |
| Seconds | A line at each multiple of the period from zero seconds, converted through the tempo map. |
| Tempo changes | No effect on musical lines. They move the ticks of frame lines and seconds lines. |
| Time folds | Lines inside a closed fold are not stops. The start and the end of the fold are stops: a closed fold is one cell, as `paw.cursor.over` does today. |
| Scope bounds | The start and the end of the scope are stops. |

Each window has one grid. Each row of the window (ruler, clip
rows, take rows, lane rows of every kind) draws the same lines through
the axis (ADR 0035). A lane does not have a second grid. The two options
`grid` (time views) and `note_grid` (note editors) stay. Their value
becomes a grid setting. A number stays valid as a step in beats.

### 2.4 How a position relates to the grid

- A position is **on the grid** when it is equal to a line, in ticks.
- Else it is **off the grid** by `pos - floor_line(pos)` ticks.
- The **cell of the cursor** is the span from the cursor to the next
  line. On the grid, that is a whole cell. Off the grid, it is the rest
  of the cell.

## 3. The rules

One rule for each class. The same rule applies in the arrange view, the
piano roll, the score, the drum grid, the vocal editor and on every lane
kind. The examples use the owner's case: take 1 from 0 to 5.312, grid 1
beat, cursor at 5.312 after `w`.

| # | Class | Keys and actions | Rule | Example |
| --- | --- | --- | --- | --- |
| 1 | Grid motions | `h` `l`, arrows, with counts; `W` `B` (the bar grid); `\|` N | Go to the next line or the line before, in ticks. From off the grid, the first step goes to the adjacent line in that direction. A count repeats the step. | `l` 5.312 → 6. `h` 5.312 → 5. `3l` 5.312 → 8. |
| 2 | Object motions | `w` `b` `e`, `0` `^` `$`, `]c` `[c`, `]'` `['`, `]t` `[t`, `n` `N`, `` `a ``, `'a`, `` `. ``, the pickers, `:goto` | Go to the exact edge or position of the thing. It can be off the grid. | `w` from 0 → 5.312 (the end of take 1). |
| 3 | Row motions | `j` `k`, `gg` `G`, `Ctrl-d` `Ctrl-u`, `Tab` in the roll | Keep the tick. When a bound clamps the position (a scope, the span of the roll's clips, a fold), keep the wanted tick (`want`, as Vim's `curswant`). The next row motion uses `want` again. Each time motion sets `want` to the new tick. | `j` from 5.312 to a track below: 5.312. |
| 4 | Operators | `d` `y` `c` `>` `<` `gc` `=` with a motion or an object | The range is from the cursor to the target of the motion, start included, end not included (exclusive), in exact ticks. A text object gives the exact bounds of its thing (`ic` the clip, `ib` the bar). | `dl` at 5.312 removes 5.312 to 6. `de` at 0 removes 0 to 5.312. |
| 5 | Selections | `v` `V` `Ctrl-v` | The range is from the anchor to the cursor, exclusive. A selection that did not grow is the cell of the cursor. The lit cells are the range, through the axis. | `v` at 5.312 selects 5.312 to 6. `vl` from 5 selects 5 to 6. |
| 6 | Moves of whole things | `>` `<`, `H` `L`, `:clip.move`, a lane point or a note moved by keys, a drag of the body of a thing | Relative: move by whole grid steps and keep the offset. Anchor: the start of the first thing. Target: the line `n` steps after the line at or before the anchor, plus the same offset. The cursor moves by the same delta. | `L` on take 1 at 0.312: to 1.312. |
| 7 | Moves of one edge | `Alt-h` `Alt-l`, `:clip.resize`, the edges of the loop and the punch, fades, a drag of an edge, a stretch edge | Absolute: the edge goes to the next line or the line before, as rule 1. | `Alt-l` on take 1: its end 5.312 → 6. |
| 8 | Snap edits | `=`, `:quantize` | Put the things on the nearest lines, with the strength and the swing. This is the one edit that removes an offset of things. | `=` on take 1 at 0.312: to 0. |
| 9 | New things at the cursor | insert (`m`, `a` `i` in the roll), `p` `P`, `S` (split), a marker, a mark, the loop from a selection, the start of a take, a punch | At the exact tick of the cursor. A pasted or new thing keeps its own length and its inner offsets. | `R` with the cursor at 7 starts take 2 at 7. |
| 10 | Recording | the end of a take, loop passes | The start is the exact tick where the take starts. The end is the stop, rounded to a tick. paw never snaps recorded data. The cursor does not move. | Take 1 ends at 5.312. |
| 11 | The pointer | press, drag | With `snap` on (the default), a press goes to the line at or before the pointer (the cell under it). A drag of a body is rule 6, a drag of an edge rule 7. `Shift` or `snap` off: exact. | A press over columns 12 and 13 at zoom 2: 6. |
| 12 | Edits of content in a lane | slip of audio in its clip, a step of a video frame, a curve point | Round to the atom of the content: a sample, a frame, a tick. The edge of the clip on the axis follows rules 6 and 7, in ticks. | A slip of audio by one grid step: the source offset changes by the samples of one beat. |
| 13 | Tempo and meter changes | `:tempo`, the tempo lane, `:meter` | No musical position changes. Things with the time base `time` keep their seconds. The grid is computed again. The cursor keeps its tick. | |
| 14 | Zoom and scroll | `zi` `zo`, `:zoom`, scroll | No position changes. With `grid=auto` the grid changes with the zoom. | |
| 15 | Playhead and cursor | `gp`, `gs`, `:cursor.to_playhead`, play from the cursor | Exact, as rule 2. The playhead is a thing. (Today `cursor.to_playhead` rounds: this changes.) | |
| 16 | The thing under the cursor | `K`, `x`, `+` `-`, `[` `]`, `c` on a point or a note | A thing with length (a clip, a note's body): the thing that contains the cursor. A thing with no length (a curve point, a marker, a hit): the first thing in the cell of the cursor. (This replaces the reach of half a grid step around the cursor.) | A point at 5.2 is under the cursor at 5, not at 5.312. |

The rules in one sentence each, for the help pages:

- **Grid keys go to grid lines. Object keys go to the object.**
- **A whole thing moves by steps and keeps its offset. One edge goes to
  grid lines.**
- **New things start at the cursor. Only `=` puts things on the grid.**

### 3.1 Cell views

The drum grid, a tracker view and the score draw cells, not a time
area. Their cursor is always on a line: it is a cell. An object motion
goes to the cell that contains the object. An off-grid thing shows in
its cell with a mark of its offset (`·` after the hit), as a
tracker shows a delay. The score's grid is the entry value (`=4`,
`=8t`) from the start of the bar. These views use the same grid module.

### 3.2 Lanes of other time bases

| Lane kind | Time base of its clips | Atom of content | Objects for `w` `b` `e` |
| --- | --- | --- | --- |
| MIDI, notes | beats | tick | clip edges; notes in the note editors |
| Audio | beats or time | sample of the source | clip edges, take edges, comp edges, stretch markers |
| Curve, automation, tempo | beats | tick | points |
| Lyrics, text | beats | tick | syllables, words |
| Video | time | frame | clip edges, cuts |

A lane kind declares its time base and its atom (`StreamFamily`
properties, architecture plan V2). The cursor is on the one axis, in
ticks, on every lane. With `grid=frame`, `h` `l` go from frame to frame
on every row of the window, so the rows stay aligned.

## 4. What the user sees and controls

| Element | On the grid | Off the grid |
| --- | --- | --- |
| Cursor | A block over its cell, from the cursor to the next line, through the axis. | One column, the cell that contains the cursor (ADR 0035), in the new group `CursorOff` (amber). |
| Status line, grid part | `grid 1/4` | `grid 1/4 · +.31` (beats after the line before, in the precision of the position display) |
| Head of the time area | `Song 2.2` | `Song 2.2.31` |
| `K` on the empty time area | the position | the position in bar, beat and ticks of 1/960, the offset, and the time in milliseconds |

Control:

- `h` or `l` puts the cursor on a line with one key, in the direction
  the user wants. Normal mode gets no new key.
- `]g` `[g` make the grid wider and finer (today). `:grid 1/8t`,
  `:grid auto`, `:grid frame`, `:grid bar` set it. `:set swing=58`.
- `:set nosnap` makes the pointer exact. `Shift` during a drag inverts
  `snap`. The option `snap` replaces `note_snap`.
- `=` puts things on the grid.

Check against the key rule:

| Key | The key rule | This design |
| --- | --- | --- |
| `h j k l w b e 0 ^ $ gg G` | only move | Only move. `h` `l` to lines, the others to things. |
| `< >` | time | Rule 6: relative moves in time. |
| `+ -` `Ctrl-a` `Ctrl-x` | main value | No change. |
| `[ ]` | second value | No change. `]g` `[g` stay the grid (a `]x` pair). |
| `K` | describes | Gives the exact position and the offset. |
| `Esc` | cancels | No change. |

Check against Vim habits: `l` and `h` are like Vim's over a Tab: the
cursor never stays inside a cell after `h` or `l`. `w` `b` `e` go to
edges, as in text. Operators are exclusive, as `dw`. `curswant` keeps
the time over `j` `k`.

## 5. How it cannot drift again

1. **One grid module**, `paw.timegrid` (Teal), on top of the axis of
   ADR 0035. It owns the tick type, the grid setting, `lines(from, to)`,
   `next(t)`, `prev(t)`, `floor(t)`, `nearest(t)`, `cell(t)`,
   `steps(anchor, n)` (rule 6) and `off(t)`. Each view, lane kind and
   extension calls it. A view gives only its window (grid setting,
   folds, scope) and its objects.
2. **One motion layer**: `paw.motion` gives `grid(dir, count)`,
   `object(list, dir, count)`, `relative(things, n)`, `edge(thing,
   side, dir, count)`. The commands of rule 1, 2, 6 and 7 in each view
   call it. The cursor modules keep a tick and `want`.
3. **Exact arithmetic**: ticks are integers. `cursor.set_tick` refuses
   a value with a fraction (an error in tests, a round in release).
   Values from the kernel are rounded to a tick once, at the boundary.
4. **A lint** (in `tools/layers.lua` or a new `tools/gridlint.lua`, run
   by the suite) refuses `opt.grid`, `opt.note_grid`, `util.round(.., grid)`
   and `/ grid` outside `timegrid.tl`, `options.tl` and the status line.
   With the lint of ADR 0035 (`/ zoom`, `* zoom`), no module can map
   time on its own.
5. **A property test** (`tests/timegrid.lua`, fixed seeds, no time): for
   grids of each kind (1/4, 1/8t, 1/16 with swing 60%, 1/7, bar, frame
   at 30000/1001, 1s), meter maps with changes (4/4, 7/8, 5/4), tempo
   maps with changes, folds and scopes, and positions on and off the
   grid:
   - after `next` or `prev` the result is a line, or a bound;
   - `next(prev(t)) >= t` and `prev(next(t)) <= t`; on the grid, `prev(next(t)) == t`;
   - `n` times `next` then `n` times `prev` from a line gives the same tick;
   - `steps(steps(a, n), -n) == a` (rule 6 keeps the offset);
   - each line is an integer; the lines are sorted and unique;
   - zoom and scroll do not change a line or the cursor.
6. **The owner's case by real keys** in the suite (see the tests below).

## 6. Mock screens (100 columns, zoom 2, grid 1 beat)

Legend: `██` the cursor on the grid (its cell), `▌` the cursor off the
grid (one column, amber), `▼` the playhead.

### 6.1 After `w`: the end of take 1, 5.312

Before (capture):

```text
 Song 2.2               │1 ▏ ▏ ▏ 2 ▏▼▏ ▏ 3 ▏ ▏ ▏ 4 ▏ ▏ ▏▕5 ▏ ▏ ▏ 6 ▏ ▏ ▏ 7
 1 █ Guitar        MSRI │▏take 1    ▏    ▏       ▏       ▏       ▏       ▏
   █in ━━━━━━━━━╸── 0.0 │▂▂▂▂▂▂▂▂▂▂▂##   ▏       ▏       ▏       ▏       ▏
 NORMAL·arrange  ■ 2.2.31 │ 0:02.7 │ 120 bpm 4/4 │ grid 1/4              ● untitled
```

After:

```text
 Song 2.2.31            │1 ▏ ▏ ▏ 2 ▼ ▏ ▏ 3 ▏ ▏ ▏ 4 ▏ ▏ ▏▕5 ▏ ▏ ▏ 6 ▏ ▏ ▏ 7
 1 █ Guitar        MSRI │▏take 1    ▏    ▏       ▏       ▏       ▏       ▏
   █in ━━━━━━━━━╸── 0.0 │▂▂▂▂▂▂▂▂▂▂▌     ▏       ▏       ▏       ▏       ▏
 NORMAL·arrange  ■ 2.2.31 │ 0:02.7 │ 120 bpm 4/4 │ grid 1/4 · +.31       ● untitled
```

The cursor and the playhead are in column 10, the cell of beats 5 to
5.5 that contains 5.312 (ADR 0035). The status line says the offset.

### 6.2 Then `l`

Before: cursor 6.312, `##` in columns 13 and 14, over two cells.

```text
   █in ━━━━━━━━━╸── 0.0 │▂▂▂▂▂▂▂▂▂▂▂▏ ## ▏       ▏       ▏       ▏       ▏
 NORMAL·arrange  ■ 2.2.31 │ 0:02.7 │ 120 bpm 4/4 │ grid 1/4              ● untitled
```

After: cursor 6 (2.3), the cell of beat 6, columns 12 and 13.

```text
 Song 2.3               │1 ▏ ▏ ▏ 2 ▼ ▏ ▏ 3 ▏ ▏ ▏ 4 ▏ ▏ ▏▕5 ▏ ▏ ▏ 6 ▏ ▏ ▏ 7
   █in ━━━━━━━━━╸── 0.0 │▂▂▂▂▂▂▂▂▂▂▂ ██  ▏       ▏       ▏       ▏       ▏
 NORMAL·arrange  ■ 2.2.31 │ 0:02.7 │ 120 bpm 4/4 │ grid 1/4              ● untitled
```

### 6.3 Then `l`, `R`, 3.2 beats, stop

Before: take 2 from 7.312 to 10.512. The offset is now in the data.

```text
 Song 2.4               │1 ▏ ▏ ▏ 2 ▏ ▏ ▏ 3 ▏ ▏▼▏ 4 ▏ ▏ ▏▕5 ▏ ▏ ▏ 6 ▏ ▏ ▏ 7
 1 █ Guitar        MSRI │▏take 1        ▏take ▏  ▏       ▏       ▏       ▏
   █in ━━━━━━━━━╸── 0.0 │▂▂▂▂▂▂▂▂▂▂▂    ##▂▂▂▂▏  ▏       ▏       ▏       ▏
```

After: take 2 from 7 to 10.2. Its start is on the grid. Its end is off
the grid, and only `w` or `e` stop there.

```text
 Song 2.4               │1 ▏ ▏ ▏ 2 ▏ ▏ ▏ 3 ▏ ▼ ▏ 4 ▏ ▏ ▏▕5 ▏ ▏ ▏ 6 ▏ ▏ ▏ 7
 1 █ Guitar        MSRI │▏take 1       ▏take 2   ▏       ▏       ▏       ▏
   █in ━━━━━━━━━╸── 0.0 │▂▂▂▂▂▂▂▂▂▂▂   ██▂▂▂▂▂   ▏       ▏       ▏       ▏
 NORMAL·arrange  ■ 3.3.20 │ 0:05.1 │ 120 bpm 4/4 │ grid 1/4              ● untitled
```

### 6.4 The piano roll on a clip that starts off the grid

Before: the roll's grid starts at the clip (5.312). So its lines are
0.312 beat later than the bars of the song. `l` steps 5.312, 5.562,
5.812. After: the roll draws the song's lines. `l` from the start of the
clip (5.312) goes to 5.5, then 5.75 (grid 1/16). Notes keep their
positions inside the clip.

## 7. Tests by real keys

Each test is in the suite, sealed, with no time in an assertion. A
golden screen at 100x16 where the look changes.

| Test | Keys | Checks |
| --- | --- | --- |
| A take that ends off the grid: `w` goes to its end, `l` to the next line, a new take starts there | stepped engine; `r`, `R`, until a beat between lines, `<Space><Space>`; `0w`, `l`, `R`, stop | cursor tick after each key; take 2 starts on beat 7; golden screens 6.1 and 6.2 |
| `h` from off the grid goes to the line before; `3l` counts lines | fixture clip 0 to 5.312; `$`, `h`, `3l` | 5, 8 |
| No drift on a triplet grid with swing | `:grid 1/8t`, `:set swing=60`, `999l`, `999h` | the same tick; each tick an integer |
| Bars of other lengths | meter 7/8 at bar 2; `l` over the bar | stops at 3.5 (the short cell) and at the bar line |
| A closed fold is one cell | fold bars 3 to 4; `l` before it | stops at the start and the end of the fold |
| A whole clip keeps its offset; `=` removes it | clip at 0.312; `L`, `2<ic` then `=ic` | 1.312, then 0 |
| One edge goes to lines | clip end 5.312; `Alt-l`, `Alt-h` | 6, 5 |
| Operators and selections are exclusive and exact | cursor 5.312; `dl`; `v<Esc>` then `gv`; `de` from 0 | removed 5.312 to 6; selection 5.312 to 6; removed 0 to 5.312 |
| `j` `k` keep the time, and return to the wanted time after a clamp | scope of bars 1 to 2; cursor at bar 3 on a track outside; `j`, `k` | `want` restored |
| A lane point is under the cursor in its cell | points at 5.2 and 6; `K` at 5, at 5.312 | 5.2 at 5; none at 5.312 |
| The piano roll grid follows the song | clip at 5.312, `Enter`, `l` | 5.5 (song), not 5.562 |
| The drum grid shows an off-grid hit in its cell | a hit at 1.1 | the cell of 1, with the offset mark |
| Off-grid state on the screen | cursor at 5.312 | golden screen: `▌`, `grid 1/4 · +.31`, `Song 2.2.31`; `K` text |
| The pointer: a press goes to the cell, `Shift` is exact, a drag of a body keeps the offset | mouse events in cells | 6; exact beat; 1.312 |
| `:cursor.to_playhead` is exact | playhead at 5.312 | 5.312 |
| Property test of `paw.timegrid` | none (module) | the property test of "How it cannot drift again" |

## 8. The plan

| Id | Bundle | Builds | Depends on | Size | Milestone |
| --- | --- | --- | --- | --- | --- |
| TM1 | The grid module | `paw.timegrid`: ticks, the grid setting (note value, `t`, `bar`, `auto`, `frame`, seconds, swing), lines over meter changes, folds and scopes, `next` `prev` `floor` `nearest` `cell` `steps` `off`; the cursor keeps a tick and `want`; the property test; the lint | TASK-325 (the axis draws the lines that TM1 gives) | M | m-15 |
| TM2 | One motion layer in the arrange view and its lanes | `paw.motion`; rules 1 to 16 for the arrange view, take rows, curve, tempo, marker and automation rows, the mouse (`arrange_mouse.tl`, `frontend/act/*`); the cursor drawn by cell and `CursorOff`; the status line and `K`; `snap` replaces `note_snap`; docs: `key-rule.md`, `keys.md`, `grammar.md`, `options.md`, the arrange view reference, the tutor's lessons that teach `h` `l` | TM1 | L | m-15 |
| TM3 | The note editors on the song's grid | the piano roll's grid and cursor in song ticks (the roll converts to clip beats only to write notes); the score, the drum grid, the vocal editor and the pattern view call `paw.timegrid`; cell views (3.1) | TM1; with PR1 | M | m-15 |

- **TASK-325** builds the axis and keeps the cursor exact. It does not
  change a move. If it keeps the cursor as a float beat, TM1 changes it
  to a tick. TM1 starts after TASK-325 is merged: both change
  `cursor.tl` and the grid lines of `arrange.tl`.
- **Piano roll bundles.** PR1 has "one unit for time" in its scope. If
  PR1 did not start yet, TM3 goes into PR1 as acceptance criteria. Else
  TM3 is a bundle after PR1. PR2 (lane host) puts lanes on the roll's
  axis and uses `paw.timegrid` for their points. PR5 (takes in the
  roll): take and comp edges are objects of rule 2.
- **LA (lanes and takes).** A lane kind declares its time base and its
  atom. Lane rows use `paw.timegrid` and the motion layer; no lane row
  steps by its own grid.
- **TK (takes and comps).** Take edges and comp edges are objects
  (rule 2). A comp range from a selection is exact (rule 5).
- **HD (lane heads, ADR 0034).** A head has no time area and no time
  motion. No change.
- **VD (video lanes).** `grid=frame` and the frame atom (rule 12).
- **Rust.** No change is necessary: the kernel keeps f64 beats, and
  each value is a tick divided by `TPQ`. A later change to i64 ticks in
  the model is an owner question (Q7).

## 9. Owner questions

| # | Question | Recommendation |
| --- | --- | --- |
| Q1 | A whole thing that moves by keys or by the pointer: keep its offset (relative, as Logic and Cubase's Grid Relative), or go to a line (absolute)? | Relative. `=` makes it absolute. A recorded take keeps its feel when it moves a bar. |
| Q2 | One edge (the end of a take, a loop edge): to grid lines? | Yes, as `h` `l`. |
| Q3 | A selection from the anchor to the cursor: exclusive (time is points, as REAPER), or inclusive of the cursor's cell (as Vim's `v`)? | Exclusive. The lit cells are the range. An empty selection is the cursor's cell. |
| Q4 | A key to put the cursor on the nearest line? | No new key. `h` and `l` put it on a line in one key, in the direction you want. A toggle of `snap` for the pointer is `:set snap!`. |
| Q5 | The default grid: fixed (1/4 in the arrange view, 1/16 in the roll, as today) or `auto` (follows the zoom, as Live and Bitwig)? | Fixed. `auto` as a setting. With `auto`, `h` `l` change their step with the zoom, which surprises in a modal editor. |
| Q6 | `:cursor.to_playhead` and the cursor after a stop: exact, or to the nearest line? | Exact (rule 15). `h` or `l` then go to a line. |
| Q7 | Change the Rust model from f64 beats to i64 ticks now? | Not now. The motion layer rounds at the boundary, and the tests guard it. Do it when a bundle changes the model of clips anyway (LA). |
| Q8 | Snap the end of a take to the grid when it stops? | No. paw never changes recorded data. `Alt-h` `Alt-l` or `=` do it on request. |
| Q9 | The offset in the status line: in hundredths of a beat (as the position), in ticks of 1/960, or in milliseconds? | Hundredths of a beat, as the position display. `K` gives ticks of 1/960 and milliseconds. |

## 10. Risks

- Many tests and guides press `l` from a position off the grid and
  expect a step. TM2 finds them with the suite and changes each to the
  new rule. The search: `set_beat(cursor.beat +`, `* paw.opt.grid`,
  `note_grid`.
- Extensions and the user's `init.lua` read `paw.opt.grid` as a number.
  A grid setting can be a string. `paw.timegrid.step()` gives the step
  in beats for them. A number stays valid as a setting.
- The roll's coordinates change from clip beats to song ticks (TM3).
  This touches `roll_clips.tl`, `roll_draw.tl`, the roll mouse and
  their tests. It is the largest change. PR1 changes the same files.
- Lines over a long song with meter changes: `lines(from, to)` is
  computed for the visible span only, and cached by the version of the
  meter map and the grid setting. A key stays under 100 ms (rule 7); a
  bench entry measures `l` on a song of 500 bars with 50 meter changes.
- Swing moves lines, so `h` `l` stop at swung lines. That is the
  intention, but it is new.
- The facts of TASK-325 were not available when this design was
  written. Assumptions: the axis gives the cell that contains a beat,
  and the cursor is kept as an exact beat. If a fact differs, the plan
  changes, not the rules.
