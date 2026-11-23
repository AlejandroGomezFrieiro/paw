# Completion

<!-- tags: complete suggestions -->

A suggestion shows notes that you can add to the clip in the piano roll. The suggestions come from sources, which extensions register through the module `paw.complete`, and without a source paw suggests nothing.

`extensions/continue` is a small source that repeats the last bar, or moves it one step up or down the key. A language server or a snippet set can be a source too. The steps to write a source are in [How to write a completion source](../how-to/write-a-completion-source.md).

## How a suggestion shows

- A suggestion shows as ghost notes in the color of the part. In the terminal the ghost notes are dashed, and in the graphical window they are transparent with a bright edge.
- A badge above the notes shows the alternative, the number of alternatives and the source, for example `1/4 continue: the bar again`.
- paw writes nothing until you accept the suggestion, and the accept is one undo step.
- In the graphical window, a row of chips is above the ghost notes. Each alternative has a numbered chip, and a click shows it. One more chip names the alternative that shows, and a click accepts it.

## When paw asks the sources

- `<C-Space>` in the piano roll (normal or insert mode) asks all the sources.
- With `paw.opt.complete_auto` on, paw also asks the sources when nothing changed for `paw.opt.complete_idle_ms` while the piano roll has the keyboard. The toolbar of the graphical window has a Suggest switch for this option.
- paw does not ask the sources while the transport plays or records, and a suggestion that came automatically disappears when the transport starts.

## Where a suggestion starts

A suggestion starts after the selected notes, which you can select with the pointer or in visual mode. If no notes are selected, it starts at the cursor. In insert mode the cursor is after the notes that you entered, so a pause after some notes is enough to get more notes.

## Keys

While a suggestion shows, the keys below work in normal and insert mode, and at other times they do their usual action.

| Keys | Effect |
| --- | --- |
| `<Tab>` | accept the full suggestion. The cursor goes to its end. |
| `<C-l>` | accept the next note or chord: the notes that start first. The rest stays. |
| `<C-n>` `<C-p>` | the next or previous alternative |
| `<A-1>` … `<A-9>` | show that alternative |
| `<C-e>`, `<Esc>` | dismiss the suggestion. In insert mode, `<Esc>` dismisses first, and leaves insert mode only when no suggestion shows. |
| `gh` | play the suggestion through the part, from one bar before, with the notes of the clip (normal mode) |

The same keys work in the graphical window when the piano roll has the focus.

## Commands

| Command | Effect |
| --- | --- |
| `:complete` | Ask the sources. |
| `:complete.accept` | Accept the suggestion. `:complete.accept next`: only the next notes. |
| `:complete.dismiss` | Dismiss the suggestion. |
| `:complete.audition` | Play the suggestion. |
| `:complete.sources` | List the sources. |

## Options

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.complete_auto` | `true` | Ask the sources automatically after a pause. |
| `paw.opt.complete_idle_ms` | `1200` | The pause before an automatic request, in ms. |
| `paw.opt.complete_deadline_ms` | `300` | The time that a request waits for the sources, in ms. |
| `paw.opt.complete_audition` | `false` | Play each alternative when it shows. |

## Behavior

- An edit of the clip, an undo, or a new request dismisses the suggestion.
- Each terminal and each graphical window attached to one kernel has its own suggestion, and an edit from one of them dismisses the suggestions for that clip in all of them.
- Playing a suggestion does not change the project.
- A request waits `paw.opt.complete_deadline_ms` for the sources. It then shows the answers that arrived, with the sources of higher priority first, and paw adds the answers that come later at the end, so a slow source does not delay a quick source.
- paw ignores a source that fails, answers two times, or gives an answer that is not valid, and the piano roll continues to work.

## A source

```lua
paw.complete.register({
  name = "octaves", priority = 10,
  views = { "pianoroll" },
  auto = true,
  complete = function(ctx, done) ... done(items) end,
  cancel = function(ctx) end,
})
```

| Field | Value |
| --- | --- |
| `name` | The name. |
| `priority` | Sources with a higher priority show first. |
| `views` | The views where the source works. |
| `auto` | True: paw can ask the source without a key press. |
| `complete(ctx, done)` | Gives the items with `done(items)`, or `done(nil)` for no items. It can call `done` immediately or later (from a timer, or when a program answers). Only the first call counts, and only while the request is the newest. |
| `cancel(ctx)` | A newer request replaced the request `ctx.id`. |

| Field of `ctx` | Value |
| --- | --- |
| `clip`, `part` | ids |
| `start`, `length` | the position of the clip, in project beats |
| `at` | where the suggestion starts, in the beats of the clip |
| `pitch` | the pitch of the cursor |
| `notes` | the notes of the clip |
| `selection` | the selected notes, or nil |
| `grid`, `view` | the grid, the view |
| `trigger` | `"manual"` or `"auto"` |
| `id` | the id of the request |
| `key` | the key, when a module gives it (`paw.harmony.key`) |

An item has a `label`, an optional `detail`, and one or more of the fields below.

| Field of an item | Value |
| --- | --- |
| `notes` | Notes to add: `{ pitch, start, length, velocity }`, with `start` in the beats of the clip as `clip:notes()` gives them. Velocity is 1 to 127 (default: `paw.opt.velocity`). |
| `remove` | The positions of the notes that the item replaces, as `clip:notes()` numbers them. |
| `velocities` | `{ [place] = velocity }`. |
| `controls` | Controller moves to add. |

`paw.complete.show(items, { keys = false })` shows items as ghost notes for a preview, without a source. With the keys on, you can accept them like any suggestion.
