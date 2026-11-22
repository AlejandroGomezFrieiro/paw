# continue

A small completion source for the piano roll. It suggests how the phrase before the cursor can continue. It knows only the notes and the key, so it is fast and always gives the same suggestions. It is also an example of a source for `paw.complete`.

```lua
paw.ext.load("extensions/continue")   -- or put the directory in ~/.config/paw/extensions
```

## Try it

1. Type `:ext.load continue`.
2. Open a MIDI clip with one bar of notes in the piano roll. Put the cursor
   after that bar.
3. Wait a moment, or press `Ctrl-Space`. Ghost notes appear after the
   cursor.
4. Press `Ctrl-n`. The ghost notes change to the next suggestion.
5. Press `Tab`. The ghost notes become notes of the clip.

## How to use the suggestions

- To ask for suggestions, press `Ctrl-Space`. If `paw.opt.complete_auto` is
  true, they also come a moment after an edit.
- To see the other suggestions, press `Ctrl-n` or `Ctrl-p`.
- To accept a suggestion, press `Tab`. To accept only its next note or
  chord, press `Ctrl-l`.
- To remove the suggestion, press `Esc`.

[Completion](../../docs/reference/completion.md) describes the keys of all
sources.

## Reference

The source reads the bar before the start of the suggestion, and the start is
the cursor or the end of the selected notes.

| Suggestion | What it is |
| --- | --- |
| the bar again | the same notes, one bar later |
| a step higher | the bar one degree higher in the key (a sequence) |
| a step lower | the bar one degree lower |
| the motif, rising | the last half bar two times, one degree higher each time |

- The key is `paw.harmony.key`. If that module does not exist, the source
  guesses the key from the notes of the clip, and it takes the major or minor
  scale that holds most of the time that the notes sound.
- A note outside the key keeps its distance from the degree below it.

| File | Contents |
| --- | --- |
| `init.lua` | the source: one call of `paw.complete.register` |
| `lua/continue.lua` | the music, as plain functions: `suggest(ctx)`, `guess_key(notes)`, `shift(pitch, steps, key)` |
