# About the key rule

<!-- tags: one-grammar -->

In Vim, `j` moves a line down in every buffer. You learn a key one time,
and it works everywhere. paw has many views: the arrange view, the piano
roll, the mixer, the device panel, the curve editor, and the views of
extensions. Before the rule, each view chose its own keys, and the same key
had different meanings. The [key rule](../reference/key-rule.md) gives
each key one meaning in every view.

## Motions only move

The motion keys (`h` `j` `k` `l` `w` `b` `e` and the others) only move.
So they work after an operator and in visual mode in every view. A view
that used a motion key for a different action broke operators there.

For this reason, `b` is only a motion: the bypass in the device panel went to
`gc`, as `gc` comments a line out in Vim. The "back to the timeline" of the
session view went to `B` (`gB` for every track). `e` is only a motion too.
The window of a plugin is `ge` in every view. The session view opens the
notes of a slot with `i`, as `i` enters notes in a clip.

## One key for the main value

`+` `-` and `Ctrl-a` `Ctrl-x` change the main value of what is under the
cursor, and `]` `[` the second value. So you do not have to remember a
key for each control. The notes of the piano roll already used `+` `-` and
`Ctrl-a` `Ctrl-x` for the pitch. The length of a note went to `Alt-h`
`Alt-l`, which already shortened and lengthened a clip.

## Where the views did not agree

Where views used one key for different actions, the rule chose one
meaning:

- `K` is the key of Vim that finds help for the word under the cursor. The side-chain of a device went to `gS` in the panel, because `gK` already shows the diagnostics in every view.
- An octave is `Ctrl-d` `Ctrl-u` (half a page in Vim), because `J` `K` are not motions: `K` describes, and `J` joins clips. In insert mode, `J` `K` still move the note an octave.
- Insert mode in the piano roll is a pencil, and the rule does not cover the keys of insert mode. There, the keys keep their meaning as far as they can. `+` `-` change the pitch, the main value. `[` `]` change the velocity, the second value. `<` `>` move the note in time. `h` `l` move the edge of the note under the cursor, so the note follows the cursor. `j` `k` bend the note, up and down. To go to another note, `Ctrl-o` does one command of normal mode, for example `w`.
- The count-in went from `gC` to `gM`, next to `gm` of the metronome. So `gC` opens curves everywhere. `gc` does not open a curve any more.
- `gn` stays the next edited clip of the piano roll, as `gn` of Vim goes to the next match. The wave of the curve editor is `g~` (an operator, and `~` looks like a wave), its shapes are `~`, and its own window is `Ctrl-w f`. `gw` is only the warp marker.
- `s` is solo wherever there is a track. The session view stops the clip of a track with `S` (`gS` every clip). The presets of the device panel are `c` on a device (choose), `]p` `[p` (step), `<Space>dw` (save, as `:w` writes) and `<Space>dW` (the default).
- The system breaks of the score are `zs` (a system starts here) and `zj` (join the bar to the system before), next to `zg` and `zp`, which also set the layout of the page. `gS` keeps its meaning of the session view and the panel.
- `a` appends. It already added a device on a track and notes after a note. It does the same in the mixer and the panel.
- `A` already added a point of automation at the cursor in every view that had it.
- `=` is only an operator: it snaps in the arrange view and the piano roll, it plays the score as written, and it puts a curve back in the vocal editor (`=in`, `==`). `c` types a value, and `x` puts a setting back to its default.
- `gs` stays the playhead to the start, and keeps its own meaning in the curve editor, the drum grid and the score. `g0` is the playhead to the start in every view.
- `R` records. A plugin starts again with `gR` in the device panel, and the virtual inputs look for ports with `gR`.
- The score gives `gv` (select again), `gt` and `gT` (tabs) back to their meanings in every view. The other voice is `gV`, every track as a score is `zS`, and triplets come from the tuplet popover `\3`. The drum grid makes triplet steps with `\3` too: one key for triplets.
- The session view makes a clip with `o` (open a line in Vim), switches the launch mode with `~` and legato with `g~`, so `n`, `m` and `gl` keep their meanings.
- `]]` `[[` go between sections, as between the sections of a text in Vim. `]s` `[s` stay the tracks of a group. `]p` `[p` go through the phonemes of the vocal editor, so `(` `)` stay the phrase motions.
- A view in a window of its own is `Ctrl-w f`, for a curve and for a text buffer.
- The keys of an extension for one view are on the local leader (`\S` sections, `\k` drums). The keys after the leader work from every view.

## The space bar is the leader, and plays with two presses

Many Vim users put the leader on the space bar, because the thumb is
always on it. In other music programs, the space bar plays and stops. One
key cannot do the two jobs. If a single Space plays, the leader keys must
wait for a pause or play a short part of the song first. So the leader is
Space, and play and stop is `<Space><Space>`. No other key starts with
`<Space><Space>`, so the second press plays at once, with no wait. A single
Space waits, and after a moment it lists the keys that can follow it.

The comma is free again in normal mode. As in Vim, `;` and `,` do the
last `f` or `t` again, in the same direction and the other direction.

## After the leader, a domain and then a key

Many Neovim configurations put a domain after the leader: `f` finds, `g`
is git, `l` the language servers. paw does the same. After `<Space>`, the
first key is a domain (`m` the mix, `d` the devices, `t` the tracks, `p`
the project) and the second key is what to do in it. So you learn one
letter for one domain, and it has the same meaning in all the keys:
`<Space>mm` shows the mixer, and `<Space>ma` measures the mix.

In the domain `f` (find), the key after `f` is the letter of the domain
of what you find: `<Space>fc` finds a clip, as `<Space>cf` fades a clip.
`<Space>fr` finds a region, as `<Space>rn` makes one. When you remember
where a thing is, you also know how to find it.

The extensions put their keys in the domain of what the keys do, not in a
domain of the extension. The undo tree is part of the project, so
undotree uses `<Space>p`. The mix measurements are part of the mix, so
mixdiag uses `<Space>m`. An extension for one large subject has its own
domain: `<Space>n` notation, `<Space>u` utau.

## Escape never leaves

`Esc` cancels and stays. So keys typed after it go where you expect. The
piano roll, the drum grid, the virtual inputs, the vocal editor and the
doctor left or closed on `Esc` before. The mix report, the undo tree and
the lists of sections did the same in a window of their own. Now `Ctrl-w p`
returns, and `q` closes a page.

## A time to change

The old keys are still there for a time, with `paw.opt.keys = "classic"`.
See [The classic keys](../reference/key-rule.md#the-classic-keys).
