# Motions, operators and modes

<!-- tags: terminal grammar -->

The keys of paw work like the keys of Neovim, on a timeline instead of a text. In the arrange view, a part is a line, a beat is a column and a clip is a word, and in the piano roll a pitch is a line and a note is a word. All keys are mappings in `runtime/lua/paw/defaults/`, made with the functions of [your configuration](../how-to/configure-paw.md), and you can change each of them.

The arrange view and the piano roll share the keys below. The keys of one view are on its page, which are [the arrange view](arrange-view.md) and [the piano roll](piano-roll.md), and [The key rule](key-rule.md) gives the meaning that a key has in every view.

## Motions

A motion moves the cursor. A count repeats it: `3W` moves three bars.

| Keys | Arrange view | Piano roll |
| --- | --- | --- |
| `h` `l` | a grid step | a grid step |
| `j` `k` | the next and the previous part | a semitone down and up |
| `Ctrl-d` `Ctrl-u` | four parts down and up | an octave down and up |
| `w` `b` `e` | the start of the next clip, the start of this clip, the end of this clip | the same for notes, at any pitch |
| `W` `B` | the next and the previous bar | the same |
| `0` `^` `$` | the start of the project, the first clip of the part, the end of its last clip | the start of the clip, the first note, the end of the clip |
| `gg` `G`, `5G` | the first and the last part, part 5 | the highest and the lowest note |
| `)` `(` | | the next phrase, the start of this phrase or the one before |
| `]c` `[c` | | the next chord, the chord before: where two or more notes start together |
| `9\|`, `:9` | bar 9; in a scope with time, its bar 9 | |
| `@9\|`, `:@9` | bar 9 of the song, also in a scope with its own bars | |
| `]z` `[z` | the next scope beside this window's scope, the one before ([Scopes](narrowing.md)) | |
| `/name`, `n` `N`, `*` | finds a clip or part by name, the next match, the previous match, the next clip with the name of this clip | finds a note by its pitch name (`/c4`) |
| `gP` | the playhead | |

To see the counts, `:set relativenumber` shows how many `j` or `k` go to each part, and `:set relativebar` shows how many `W` or `B` go to each bar. [The part column](arrange-view.md#the-part-column) has the details.

## Marks and jumps

| Keys | Effect |
| --- | --- |
| `ma`, `'a`, `''` | Sets mark `a`. Goes to mark `a`. Goes to the place before the last jump. |
| `:delmarks a b c-e`, `:delmarks!` | Removes marks, the same as in Vim (`:delm`). `Tab` completes the marks that are set. With `!`, removes every lowercase mark. |
| `Ctrl-o` `Ctrl-i` | Moves back and forward through the places of the jumps. To enter a scope, to leave it and `]z` are jumps, and a jump keeps the scope of the window. |
| `g;` `g,` | Moves back and forward through the places of the edits (`3g;` three edits back). Each view keeps its own list. |
| `` `. ``, `'.` | Goes to the place of the last edit. |
| `:changes` | Lists the places of the edits. |
| `g'`, `g"`, `gx`, `gX` | Puts a marker (a name on the ruler) at the cursor. Chooses a marker from a list. Removes the marker at the cursor. Removes the region that the cursor is in. |

## Operators

An operator acts on what a motion moves over, on a text object, or on a selection. An operator typed two times acts on whole lines, so `dd` deletes a part and `3dd` deletes three parts.

| Keys | Arrange view | Piano roll |
| --- | --- | --- |
| `d` | deletes: `dw` up to the next clip, `d2W` two bars, `dd` the part | deletes notes: `dw`, `d4l`, `dd` every note of the pitch |
| `y` | copies to a register, for `p` | the same |
| `c` | empties the time, and opens a new clip there to enter notes | deletes, then enters notes |
| `>` `<` | moves clips a grid step later or earlier (`>>` all clips of the part) | the same for notes |
| `=` | snaps clips and their notes to the grid | snaps notes to the grid |
| `gc` | mutes or unmutes clips, `gcc` the part | |
| `gl` | sets the playback loop to it and turns looping on: `glic` the clip, `gl4W` four bars, `glar` the region | the same |
| `zn` | enters it as a scope, in this window: `znar` the region, `znag` the group, `znit` the part; `znn` the innermost scope at the cursor ([Scopes](narrowing.md)) | |
| `zf` | folds it: `zfar` the region into one column, `zfag` the group into one row, `Vjjzf` the parts into one row ([Folds](narrowing.md#folds)) | |

## Text objects

A text object names a part of the project.

| Keys | Arrange view | Piano roll |
| --- | --- | --- |
| `ic` | the clip under the cursor | the chord at the cursor |
| `ac` | the clip and the gap after it | the chord as the harmony reads it |
| `ib` | this bar (`2ib` two bars) | this bar |
| `il` | the loop | |
| `ir` | the innermost region that the cursor is in, on this part (`2ir` the region around it) | the region that the cursor is in |
| `ar` | the innermost region that the cursor is in, on every part (`2ar` the region around it) | the same |
| `it` | everything on the part | |
| `ie` | the entire project | every note of the clip |

In a window narrowed to a scope ([Scopes](narrowing.md)), the text objects take only what the scope shows. `ie` is the entire scope, its parts in its time. `ar` is the region on the parts of the scope, cut at the edges of its time, and `ir` and `it` are cut there too. So in `Song › Bridge › Strings`, `dar` deletes the clips of the strings in the region, and the other parts keep theirs.

In visual mode, the same text object again takes in one more, as `iw` does in Vim, so `vic` and then `ic` selects this chord and the next.

### Objects of the piano roll

In the piano roll, the text objects are the objects of the music. `i` names the object, and `a` names the object with what is around it. A count takes more of the same object, and each operator acts on each object, so `div` deletes a voice, `>ic` moves a chord later, `yip` copies a phrase, and `vi=` and then `+` transposes every note of a pitch.

| Keys | `i`: the object | `a`: with what is around it | A count |
| --- | --- | --- | --- |
| `in` `an` | the note under the cursor | the note and the rest after it, up to the next note of its voice | `3in`: the note and the next two notes of its voice |
| `ic` `ac` | the chord: the notes that start with the note under the cursor. Away from a note, the notes that sound at the cursor | the chord as [the harmony](harmony.md) reads it: every note of its phrase that starts while that chord holds, also the notes of a broken chord. Where the harmony reads no chord, the notes that sound with the chord | `2ic`: the chord and the next place where two or more notes start together |
| `ip` `ap` | the phrase: the notes with no rest between them longer than `paw.opt.phrase_rest` (half a beat). From a rest, the next phrase | the phrase and the rest after it | `2ip`: two phrases |
| `iv` `av` | the voice of the note: the bass if the note is the lowest of the notes that sound with it, else the line at its place from the top (the top line, the second line) | the voice and the notes that double it, on the same pitch class, at the same time | |
| `i=` `a=` | every note of the pitch | every note of the pitch class, in every octave | |
| `ib` `ab` | the bar | the same | `2ib`: two bars |
| `ir` `ar` | the region of the song that the cursor is in | the same | `2ir`: the region around it |
| `ie` `ae` | every note of the clip, or of the clips that the roll edits | the same | |

A note that sounds alone is in the top line and in the bass. Two notes can overlap for less than an eighth of a beat, and they are then legato, which means the first note is not a second voice.

A voice, a pitch class or a chord can leave other notes between its notes. The object names its notes, and an operator does not touch the other notes. In visual mode, such a selection shows on its notes.

`)` and `(` go to the next phrase and to the start of this phrase, in the same way as the sentence motions of Vim. Extensions add objects with `paw.keymap.textobject`, and the articulations extension adds `ia` (the notes with the same articulation).

## Visual mode

Visual mode selects first, and an operator or a key then acts on the selection.

| Keys | Arrange view | Piano roll |
| --- | --- | --- |
| `v` | selects time, across the parts that `j` and `k` add | selects time at every pitch |
| `V` | selects whole parts | selects whole pitches |
| `Ctrl-v` | | selects a rectangle |

| Keys | On a selection |
| --- | --- |
| `x` | Deletes it. |
| `~` | Mutes it. |
| `J` | Joins the clips. |
| `Ctrl-a` `Ctrl-x`, `+` `-` | Transposes it. Over whole parts (`V`), changes the volume. |
| `]` `[` | Over whole parts (`V`), changes the pan. |
| `p` | Replaces it with the register. |
| `o` | Goes to the other end. |
| `gv` | Selects the last selection again. |
| `:` | Types a command for the selection. The line starts with `'<,'>`, the name of the last selection. |

A selection includes the note (or drum hit) under its far end, in the same way that the selection of Vim includes the character under the cursor.

## Registers

| Keys | Effect |
| --- | --- |
| `p` | Pastes after the clip or note under the cursor. Parts go below. |
| `P` | Pastes at the cursor. Parts go above. |
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

The key or the command that changed something names a step, and a motion before it does not. A line typed after `:` names its step, and a value set to the value that it has makes no step. The undotree extension adds `g-`, `g+`, `:earlier 2m` and `:later 5`, to return in time across branches. [Options](options.md#undo-and-safety) gives the size of the history.

## Ranges

`:` also takes the Ex commands of Vim over bars and parts, for example `:5,8d`, `:%s/c4/d4/g` and `:g/vel<20/d`. A command can also take bars before its name, as in `:5,8notation.transpose 2`. [Ex commands](ex.md) describes them.
