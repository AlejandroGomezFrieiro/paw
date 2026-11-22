# Snippets

<!-- tags: snippet -->

A snippet is music with a name, made from the context at the cursor. For
example, `dominant` before a C major chord writes G7 from the cursor to
the C chord, in the range of the track and moving smoothly from the chord
before it. The module is `paw.snippet`, and the snippets come from
extensions, where `extensions/snippets` is the first set. For the steps to
write one, see [How to write a snippet](../how-to/write-a-snippet.md).

## Expand a snippet

| Keys, command | Effect |
| --- | --- |
| `:snippet dominant` | Expand a snippet at the cursor of the piano roll. |
| `:snippet`, `<C-s>` | Open a picker of the snippets of the piano roll. `<C-s>` works in normal, insert and visual mode. |
| `3<C-s>`, `:3snippet walk` | Expand the snippet three times. Each repeat starts where the one before ended. |
| `<C-Space>` | Show the snippets among the suggestions (the `snippets` source, see [Completion](completion.md)). |

- The picker is at the top of the screen, and the list gets shorter as you type.
  Its pane shows the notes and choices of the selected snippet, and the
  piano roll shows its notes as named ghost notes. `Enter` writes it.
- A snippet that takes the count itself (`dominant`, `bass`, `pedal`) uses
  the count in its own way, so `2` with `dominant` writes D7 and then G7.
- On a selection (visual mode, then `<C-s>` or `:snippet`), the snippet
  gets the selected notes: `harmonize` adds a voice below them,
  `voice-lead` voices them again.
- A snippet in the suggestions shows its notes as the ghost, and paw writes
  it as it is, with no choices. paw does not offer snippets automatically
  after a pause.
- In the piano roll, `<C-s>` opens the picker and does not save. `:w`
  saves.

## The active snippet

The expansion is one undo step, and after it the snippet is active. Its notes
are violet, and a band at the bottom of the piano roll shows its range, its
name and its current choice. In the graphical window, a chip below its
notes shows the same information.

| Keys (piano roll, normal and insert mode) | Effect |
| --- | --- |
| `<Tab>` `<S-Tab>` | the next choice, the choice before |
| `<C-n>` `<C-p>` | the next value of the choice, the value before (with no choice selected: the first choice). The notes change in the same undo step. |
| `<C-y>`, `<Esc>` | finish: keep the notes |

- A move of the cursor out of the range of the snippet, or any other edit,
  also finishes it.
- One `u` removes the full snippet, after any number of changes of choice.
- While a snippet is active, its keys come before the keys of a
  suggestion, and before `<Esc>` leaves insert mode. When no snippet is
  active, the keys do their usual action (`<Tab>` goes to the next view,
  `<C-y>` redoes).

## The first set

`extensions/snippets` holds the snippets below. Load it with `paw.ext.load`, or
link it into `<config>/extensions`.

| Snippet | Writes | Choices |
| --- | --- | --- |
| `dominant` | V7 of the next chord, from the cursor to the chord. A count chains dominants back. | voicing, kind (7, 9, 7b9, 7sus4, triad), length |
| `secondary` | V7 of a chord of the key: the next chord, or ii, iii, IV, V, vi | voicing, of, kind |
| `two-five` | ii7 then V7 into the next chord (iiø7 and V7b9 before a minor chord), in the same time | voicing, split (half, 3:1, 1:3) |
| `tritone` | bII7, the tritone substitute of the dominant of the next chord | voicing, kind |
| `passing-dim` | a diminished seventh into the next chord: on its leading note, or on its root | voicing, kind, length |
| `sus` | the next chord, suspended until it comes, then resolved | voicing, sus (sus4, sus2, 7sus4), resolve |
| `cadence` | V-I (or IV-V-I, ii-V-I, IV-I) to the tonic of the key, one bar each | voicing, kind, each |
| `pedal` | a held tonic, dominant or chord root at the bottom of the range | note, length |
| `arp` | the chord at the cursor as an arpeggio over its length | pattern (up, down, up-down, broken), rate, voicing |
| `bass` | root and fifth (or roots, or octaves) below the chords, in the range of a bass | pattern, length |
| `harmonize` | a voice a third or a sixth from each selected note, in the key at the note | interval |
| `voice-lead` | the selected chords voiced again to move least, with the bass kept or free | bass, voicing |

The first value of the `voicing` choice is `smooth`, which selects
the chord position that moves least from the notes of the clip before
the cursor, and into the notes after it. If the clip has no notes before
the cursor, it moves least from the notes of other tracks in its range.

## Where snippets are found

- `init.lua`, with `paw.snippet.add`.
- Each file in `<config>/snippets/`. A file calls `paw.snippet.add` or
  returns a list of snippets.
- The `snippets/` directory of an extension, loaded with the extension.

If two snippets have the same name, your snippet replaces the snippet of
the extension.

## A snippet

```lua
paw.snippet.add({
  name = "plagal", desc = "IV then I of the key, two beats each",
  views = { "pianoroll" },
  choices = { { name = "voicing", values = { "smooth", "close", "open" } } },
  expand = function(ctx) ... return { notes = notes } end,
})
```

| Field | Value |
| --- | --- |
| `name` | The name. |
| `desc` | One line for the picker. |
| `views` | The views that offer it. |
| `choices` | A list of `{ name, values }`. |
| `count = true` | The snippet uses `ctx.count` itself. Else paw repeats it. |
| `expand(ctx)` | Returns `{ notes, choices, remove }`, or nil and a reason. The picker and the command line show the reason ("no chord after the cursor"). |

The result of `expand`:

| Field | Value |
| --- | --- |
| `notes` | `{ pitch, start, length, velocity }` in project beats. Velocity is 1 to 127 (default: `paw.opt.velocity`). They go into the clip in the piano roll, and the clip grows to hold them. |
| `choices` | `{ name, values }`, as on the snippet. When a choice changes, paw expands the snippet again with `ctx.values[name]` set to the new value, on the clip as it was before the first expansion. A choice can have `apply(result, value)` that returns the notes. |
| `remove` | The notes of `ctx.selection` that the snippet replaces. |

### The context

| Field of `ctx` | Value |
| --- | --- |
| `at` | the cursor, in project beats |
| `pitch` | the row of the cursor |
| `clip`, `track` | objects |
| `clip_id`, `track_id` | ids |
| `start` | the start of the clip |
| `notes` | the notes of the clip, in project beats |
| `selection` | the selected notes, with their `place`, or nil |
| `region` | `{ from, to }` |
| `harmony` | the module `paw.harmony` |
| `key` | the key at the cursor |
| `range` | the range of the track |
| `grid`, `count`, `values`, `velocity`, `opt` | the grid, the count, the values of the choices, the velocity, the options |

| Helper | Result |
| --- | --- |
| `ctx:voice(tones, opts)` | Pitches for a chord in the range of the track, led from the chord before `opts.from` (the cursor) and into the chord at `opts.to`. The `voicing` choice is its style. `prev`, `next` (pitches, or false), `bass`, `count`, `low`, `high` as in `paw.harmony.voice.voice`. |
| `ctx:chord(tones, from, to, opts)` | The same, as notes from `from` to `to`. |
| `ctx:before(beat)`, `ctx:after(beat)` | The chord of this clip before a beat, and at it. |
| `ctx:around(beat, before)` | What other tracks play at a beat, in the range of this track. |
| `ctx:until_next()` | The start of the next chord, else the end of the bar. |

## Lua

| Function | Effect |
| --- | --- |
| `paw.snippet.add(spec)` | Add a snippet. |
| `paw.snippet.expand(name, { count, at, values })` | Expand a snippet. |
| `paw.snippet.preview(name)` | What the snippet writes, without a change. |
| `paw.snippet.active()` | The active snippet, or nil. |
| `paw.snippet.jump(dir)` | The next or previous choice. |
| `paw.snippet.step(dir)` | The next or previous value. |
| `paw.snippet.finish()` | Finish the active snippet. |
| `paw.snippet.pick()` | Open the picker. |
| `paw.snippet.offered(view)` | The snippets of a view. |
| `paw.snippet.get(name)`, `paw.snippet.remove(name)` | Get or remove a snippet. |
| `paw.snippet.load_dir(dir, source)` | Load the snippets of a directory. |

Events: `snippet.expanded`, `snippet.finished`.
