# rulerplus

The rulerplus extension is an example of how to add to the ruler: a row of its own, a namespace of marks, and a change to a row of paw. You can use it as it is, or copy it and change it. It is written in Teal, in one file, [init.tl](init.tl).

```lua
paw.ext.load("extensions/rulerplus")   -- or type :ext.load rulerplus
```

With rulerplus, the ruler shows more than the numbers of the bars:

```
1       2       3       4       ┃5      6       7       8       ┃9
C               F
in C major
```

- The row `harmony`, under the bar numbers, shows the chord at the start of
  each bar where the chord changes. The chords come from the harmony that paw
  reads in the song.
- The second line of the row shows the key where the key changes, for
  example `in C major` or `in D dorian`.
- A mark `┃` before the first bar of each phrase. A phrase is 4 bars
  at first.
- With `relativebar`, a sign on the counts: `+3` is three `W` ahead, `-2`
  is two `B` behind.

A chord gets shorter, with `…`, when the next chord is close. A key shows
whole or not at all, and more shows when you zoom in. Press `K` on the ruler
to see what has no room.

## Try it

1. Type `:ext.load rulerplus`, and open a song with chords.
2. Look at the ruler, where the chords show at the bars in which they change.
3. Press `\p`, and the phrase marks are every 8 bars. Press `\p` again for
   16 bars, and again for no marks.
4. Type `:set rbar`, and the counts on the ruler get a sign. Press `3W`,
   and the cursor goes to the bar marked `+3`.
5. Type `:ext.unload rulerplus`, and the ruler is as it was before.

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

### The row and the namespace

| Name | Kind | Priority | Glyphs | Styles |
| --- | --- | --- | --- | --- |
| `harmony` | a row after `bars` | chords 20, keys 15 | | `chord`, `key` |
| `rulerplus.phrase` | a namespace over `bars` | 15 | `sign` | `phrase` |

With `paw.opt.ascii`, the phrase mark is `|`. To change them, put code like
this in your `init.lua`, after the extension loads:

```lua
paw.ruler.set("harmony", { styles = { chord = "RulerBar" } })
paw.ruler.set("rulerplus.phrase", { glyphs = { sign = "◆" } })
```

To hide the chords and the keys, take the row out of `paw.opt.rulerrows`
with `:set rulerrows-=harmony`.

## How it works

The extension calls only the functions of `paw.ruler` and `paw.marks`, and
paw records its row, its namespace and its change as belonging to the
extension. When the extension unloads, paw removes the row and the namespace
and puts back the row `bars` as it was. [The
ruler](../../docs/reference/ruler.md) describes each function, and [how to
add a row to the ruler](../../docs/how-to/add-a-row-to-the-ruler.md) shows how
to write your own. [columnplus](../columnplus/README.md) is
the matching example for the part column.
