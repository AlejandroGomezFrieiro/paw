# columnplus

An example of how to personalize the track column, the narrow column at
the left of the track headers. Use it as it is, or copy it and change it.
It is written in Teal, in one file: [init.tl](init.tl).

```lua
paw.ext.load("extensions/columnplus")   -- or type :ext.load columnplus
```

With columnplus, the column shows these parts, from the left:

```
▎  1  2 █ Drums
▎▿ 2    ▌ Strings
▎┆ 3    ▌ Violins
▎└ 4    ▌ Cellos
▎  5 ≡1 ▌ Keys
```

- A strip in the color of each track, down all of its lines, and the
  folds of the groups at the far left, with arrows.
- The number of the track, as before. The number of the cursor's track
  is in the color of the accent.
- The signs: `≡` on a track with takes, `∗` on a frozen track and `∘` on
  a track that plays through a frozen track.
- How many clips the track has. The count is in a lighter color when a
  clip of the track has takes.

## Try it

1. Type `:ext.load columnplus`, and open a song with groups.
2. Press `\z` two times. The folds change to plus and minus signs, then
   to the glyphs of paw.
3. Press `\#`. The clip counts go. Press `\#` again to show them.
4. Click the strip of a track. Choose a color for the track.
5. Put the cursor on a track with takes and press `K`. The description
   tells how many clips have takes.
6. Type `:ext.unload columnplus`. The column is as it was before.

## Reference

### Keys

The keys work in the arrange view.

| Keys | Effect |
| --- | --- |
| `\z` | the next look of the folds: arrows, plus, paw |
| `\#` | show or hide the clip counts |

### Commands

| Command | Effect |
| --- | --- |
| `:columnplus.folds [look]` | the look of the folds: `arrows`, `plus` or `paw`. With no look, the next look |
| `:columnplus.clips` | show or hide the clip counts |

### Options

| Option | Default | Effect |
| --- | --- | --- |
| `columnplus_folds` | `arrows` | the glyphs of the folds: `arrows` (`▿ ▹ ┆ └`), `plus` (`- + \| \``) or `paw` (the glyphs of paw) |
| `columnplus_foldfirst` | true | the folds at the far left. With false, they stay after the numbers and the signs |

With `paw.opt.ascii`, the parts use plain ASCII characters.

### The parts and the signs

| Name | Kind | Order | Glyphs | Styles |
| --- | --- | --- | --- | --- |
| `strip` | part | 1 | `strip` | the color of the track |
| `clips` | part | 40 | | `count`, `takes` |
| `takes` | sign | priority 15 | `takes` | `takes` |
| `frozen` | sign | priority 25 | `frozen`, `held` | `frozen` |

You change them the same way as the parts of paw, in your `init.lua` after
the extension loads:

```lua
paw.trackcolumn.set("clips", { styles = { count = "Faint" } })
paw.trackcolumn.set_sign("takes", { glyphs = { takes = "T" } })
```

To remove a part, take its name out of `paw.opt.trackcolumn`:
`:set trackcolumn-=strip`.

## How it works

The extension calls only the functions of `paw.trackcolumn`, and paw records
each part, sign and change as the extension's. When the extension unloads,
paw removes its parts and signs and puts back the parts of paw that it
changed. [The track column and the bar
labels](../../docs/reference/trackcolumn.md) describes each function. To
write your own, read [How to personalize the track column and the
ruler](../../docs/how-to/personalize-the-track-column-and-the-ruler.md). The
extension [rulerplus](../rulerplus/README.md) is the example for the ruler.
