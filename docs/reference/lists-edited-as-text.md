# Lists edited as text

<!-- tags: text-buffers textbuf -->

paw shows some parts of the project as plain text, in a buffer that lists the things with one on each line. You edit the lines with the keys of Vim, and `:w` makes the project agree with the lines.

## The buffers

| Buffer | Example line | A line is |
| --- | --- | --- |
| `paw://parts` | `Bass  vol -6.0  pan L10  M--  out Bus A  group  in Strings  color #ff9e64  ▸ Synth, EQ` | a part: its name, volume in dB, pan, flags (`M` muted, `S` soloed, `R` armed, `-` not), the part that it plays into (the master without `out`), `group` on a group, the group that it is in, its color, its devices |
| `paw://sends` | `Drums  → Verb  -12.0 dB  post` | a send: the part that it comes from, the part that it goes to, its level, `pre` or `post` the fader |
| `paw://part/2/devices` | `Comp  on  wet 80%  preset Glue` | a device of the second part (`master` for the master part): the device, `on` or `off` (bypassed), its wet share, its preset |
| `paw://markers` | `9.1  Chorus  to 13.1  color #9ece6a` | a marker at bar 9, beat 1. With `to`, a region that ends at bar 13. |

`:e paw://parts` shows a buffer in this window, `:vs paw://sends` next to
it, and `:textbuf.open markers` below it.

Two spaces separate the fields, and every field after the first starts with its word, so the fields can be in any order. A field that is missing has its default value, which is 0 dB, the center, not muted, the master, no group and no color. A name that has two spaces in it goes in quotes.

## Keys

All keys of the text work as in Vim, and the list below names the main groups.

- the motions `h` `j` `k` `l`, `w` `b` `e`, `W` `B` `E`, `0` `^` `$`, `f` `t` `F` `T` `;` `,`, `gg` `G`.
- the operators `d` `c` `y` `gu` `gU` `g~`, with every motion, counts and registers.
- `x` `X` `s` `S` `C` `D` `Y` `r` `~` `J` `p` `P`.
- insert mode with `i` `a` `I` `A` `o` `O`. `Tab` types the two spaces between fields.
- `v`, `V` and `Ctrl-v` selections. `I` and `A` type on every line of a block.
- `u` and `Ctrl-r` undo and redo the text, and `.` repeats the last change.

| Keys or command | Effect |
| --- | --- |
| `iw` `aw` | A word. |
| `if` | The value of the field under the cursor, so `cif` changes it. |
| `af` | The whole field. |
| `Ctrl-a` `Ctrl-x` | Add or subtract 1 (or the count) to the number under or after the cursor, and keep its decimals. On a volume it is a dB, on the position of a marker a bar. On a selection, the number of each line. |
| `:s/vol -6/vol -9/g` | Changes text, over a range of lines. |
| `:sort` | Sorts the lines. `!` reverses, `n` sorts by number, `i` ignores case. |
| `:d`, `:y`, `:m 0`, `:normal` | Take ranges of lines, e.g., `:%s`, `:2,4d` and `:.,$sort`, and `:'<,'>` after `:` in a selection. |
| `:5` | Goes to line 5. |
| `Enter` | On a part: opens its devices (`paw://part/N/devices`). On a device: shows it in the device panel. On a marker: puts the cursor there. |
| `-` | In a list of devices: returns up to the parts. |

## What an edit does

| Edit | What `:w` does |
| --- | --- |
| a field changed (`cw` on a name, `Ctrl-a` on a volume, `rM` on the flags) | changes that field of that thing, and only that field |
| `dd` | deletes the part, send, device or marker |
| `yyp`, `yyP` | copies it: a part with its devices, clips and automation, a device with its state |
| `ddp`, `:m`, `:sort` | moves it. Parts and devices go in the order of the lines. |
| a new line (`o`) | makes a new thing: `Lead  vol -12  ▸ synth` a part with a synth, `reverb` a device, `17.1  Bridge` a marker |

Each line has the id of its thing, which does not show, so a renamed line is a rename and a moved line is a move, not a delete and a new thing. The gutter shows the place of the line when paw read it, with `~` on a changed line, `+` on a new line or a copy, and `!` on a line that paw cannot read, and the bottom line gives the reason for that last case. The title shows `[+]` while the buffer has changes.

## Write

`:w` shows the plan in a float, with lines such as `rename Bass → Bassline`, `Bassline: volume -6.0 → -3.0 dB` and `delete Pad (2 devices, 4 clips)`.

| Key or command | Effect |
| --- | --- |
| `y`, `Enter` | Applies the plan as one undo step. One `u` in any other window undoes all of it. |
| `n`, `Esc` | Returns to the buffer. |
| `:w` without changes | Saves the project, as in other buffers. |
| `:e!` | Discards the changes and reads the buffer again. |
| `:q` | Does not close a window on a buffer with changes. `:q!` does. |
| `:w!` | Applies your changes over changes made elsewhere. |

A line that paw cannot read stops the write, and the cursor goes to it.

A buffer without changes follows the project, so if you rename a part in the arrange view, its line changes. A buffer with changes shows `changed elsewhere` when the project changes, and `:w` then refuses. `:w!` applies your changes, but only the fields that your lines changed, so a volume moved elsewhere in the meantime keeps its new value.

In the graphical window, a text buffer shows in a pane, and `:textbuf.window` (`Ctrl-w f`) shows it in a window of its own with the same keys.

An extension makes its own kind of list with `paw.textbuf.kind` (see
[The Lua interface](scripting.md)).
