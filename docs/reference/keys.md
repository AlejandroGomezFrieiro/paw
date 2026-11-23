# Keys, by idea
<!-- tags: course-keys -->

The keys page is a list of keys to keep next to the keyboard, and the keys are written as Vim writes them. `<C-r>` is Ctrl and r, `<A-j>` is Alt and j, `<CR>` is Enter, and `<Esc>` is Escape. `<Space>` (the space bar) is the leader key, and `\` is the local leader of a view (the notation popovers). **A** is the arrange view, **R** is the piano roll, **M** is the mixer, and **D** is the device panel.

The tests of the tutor compare every key here with the mappings of paw, and `?` in paw lists every key of the view that you are in.

## The sentence

A command is a count, an operator, and a motion or a text object, e.g., `3>ic`, `d2W`, `yic` and `gl4W`. An operator typed twice takes whole rows (tracks in A, pitches in R), as in `dd` and `3yy`. `"a` before it names a register, as in `"ayic`, and `.` repeats the last change.

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
| `5\|` | bar 5 (also `:5`); in a scope with time, its bar 5 | |
| `@19\|` | bar 19 of the song, also in a scope with its own bars (also `:@19`) | |
| `gP` | cursor to the playhead | |
| `]'` `['` | next marker or region, the one before | |
| `]r` `[r` | next region at the same level, the one before | |
| `]z` `[z` | the next scope beside this window's scope, the one before (a region, a group, a track; `3]z` three on): [Scopes](narrowing.md) | |
| `)` `(` | | next phrase, start of this phrase or the one before |
| `zs` `zz` `ze` | put the cursor at the left, in the middle, at the right of the timeline | |
| `zh` `zl` | scroll a bar | |

The motion keys only move, in every view. In **M**, `h` `l` are strips, `j` `k` are the rows of a strip (devices, sends, fader, pan, mute, solo, arm), `gg` `G` are its top and bottom, and `0` `$` are the first and last strip. In **D**, `j` `k` are rows, `w` `b` are devices, and `e` is the last parameter of a device.

## Act (operators and single keys)

| Keys | A | R |
| --- | --- | --- |
| `d` | delete | delete notes |
| `y` | yank | yank notes |
| `c` | empty and enter notes in a new clip | delete and enter notes |
| `>` `<` | move clips later, earlier | move notes |
| `=` | snap clips and notes to the grid | snap notes |
| `gc` | mute or unmute clips (`gcc` the track) | |
| `gl` | set the playback loop to it, and turn looping on | the same |
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
| `zn` `znn` | `zn` and a motion: enter what the motion covers as a scope, in this window: `znar` the region, `znag` the group, `znit` the track, `Vjjzn` the selected tracks; `znn` the innermost scope at the cursor ([Scopes](narrowing.md)) | |
| `zw` `zW` | up one level of scope; up to the whole song | |
| `zf` | `zf` and a motion: fold what the motion covers: `zfar` the region into one column (`Bridge ▸ 8`), `zfag` the group into one row, `Vjjzf` the selected tracks into one row (`Fold 1`), a visual block into one cell over its tracks and bars ([Folds](narrowing.md#folds)) | |
| `za` `zc` | close the fold, group or region at the cursor, or open it; close it | |
| `zm` `zr` | close one more level of regions, the deepest first; open one level | |
| `zd` `zE` | delete the fold at the cursor (its tracks and clips stay); delete every fold of the window | |
| `zM` `zR` | close every group, region and fold of the window; open them all | |
| `<Space>tv` `<Space>ta` `<Space>tr` `<Space>tx` `<Space>tl` | a new VCA over the selected tracks; put them under a VCA; take them out of their VCAs; take the VCA at the cursor away; link the faders of a group | |
| `I` `<A-i>` | choose the input (audio, MIDI port and channel), monitor it | |
| `a` | add a device | enter notes after the note |
| `A` | add a volume automation point | |
| `<Space>at` `<Space>ax` | automation off and on, clear it | |
| `<Space>am` | the track's automation mode: read, touch, latch, write, off in turn | |
| `]t` `[t` | the clip's next take, the one before | |
| `zt` `zT` | show or hide the track's take lanes, the tempo lane under the ruler | |
| `g'` `g"` | put a marker at the cursor; go to one from a list | |
| `gx` | remove the marker at the cursor; a right click on its name under the ruler has "Remove" | |
| `gX` | remove the region that the cursor is in; its clips stay | |
| `K` | describe what is under the cursor in a small float under it, and `K` again to move into the float; on a closed fold or in a scope, the fold or the scope first ([Scopes](narrowing.md#what-k-says-of-a-scope)) | the note |
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

In **D**, `A` automates the parameter, and `gC` or `<CR>` edits its curve. On a lane row, `gC` or `<CR>` edits the curve of the lane, and `gc` turns the lane off and on.

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
| `<Space>dw` | save a preset |
| `yy` `dd` `p` | devices (`yy` on a parameter: its setting) |
| `<A-j>` `<A-k>` | reorder |
| `gS` | the track that the device listens to (side-chain) |
| `O` | where its further output pairs play |
| `\p` | pin the panel to its track, or follow the cursor again |

## Name a region (text objects)

| Keys | A | R |
| --- | --- | --- |
| `ic` | the clip under the cursor | the chord: the notes that start together (`2ic` two chords) |
| `ac` | the clip and the gap after it | the chord as the harmony reads it, also a broken chord |
| `in` `an` | | the note under the cursor (`2in` and the next of its voice), with the rest after it |
| `ip` `ap` | | the phrase, with the rest after it |
| `iv` `av` | | the voice of the note: the top line, the bass or a line between, with its octave doublings |
| `i=` `a=` | | every note of the pitch, of the pitch class |
| `ib` | this bar (`2ib` two) | this bar |
| `ir` | the region, on this track (`2ir` the region around it) | the region (`2ir` the region around it) |
| `il` | the loop | |
| `it` | everything on the track | |
| `ie` | the entire project (in a scope, the entire scope) | every note of the clip |

In visual mode, the same text object again takes in one more, so `vic` and then `ic` selects two chords.

## Select (visual mode)

| Keys | |
| --- | --- |
| `v` `V` `<C-v>` | select time, whole rows, a block (R) |
| `o` | go to the other end |
| `gv` | select the last selection again |
| `x` `p` | delete it, replace it with the register |
| `<CR>` | (A) edit the notes of the MIDI clips selected together in R |
| `~` `J` | mute, join (A) |
| `<C-a>` `<C-x>` `+` `-` | transpose the notes that start in the selection, and no others; a count first is how much: `vib12<C-a>` moves the notes of one bar up an octave. The message says how many notes moved, how far and in which clips (over whole tracks, `V`: the volume) |
| `:` | a command for the selection: the line starts `:'<,'>` |
| `<Esc>` | back to normal mode |

## Insert at the cursor (insert mode, A)

`i` starts insert mode in A. Each key inserts one item at the cursor, and the cursor steps past the item, so `mmm` inserts three clips. Letters only insert, the arrows move, and insert mode never moves a clip. Everything from `i` to `<Esc>` is one undo step. See [Insert mode](insert-mode.md).

| Keys | |
| --- | --- |
| `m` | a MIDI clip |
| `a` | an automation point, on the lane row or on the volume |
| `r` `'` | a region, a marker |
| `f` | a sound or MIDI file, which paw asks for |
| `u` | a vocal clip (the utau extension) |
| `3m` | three of them |
| `<CR>` | open what was inserted last (the piano roll); with nothing, enter notes here |
| `<BS>` | take back what was inserted last |
| `K` | what each key inserts |
| `<Esc>` | back to normal mode |

## Draw notes (insert mode, R)

| Keys | |
| --- | --- |
| `i` | draw from the cursor: on a note, take it at its start; else a new note (in A: `i` `<CR>`, in the clip under the cursor, or a new one) |
| `a` | take the note under the cursor, or the note that ends there (after `e`), at its end; else a new note a step on |
| `l` `h` | the edge under the cursor a step right, left: at the end, longer, shorter; at the start, shorter, longer; a count first: `4l` |
| `o` `^` `$` `0` | the other edge; the start; the end; the start |
| `+` `-` `<C-a>` `<C-x>` | the note up, down a semitone; a count first: `3+` |
| `K` `J` | the note up, down an octave |
| `r` and a name | the nearest pitch of that name: `ra`, `rf#`, `rbb` |
| `k` `j` | bend the note up, down at its end (its own pitch bend), `bend_step` semitones each |
| `>` `<` | the note a step later, earlier |
| `=` and a value | the length as a note value: `=4` a beat, `=8.` dotted, `=8t` a triplet |
| `c` | a chord at the note: choose it, or type its symbol (`V7`, `ii`, `V7/V`, `Cmaj7`, `F#m9/C#`) |
| `C` | a strummed chord: the same list, its notes a 64th apart (`2C` two 64ths; `strum_dir` down) |
| `a` | an articulation on the note, by name (with the articulations extension) |
| `e` and a kind | a controller at the note: `em` modulation, `ee` expression, `eb` breath, `es` sustain, `e` and a number any; a count first is the value: `100em` |
| `<C-n>` `<C-p>` `<C-e>` | suggest the next note or chord in place, the one before; put back |
| `m` and a kind | a mark of the song at the note: `mk` a key change, `mt` a tempo, `ms` a time signature, `mr` a region to the end of the note, `m'` a marker |
| `<CR>` | keep it, draw the next where it ends (a note that starts there is taken) |
| `<Space>` | keep it, draw the next after a step's rest |
| `.` | keep it, draw it again after it (a count: more times) |
| `x` | erase the note (a note of the clip goes at `<Esc>`) |
| `<BS>` `<C-w>` | take back the note kept last |
| `<C-u>` | take back all that this insert drew |
| `[` `]` | softer, louder |
| `I` | step input on or off (notes from a MIDI keyboard) |
| `<C-o>` | one command of normal mode, then draw again |
| `<Esc>` | write what was drawn (one undo step; `.` draws it again) and return to normal mode |

## Enter notes from a MIDI keyboard (step input, R)

| Keys | |
| --- | --- |
| `I` | step input from normal mode: keys of a MIDI controller enter notes at the cursor, keys held together a chord |
| `=` and a value | the step: the length of the notes and rests that follow |
| `<Space>` | a rest of one step |
| `<BS>` | take back what was entered last |
| `I` (in step input) | back to drawing |
| `<Esc>` | write all the notes (one undo step) |
| the sustain pedal | a rest of one step with no key held, the held keys a step longer otherwise; `:step.learn` binds more [controls](piano-roll.md#controls-of-the-controller) |

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
| `<Space>.` | adjust the last change: a panel shows the parameters of the last command (`:quantize`, `:transpose`, `:clip.fade`), and the result changes while you change them (see [The adjust panel](#the-adjust-panel)) |
| `"a` | the register for the next command; `"0` last yank, `"_` nowhere |
| `qa` … `q` | record keys into register a |
| `q:` `q/` | edit the history of `:` or `/` in the [command-line window](cmdline.md#the-command-line-window), and `Enter` runs a line |
| `@a` `@@` `@:` | play them, the last macro again, the last command line |
| `ma` `'a` `''` | set mark a, go to it, back to before the jump |
| `:delmarks a-d` `:delmarks!` | remove marks (letters, ranges); all lowercase ones |
| `<C-o>` `<C-i>` | back, forward through jumps |
| `g;` `g,` | back, forward through the places the project was edited |
| `` `. `` `'.` | the place of the last edit |

### The adjust panel

`<Space>.` after `:quantize`, `:transpose` or `:clip.fade` opens a small panel over the screen. Its title names the command and the range it changed, for example `Quantize · 48 notes`. Each row is one parameter and its value. The window shows the same panel as the terminal.

| Keys | |
| --- | --- |
| `j` `k` | choose a parameter |
| `+` `-`, `<C-a>` `<C-x>` | change the value by its step; a count multiplies the step (`5-`) |
| `<CR>` | type a value for the parameter on the command line |
| `:` | open the command line with `:adjust` and all the values |
| `<Esc>` | close the panel and keep the result |

Each change runs the command again as `:adjust` does, so all the changes are one undo step. When changes come quickly, as when you hold a key, paw runs only the last one, 50 ms after it. `u` after `<Esc>` undoes the whole command. With nothing to adjust, `<Space>.` opens the command line, which says why.

## The leader keys

After the leader, the first key is a domain, and the next key is what to do in it or what to find. `<Space>f` finds, so `<Space>fc` finds a clip and `<Space>fr` finds a region. After `<Space>f`, the key is the key of the same domain, so `c` is the clip in `<Space>cf` and in `<Space>fc`. When you stop after the domain, the key hints show its keys, and `<Space><Space>` plays and stops.

| Domain | Keys |
| --- | --- |
| a: automation (A) | `<Space>aa` `<Space>aA` the lanes of the track, of every track; `<Space>al` choose what to automate; `<Space>am` the mode; `<Space>at` off and on; `<Space>aw` write; `<Space>ax` clear |
| c: clip (A) | `<Space>cf` fade the clip in and out; `<Space>cl` put a linked copy after the clip; `<Space>cu` take the clip out of its link |
| d: devices | `<Space>dd` show or hide the device panel; `<Space>da` add a device; in D, `<Space>dw` save a preset and `<Space>dW` make it the default |
| f: find | `<Space>ff` files, `<Space>fg` any text, `<Space>fk` keys, `<Space>fc` clips, `<Space>fr` regions, `<Space>fm` markers, `<Space>ft` tracks, `<Space>fd` the devices of the track, `<Space>fn` notes, `<Space>fa` audio files, `<Space>f:` commands, and more: [Pickers](pickers.md) |
| g: versions (projdiff) | `<Space>gd` what changed since the save, `<Space>gm` settle merge conflicts, `<Space>gs` keep a snapshot |
| h: tutor | `<Space>hh` a hint, `<Space>hn` the next step, `<Space>hr` start again, `<Space>hl` the lessons, `<Space>hq` leave |
| l: language servers | `<Space>la` fixes and actions, `<Space>ll` what they say about what is under the cursor, `<Space>li` the servers; with MIDI LSP, `<Space>lD` every problem and `<Space>lR` its rules |
| m: mix | `<Space>mm` show or hide the mixer; with mixdiag, `<Space>ma` measure the mix, `<Space>mx` the findings, `<Space>mr` the report, and more |
| n: notation | `<Space>nn` the clip as notation, `<Space>ns` every track as a score, `<Space>nc` the pages, `<Space>ne` `<Space>nE` export MusicXML, PDF |
| p: project | `<Space>pr` recent projects; with undotree, `<Space>pu` the undo tree, `<Space>pc` `<Space>pC` write and list checkpoints, `<Space>pa` `<Space>pb` `<Space>pB` mark A, switch A and B, forget them, `<Space>pn` name the state, `<Space>p.` what the last step changed |
| r: markers and regions | `<Space>rm` add a marker, `<Space>rn` make a region, `<Space>rx` remove the marker, `<Space>rX` remove the region, `<Space>rl` loop the region, `<Space>rR` render the regions |
| t: tracks (A) | `<Space>ts` send, `<Space>to` output, `<Space>tg` `<Space>tG` make a group, remove the track from its group, `<Space>tv` a new VCA, `<Space>ta` `<Space>tr` add to a VCA, remove from it, `<Space>tx` remove the VCA, `<Space>tl` link the faders |
| T: tempo and transport | `<Space>Tt` tap the tempo, `<Space>Tm` the metronome, `<Space>Tc` the count-in |
| u: utau | `<Space>ut` add a vocal track, `<Space>uv` make the track vocal, `<Space>us` the singer, `<Space>ue` the vocal editor, `<Space>ul` the lyric sheet, `<Space>ur` render again, `<Space>uf` `<Space>uF` freeze, unfreeze, `<Space>uo` OpenUtau, `<Space>ui` the engine |
| v: views | `<Space>vm` mixer, `<Space>vd` device panel, `<Space>vp` piano roll, `<Space>vs` session view, `<Space>vn` notation, `<Space>vu` undo tree |
| w: workspaces | `<Space>ww` choose a workspace, `<Space>wr` record, `<Space>we` edit, `<Space>wm` mix, `<Space>wn` score, `<Space>ws` save the screen as a workspace (see [Workspaces](windows.md#workspaces)) |
| z: scopes | `<Space>zz` a scope from a list, `<Space>za` add a subproject here, `<Space>zp` promote the subproject at the cursor to a view, `<Space>zw` save this window's view as a subproject per track (`.` saves the next view beside it), `<Space>zW` save it as a subproject with its own row (see [Subprojects](subprojects.md)), `<Space>zs` `<Space>zv` `<Space>zt` the scope at the cursor (or of the selection) in a new split, vertical split, tab, `<Space>zn` name this window's scope |

`u` and `<C-r>` (undo and redo) have no leader, and the keys of one view are on the local leader `\`. `<Space>.` is the one leader key that is not a domain: it adjusts the last change (see [Repeat and remember](#repeat-and-remember)).

## Play

| Keys | |
| --- | --- |
| `<Space><Space>` | play from the cursor, or stop. The cursor never moves by itself; the playhead stays where the song stopped. `play_from` chooses the cursor or the playhead |
| `<S-CR>` | play from the playhead (the other start; with `play_from=playhead`, from the cursor) |
| `gs` `gp` | playhead to the start, to the cursor; play starts there until the cursor moves. `g0` is the playhead to the start too, also in the views where `gs` does another thing (curve editor, drum grid, score) |
| `gL` `gm` | playback loop on and off, metronome |
| `gM` | count a bar in before recording, or not |
| `<Space>Tt` | tap the tempo (the beat): press it on each beat, four times or more |
| `gI` | punch recording on and off (over a selection: punch there); `:preroll 2` plays two bars before the punch in |
| `R` | record armed tracks from the cursor, as `<Space><Space>` plays (while the song plays, from the playhead), or stop recording; with the loop on, every time round is a take |

## Find

| Keys | |
| --- | --- |
| `?` | every key of this view |
| `:` | a command by name; `<Tab>` completes, `<Up>` for history |
| `/` `n` `N` `*` | find a clip or track by name (in R a pitch: `/c4`); next, previous; next with this name |
| `<Space>f:` | pick a command |
| `<Space>fk` `<Space>ft` `<Space>fc` `<Space>fd` | pick a key, track, clip, device of the track |
| `<Space>fm` `<Space>fr` `<Space>f'` `<Space>f"` | markers, regions, marks, registers |
| `<Space>fl` `<Space>ff` `<Space>fo` `<Space>fp` `<Space>f.` | messages, files, options, every picker, the last picker |
| `<Space>fh` `<Space>fg` `<Space>fn` `<Space>fa` | help tags, any text in the project, notes (pitch, lyric, articulation), audio files |
| `<Space>da` | a device to add to the track |
| `<Space>fz` | a scope to enter, or a level of this window's scope to go up to (also `<Space>zz`) |
| `<Space>pr` | recent projects (`:recent 2` opens the second) |
| `<Space>fq` `<Space>fu` `<Space>fe` `<Space>fs` `<Space>fP` | the quickfix list, undo states, extensions, the Lua API, presets |
| `<C-Space>` | in a picker of presets, devices, files, beats, snippets, clips or notes: hear the item under the selection, or stop the sound; `<Esc>` takes back what was tried |
| in a picker | Tab marks a line, Ctrl-q sends the marked (or all) to the quickfix list; Ctrl-v, Ctrl-x, Ctrl-t open it beside, below, in a tab; Ctrl-r steps fuzzy, exact, regex; Alt-d deletes; Ctrl-Up what was typed before |
| `:vimgrep /pizz/` | every text in the project that matches, in the quickfix list |
| `:select clip[name~=pizz] > note[pitch>=C5]` | choose what a query finds; `:query` lists it |
| `]c` `[c` | next, previous clip of the same kind on the track (R: next, previous chord; `]n` `[n`, note of the same pitch) |
| `]s` `[s` | next, previous track in the group (in a score, instrument in the group) |
| `]]` `[[` | with the sections extension, the next and previous section in A (in a score, the next and previous instrument) |
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
| `<Space>mm` `<Space>dd` `<Space>vp` `<Space>vs` | mixer, device panel, piano roll, session view (with the clip launcher extension) |
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
| `<C-=>` `<C-->` `<C-0>`, `z+` `z-` `z=` | taller rows, shorter rows, rows as tall as the options say: tracks in the arrange view (on a selection or with a count, those tracks), the lane at the cursor, keys in the piano roll. Most terminals don't send `Ctrl` with `=` `-` `0`: `z+` `z-` `z=` work in each one |
| `<C-s>` `:w` | save |
| `ZZ` `ZQ` `:q` | save and quit, quit, close the window (quit in the last one) |

## Edit lists as text (`:e paw://tracks`)

The tracks, sends, the devices of a track and the markers show as lines of text (`paw://tracks`, `paw://sends`, `paw://track/2/devices`, `paw://markers`). Every motion, operator, count, register, selection and `.` works on the text as in Vim, and nothing changes in the project until `:w`.

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
| `<C-w>f` | the buffer in a window of its own, in the graphical frontend (as in a curve) |


## Files (`:e folder`)

A folder shows as lines to edit, and as a tree (`:Files`). The edits are those of text, `:w` shows the plan and `y` does it, and deleted files go to the trash.

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
| `<Space>la` | fixes and actions for what is under the cursor; Enter makes one, as one undo step |
| `:diagnostics` | every diagnostic, grouped by what it is about; Enter goes there |
| `:lsp` | the language servers: `:lsp info`, `:lsp restart`, `:lsp log` |

## The quickfix list

| Keys | |
| --- | --- |
| `]q` `[q` | next, previous entry of the quickfix list (Problems: what went wrong anywhere): the view that shows it gets the keyboard |
| `]Q` `[Q` | last, first entry |
| `]l` `[l` | next, previous entry of the window's location list |
| `:copen` `:cclose` | the list's window along the bottom; in it `j` `k` move, `Enter` goes, `<Space>la` fixes, `q` closes |
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
- [The clip launcher](../../extensions/launcher/README.md): the session view (`<Space>vs`)
- [The tutor](../../extensions/tutor/README.md): the course (`:tutor`)
- [The doctor](../../extensions/doctor/README.md): the check of the hardware (`:doctor`)
- [Each other extension](extensions.md): the README of each one
