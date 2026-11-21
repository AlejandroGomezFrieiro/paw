# Motions, operators and modes

<!-- tags: terminal grammar -->

The keys of paw work as the keys of Neovim, on a timeline in place of a
text. In the arrange view, a track is a line, a beat is a column and a
clip is a word. In the piano roll, a pitch is a line and a note is a word.
All keys are mappings in `runtime/lua/paw/defaults/`, made with the
functions of [your configuration](../how-to/configure-paw.md). You can
change each of them.

This page gives the keys that the arrange view and the piano roll share.
The keys of one view are on its page: [the arrange view](arrange-view.md),
[the piano roll](piano-roll.md). [The key rule](key-rule.md) gives the
meaning that a key has in every view.

## Motions

A motion moves the cursor. A count repeats it: `3W` moves three bars.

| Keys | Arrange view | Piano roll |
| --- | --- | --- |
| `h` `l` | a grid step | a grid step |
| `j` `k` | the next and the previous track | a semitone down and up |
| `Ctrl-d` `Ctrl-u` | four tracks down and up | an octave down and up |
| `w` `b` `e` | the start of the next clip, the start of this clip, the end of this clip | the same for notes, at any pitch |
| `W` `B` | the next and the previous bar | the same |
| `0` `^` `$` | the start of the project, the first clip of the track, the end of its last clip | the start of the clip, the first note, the end of the clip |
| `gg` `G`, `5G` | the first and the last track, track 5 | the highest and the lowest note |
| `9\|`, `:9` | bar 9 | |
| `/name`, `n` `N`, `*` | finds a clip or track by name, the next match, the previous match, the next clip with the name of this clip | finds a note by its pitch name (`/c4`) |
| `gP` | the playhead | |

To see the counts, `:set relativenumber` shows how many `j` or `k` go to
each track, and `:set relativebar` how many `W` or `B` go to each bar.
See [The track column](arrange-view.md#the-track-column).

## Marks and jumps

| Keys | Effect |
| --- | --- |
| `ma`, `'a`, `''` | Sets mark `a`. Goes to mark `a`. Goes to the place before the last jump. |
| `:delmarks a b c-e`, `:delmarks!` | Removes marks, as in Vim (`:delm`). `Tab` completes the marks that are set. With `!`, removes every lowercase mark. |
| `Ctrl-o` `Ctrl-i` | Moves back and forward through the places of the jumps. |
| `g;` `g,` | Moves back and forward through the places of the edits (`3g;` three edits back). Each view keeps its own list. |
| `` `. ``, `'.` | Goes to the place of the last edit. |
| `:changes` | Lists the places of the edits. |
| `g'`, `g"`, `gx`, `gX` | Puts a marker (a name on the ruler) at the cursor. Chooses a marker from a list. Removes the marker at the cursor. Removes the region that the cursor is in. |

## Operators

An operator acts on what a motion moves over, on a text object, or on a
selection. An operator typed two times acts on whole lines: `dd` deletes a
track, `3dd` three tracks.

| Keys | Arrange view | Piano roll |
| --- | --- | --- |
| `d` | deletes: `dw` up to the next clip, `d2W` two bars, `dd` the track | deletes notes: `dw`, `d4l`, `dd` every note of the pitch |
| `y` | copies to a register, for `p` | the same |
| `c` | empties the time, and opens a new clip there to enter notes | deletes, then enters notes |
| `>` `<` | moves clips a grid step later or earlier (`>>` all clips of the track) | the same for notes |
| `=` | snaps clips and their notes to the grid | snaps notes to the grid |
| `gc` | mutes or unmutes clips, `gcc` the track | |
| `gl` | loops it: `glic` loops the clip, `gl4W` four bars | the same |

## Text objects

A text object names a part of the project.

| Keys | Arrange view | Piano roll |
| --- | --- | --- |
| `ic` | the clip under the cursor | the notes that sound together at the cursor |
| `ac` | the clip and the gap after it | those notes and every note that overlaps them |
| `ib` | this bar (`2ib` two bars) | this bar |
| `il` | the loop | |
| `ir` | the region that the cursor is in, on this track | |
| `ar` | the region that the cursor is in, on every track | |
| `it` | everything on the track | |
| `ie` | the entire project | every note of the clip |
| `in` | | the note under the cursor |

## Visual mode

Visual mode selects first. Then an operator or a key acts on the selection.

| Keys | Arrange view | Piano roll |
| --- | --- | --- |
| `v` | selects time, across the tracks that `j` and `k` add | selects time at every pitch |
| `V` | selects whole tracks | selects whole pitches |
| `Ctrl-v` | | selects a rectangle |

| Keys | On a selection |
| --- | --- |
| `x` | Deletes it. |
| `~` | Mutes it. |
| `J` | Joins the clips. |
| `Ctrl-a` `Ctrl-x`, `+` `-` | Transposes it. Over whole tracks (`V`), changes the volume. |
| `]` `[` | Over whole tracks (`V`), changes the pan. |
| `p` | Replaces it with the register. |
| `o` | Goes to the other end. |
| `gv` | Selects the last selection again. |
| `:` | Types a command for the selection. The line starts with `'<,'>`, the name of the last selection. |

A selection includes the note (or drum hit) under its far end, as the
selection of Vim includes the character under the cursor.

## Registers

| Keys | Effect |
| --- | --- |
| `p` | Pastes after the clip or note under the cursor. Tracks go below. |
| `P` | Pastes at the cursor. Tracks go above. |
| `3p` | Pastes three times, one after the other. A next `p` continues from the last one. |
| `"a` | Names register `a` for the next command (`"ayy`, `"ap`). |
| `"_` | The register that keeps nothing. |
| `"0` | The register of the last copy. |
| `:registers` | Shows the registers. |

Pasted time replaces the music that was there. With `paw.opt.ripple = true`,
a delete closes the gap and a paste moves the music after it.

## Repeat and macros

| Keys | Effect |
| --- | --- |
| `.` | Repeats the last change, with a new count if you give one. |
| `qa` | Records keys into register `a`, until the next `q`. |
| `@a` | Plays the keys of register `a`. `5@a` plays them five times. |
| `@@` | Plays the last macro again. |
| `@:` | Repeats the last command line. |

## Undo

| Keys | Effect |
| --- | --- |
| `u` | Undoes the last step, and shows its name: `undid Delete the clip`. |
| `Ctrl-r` | Redoes the step. |

The key or the command that changed something names a step. A motion
before it does not. A line typed after `:` names its step. A value set to
the value that it has makes no step. The undotree extension adds `g-`,
`g+`, `:earlier 2m` and `:later 5`, to return in time across branches.
See [Options](options.md#undo-and-safety) for the size of the history.

## Ranges

`:` also takes Vim's Ex commands over bars and tracks: `:5,8d`,
`:%s/c4/d4/g`, `:g/vel<20/d`. A command can also take bars before its
name: `:5,8notation.transpose 2`. See [Ex commands](ex.md).
