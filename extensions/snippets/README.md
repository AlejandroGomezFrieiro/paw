# snippets

The snippets extension is a first set of snippets for the snippet engine of the core (`paw.snippet`), in the same way that friendly-snippets is a set for LuaSnip. The snippets write chords that lead into the next chord of the song, parts made from the chords that are already there, and voices for a selection.

```lua
paw.ext.load("/path/to/paw/extensions/snippets")   -- or link it into ~/.config/paw/extensions
```

## Try it

1. Type `:ext.load snippets`.
2. Open a clip in the piano roll, before a bar with a C major chord.
3. Type `:snippet dominant`. A G7 chord appears from the cursor to the C
   major chord.
4. Press `Tab`, then `Ctrl-n`, and the voicing of the chord changes.
5. Press `u`, and the chord goes away.

## How to use a snippet

- To expand a snippet by name, type `:snippet name`, or press `Ctrl-s` and
  type some letters of the name.
- To go to the choices of the snippet, press `Tab`. To change a choice,
  press `Ctrl-n`.
- To remove the snippet, press `u`.
- To replace a snippet of this set, write one with the same name in
  `init.lua` or in `<config>/snippets/`, and paw uses yours.

[The first set](../../docs/reference/snippets.md#the-first-set)
lists what each snippet writes and its choices, and it tells you how to write your own.

## Reference

| File | Snippets |
| --- | --- |
| `snippets/harmony.lua` | `dominant`, `secondary`, `two-five`, `tritone`, `passing-dim`, `sus`, `cadence` |
| `snippets/patterns.lua` | `pedal`, `arp`, `bass` |
| `snippets/voices.lua` | `harmonize`, `voice-lead` |

`lua/snippets/init.lua` (`require("snippets")`) holds the parts that the
snippets share, for snippets of your own:

| Name | What it is |
| --- | --- |
| the voicing and length choices | choices that many snippets give |
| `dominant_tones` | the tones of a dominant chord |
| `split` | a span cut on the grid |
| `progression` | chords, each voiced from the chord before it |
| `next_chord` | the next chord of the song |

The suite runs `tests.lua`, which tests the example of the owner (G7 before a C major chord on another part, and in the same clip through the picker). It also tests the chords of each snippet on known material, and it tests choices, counts and undo.
