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
| `gC` | a curve (`<CR>` too on a lane row and in **D**) |
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
| `s` `M` `r` | solo, mute, arm the track |
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
| `]s` `[s` | next, previous track in the group (in a score, instrument in the group). With the sections extension, the next and previous section in A |
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

## Launch clips (the session view, `,l`)

With the clip launcher extension (`:ext.load launcher`). Its
[README](../../extensions/launcher/README.md) has all of its keys.

| Keys | |
| --- | --- |
| `h` `l` `j` `k` | previous, next track; next, previous slot (`gg` `G` first, last) |
| `<CR>` `L` | launch the slot (an empty one stops the track), launch the row as a scene |
| `S` `gS` | stop the track's clip, every clip |
| `B` `gB` | the track back to its timeline, every track |
| `s` `M` `r` | solo, mute, arm the track |
| `n` `i` | a new MIDI clip in the slot, open its notes |
| `x` `dd` `yy` `p` | empty the slot, yank its clip, paste a clip into it |
| `gp` | copy the arrange view's clip into the slot |
| `m` `gl` | the next launch mode (trigger, gate, toggle), legato on or off |
| `R` `4R` | record a bar, or four, into the empty slot from the next boundary |
| `grn` `C` | name the scene, capture what is launched into the timeline |

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

## The tutor

| Keys | |
| --- | --- |
| `:tutor` `:tutor 5` | the course where you left off, lesson 5 |
| `,hh` `,hn` `,hr` | a hint, skip the step, restart the lesson |
| `,hl` `,hq` | the lessons, leave the tutor |

## The doctor

| Keys | |
| --- | --- |
| `:doctor` `:doctor all` `:doctor input` | open the hardware check, run every check, run one |
| `j` `k` `<CR>` `A` `u` | on its page: choose a check, run it, run all, run those that need nobody |
| `y` `n` `s` ... | answer the question it asks (the keys are listed under it); `s` skips |
| `<Esc>` `q` | stop the run (the page stays), close the page |

## Notation

The notation extension (`,n` on a MIDI clip) has its own keys. They are in
[its README](../../extensions/notation/README.md), and `?` in the view lists
them. Notation is a view of the MIDI of the clip. Every edit in it is an
edit of the notes. What it decides (a spelling, a voice, a dynamic) is kept
next to the notes.

Normal mode takes the grammar of the piano roll. Insert mode enters notes by
letter:

| Keys | In insert mode |
| --- | --- |
| a capital letter | adds the note to the chord |
| Alt-2 to Alt-8 | add an interval above |
| `~` | ties |
| `t` | enters triplets |
| `v` | enters in the other voice |
| `R` | repeats the chord |
| the numbers | choose the value (5 a quarter) |

| Keys | In normal mode |
| --- | --- |
| <kbd>zg</kbd> | shows the engraved page as one long system |
| <kbd>zp</kbd> | shows it on pages under the title (`:notation.export pdf` writes them) |
| <kbd>zs</kbd> | starts a system at the bar under the cursor |
| <kbd>zj</kbd> | joins the bar to the system before |

The grammar in notation is about the score. Operators and text objects act
on what is written. Each edit is one undo step that `.` repeats.

- Objects:

  | Keys | Object |
  | --- | --- |
  | `in` `an` | the note (with its ties) |
  | `ic` `ac` | the chord (with grace notes and ties) |
  | `i.` `a.` | the beat (`a.` in every voice) |
  | `ib` `ab` | what the bar holds, the bar itself (`dab` removes it, `p` puts it back) |
  | `ip` `ap` | the phrase |
  | `iv` `av` | the voice |
  | `is` `as` | the staff |
  | `it` `at` | the tuplet |
  | `il` `al` | the slur |
  | `ie` | the clip (as in the piano roll) |
- Operators:

  | Keys | In notation |
  | --- | --- |
  | `gU` `gu` | up, down a step of the key (`3gUib` three steps) |
  | `g+` `g-` | up, down a semitone |
  | `g~` | respell |
  | `g(` | slur (`g(ip`) |
  | `g?` | retrograde (`2g?` inverts) |
  | `gq` | tidy |
  | `g@` | make the notes play as the marks say (a prompt shows it first) |
  | `!` | filter (`!ib reverse`, `!ib tac`) |

- Motions: `f` `F` `t` `T` and a letter, `;` `,` again (`,` waits a moment:
  it is the leader), `)` `(` by phrase, `]v` `[v` by voice, `Ctrl-j`
  `Ctrl-k` by staff.
- Note entry: `I` moves the music after the cursor later (`Insert` toggles
  it). `r` and a letter changes the pitch of a note. `R` changes pitches in
  turn (it does not record here). In insert mode, `/` `//` is a grace note,
  `Ctrl-t` a tuplet, `Ctrl-o` one normal command, `Ctrl-r` a register, and
  `Tab` the suggestion.

A popover writes everything that is not a note. The local leader (a
backslash) and a letter opens a one-line prompt at the caret. In visual
mode, the popover is for the selection. In insert mode, use it after
`Ctrl-o`, and the note entry continues after it.

In a popover, `Tab` completes, and `Up` gives the text typed before in that
popover. The page shows the result in the accent color while you type.
`Enter` writes it as one undo step, and `Esc` writes nothing. Each popover
is an Ex command, so `.`, `@:` and `:5,8notation.dyn p` do the same.

The popovers are keys of the notation view (its README has them all):

| Popover | Keys | Accepts |
| --- | --- | --- |
| dynamics | `\d` | `mp`, `sfz`, `fp`, `p subito`, `mp<f`, `<`, `>`, `niente<` |
| tempo | `\t` | `Allegro q=132`, `q.=60`, `rit.`, `accel.`, `a tempo` |
| time signature | `\m` | `6/8`, `3+3+2/8`, `C`, `¢` |
| key | `\k` | `Eb`, `f#m`, `D dorian` |
| clef | `\C` | `bass`, `treble8`, `alto`, `tenor` |
| barlines, repeats, endings | `\b` | `\|\|`, `\|.`, `\|:`, `:\|`, `1.`, `2.` |
| text | `\X` | `dolce` |
| rehearsal mark | `\r` | `A` (Enter alone: the next letter) |
| chord symbols | `\q` | `Cmaj7`, `G/B`, `N.C.`; `Space` next beat |
| lyrics | `\l` | syllables; `Space` next note, `-` hyphen, `_` extender; `verse=2 ` first |
| intervals | `\i` | `3`, `-6`, `8`, `m3`, `P5` |
| tuplets | `\3` | `3`, `5:4` |
| voice | `\v` | `1` to `4` |
| ornaments | `\o` | `tr`, `mordent`, `turn`, `fermata` |
| playing techniques | `\p` | `pizz.`, `arco`, `con sord.` |
| the last popover again, with its text | `\.` | |

You edit a score of several tracks (`:help notation-scores`) where you read
it. Each staff is a line, and every key writes to the track of the staff
under the cursor.

| Shows | Command |
| --- | --- |
| the tracks of the tab (or every track) | `:score` |
| a group | `:score Strings` |
| the selected tracks of the arrange view | `:score selection` |
| the tracks over the time of the clip | `gT` |
| the pages to check before export. This is the one view that you cannot edit. | `:score.check`, `zp` |

| In a score | Keys |
| --- | --- |
| the cursor's pitch, as on one staff (note entry goes by it) | `j` `k` |
| a staff down, up: a grand staff's two, then the next instrument | `<C-j>` `<C-k>` |
| the next, previous instrument (a grand staff is one) | `]]` `[[` |
| the next, previous instrument in the same group | `]s` `[s` |
| the group's first, last instrument (again: the group before, after) | `[{` `]}` |
| a block of bars by staves, which x, d, y, gU, >, a popover... act on, each staff's clip, one undo step | `<C-v>` then those |
| whole staves | `V` then those |
| on a condensed staff, the other player (voice 2 is the second's clip) | `]v` `[v` |
| Ex over staves: s4, s2,s5, s. the cursor's, a group's name | `:5,8 s4 d`, `:5,8 Strings notation.dyn p` |

`:set score_dim` dims the other staves, and `:set score_colors` tints them
in the colors of their tracks.

The full score and the parts (`:help notation-parts`) are on `\P`:

| Shows or does | Keys |
| --- | --- |
| the score | `\Ps` |
| the condensed score (two players to a staff) | `\Pc` |
| the part of this track (letters typed in a transposed part are the written notes) | `\Pp` |
| the next and the previous part | `\Pn` `\PN` |
| the clip alone | `\Po` |
| a system break in the part | `\Pb` `\Pj` |
| export (`:part.export parts.pdf all`) | `\Pe` |

In the piano roll, the notes of the other tracks show behind, in their
colors (as the visible tracks of REAPER). `]t` `[t` make the next or the
previous of them the edited track. `<Tab>` `<S-Tab>` go round them. With no
track shown, `<Tab>` is the next view. A click on a note behind makes its
track the edited track.

## Articulations

The articulations extension (`:ext.load articulations`) gives each note the
way to play it, as its MIDI 2.0 attribute. The map of a track (`:art.map`)
names the articulations and configures the piano roll. Its keys are keys of
the piano roll. Its README has all of them:

| What | Keys |
| --- | --- |
| the articulation of the note, or of the selection, heard as you choose | `\a` |
| a modifier (con sord.) over the note or the selection | `\A` |
| the pen: what notes are entered with, in insert mode | `\a` |
| the run of notes with the articulation under the cursor | `ia` `aa` |
| the instrument's linked controllers (dynamics) as one curve | `\c` |

`:'<,'>art stc`, `:5,8art pizz` and `:g/art=pz/art arco` do the same on
ranges and matches.
