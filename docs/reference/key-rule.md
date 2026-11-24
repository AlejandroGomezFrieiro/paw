# The key rule

<!-- tags: key-rule keys-one-grammar -->

Every view obeys one rule for its keys, which is that a key has the same meaning in each view. `tests/keys_constitution.lua` examines the mappings of every view, also those of the bundled extensions, and fails on a mapping that breaks the rule. `:lua =paw.keyrule.broken()` does the same check on your own mappings.

Buffers of text (`:e paw://parts`) keep the keys of Vim for text, so `Ctrl-a` adds to the number under the cursor there, and `-` goes up to the buffer above, as in oil.nvim. Their motions and operators obey the rule.

The rule is for normal mode, visual mode and the motions after an operator. In insert mode, keys insert, in the same way that letters insert text in Vim. In the arrange view, `m` inserts a MIDI clip (see [Insert mode](insert-mode.md)), and in the piano roll, `l` makes the note longer.

[About the key rule](../explanation/about-the-key-rule.md) gives the reasons for the rule.

## The keys in every view

| Keys | Meaning in every view |
| --- | --- |
| `h` `j` `k` `l` and the arrows, `w` `b` `e` `0` `^` `$` `gg` `G`, with counts | Motions only. They work after an operator and in visual mode. `h` `l` go along the columns of the view, `j` `k` along its rows. In the mixer, `h` `l` go from strip to strip, and `j` `k` along the rows of a strip. In the devices view, `h` `l` go along the chain and `j` `k` across the branches of a split. In the inspector, `j` `k` go over the devices and their parameters, `w` `b` from device to device, and `e` to the last parameter of a device. |
| `+` `-`, `Ctrl-a` `Ctrl-x` | The main value of what is under the cursor, up and down. A count first gives how much: `6 Ctrl-x` is 6 dB down on a fader, six semitones down on a note. On a selection, the value of all of it. |
| `]` `[` | The second value, up and down. They act at once, also when you press them fast: `]]` is two steps, unless the view has `]]` as a motion (the sections of the arrange view, the staffs of a score). A key that comes soon after and makes a longer mapping (`]g`, `]q`) takes back the step and does its own action. |
| `>` `<` | The time operators: later and earlier (`>>`, `>ic`, `3>` on a selection). Never pan. |
| `K` | Describes what is under the cursor. `gK` gives what the diagnostics and language servers say about it. |
| `ge` | The plugin window of what is under the cursor (an insert in the mixer, a device in the panel), else of the part. |
| `gc` | Mute: an operator over clips and parts (`gcc` the part), and over strips in the mixer. A lane of automation off or on. A device bypassed (`gcc` in the panel). |
| `gC` | Opens the curve of what is under the cursor: a lane row, a parameter, the fader or pan of the mixer, the strip of the piano roll. `Enter` does the same on a lane row and a parameter. `gX` opens the expression of the note. |
| `Alt-h` `Alt-l`, `H` `L` | Shorter and longer. Earlier and later. For a clip, a note, a chord in the score. |
| `Esc` | Cancels: a count, an operator, a selection, insert mode, a suggestion, the chosen notes, a check that runs. When nothing else is left to cancel, it ends a recording: it stops the song and keeps the take, as leaving insert mode keeps the text. During the count-in, it calls the take off. It never stops a song that only plays. It never leaves or closes a view. A second `Esc` says how to leave: `Ctrl-w p` returns to the window before, and `:q`, `ZZ`, `Ctrl-w c` or the key of the view (`<Space>mm` `<Space>dd` `<Space>vp`, `q` on a page) close it. Pickers, menus and floating lists are prompts, and close on `Esc`. |
| `s` `M` `r` | Solo, mute, arm the part: in the arrange view, the mixer, the session view of the clip launcher (the part of the column) and the device panel (its part). |
| `a` | Append: a device after the chain of the part (arrange view, mixer, device panel), notes after the note (piano roll, score), a drawing from the curve (curve editor). |
| `A` | Automate the main value: a point at the cursor on the volume of the part, the parameter, the lane. |
| `c` | Change what is under the cursor: an operator over clips and notes. On a lane point or a parameter, type its value. On a device, choose a preset. |
| `~` | Switch a property of what is under the cursor: the mute of a clip, the shape of a part of a curve, the vibrato of a note. |
| `]x` `[x` | The next and the previous item of a list: `]d` diagnostics, `]t` takes, `]p` presets (phonemes in the vocal editor), `]c` chords (piano roll) and clips of the same kind (arrange view), `]e` curves (vocal editor), `]'` markers, `]z` scopes (arrange view). `]g` `[g` change the grid. |
| `Ctrl-d` `Ctrl-u` | A big step along `j` `k`: four parts, an octave (piano roll, score, vocal editor), ten steps of a curve. |

## The main and the second value

| View, under the cursor | Main: `+` `-` `Ctrl-a` `Ctrl-x` | Second: `]` `[` |
| --- | --- | --- |
| Arrange view, a part (and `V` over parts) | the volume, a dB | the pan, a tenth |
| Arrange view, a selection of clips (`v`, `Ctrl-v`) | the pitch of their notes, a semitone | |
| Arrange view, a lane row | the value of the point | |
| Mixer | the row: the fader or a send in dB, the pan in tenths, a switch on (`+`) or off (`-`), an insert on or bypassed | the pan of the strip |
| Device panel | the parameter, 1/100 of its range. On the row of a device, its wet mix | |
| Piano roll | the pitch of the note, a semitone | its velocity, by 10 |
| Score (notation) | the pitch of the note: sharpen, flatten | |
| Drum grid | the velocity of the hit, by 16 | the same: a hit has no pitch |
| Curve editor | the value of the point | the bend of the smooth part after it |
| Vocal editor | the pitch of the note | the start of its phoneme |
| Virtual inputs | the setting. On the row of an input, on or off | |

## Leaders

| Leader | Meaning |
| --- | --- |
| The leader | `<leader>` in a mapping. It is `paw.opt.leader`, the space bar by default (`" "`). It starts the keys that mean the same in every view: `<Space>mm` the mixer, `<Space>dd` the device panel. `<Space><Space>` plays and stops at once: no other key starts with it. `<Space>.` adjusts the last change. |
| The local leader | `<localleader>` in a mapping. It is `paw.opt.localleader`, a backslash by default, as in Vim. It starts the keys of one view, for example the notation popovers (`\d` dynamics, `\t` tempo) and the fades of a clip in the arrange view (`\fi`, `\fo`). |

A key of one view must not use a key of the global leader, or the leader alone. One exception is that a view can play in its own way on the keys that play (`role = "play"`), as the vocal editor plays from its cursor. `:lua =paw.keyrule.broken()` lists the keys that do not obey. The key hints show both leaders as you type them.

When you set `paw.opt.leader` in `init.lua` or with `:set`, every key on the leader moves to the new leader, also the keys that paw mapped before. With `paw.opt.leader = ","`, the mixer is `,mm` and `,<Space>` plays.

The keys of an extension for one view are on the local leader. In the arrange view, `\S` is sections, `\T` templates, `\t` patterns, `\k` drums, `\V` vocal parts, `\i` virtual inputs and `\n` notation. The keys of an extension after the leader work from every view (`<Space>ma`, `<Space>pu`, `<Space>vs`), and `:lua =paw.keyrule.broken()` lists a key of an extension for one view that is on the leader.

After the leader, the first key is a domain, so `<Space>f` finds, `<Space>m` is the mix, and `<Space>t` the parts. The second key is what to do or what to find, and [The leader keys](keys.md#the-leader-keys) lists the domains. An extension puts its keys in the domain of what they do, so mixdiag uses `<Space>m` and undotree uses `<Space>p` (project).

The core keeps some keys of its own views after the leader, on keys that no global mapping uses. In the arrange view, these are the automation (`<Space>a`), the parts (`<Space>t`, for groups, VCAs, sends and outputs) and fades (`<Space>cf`). In the device panel, they are the presets (`<Space>dw` `<Space>dW`). `<Space>la` gives the fixes and actions in each view.

## Keys and the word part

Earlier versions of paw called a part a track. The keys kept their letters when the word changed, so `<Space>t` is still the domain of the parts. Only the words changed: the commands are `:part.*` (`:part.name`, `:part.midi`), the list of keys after `<Space>` names the domain `parts`, and the messages say part.

## The classic keys

`paw.opt.keys = "classic"` in `init.lua` (or `:set keys=classic`) gives the keys as they were before the rule, for a time, and `:set keys=default` removes them again. The table below lists the changes.

| View | Before | Now |
| --- | --- | --- |
| Arrange | `(` `)` pan | `[` `]` |
| Arrange | `Ctrl-a` `Ctrl-x` transpose the clip | volume. `vic` then `Ctrl-a` transposes |
| Everywhere | `gC` count a bar in | `gM` |
| Lane row | `gc` the curve | `gC` or `Enter`. `gc` turns the lane off or on |
| Mixer | `j` `k` the fader | `+` `-`. `j` `k` move along the strip |
| Mixer | `<` `>` pan | `[` `]` |
| Mixer | `gg` `G` first and last part | first and last row. `0` `$` first and last strip |
| Device panel | `h` `l`, `H` `L` the parameter | `+` `-`, with a count |
| Device panel | `b` bypass | `gc` |
| Device panel | `e`, `Enter` the plugin window | `ge`. `Enter` on a parameter opens its curve |
| Device panel | `s`, `<` `>`, `w`, `W` presets | `c` on a device, `[p` `]p`, `<Space>dw`, `<Space>dW`. `s` solos |
| Device panel | `K` side-chain | `gS` |
| Device panel | `gc` the curve | `gC`, `Enter` |
| Piano roll | `J` `K` an octave | `Ctrl-d` `Ctrl-u` |
| Piano roll | `+` `-` length | `Alt-l` `Alt-h`. `+` `-` the pitch |
| Piano roll | `gc` the curve of the strip, `gC` of the note | `gC`, `gX` |
| Piano roll, drum grid, virtual inputs, vocal editor | `Esc` back to the window before, after it ends a take | `Ctrl-w p`. `Esc` stays |
| Doctor | `Esc` closes the page when nothing runs | `q`. `Esc` stops a run |
| Curve editor | `J` `K` ten steps | `Ctrl-d` `Ctrl-u` |
| Curve editor | `s` shape, `<` `>` bend | `~`, `[` `]`. `<` `>` move points in time |
| Curve editor | `gn` a wave, `gw` its own window | `g~`, `Ctrl-w f` |
| Session | `s` `S` stop, `b` `B` back, `e` notes | `S` `gS`, `B` `gB`, `i`. `s` solos |
| Virtual inputs | `h` `l`, `H` `L` the setting | `+` `-`, with a count |
| Score | `+` `-` length, `Alt-h` `Alt-l` move the chord, `J` `K` octave, `ge` respell | `Alt-l` `Alt-h`, `H` `L`, `Ctrl-d` `Ctrl-u`, `g~`. `+` `-` sharpen and flatten |
| Vocal editor | `+` `-` length, `J` `K` octave, `Ctrl-a` select all, `Ctrl-x` cut, `gc` `gC` curves, `gA` phrase | `Alt-l` `Alt-h`, `Ctrl-d` `Ctrl-u`, `gA`, `d`, `]e` `[e`, `vap`. `+` `-` `Ctrl-a` `Ctrl-x` the pitch |
| Lyric sheet | `K` kana, `Esc` closes | `~`, `q` |
