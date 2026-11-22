# About the key rule

<!-- tags: one-grammar -->

The [key rule](../reference/key-rule.md) gives each key of paw one meaning
in every view, so you learn a key one time and it works everywhere. Vim
works in the same way, where `j` moves a line down in every buffer. paw has
many views, e.g., the arrange view, the piano roll, the mixer, the device
panel, the curve editor and the views of extensions. Before the rule, each
view chose its own keys, and the same key had different meanings.

## Motions only move

The motion keys (`h` `j` `k` `l` `w` `b` `e` and the others) only move, so
they work after an operator and in visual mode in every view. A view that
used a motion key for another action broke operators in that view.

For that reason, `b` is only a motion. The bypass in the device panel went
to `gc`, as `gc` comments a line out in Vim, and the "back to the timeline"
of the session view went to `B` (`gB` for every track). `e` is only a
motion too, so the window of a plugin is `ge` in every view. The session
view opens the notes of a slot with `i`, as `i` enters notes in the piano
roll.

The rule is for normal and visual mode. In insert mode, the keys are not
commands, and they insert, as letters insert text in Vim. For example, in
the insert mode of the arrange view, `m` inserts a MIDI clip and `r` a
region, and only the arrow keys move.

## One key for the main value

`+` `-` and `Ctrl-a` `Ctrl-x` change the main value of what is under the
cursor, and `]` `[` change the second value, so you do not have to remember
a key for each control. The notes of the piano roll already used `+` `-`
and `Ctrl-a` `Ctrl-x` for the pitch. The length of a note went to `Alt-h`
`Alt-l`, which already shortened and lengthened a clip.

## Where the views did not agree

Where views used one key for different actions, the rule chose one meaning.
The sections below list each choice.

### Help, octaves and the pencil

`K` is the key of Vim that finds help for the word under the cursor, so the
side-chain of a device went to `gS` in the panel, because `gK` already
shows the diagnostics in every view. An octave is `Ctrl-d` `Ctrl-u`, which
is half a page in Vim, because `J` `K` are not motions. `K` describes, and
`J` joins clips. In insert mode, `J` `K` still move the note an octave.

Insert mode in the piano roll is a pencil, and the rule does not cover the
keys of insert mode. There, the keys keep their meaning as far as they can:

- `+` `-` change the pitch, which is the main value, and `[` `]` change the
  velocity, which is the second value. `<` `>` move the note in time.
- `h` `l` move the edge of the note under the cursor, so the note follows
  the cursor, and `j` `k` bend the note up and down.
- To go to another note, `Ctrl-o` does one command of normal mode, e.g.,
  `w`.

### Keys that start with `g`

The count-in went from `gC` to `gM`, next to `gm` of the metronome, so `gC`
opens curves everywhere, and `gc` does not open a curve any more. `gn`
stays the next edited clip of the piano roll, as `gn` of Vim goes to the
next match. The wave of the curve editor is `g~`, because it is an operator
and `~` looks like a wave. Its shapes are `~`, its own window is
`Ctrl-w f`, and `gw` is only the warp marker.

`gs` stays the playhead to the start, and it keeps its own meaning in the
curve editor, the drum grid and the score, so `g0` is the playhead to the
start in every view. `R` records, so a plugin starts again with `gR` in the
device panel, and the virtual inputs look for ports with `gR`.

### Tracks, the session view and the device panel

`s` is solo wherever there is a track, so the session view stops the clip
of a track with `S` (`gS` every clip). The presets of the device panel are
`c` on a device (choose), `]p` `[p` (step), `<Space>dw` (save, as `:w`
writes) and `<Space>dW` (the default).

The session view makes a clip with `o`, which opens a line in Vim. It
switches the launch mode with `~` and legato with `g~`, so `n`, `m` and
`gl` keep their meanings.

### The score

The system breaks of the score are `zs` (a system starts here) and `zj`
(join the bar to the system before). They are next to `zg` and `zp`, which
also set the layout of the page, and `gS` keeps its meaning of the session
view and the panel.

The score gives `gv` (select again), `gt` and `gT` (tabs) back to their
meanings in every view. The other voice is `gV`, every track as a score is
`zS`, and triplets come from the tuplet popover `\3`. The drum grid also
makes triplet steps with `\3`, so one key makes triplets.

### Adding, operators and values

`a` appends. It already added a device on a track and notes after a note,
and it does the same in the mixer and the panel. `A` already added a point
of automation at the cursor in every view that had it.

`=` is only an operator. It snaps in the arrange view and the piano roll,
it plays the score as written, and it puts a curve back in the vocal editor
(`=in`, `==`). `c` types a value, and `x` puts a setting back to its
default.

### Sections, windows and the local leader

`]]` `[[` go between sections, as between the sections of a text in Vim,
and `]s` `[s` stay the tracks of a group. `]p` `[p` go through the phonemes
of the vocal editor, so `(` `)` stay the phrase motions.

A view in a window of its own is `Ctrl-w f`, for a curve and for a text
buffer. The keys of an extension for one view are on the local leader
(`\S` sections, `\k` drums), and the keys after the leader work from every
view.

## The space bar is the leader, and plays with two presses

Many Vim users put the leader on the space bar, because the thumb is always
on it. In other music programs, the space bar plays and stops, and one key
cannot do both jobs. If a single Space played, the leader keys would have
to wait for a pause or play a short part of the song first. The leader is
therefore Space, and play and stop is `<Space><Space>`. No other key starts
with `<Space><Space>`, so the second press plays at once, with no wait. A
single Space waits, and after a moment it lists the keys that can follow
it.

The comma is free again in normal mode. As in Vim, `;` and `,` do the last
`f` or `t` again, in the same direction and in the other direction.

## After the leader comes a domain and then a key

Many Neovim configurations put a domain after the leader, e.g., `f` finds,
`g` is git and `l` is the language servers, and paw does the same. After
`<Space>`, the first key is a domain, e.g., `m` the mix, `d` the devices,
`t` the tracks or `p` the project. The second key is what to do in that
domain. You learn one letter for one domain, and it has the same meaning in
all the keys, so `<Space>mm` shows the mixer, and `<Space>ma` measures the
mix.

In the domain `f` (find), the key after `f` is the letter of the domain of
what you find. For example, `<Space>fc` finds a clip, as `<Space>cf` fades
a clip, and `<Space>fr` finds a region, as `<Space>rn` makes one. When you
remember where a thing is, you also know how to find it.

The extensions put their keys in the domain of what the keys do, and not in
a domain of the extension. The undo tree is part of the project, so
undotree uses `<Space>p`, and the mix measurements are part of the mix, so
mixdiag uses `<Space>m`. An extension for one large subject has its own
domain, e.g., `<Space>n` for notation and `<Space>u` for utau.

## Escape never leaves

`Esc` cancels and stays, so the keys that you type after it go where you
expect. Before the rule, the piano roll, the drum grid, the virtual inputs,
the vocal editor and the doctor left or closed on `Esc`. The mix report,
the undo tree and the lists of sections did the same in a window of their
own. Now `Ctrl-w p` returns, and `q` closes a page.

## The old keys for a time

The old keys are still there for a time, with `paw.opt.keys = "classic"`.
See [The classic keys](../reference/key-rule.md#the-classic-keys).
