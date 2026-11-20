# Keys, by idea
<!-- tags: course-keys -->

One page to keep next to the keyboard. The keys are written as Vim writes
them. `<C-r>` is Ctrl and r, `<A-j>` Alt and j, `<CR>` Enter, `<Esc>`
Escape. `,` is the leader key, and `\` the local leader of a view (the
notation popovers). **A** is the arrange view, **R** the piano roll, **M**
the mixer, **D** the device panel.

The tests of the tutor compare every key
here with the mappings of paw. `?` in paw lists every key of the view that
you are in.

## The sentence

**count** · **operator** · **motion** or **text object**, for example `3>ic`, `d2W`, `yic`,
`gl4W`. An operator typed twice takes whole rows (tracks in A, pitches in R):
`dd`, `3yy`. `"a` before it names a register: `"ayic`. `.` repeats the last
change.

## Move (motions)

| Keys | A | R |
| --- | --- | --- |
| `h` `l` | a grid step | a step in time |
| `j` `k` | next, previous track | a semitone down, up |
| `<C-d>` `<C-u>` | four tracks down, up | an octave down, up |
| `w` `b` `e` | next clip's start, this clip's start, this clip's end | the same for notes |
| `W` `B` | next, previous bar | next, previous bar |
| `0` `^` `$` | start of the project, first clip, end of the last clip | start of the clip, first note, end of the clip |
| `gg` `G` | first, last track (`5G` track 5) | highest, lowest note |
| `5\|` | bar 5 (also `:5`) | |
| `gP` | cursor to the playhead | |
| `]'` `['` | next marker or region, the one before | |
| `zz` `zh` `zl` | center the cursor, scroll a bar | |

These keys only move, in every view. In **M**, `h` `l` are strips. `j` `k`
are the rows of a strip (devices, sends, fader, pan, mute, solo, arm), `gg`
`G` its top and bottom, `0` `$` the first and last strip. In **D**, `j` `k`
are rows, `w` `b` devices, `e` the last parameter of a device.

## Act (operators and single keys)

| Keys | A | R |
| --- | --- | --- |
| `d` | delete | delete notes |
| `y` | yank | yank notes |
| `c` | empty and enter notes in a new clip | delete and enter notes |
| `>` `<` | move clips later, earlier | move notes |
| `=` | snap clips and notes to the grid | snap notes |
| `gc` | mute or unmute clips (`gcc` the track) | |
| `gl` | loop it | loop it |
| `x` | delete the clip | delete the note |
| `D` `C` `Y` | delete, change, yank to the end of the track | to the end of the clip |
| `p` `P` | paste after the clip (tracks below), at the cursor (tracks above) | after the note, at the cursor |
| `&` `S` `J` `~` | repeat, split, join, mute the clip | |
| `H` `L` `<A-h>` `<A-l>` | move the clip, shorten and lengthen it | move the note, shorten and lengthen it |
| `+` `-` `<C-a>` `<C-x>` | track volume (`6<C-x>` six dB down) | the note's pitch (`12<C-a>` an octave up) |
| `[` `]` | pan | velocity |
| `<CR>` | open the clip in R | add or remove a note |
| `gh` | | hear the pitch |
| `ga` `gE` | | edit the clip of another track's note under the cursor instead; edit it too, or no longer |
| `gn` `gN` | | the next, the previous clip edited becomes the active one |
| `gC` `gX` | the lane's curve (on a lane row; `gc` turns it off and on) | the strip's controller as a curve, the note's own |
| `o` `O` | add a track below, above | |
| `grn` `grc` | rename the track, the clip | |
| `gw` `gW` | put a warp marker on an audio clip at the cursor, take off the nearest | |
| `<A-j>` `<A-k>` | move the track down, up | |
| `M` `s` `r` | mute, solo, arm the track | |
| `zn` `zw` | narrow to the group at the cursor, in a tab of its own; widen again | |
| `,vn` `,va` `,vr` `,vx` `,vl` | a new VCA over the selected tracks; put them under a VCA; take them out of their VCAs; take the VCA at the cursor away; link the faders of a group | |
| `I` `<A-i>` | choose the input (audio, MIDI port and channel), monitor it | |
| `a` | add a device | enter notes after the note |
| `A` | add a volume automation point | |
| `,at` `,ax` | automation off and on, clear it | |
| `,am` | the track's automation mode: read, touch, latch, write, off in turn | |
| `]t` `[t` | the clip's next take, the one before | |
| `zt` `zT` | show or hide the track's take lanes, the tempo lane under the ruler | |
| `g'` `g"` | put a marker at the cursor; go to one from a list | |
| `gx` | remove the marker or region at the cursor; a right click on its name under the ruler has "Remove" | |
| `K` | describe what is under the cursor | the note |
| `u` `<C-r>` | undo, redo (`3u`) | the same |

The same keys mean the same in every view:

| Keys | In every view |
| --- | --- |
| `+` `-` (`<C-a>` `<C-x>` with a count) | the main value under the cursor |
| `[` `]` | the second value |
| `>` `<` | move in time |
| `K` | describe |
| `ge` | the window of the plugin |
| `gc` | mute or bypass |
| `gC` `<CR>` | a curve |
| `<Esc>` | cancel, and stay in the view |
| `<C-w>p` | the window before |

The full rule is in [The key rule](key-rule.md).

In **D**, `A` automates the parameter, and `gC` or `<CR>` edits its curve.
On a lane row, `gC` or `<CR>` edits the curve of the lane, and `gc` turns the
lane off and on.

In the **curve editor**:

| What | Keys |
| --- | --- |
| move the cursor in time and value | `h` `l` `j` `k` |
| from point to point | `w` `b` |
| add a point | `o` `A` |
| remove it | `x` |
| raise and lower it | `+` `-` |
| type its value | `c` |
| its shape | `~` |
| its bend | `[` `]` |
| draw with the cursor until `<Esc>` | `i` |
| points | `d` `y` `p` `>` `<` |
| smooth, thin, quantize | `gs` `gS` `gq` |
| a wave (then `<Tab>` `<C-n>` `<C-y>`) | `g~` |

| Keys | M |
| --- | --- |
| `+` `-` | the row under the cursor: the fader, a send, the pan, a switch |
| `[` `]` | pan |
| `x` | clear the row |
| `<CR>` | type it |
| `M` `s` `r` `I` | mute, solo, arm, input |
| `gc` | mute |
| `dj` `yj` `p` | rows |
| `dd` `yy` `p` | tracks |
| `V` with `-` | several faders |

| Keys | D |
| --- | --- |
| `+` `-` | change the parameter (`10+`) |
| `a` | add a device |
| `x` | remove (on a parameter: its default) |
| `gc` | bypass |
| `c` | a preset or a value |
| `[p` `]p` | step presets |
| `,w` | save a preset |
| `yy` `dd` `p` | devices (`yy` on a parameter: its setting) |
| `<A-j>` `<A-k>` | reorder |
| `gS` | the track that the device listens to (side-chain) |
| `O` | where its further output pairs play |
| `\p` | pin the panel to its track, or follow the cursor again |

## Name a region (text objects)

| Keys | A | R |
| --- | --- | --- |
| `ic` | the clip under the cursor | the notes that sound together at the cursor |
| `ac` | the clip and the gap after it | the same and every note that overlaps them |
| `ie` | the entire project | every note of the clip |
| `in` | | the note under the cursor |
| `ib` | this bar (`2ib` two) | this bar |
| `il` | the loop | |
| `it` | everything on the track | |
| `ie` | the entire project | every note of the clip |

## Select (visual mode)

| Keys | |
| --- | --- |
| `v` `V` `<C-v>` | select time, whole rows, a block (R) |
| `o` | go to the other end |
| `gv` | select the last selection again |
| `x` `p` | delete it, replace it with the register |
| `<CR>` | (A) edit the notes of the MIDI clips selected together in R |
| `~` `J` | mute, join (A) |
| `<C-a>` `<C-x>` `+` `-` | transpose; a count first is how much: `12<C-a>` (over whole tracks, `V`: the volume) |
| `:` | a command for the selection: the line starts `:'<,'>` |
| `<Esc>` | back to normal mode |

## Draw notes (insert mode, R)

| Keys | |
| --- | --- |
| `i` | draw a note from the cursor (in A: in the clip under the cursor, or a new one) |
| `a` | draw from where the note under the cursor ends |
| `l` `h` | the note a step longer, shorter; a count first: `4l` |
| `k` `j` `<C-u>` `<C-d>` | the note up, down a semitone; an octave (`K` `J` too) |
| `<CR>` | keep it, draw the next where it ends |
| `<Space>` | keep it, draw the next after a step's rest |
| `o` | keep it, draw another from the same start, for a chord |
| `<BS>` | take back the note kept last |
| `[` `]` | softer, louder |
| `I` | keep what was drawn and type notes from here as on a piano (a piano's letter while drawing says so) |
| `<Esc>` | write what was drawn (one undo step; `.` draws it again) and return to normal mode |

## Enter notes as on a piano (`I`, R)

| Keys | |
| --- | --- |
| `I` | insert mode with the keyboard as a piano (`:set roll_insert=keys` for `i` too) |
| `a w s e d f t g y h u j k` | C, C♯, D, … up to the next C; a capital stays, for chords |
| `1` … `9` | notes that many steps long |
| `<Space>` `<BS>` | a rest; step back and remove |
| `z` `x` | octave down, up |
| `<Esc>` | back to normal mode |

## Write from the harmony (snippets, R)

| Keys | |
| --- | --- |
| `<C-s>`, `:snippet name` | choose a snippet and write it at the cursor or over the selection (`3<C-s>` three times); in normal, insert and visual mode |
| `<Tab>` `<S-Tab>` | while a snippet is active: its next choice, the one before (before a suggestion's keys) |
| `<C-n>` `<C-p>` | the choice's next value, the one before, written again in the same undo step |
| `<C-y>` `<Esc>` | done with the snippet |

See [Snippets](snippets.md) and [Completion](completion.md).

## Take a suggestion (piano roll, normal and insert mode)

| Keys | |
| --- | --- |
| `<C-Space>` | ask the completion sources what comes next |
| `<Tab>` | accept the suggestion that shows |
| `<C-l>` | accept its next note or chord only |
| `<C-n>` `<C-p>` | the next, the previous alternative |
| `<A-1>` … `<A-9>` | show that alternative |
| `<C-e>` `<Esc>` | dismiss it (`<Esc>` leaves insert mode only when nothing shows) |
| `gh` | hear it from a bar before (normal mode) |

## Repeat and remember

| Keys | |
| --- | --- |
| `.` | repeat the last change (`3.` with a new count) |
| `"a` | the register for the next command; `"0` last yank, `"_` nowhere |
| `qa` … `q` | record keys into register a |
| `@a` `@@` `@:` | play them, the last macro again, the last command line |
| `ma` `'a` `''` | set mark a, go to it, back to before the jump |
| `:delmarks a-d` `:delmarks!` | remove marks (letters, ranges); all lowercase ones |
| `<C-o>` `<C-i>` | back, forward through jumps |
| `g;` `g,` | back, forward through the places the project was edited |
| `` `. `` `'.` | the place of the last edit |

## Play

| Keys | |
| --- | --- |
| `<Space>` | play, stop |
| `<S-CR>` | play from the cursor |
| `gs` `gp` | playhead to the start, to the cursor |
| `gL` `gm` | loop on and off, metronome |
| `gM` | count a bar in before recording, or not |
| `,b` | tap the tempo (the beat): press it on each beat, four times or more |
| `gI` | punch recording on and off (over a selection: punch there); `:preroll 2` plays two bars before the punch in |
| `R` | record armed tracks from the cursor (while the song plays, from the playhead), or stop recording; with the loop on, every time round is a take |

## Find

| Keys | |
| --- | --- |
| `?` | every key of this view |
| `:` | a command by name; `<Tab>` completes, `<Up>` for history |
| `/` `n` `N` `*` | find a clip or track by name (in R a pitch: `/c4`); next, previous; next with this name |
| `,,` | pick a command |
| `,fk` `,ft` `,fl` `,fa` `,fd` | pick a key, track, clip, device to add, device of the track |
| `,fm` `,fr` `,fn` `,ff` `,fo` `,fp` `,f.` | marks, registers, messages, files, options, every picker, the last picker |
| `,fR` | recent projects (`:recent 2` opens the second) |
| `,fh` `,f'` `,fg` `,fN` `,fw` | help tags, markers and regions, any text in the project, notes (pitch, lyric, articulation), sound files |
| `,fq` `,fu` `,fe` `,fs` `,fP` | the quickfix list, undo states, extensions, the Lua API, presets |
| `<C-Space>` | in a picker of presets, devices, files, beats, snippets, clips or notes: hear the item under the selection, or stop the sound; `<Esc>` takes back what was tried |
| in a picker | Tab marks a line, Ctrl-q sends the marked (or all) to the quickfix list; Ctrl-v, Ctrl-x, Ctrl-t open it beside, below, in a tab; Ctrl-r steps fuzzy, exact, regex; Alt-d deletes; Ctrl-Up what was typed before |
| `:vimgrep /pizz/` | every text in the project that matches, in the quickfix list |
| `:select clip[name~=pizz] > note[pitch>=C5]` | choose what a query finds; `:query` lists it |
| `]c` `[c` | next, previous clip of the same kind on the track (R: `]n` `[n`, note of the same pitch) |
| `]s` `[s` | next, previous track in the group (in a score, instrument in the group) |
| `[{` `]}` | up to the group the track is in; its last track (in a score, the group's first and last instrument); `[u` is `[{` too |
| `]u` | down into the group: its first track |
| `ig` `ag` | the group's tracks; with the group track |

Stop half way through a sequence and the keys that can follow are listed.

## Help

| Keys | |
| --- | --- |
| `:help` `:help gU` | the manual: its contents; where a key, command (`:help :s`), option (`:help 'timebind'`) or section is described; `<Tab>` completes |
| `<C-]>` | in help: follow the link, or find the word, under the cursor |
| `<C-t>` `<C-o>` | in help: back to where the link was followed from |
| `K` | in help: find the word under the cursor |
| `:helpgrep stretch` | every line of help that holds the words, in the quickfix list |

## Views and the program

| Keys | |
| --- | --- |
| `<Tab>` `<C-w>w` | next window |
| `<C-w>p` | back to the window that had the keyboard before (out of R, say) |
| `<C-^>` | show again what this window showed before (`:b #`) |
| `,m` `,d` `,p` `,l` | mixer, device panel, piano roll, session view (with the clip launcher extension) |
| `E` | in R: the clip's notes and controller moves as a list to change in place |
| `<C-w>c` `<C-w>o` | close this window, close every other window |
| `<C-w>s` `<C-w>v` | split the window, one above the other, side by side (`:vs roll` shows the piano roll beside) |
| `<C-w>h` `<C-w>j` `<C-w>k` `<C-w>l` | the window left, below, above, right |
| `<C-w>H` `<C-w>J` `<C-w>K` `<C-w>L` | move the window to the far left, bottom, top, right |
| `<C-w>x` `<C-w>r` `<C-w>T` | exchange the window with the next, rotate them, the window to a tab of its own |
| `<C-w>d` | in the graphical window: a view in a window of its own back into the main window, as a pane |
| `gt` `gT` | next tab, previous tab (`:tabnew` makes one) |
| `ge` | the track's plugin window |
| `zi` `zo` `[g` `]g` | zoom in, out; finer, coarser grid |
| `<C-s>` `:w` | save |
| `ZZ` `ZQ` `:q` | save and quit, quit, close the window (quit in the last one) |

## Edit lists as text (`:e paw://tracks`)

The tracks, sends, the devices of a track and the markers as lines of text
(`paw://tracks`, `paw://sends`, `paw://track/2/devices`, `paw://markers`).
Every motion, operator, count, register, selection and `.` works on the
text as in Vim. Nothing changes in the project until `:w`.

| Keys | |
| --- | --- |
| `cw` `cif` | change the name, change the value of the field under the cursor (`af` the whole field) |
| `dd`, `yy` `p`, `dd` `p` | delete; copy (a track with its devices and clips); move down |
| `o` `O` | a new line: a new track, device or marker (`Tab` types the space between fields) |
| `<C-a>` `<C-x>` | add, take 1 (or the count) from the number under or after the cursor |
| `rM` `rS` `rR` `r-` | on a track's flags: mute, solo, arm, or not |
| `<C-v>` `I` `A` `r` | in a block: type before or after it on every line, replace it |
| `u` `<C-r>` | undo, redo the text |
| `:w` | show what will change; `y` or `<CR>` applies it as one undo step, `n` returns to the buffer |
| `:e` | with `!` (`:e!`), throw the changes away and read again; `:w!` applies over changes made elsewhere since |
| `:sort` | sort the lines (`!` reversed, `n` by number); over ranges of lines too: `:%s/a/b/g`, `:2,4d`, `:m 0` |
| `<CR>` `-` | a track's devices, a device in the panel, go to a marker; back up to the tracks |
| `gw` | the buffer in a window of its own, in the graphical frontend |


## Files (`:e folder`)

A folder as lines to edit, and as a tree (`:Files`). The edits are those of
text. `:w` shows the plan and `y` does it. Deleted files go to the trash.

| Keys | |
| --- | --- |
| `<CR>` `-` | open (a folder goes in, a project opens, a sound is placed at the cursor); up |
| `go` `gh` `gH` | a sound on a new track; hear it; hear each as the cursor rests |
| `g.` | show or hide files that start with a dot |
| `za` `zR` `zM` | in the tree: open or close a folder, all, none |
| `cw` `dd` `yy` `p` `o` | rename (or move, with a path); trash; copy; new file (`name/` a folder) |

## Diagnostics and language servers

| Keys | |
| --- | --- |
| `]d` `[d` | next, previous diagnostic this view shows (R, A, M, D): the cursor goes there |
| `gK` | what the diagnostics and language servers say about what is under the cursor |
| `,ca` | fixes and actions for what is under the cursor; Enter makes one, as one undo step |
| `:diagnostics` | every diagnostic, grouped by what it is about; Enter goes there |
| `:lsp` | the language servers: `:lsp info`, `:lsp restart`, `:lsp log` |

## The quickfix list

| Keys | |
| --- | --- |
| `]q` `[q` | next, previous entry of the quickfix list (Problems: what went wrong anywhere): the view that shows it gets the keyboard |
| `]Q` `[Q` | last, first entry |
| `]l` `[l` | next, previous entry of the window's location list |
| `:copen` `:cclose` | the list's window along the bottom; in it `j` `k` move, `Enter` goes, `,ca` fixes, `q` closes |
| `:cdo` `:cfdo` `:cfix` | a command on every entry, on every track of them; make every fix (each one undo step) |
| `:colder` `:cnewer` `:cdiag` | the list before, after; a list of the diagnostics |

## Other tracks in the piano roll

In the piano roll, the notes of the other tracks show behind, in their
colors (as the visible tracks of REAPER). `]t` `[t` make the next or the
previous of them the edited track. `<Tab>` `<S-Tab>` go round them. With no
track shown, `<Tab>` is the next view. A click on a note behind makes its
track the edited track.

## Keys of the extensions

An extension adds its own keys. `?` in its view lists them, and its page
describes them:

- [Notation](../../extensions/notation/doc/reference.md#keys): the score, note entry by letter, the popovers, scores and parts
- [Articulations](../../extensions/articulations/README.md): the articulation of a note in the piano roll
- [The clip launcher](../../extensions/launcher/README.md): the session view (`,l`)
- [The tutor](../../extensions/tutor/README.md): the course (`:tutor`)
- [The doctor](../../extensions/doctor/README.md): the check of the hardware (`:doctor`)
- [Each other extension](extensions.md): the README of each one
