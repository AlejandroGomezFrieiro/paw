# Scopes UX: how folds, scopes and subprojects look and feel in the terminal

TASK-233. Status: proposal for the owner's review. Nothing is built.

Read with: `docs/explanation/about-scopes.md`, `docs/reference/narrowing.md`,
`docs/reference/subprojects.md`, `docs/reference/key-rule.md`, and the design
`backlog/docs/designs/nest.md` (sections 3.1 to 3.7; the owner accepted Q1 to Q30).

Assumptions:

- TASK-226 is fixed. Inside a subproject, the region row shows only the regions that the block
  covers, the cursor never shows a negative bar, and the ruler of a scope uses one numbering.
  This design does not design those bugs away. It uses the fixed screens as the base.
- TASK-224 (a closed block fold is one step of the cursor) and TASK-225 (the cell shows its bar
  count) get built. Ticket UX-6 below takes TASK-225 into a larger change of the cell.
- The user word is **subproject**. `nest` stays in commands and code only (question 18 of the nest design).

Contents:

1. The screens: what we looked at
2. The ideas from other tools
3. The vocabulary of marks
4. The user tasks, with screens before and after
5. What `K` shows, and its size
6. What `:scope.write`, `:scope.write!` and `:nest.new` do to the song's tracks
7. The track height
8. Other problems that the screens show
9. The build tickets, in order
10. Questions for the owner

## 1. The screens: what we looked at

The screens come from sealed runs (`tests/tools/run.sh --clean --no-plugins --audio null
--headless`) of the binary of the merge folder:

- `scratchpad/screens/shots.txt` (made by `shots.lua`): a song of 5 tracks, the groups Drums
  and Keys, the regions Intro, Verse and Chorus. Shots 1 to 14.
- `scratchpad/ux/v1.txt` and `scratchpad/ux/v2.txt` (made by `v1.lua` and `v2.lua`, variants of
  `shots.lua`): a song of 8 tracks and 6 regions, zoomed out, a per-track `:scope.write`, a
  `:scope.write!` of a group in a region, two blocks of one subproject, a subproject inside a
  subproject, two windows, `K` on many things, a `:scope.write!` of a whole group, and the track
  heights 2 and 1.

The screen text below copies those runs. A line that ends in `…` was cut to fit the width of this design.

## 2. The ideas from other tools

| Tool | What it does | What we take |
| --- | --- | --- |
| Vim folds [1] | A fold column at the left: `-` on the first line of an open fold, `\|` under it, `+` on a closed fold. A nested fold is one column further right. A closed fold is one line with its size: `+--  45 lines: text`. | paw has this already in the track column (`▾ │ ╰ ▸`). We keep it, and add one more kind of guide for the rows of a subproject. A closed thing always says its size. |
| Emacs narrowing [2] | The word `Narrow` shows in the mode line while the buffer is narrowed. The text outside is not shown at all. | One word, always visible, per window. Nothing drawn outside the scope: the scope ends at a hard edge. |
| Neovim `winbar` and hover floats [3] | Each window can have its own top line. A hover float is as big as its text, with a maximum height and width; `K` a second time goes into the float. | A window bar per arrange window for the path of its scope. `K` as a small float, not a page. |
| tmux and `zellij` [4] [5] | tmux puts `Z` in the status of a window with a zoomed pane. `zellij` draws a frame around each pane with its title. | The state of each window shows on the window, not only on the one status line. Two splits must each say where they are. |
| REAPER subprojects and folder tracks [6] [7] | "Move tracks to new subproject" puts the tracks into a new project and leaves one item on one track. A folder track is a bus: its children route into it. | The return row of the nest design. A folder that is a bus is one idea; a subproject is a second idea. Do not mix them on one row without saying so. |
| Ableton Live group tracks [8] | A group folds with a button. In the arrangement, the group track shows an overview of the clips of its tracks. | A group row, open or folded, shows an overview of what its tracks play. A folded group must not look empty. |
| Logic Pro track stacks [9] | Two kinds. A folder stack groups tracks "without changing the audio routing". A summing stack routes the tracks to a bus. | The routing question below has the same two answers. A command that moves material must not change the routing of what stays, unless the user asks. |
| Bitwig group tracks [10] | A folder icon shows and hides the tracks of a group. When a group is open and the focus is in it, a new track goes into the group. | `:nest.new` puts the return row where `o` puts a track: inside the group of the cursor. |
| Terminal music tools | No terminal tracker or sequencer that we found has folds or nested projects. Trackers (for example the pattern matrix of Renoise) collapse a track to a narrow column with its name. | Nothing new. paw is first here, so the marks must follow Vim. |

Sources:

1. Vim, `:help fold.txt`, `'foldcolumn'` and `foldtext`: <https://vimhelp.org/fold.txt.html>
2. GNU Emacs manual, Narrowing: <https://www.gnu.org/software/emacs/manual/html_node/emacs/Narrowing.html>
3. Neovim, `'winbar'` and `vim.lsp.util.open_floating_preview()`: <https://neovim.io/doc/user/options.html#'winbar'>, <https://neovim.io/doc/user/lsp.html>
4. tmux(1), window flags (`Z` zoomed): <https://manpages.debian.org/tmux>
5. `zellij`, pane frames: <https://`zellij`.dev/documentation/options.html>
6. Sound on Sound, REAPER subprojects: <https://www.soundonsound.com/techniques/reaper-subprojects>
7. Sound on Sound, REAPER groups, folders and matrices: <https://www.soundonsound.com/techniques/groups-folders-matrices>
8. Ableton Live manual, Mixing (group tracks): <https://www.ableton.com/en/manual/mixing/>
9. Logic Pro, Track Stacks overview: <https://help.apple.com/logicpro/mac/10.4/en.lproj/lgcp9bc4b63d.html>
10. Bitwig Studio user guide, Intro to Tracks: <https://bitwig.com/userguide/latest/intro_to_tracks>

## 3. The vocabulary of marks

One idea has one glyph and one word. The ruler, the track column, the window bar, the status line,
`K`, the messages and the picker use the same glyph and the same word.

| Idea | Glyph | Word | Ruler | Track column and header | Window bar, status line | `K` and messages |
| --- | --- | --- | --- | --- | --- | --- |
| A path of scopes | `›` | (none) | | | `Verse › Keys` | `Song › Verse › Keys` |
| Open (a group, a fold, a return row) | `▾` | open | `▾` on a region | `▾` then `│` down, `╰` on the last | | `open` |
| Folded | `▸` | folded | `▸Verse 8` | `▸Drums +2` | | `folded` |
| Subproject | `⧉` | subproject | block frame `⧉ Bridge` | `⧉` before the name of a return row; `┆` guide on its rows that `za` shows | `⧉Bridge` | `subproject Bridge` |
| A song bar (inside a scope) | `@` | song bar | `@9 @11` on the second row | | `1.2 @9.2` | `bars 1-8 (song @9-16)` |
| End of a scope | `┃` | end | `┃ end of Verse` | `┃` down every row; blank after it | | |
| A clip cut at an edge | `‹` `›` | continues | | `‹Kick … ›` | | `continues before`, `continues after` |
| One subproject in more places | `×2` | places | `⧉ Bridge ×2` on each block | | | `plays in 2 places: @9, @25` |
| The loop | `▕` | loop | `▕` at the loop edges | | `loop 1–8` | |

Changes from today, and why:

- **`›` means only "a level of the path".** Today `›` has three meanings: the path separator, the
  sign "this window is in a scope" in the track column, and the right edge of a cut clip (shot 6:
  `‹Kick ›` beside `1 ›▾▌ Drums`). The sign in the track column goes, because the window bar
  (see the first task) says it in words. The cut clip keeps `‹ ›`: there the glyph points to more of the
  clip outside, and it never touches the track column.
- **`@` marks a song bar on the screen as it does in what you type.** `@19|` and `:tempo 96 at @19`
  already mean bar 19 of the song. The ruler and the status line use the same `@`, so the user
  reads `1.2 @9.2` in the way that they type it. Today the status line says `1.2 (9.2)`, and the
  ruler mixes the bar numbers of the scope and of the song on one row (TASK-226).
- **`┃` is the end of a scope.** Today the only mark is `▕`, which is the loop edge (shot 13:
  `▕3`). It shows the end only because the loop follows the scope. With `:set noscopeloop` the end
  has no mark at all. A scope end and a loop edge are two ideas, so they get two glyphs.
- **`⧉` is on every row that belongs to a subproject**, not only on the block and the status line.
- **`×2` and "places", not "instances".** "Instance" is a word of programmers. A musician says the
  bridge "plays twice" or "in two places".
- **"subproject", not "nest", in `K`.** Today `K` says `nest Bridge · 4/4 …` (shot 10).

ASCII: with `paw.opt.ascii`, the glyphs become `>` (path), `v` `>` (open, folded), `#`
(subproject), `@`, `|` (end), `<` `>` (cut), `x2`, `|` (loop).

## 4. The user tasks, with screens before and after

Five tasks come from the ticket. Each has the screen today, the problem in the words of the user,
the screen proposed, and the keys. A sixth part covers two windows, because each task can happen
in a split.

The proposed screens are 100 columns. They use the track height of today (3 rows), so that the
screens before and after compare line by line. The part on the track height is about the height.

### 4.1 Work on a section (a region)

The user wants to work on the verse only: hear it in a loop, edit it, and not see the rest.

**Today** (shot 6, `:narrow Verse`, with the ruler as TASK-226 will fix it):

```
 cur 1.1.00               │1       3       5       7      ▕9       11      13      15      17      19
                          │▏Verse                          ▏Chorus
 1 ›▾▌ Drums         MSRI │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
    │▌in ──────────── 0.0 │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
    │▌   C                │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
 2  │█ Kick          MSRI │‹Kick                          ›▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
    │█in ──────────── 0.0 │▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
    │█   C        → Drums │                                ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
 …
 NORMAL·arrange  ■ 1.1.00 │ 120 bpm 4/4 │ loop 1–8       Song › Verse 1.1 (9.1) │ ● untitled │ cpu ▁ 0%
Song › Verse · bars 1-8 (song 9-16) · 4/4 · 7 tracks · `zw` goes back
```

The problems, in the words of the user:

- "After bar 8 I see empty bars. Did my clips go? Can I write there?" The end is a thin `▕`, the
  same mark as the loop.
- "The ruler says Chorus after the verse. I asked for the verse only."
- "Where am I?" The path is at the far right of the status line, between other parts.
- "The group rows are empty bars." A group row draws only the grid.

**Proposed** (same keys: `:narrow Verse<CR>`, or `znar` on the verse):

```
 Verse                    │1       3       5       7      ┃
 cur 1.1 @9.1             │@9      @11     @13     @15    ┃ end of Verse · zw: the song
 1  ▾▌ Drums         MSRI │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃
    │▌in ──────────── 0.0 │                               ┃
    │▌   C                │                               ┃
 2  │█ Kick          MSRI │‹Kick                         ›┃
    │█in ──────────── 0.0 │▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄ ┃
    │█   C        → Drums │                               ┃
 3  ╰▌ Snare         MSRI │‹Snare                        ›┃
     ▌in ──────────── 0.0 │▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄ ┃
     ▌   C        → Drums │                               ┃
 4  ▾▌ Keys          MSRI │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃
    │▌in ──────────── 0.0 │                               ┃
    │▌   C                │                               ┃
 5  │▌ Piano         MSRI │‹Piano                        ›┃
    │▌in ──────────── 0.0 │▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄ ┃
    │▌   C         → Keys │                               ┃
 6  ╰▌ Pad           MSRI │‹Pad                          ›┃
     ▌in ──────────── 0.0 │▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄ ┃
     ▌   C         → Keys │                               ┃
 7   ▌ Bass          MSRI │‹Bass                         ›┃
     ▌in ──────────── 0.0 │▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄ ┃
     ▌   C                │                               ┃
         o new track      │                               ┃
                          │
     ▌ Master             │
     ▌   ▀▀▀▀▀▀▀▀▀▀▀▀ 0.0 │
 NORMAL·arrange  ■ 1.1.00 │ 120 bpm 4/4 │ loop 1–8                   Verse 1.1 @9.1 │ ● untitled
Song › Verse · bars 1-8 (song @9-16) · 4/4 · 7 tracks · `zw` goes back
```

What changes:

- **The window bar.** The two left cells of the ruler are the window bar. The first line gives the
  path of the scope of this window, without `Song ›` (it is always there). In the song it says
  `Song`. The second line gives the cursor in the bars of the scope and of the song. Today the
  first cell says `cur 1.1.00` and the second cell is empty, in every shot. The path is cut at the
  left when it is long: `…› Verse › Keys`.
- **The end.** A column `┃` after the last bar of the scope, on the ruler and on every row. After
  it, nothing: no grid, no clips, no region names. The second row of the ruler says what is after
  it and the key to see it.
- **One numbering per row.** Row 1 has the bars of the scope. Row 2 has the bars of the song, with
  `@`, as `scopebars=both` asks. The region row does not show when the only region in the scope is
  the scope itself. A region inside the scope (`Verse A` in `Verse`) shows on a third row, as in
  the song.
- **A group row shows an overview.** `━` where at least one track of the group has a clip, blank
  where none has. This is the summary that Ableton draws on a group track [8]. It costs nothing in
  rows: the line was there and empty.
- **No `›` in the track column.** The window bar says it.

Keys: no new key. `0` and `$` stop at the edges, as today. `l` on the last bar stays on it, and
the message says `end of Verse: zw goes to the song`.

### 4.2 Work on a group

The user wants to see only the drums, or to fold them away to make room.

**Today, folded** (shot 3b, `za` on Kick):

```
 cur 1.1.00              │▼       3      ▕5       7       9       11      13      15      17      19
                         │▏Intro                          ▏Verse                          ▏Chorus
 1 ▸█ Drums +2      MSRI │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
    █in ──────────── 0.0 │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
    █   C                │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
    █                    │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
 2 ▾▌ Keys          MSRI │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
```

The problem: "I folded the drums and now the row is empty. Is there anything in it?" A folded group
is four rows of grid with nothing in them (with `track_height=auto`, the rows grow to 4 when there
is room, so the fold makes the screen look emptier, not fuller).

**Proposed** (same key, `za`):

```
 Song                    │▼       3      ▕5       7       9       11      13      15      17      19
 cur 1.1                 │▏Intro                          ▏Verse                          ▏Chorus
 1 ▸█ Drums +2      MSRI │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    █in ──────────── 0.0 │Kick ▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄
    █   C                │Snare▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄
 2 ▾▌ Keys          MSRI │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- Line 1 of a group row: the overview `━` (as in 4.1).
- The other lines of a folded group row: one line per member while they fit, with the name of the
  member and the small notes of its clips. With more members than lines, the last line says
  `+3 more`. At height 1 only the overview shows.
- A folded group keeps the height of one track. It does not grow to fill the screen.

**Narrowed to the group** (`:narrow Drums`, `znag`): as today, plus the window bar says `Drums`,
and no `›` in the track column. No other change.

### 4.3 Work on a part of some tracks (a block)

The user wants to hide the busy piano and pad in bars 9 to 24 while they work on the drums, or to
work on that block only.

**Today** (shot 4, `<C-v>j16lzf` on Piano at bar 9):

```
 5 │█ Piano         MSRI │▏Piano                           Fold 1
   │█in ──────────── 0.0 │▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄
   │█   C         → Keys │▏
 6 ╰▌ Pad           MSRI │▏Pad
    ▌in ──────────── 0.0 │▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄
    ▌   C         → Keys │▏
folded Fold 1 (2 tracks, 16 bars) · `za` opens it, `zd` deletes it
```

The problem: "My piano and pad stop at bar 8. Did I delete them?" The cell has no edge, no size and
no fill. Only the message, which goes away, says what it is. `Fold 1` says nothing about the
content.

**Proposed** (same keys):

```
 5 │█ Piano         MSRI │▏Piano                          ╭▸ Fold 1 · 16 bars · Piano, Pad ───────
   │█in ──────────── 0.0 │▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   │█   C         → Keys │▏                               │
 6 ╰▌ Pad           MSRI │▏Pad                            │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    ▌in ──────────── 0.0 │▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  │
    ▌   C         → Keys │▏                               ╰─ za opens · znn enters ───────────────
folded Fold 1 (2 tracks, 16 bars) · `za` opens it, `zd` deletes it
```

- A frame around the block, over all of its rows and bars. A block fold cannot get narrower, as a
  time fold does, because the other tracks go on in that time. So the frame shows that something is
  there.
- The top edge: `▸`, the name, the bars (TASK-225), and the tracks by name (by count when the
  names do not fit: `2 tracks`).
- One overview line `━` per track, where it has clips.
- The bottom edge: the keys. When the block is one track high, the hint goes.
- The default name is the names of the tracks and the bars, for example `Piano, Pad 9-24`, not
  `Fold 1`. The user can rename it with `:scope.name`. `Fold 1` stays for a fold of tracks with no
  time, where the names can be long.
- The cursor: TASK-224 as it is. `j` and `l` go over the block in one step.

**Narrowed to the block** (`<C-v>j16lzn`): as 4.1, with the window bar `Piano, Pad 9-24`.

### 4.4 Reuse a section (a subproject in two places)

The user made the bridge a subproject. It plays at bar 9 and at bar 25. They want to see what is in
it, from the song, and to know that an edit changes both places.

**Today** (shot 11, `za` on the return row Bridge):

```
 cur 9.2.00              │▼       3      ▕5       7       9       11      13      15      17      19
                         │▏Intro                          ▏Verse                          ▏Chorus
 1 ▾▌ Drums         MSRI │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
   │▌in ──────────── 0.0 │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
   │▌   C                │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
 2 │▌ Kick          MSRI │▏Kick
   │▌in ──────────── 0.0 │▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄
   │▌   C        → Drums │▏
 3 ╰▌ Snare         MSRI │▏Snare
    ▌in ──────────── 0.0 │▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄
    ▌   C        → Drums │▏
 4  █ Bridge        MSRI │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏⧉ Bridge                      ▏▏   ▏   ▏
    █in ──────────── 0.0 │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄ ▏▏   ▏   ▏
    █   C                │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀ ▏▏   ▏   ▏
 5 ▾▌ Keys          MSRI │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
   │▌in ──────────── 0.0 │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
   │▌   C                │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
 6 │▌ Piano         MSRI │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏Piano                          ▏   ▏   ▏
   │▌in ──────────── 0.0 │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▏   ▏   ▏
   │▌   C         → Keys │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏                               ▏   ▏   ▏
 7 │▌ Pad           MSRI │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏Pad                            ▏   ▏   ▏
   │▌in ──────────── 0.0 │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▏   ▏   ▏
   │▌   C         → Keys │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏                               ▏   ▏   ▏
 8 │▌ Piano         MSRI │▏Piano                          ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏Piano
   │▌in ──────────── 0.0 │▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏▄  ▄▄  ▄▄
   │▌   C       → Bridge │▏                               ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
    ▌ Master             │
    ▌   ▀▀▀▀▀▀▀▀▀▀▀▀ 0.0 │
 NORMAL·arrange  ■ 1.1.00 │ 0:00.0 │ 120 bpm 4/4 │ grid 1/1                       ● untitled │ cpu ▁ 0%
the whole song
```

The problems, in the words of the user:

- "Which Piano is which? I see two." Rows 5 to 7 are inside Bridge. Row 8 is the song's own
  Piano. Nothing tells them apart: the same guides `▾ │`, the same numbers, the same header.
- "Why does my song's Piano go to Bridge?" (see the routing part).
- "Bridge has no `▾` or `▸`, but `za` opens it." The return row looks like a plain track.
- "If I edit this, does the other bridge at bar 25 change too?" The block says `⧉ Bridge` and
  nothing about the second place. Only `K` says `2 instances`.
- "The song's numbers moved." The song's Piano was 5 and is now 8, because the rows of the
  subproject take song numbers.

**Proposed** (same keys, `za` on the return row; with the routing that the routing part recommends, so the song's Keys
group stays and Bridge is inside it):

```
 Song                    │9       11      13      15      17      19      21      23      25      27
 cur 9.2                 │▏Verse                          ▏Chorus                         ▏Verse 2
 4 ▾▌ Keys          MSRI │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   │▌in ──────────── 0.0 │
   │▌   C                │
 5 │▌ Piano         MSRI │▏                               ▏Piano                          ▏
   │▌in ──────────── 0.0 │▏                               ▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▏
   │▌   C         → Keys │▏                               ▏                               ▏
 6 │▌ Pad           MSRI │▏                               ▏Pad                            ▏
   │▌in ──────────── 0.0 │▏                               ▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▏
   │▌   C         → Keys │▏                               ▏                               ▏
 7 ╰▾⧉ Bridge ×2    MSRI │╭⧉ Bridge ×2 ──────────────────╮                                ╭⧉ Bridge
   ┆ in ──────────── 0.0 │▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  │                                │▄  ▄▄  ▄
   ┆    C         → Keys │▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀  │                                │▀  ▀▀  ▀
   ┆▾▌ Keys              │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┆                                ┆━━━━━━━━
   ┆│▌in ──────── 0.0    │                               ┆                                ┆
   ┆│▌ Piano             │Piano                          ┆                                ┆Piano
   ┆│▌in ──────── 0.0    │▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ┆                                ┆▄  ▄▄  ▄
   ┆╰▌ Pad               │Pad                            ┆                                ┆Pad
   ┆ ▌in ──────── 0.0    │▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ┆                                ┆▄  ▄▄  ▄
   ╰┄ end of ⧉Bridge ┄┄┄┄│┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┘                                └┄┄┄┄┄┄┄┄
 8  ▌ Bass          MSRI │▏Bass
    ▌in ──────────── 0.0 │▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄
    ▌   C                │▏
    ▌ Master             │
    ▌   ▀▀▀▀▀▀▀▀▀▀▀▀ 0.0 │
 NORMAL·arrange  ■ 1.1.00 │ 0:00.0 │ 120 bpm 4/4 │ grid 1/1                       ● untitled │ cpu ▁ 0%
showing the 3 tracks of ⧉Bridge under its row: an edit here changes both places (@9, @25)
```

What changes:

- **The return row** has `⧉` before its name, and `▾` or `▸` in the fold column, because `za`
  opens and closes it. `×2` after the name says that the subproject plays in two places. Every
  block of it says `×2` too.
- **The rows of the subproject** have the guide `┆` (a dotted line) in the fold column, not `│`.
  The dotted guide means "inside a subproject, not a song track". The rows of the subproject keep
  their own groups and guides (`▾ │ ╰`) one column to the right, as Vim nests folds [1].
- **No song numbers on those rows.** The song's tracks keep their numbers. `j` and `k` still go
  through the rows. `t5` is still the song's fifth track.
- **The headers of those rows are lighter** (style `TrackHeaderNest`): no MSRI chips (they are in
  the subproject's mixer, `znn` to reach them) and a short fader. One header row less, so the
  subproject takes less room. At height 1 the guide is the only mark, and it is enough.
- **Only the time of the blocks has content.** Over a block, the rows show what the subproject
  plays there. Outside the blocks, the rows are blank, with `┆` at the edges of each block. Today
  the rows draw the grid outside the blocks, as if a clip could go there.
- **A closing line**, `╰┄ end of ⧉Bridge`, so that the eye sees where the song's own tracks start
  again. It costs one row. It is the line that the user asked for in their words ("which Piano is
  which").
- **The message** says that an edit changes both places.

Keys: `za` on the return row, as today. `za` on a row of the subproject closes them all and puts
the cursor on the return row, as today. `]z` goes to the next block. `znn` enters.

### 4.5 Make a subproject of a part of the song

The user is in `Song › Verse › Keys` and types `:scope.write! Bridge`.

**Today, inside after the write** (shot 8) and **the song after** (shot 9):

```
 NORMAL·arrange  ■ -7.1.00 │ 120 bpm 4/4 │ loop 1–8       Song › Verse › ⧉Bridge 1.1 (9.1) │ ● untitled
nested 3 tracks, bars 9-16, as Bridge (4/4); on its own row Bridge
```

```
 1 ▾▌ Drums         MSRI │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
 …
 4  ▌ Bridge        MSRI │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏⧉ Bridge                      ▏▏   ▏   ▏   ▏
    ▌in ──────────── 0.0 │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄ ▏▏   ▏   ▏   ▏
    ▌   C                │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀ ▏▏   ▏   ▏   ▏
 5 │▌ Piano         MSRI │▏Piano                          ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏Piano
   │▌in ──────────── 0.0 │▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏▄  ▄▄  ▄▄  ▄▄
   │▌   C       → Bridge │▏                               ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
 6 ╰▌ Pad           MSRI │▏Pad                            ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏Pad
    ▌in ──────────── 0.0 │▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏▄  ▄▄  ▄▄  ▄▄
    ▌   C       → Bridge │▏                               ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
```

The problems, in the words of the user:

- "Where is my Keys group?" It went. The group track became the return row `Bridge`.
- "Why do Piano and Pad go to Bridge now?" The song's Piano and Pad (bars 1 to 8 and 17 to 24) now play
  through the row of a subproject. The sound is the same, because the row has the devices of the
  Keys group. But the user did not ask for it, and the message does not say it.
- "Bridge has no `▾`, but Piano and Pad are under it." The row is a group and a return row at the
  same time, and it shows neither.

The same happens with `:narrow Verse`, `:narrow Drums`, `:scope.write! Beat` (`v1.txt`, shot F):
the Drums group goes, and Kick and Snare play `→ Beat`.

**Proposed** (same keys; the routing part gives the reasons):

```
 Song                    │▼       3       5       7       9       11      13      15      17      19
 cur 9.1                 │▏Intro                          ▏Verse                          ▏Chorus
 4 ▾▌ Keys          MSRI │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   │▌in ──────────── 0.0 │
   │▌   C                │
 5 │▌ Piano         MSRI │▏Piano                          ▏                               ▏Piano
   │▌in ──────────── 0.0 │▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▏                               ▏▄  ▄▄  ▄▄
   │▌   C         → Keys │▏                               ▏                               ▏
 6 │▌ Pad           MSRI │▏Pad                            ▏                               ▏Pad
   │▌in ──────────── 0.0 │▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▏                               ▏▄  ▄▄  ▄▄
   │▌   C         → Keys │▏                               ▏                               ▏
 7 ╰▸⧉ Bridge       MSRI │▏                               ╭⧉ Bridge ─────────────────────╮▏
    ┆in ──────────── 0.0 │▏                               │▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄ │▏
    ┆   C         → Keys │▏                               │▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀ │▏
 8  ▌ Bass          MSRI │▏Bass
 …
made the subproject ⧉Bridge from Piano and Pad, bars 9-16; its row is in the group Keys, so it plays as before
```

- The group Keys stays. The song's Piano and Pad keep their output (`→ Keys`) and their clips
  outside bars 9-16.
- The return row `⧉ Bridge` goes into the group Keys, after its last track. So the subproject plays
  through the Keys bus, as the clips did. The sound is the same.
- The message says where the row is and why. When something does change (a send, a VCA, a second
  bus), the message names it, as `:scope.write!` does today for sends.

### 4.6 Bring in a part of another song

The user has an old song with a good bridge, and wants it in this song. The command for it is `:import <folder>`
(TASK-7.16, not built). No screen exists today.

**Proposed** (`:import ~/music/old-song` with the cursor on Bass at bar 33; or a path into the
song, `:import ~/music/old-song/nests/Bridge`):

```
 8  ▌ Bass          MSRI │▏Bass
    ▌in ──────────── 0.0 │▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄
    ▌   C                │▏
 9  ▸⧉ Old song     MSRI │▏                               ╭⧉ Old song · from old-song ───╮
    ┆in ──────────── 0.0 │▏                               │▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄ │
    ┆   C                │▏                               │▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀  ▀▀ │
imported old-song as the subproject ⧉Old song at @33, 8 bars; the first edit inside makes it this song's copy
```

- It is a subproject like any other, with the same marks. No new glyph.
- The block says `from old-song` while the subproject refers to the folder. After the first edit
  (it becomes this song's copy), the words go, and `K` says `copied from old-song` (the word that
  `K` uses for a copied clip today).
- The return row goes where `o` puts a track (see the routing part).

### 4.7 Two windows

**Today** (`v1.txt`, shot K: inside `⧉Beat`, then `<C-w>v` and `zW` in the new window):

```
 cur 25.1.00    │      25      27      29      31 │ cur 25.1.00   │      25      27      29      31
                │  48  ▏Verse 251  52  53  54  55 │               │      ▏Verse 2
 1 ›▾█ Drums    │  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏  │ 1  ▌ Beat     │  ▏   ▏⧉ Beat
 …
 NORMAL·arrange  ■ 1.1.00 │ 0:00.0 │ 120 bpm 4/4 │ grid 1/1                   ● untitled │ cpu ▁ 0%
```

The problem: "What is the left window?" The status line shows only the current window (the song).
The left window shows `›` and a ruler that mixes bars and a region name (`Verse 251`, TASK-226).
Nothing says that the left window is inside `⧉Beat`.

**Proposed:**

```
 ⧉Beat          │1       3       5       7      ┃ │ Song          │      25      27      29      31
 cur 1.1 @25.1  │@25     @27     @29     @31    ┃ │ cur 25.1      │      ▏Verse 2
 1  ▾█ Drums    │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃ │ 1 ▸⧉ Beat ×2  │  ▏   ▏╭⧉ Beat ×2 ───────────
```

Each window bar says where its window is. tmux and `zellij` do the same for each pane [4] [5].
The narrow window cuts the path at the left (`…›Keys`) and keeps the name of the innermost scope.

## 5. What `K` shows, and its size

**Today** (shot 10): `K` opens `paw.ui.page("Under the cursor")`, a box of the full screen (98 by
28) for 7 lines of text. It hides the song. The user loses the place that they asked about.

**Proposed:** `K` opens a float, as the hover of Neovim does [3].

- Its size is its text: the longest line plus 4 columns, at most 72 columns and at most half of the
  window's rows. With more text, the last line says `K again: all of it`.
- It opens below the cursor's row, at the cursor's column. When there is no room below, it opens
  above. It never covers the cursor's cell.
- `K` a second time puts the keyboard in the float, where `j` `k` scroll and `q` or `Esc` close.
  Any other key closes it and does what it does, as a hover does.
- The order: the most specific thing first. A fold or a scope, then the clip or block, then the
  track. One title line and at most 4 lines for each. The track part on a block is short (the row's
  volume and output only), because the block is the question.
- The last line gives the keys for what is under the cursor, in the style of the hint line.
- The words are those of the vocabulary of marks.

`K` on a block of a subproject:

```
 7 ╰▸⧉ Bridge ×2    MSRI │▏                               ╭⧉ Bridge ×2 ───────────────────╮
    ┆in ──────────── 0.0 │▏                               │▄ ╭─ ⧉ Bridge ─────────────────────────────────────╮
    ┆   C         → Keys │▏                               │▀ │ subproject · 8 bars · 4/4 · follows the tempo   │
 8  ▌ Bass          MSRI │▏Bass                              │ 3 tracks: Keys, Piano, Pad · live               │
    ▌in ──────────── 0.0 │▏▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄  ▄▄ │ plays in 2 places: @9 (here), @25               │
    ▌   C                │▏                                  │ row Bridge: 0.0 dB, pan C, → Keys               │
                         │                                   │ znn enter · za tracks · ]z next · <Space>zp     │
                         │                                   ╰─────────────────────────────────────────────────╯
```

`K` on a closed fold (today `v2.txt`, shot N, 12 lines in a page of 28):

```
 ╭─ ▸ Piano, Pad 9-24 ───────────────────────────────────╮
 │ folded · bars 9-24 (16 bars) · 2 tracks: Piano, Pad   │
 │ Song › Piano, Pad 9-24                                │
 │ za open · znn enter · zd delete                       │
 ╰───────────────────────────────────────────────────────╯
```

`K` in a scope, on no clip: the scope line that the message gives today
(`Song › Verse · bars 1-8 (song @9-16) · 4/4 · 7 tracks`), and the keys `zw up · zW song · ]z next`.

`K` on a track (no clip): the track part as today, in the float. The page stays for `:info`
(the long form), so a script and a user who wants all of it still have it.

## 6. What `:scope.write`, `:scope.write!` and `:nest.new` do to the song's tracks

### 6.1 The rule

A command that moves material into a subproject does not change the routing of what stays in the
song. When it must change a route, it says which route and why, in the message. Logic makes the same
difference between Logic's folder stack ("without changing the audio routing") and summing stack
[9]. The user asked for a subproject, not for a new bus.

### 6.2 `:scope.write!` (its own row): the choices

The case that the screens show: the view is a group (Keys) or tracks of a group, over some bars,
and the tracks have clips outside those bars. So they stay in the song, and copies go in. A section of a song is
the usual case: a section of a song.

| Choice | What the song gets | Sound | What the user sees |
| --- | --- | --- | --- |
| A. Today | The group track becomes the return row. The song's tracks of the group play into it. | Same | The group goes. Song tracks play `→ Bridge`. A row that is a group and a return row. |
| B. The group stays; the return row goes into it | The group, its tracks and their routes stay. A new return row, last in the group, plays into the group's bus. | Same | One new row in the group. Nothing else changes. |
| C. The group stays; the return row goes to the master | As B, but the row is outside the group. | Changes: the group's devices no longer process the section | One new row. The sound changes without a word. |
| D. Refuse | Nothing. The message says to use `<Space>zw` (per track). | Same | Nothing. |

**Recommendation: B.** It keeps the sound and changes the fewest things. The return row is in the
place where the eye looks for the keys of the song: in the Keys group. Undo and promote stay
clear: `<Space>zp` puts the tracks back as a group inside Keys, and the user can `zd` that
group's fold or remove the group.

When every track of the view moves in whole (nothing outside the time), the rule of today stays:
the group track becomes the return row, with its devices, fader, sends and lanes. Then no song
track plays into it, so it is only a return row.

**Tracks from more than one bus.** `:narrow Verse` on the whole song, then `:scope.write!`, takes
tracks from Drums, Keys and Bass. Today the row then plays into the master, and the Drums bus and
the Keys bus no longer process the verse. The sound changes without a word. Recommendation:

1. The row plays into the master (no one bus is right).
2. The message names each bus that no longer processes the section: `the Drums bus and the Keys bus
   no longer process bars 9-16: :nest.outputs stems keeps them`.
3. `:nest.outputs stems` on that row makes one stem row per bus (per group of the subproject, as
   the nest design allows), and puts each stem row in its song group. Then the sound is the same again.

A `stems` word on the command (`:scope.write! Bridge stems`) does both at once. Question 3 asks the
owner if `stems` should be the default for this case.

**Regions.** A view with no time (a group over the whole song) must leave the song's regions in
the song. Today it takes all of them into the subproject (`v2.txt`, shots O and P: the message says
`6 markers and regions inside it`, and the song's region row is gone). The list of other problems gives it as a
bug.

### 6.3 `:scope.write` (per track)

No change to routing: each track keeps its devices and gets a block over the time (`v1.txt`, shots
C and D). The routing per track is right. Two small changes:

- Each block says `⧉ Bridge` and the part: `K` says `subproject Bridge, the part of Kick (1 of 8
  tracks)`.
- The message says that the window stayed in the view, as the docs say, so the user does not look
  for a new row: `nested 8 tracks, bars 9-16, as ⧉Bridge, per track: each track plays its part`.

### 6.4 `:nest.new`

Today the return row goes below the track of the cursor, at the top level of the song, and plays
into the master (shot 13 and 14: `Fill` under `Bass`).

**Recommendation:** the return row goes where `o` puts a new track. On a track of a group, it goes
into the group, after the cursor's track, and plays into the group. The reference page on scopes gives the same rule for a track added in the scope of a group, and the rule of Bitwig for a new
track in an open group [10]. Outside a group, as today.

## 7. The track height

Today each track is 3 rows (`track_height = "auto"`, from 3 to 4). On a screen of 30 rows, the
song has 24 rows for tracks: 8 tracks fit, and a song of 10 tracks scrolls. Folds and scopes
matter more because of it. `z-` already gives 2 and 1 rows per track (`v2.txt`, shots R and S),
and they read well:

```
 1 ▾▌ Drums     0.0 MSRI │▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
 2 │▌ Kick      0.0 MSRI │▏Kick
 3 ╰▌ Snare     0.0 MSRI │▏Snare
 4  ▌ Keys      0.0 MSRI │▏⧉ Keys2
```

The rows of a track: 1, the name, the chips and the clip names; 2, the fader and the notes; 3, the
pan, the devices and the output (`C → Keys`); 4, the input.

| Choice | Effect |
| --- | --- |
| A. Keep 3 to 4 | The song of the screens fills the screen. 10 tracks scroll. |
| B. `auto` from 1 to 3: the tallest that fits every track | A short song looks as today. A long song gets 2 rows, then 1. The screen never scrolls while the tracks can fit at 1 row. |
| C. Default 2 | A short song loses the output row, which helps to read the routes. |
| D. The cursor's track is taller | The rows move under the eye at each `j` and `k`. Bad for keys that must feel fast and stable. |

**Recommendation: B**, and 4 rows only by `z+` or `:set track_height=4`. The marks of this design
work at every height: the fold column (`▸ ▾ │ ╰ ┆`) is on the first row, the group overview `━`
is on the first row, and `⧉` is before the name. What goes at 2 rows is the route row (`→ Keys`).
So `K` and the mixer must show the route, and they do.

## 8. Other problems that the screens show

Found in the runs. They are not in TASK-226. Each needs a bug ticket (the orchestrator decides).

1. **`:scope.write!` of a view with no time takes every region of the song.** `:narrow Keys`,
   `:scope.write! Keys2` (`v2.txt`, shots O and P): `6 markers and regions inside it`, and the
   song has no region row after it. subprojects.md says that a region over the whole time stays in
   the song. A view with no time takes the song from its start to the end of its clips, so each
   region falls inside it.
2. **`:scope.write!` makes the group track the return row when not every track moved in.** Shots 9
   and F. subprojects.md says it does so only "when the view is a group whose tracks all move in".
   The routing part decides what it should do.
3. **Inside a subproject inside a subproject, the status line has no song bar.** `v1.txt`, shot J:
   `Song › ⧉Beat › ⧉Roll 1.1`, without `(…)`. It can be part of TASK-226 #2.
4. **In a narrow split, the second ruler row writes a region name over bar numbers**: `Verse 251`
   (`v1.txt`, shot K). It is the same cause as TASK-226 #3.

## 9. The build tickets, in order

Each ticket changes screens. Each gets a golden screen test with `T.expect_screen` at 100x30, with
real keys, for each screen that it changes. The order puts first what the user sees most, and what
the later tickets build on. The sizes use the sizes of Backlog (XS, S, M, L).

| # | Title | Size | Screens that change | Depends on |
| --- | --- | --- | --- | --- |
| UX-1 | The window bar: the scope path and the cursor in the two left cells of the ruler, per window; no `›` sign in the track column; `@` for song bars in the status line | S | Every arrange screen (4.1, 4.2, 4.3, 4.7); the status line in a scope | TASK-226 |
| UX-2 | The end of a scope: `┃` on the ruler and every row, nothing after it, `end of Verse · zw: the song`; no region row when it only repeats the scope; the `@` row of song bars | S | 4.1; inside a subproject (shot 12, 13); a block scope | UX-1, TASK-226 |
| UX-3 | The rows of a subproject under its return row: `▾`/`▸` and `⧉` and `×2` on the return row, the `┆` guide, no song numbers, the light header, blank outside the blocks, the closing line, the message | M | 4.4 (shot 11); 4.5 after `za` | UX-1 |
| UX-4 | `K` as a float: sized to its text, under the cursor, `K` again to go in; the words of the vocabulary (`subproject`, `places`, `@`); `:info` keeps the page | M | 5 (shots 10, H, L, M, N) | |
| UX-5 | `:scope.write!` keeps the song's groups and routes (choice B), names each route that changes, `stems` word; a view with no time keeps the song's regions (bug 8.1); fix 8.2 | M | 4.5 (shots 8, 9, E, F, O, P); subprojects.md | |
| UX-6 | Overviews: `━` on a group row, the members of a folded group, the frame of a closed block fold with its bars and tracks (takes in TASK-225), the default name of a block fold | S | 4.2 (shots 2, 3b); 4.3 (shot 4) | TASK-224 |
| UX-7 | `track_height=auto` from 1 to 3 | XS | Every arrange screen with more tracks than fit (shots A, B); the golden screens of other tests that use auto | UX-1 to UX-6 (their golden screens are made at the height of today first) |
| UX-8 | `:nest.new` and `:import` put the return row where `o` puts a track | XS | 4.6; shots 13, 14 | |
| UX-9 | Words and docs: `nest` to `subproject` in `K`, messages and the picker (`nest` mark to `⧉`); `about-scopes.md`, `narrowing.md`, `subprojects.md`, `keys.md`, the tutor's lessons on scopes | S | The picker `<Space>zz`; the messages | UX-1 to UX-8 |

UX-1 to UX-4 and UX-6 change only views (Teal, `runtime/lua/paw/views/arrange.tl`,
`arrange_track.tl`, `trackcolumn.tl`, `folds.tl`, `defaults/modal.lua`). UX-5 changes
`nest.tl` and the scope writer. No ticket touches the engine. The scene of the arrange view carries
the new marks, so the window can draw them later (`paw-gui` stays paused).

## 10. Questions for the owner

1. **`:scope.write!` and the groups (routing, its own row).** Keep the group and put the return row into it
   (B), or keep today's behavior (A)? Recommendation: B. It keeps the sound and changes nothing that
   the user did not ask for.
2. **The window bar (UX-1).** Use the two left cells of the ruler (no new row), or a new row at the
   top of each window, as Neovim's `winbar`? Recommendation: the two cells. They are empty today, and
   a row is expensive on a screen of 30 rows.
3. **A view over several buses (routing, its own row).** Make stems by default, so the sound stays the same,
   or one return row to the master with a message that names the buses? Recommendation: one row
   and the message, with `stems` as a word on the command. Stems add rows, and most users want one
   row for a section.
4. **The rows that `za` shows under a return row (4.4).** Show a closing line `end of ⧉Bridge`
   (one row more), or only the `┆` guide? Recommendation: the closing line. The user's problem was
   "which Piano is which", and the line answers it at a glance.
5. **The track height.** `auto` from 1 to 3 (B)? Recommendation: B.
6. **`K`.** A float with a maximum of half the window, and `:info` for the full page?
   Recommendation: yes.
7. **`@` for song bars on the screen (the vocabulary).** The ruler and status line show `@9`, as the user
   types `@9|`. Or keep `(9.1)` in brackets? Recommendation: `@`. One sign for one idea.
8. **The default name of a block fold (4.3).** `Piano, Pad 9-24` instead of `Fold 1`?
   Recommendation: yes. The name then says what the fold holds.
9. **`:nest.new` in a group (6.4).** Put the return row in the cursor's group, as `o` does?
   Recommendation: yes.
