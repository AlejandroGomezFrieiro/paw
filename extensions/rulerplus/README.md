# rulerplus

An example of how to personalize the bar labels of the ruler. Use it as
it is, or copy it and change it. It is written in Teal, in one file:
[init.tl](init.tl).

```lua
paw.ext.load("extensions/rulerplus")   -- or type :ext.load rulerplus
```

With rulerplus, the label of a bar can show more than its number:

```
1 C (C) 2       3 F     4       ┃5      6       7       8       ┃9
```

- The chord at the start of the bar, when it is not the chord of the bar
  before. The chords come from the harmony that paw reads in the song.
- The key, in short, where it changes: `(C)` is C major, `(Am)` is A
  minor, `(D dor)` is D Dorian.
- A mark `┃` before the first bar of each phrase. A phrase is 4 bars
  first.
- With `relativebar`, a sign on the counts: `+3` is three `W` ahead, `-2`
  is two `B` behind.

A part shows only when the label has room for it before the next bar.
When you zoom in, more shows.

## Try it

1. Type `:ext.load rulerplus`, and open a song with chords.
2. Look at the ruler. The chords show where they change.
3. Press `\p`. The phrase marks are every 8 bars. Press `\p` again for
   16 bars, and again for no marks.
4. Type `:set rbar`. The counts on the ruler have a sign. Press `3W`.
   The cursor goes to the bar marked `+3`.
5. Type `:ext.unload rulerplus`. The ruler is as it was before.

## Reference

### Keys

In the arrange view.

| Keys | Effect |
| --- | --- |
| `\p` | the next length of a phrase: 4, 8, 16 bars, no marks |

### Commands

| Command | Effect |
| --- | --- |
| `:rulerplus.phrase [bars]` | a phrase mark every number of bars, from 0 (no marks) to 64. With no number, the next length |

### Options

| Option | Default | Effect |
| --- | --- | --- |
| `rulerplus_phrase` | 4 | the bars of a phrase. 0 shows no marks |
| `rulerplus_signed` | true | with `relativebar`, a `+` or `-` before each count |

### The parts

| Name | Order | Glyphs | Styles |
| --- | --- | --- | --- |
| `phrase` | 5 | `phrase` | `phrase` |
| `chord` | 25 | | `chord` |
| `key` | 30 | | `key` |

The part `number` of paw has order 10, so the phrase mark is before the
number and the chord and the key are after it. With `paw.opt.ascii`, the
mark is `|`. You change the parts in your `init.lua` after the extension
loads:

```lua
paw.ruler.set("chord", { styles = { chord = "RulerBar" } })
paw.ruler.set("phrase", { glyphs = { phrase = "◆" } })
```

To remove a part, take its name out of `paw.opt.barlabel`:
`:set barlabel-=key`.

## How it works

The extension calls the functions of `paw.ruler` only. paw records each
part and change as the extension's. When the extension unloads, paw
removes its parts and puts back the part `number` as it was. [The track
column and the bar labels](../../docs/reference/trackcolumn.md) gives
each function.
[How to personalize the track column and the
ruler](../../docs/how-to/personalize-the-track-column-and-the-ruler.md)
shows how to write your own. [columnplus](../columnplus/README.md) is
the example for the track column.
