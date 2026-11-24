# Insert mode in the arrange view

<!-- tags: insert insertkeys paw.insert i -->

In the arrange view, `i` starts insert mode, as in Vim, and the status line shows `INSERT`. In insert mode, each key inserts one item at the cursor, which can be a clip, a region, a marker or an automation point. `Esc` stops insert mode. Extensions and `init.lua` add keys and change what each key inserts. The other keys of the view are in [The arrange view](arrange-view.md).

## The keys

| Key | Inserts | `Enter` after it |
| --- | --- | --- |
| `m` | An empty MIDI clip, as long as `paw.opt.clip_length`. | Opens the clip in the piano roll, in insert mode. |
| `a` | An automation point at the value that the lane has there. On a lane row, the point goes on that lane. On a part, it goes on the volume lane. | Stops insert mode. |
| `r` | A region, as long as `paw.opt.clip_length`. | Asks for the name of the region. |
| `'` | A marker. | Asks for the name of the marker. |
| `f` | A sound file or a MIDI file. paw asks for the file. | Stops insert mode. |
| `u` | A vocal clip on a vocal part. Only with the utau extension. | Opens the vocal editor. |

The other keys of insert mode are in the table below.

| Key | Effect |
| --- | --- |
| `1` to `9`, then `0` to `9` | A count for the next key: `3m` inserts three clips. |
| `Enter` | Opens the item that you inserted last, and stops insert mode. If you inserted nothing, it opens the clip under the cursor in the piano roll to enter notes. If there is no clip, it makes one. |
| `Backspace` | Removes the item that you inserted last. The cursor returns to its start. |
| `K` | Tells what each key inserts. |
| The arrow keys | Move the cursor one grid step, or one part. |
| `Esc` | Stops insert mode. |

- The cursor moves to the end of the item that you inserted, so `mmm` inserts three clips one after the other. After a marker or a point, it moves one grid step.
- The letters only insert, so `h` `j` `k` `l` `w` `b` do not move the cursor in insert mode. To move, use the arrow keys, or press `Esc`, move, and press `i` again.
- Insert mode never moves a clip that is there. A clip that starts in another clip, or goes over it, is not inserted, and a message tells you why. Regions and markers can go over other items.
- All that you insert from `i` to `Esc` is one undo step, so `u` removes all of it and `.` inserts it again.
- A key with no item says so, and `K` tells the keys.
- After a moment, a box shows each key and what it inserts, and in the graphical window the box is the same.
- `i` then `Enter` enters notes at the cursor in two keys, in the clip under the cursor or in a new clip.

`paw.opt.insertkeys` is the list of the keys that work, in the order of the box, so `:set insertkeys=m,r` keeps only `m` and `r`.

## paw.insert.add

```lua
paw.insert.add("M", {
  kind = "midi",
  desc = "A two-bar drum clip",
  length = "2 bars",
  name = "Drums %d",
  notes = { { pitch = 36, start = 0, length = 0.5 }, { pitch = 38, start = 1, length = 0.5 } },
})
```

`add` puts the key in `paw.opt.insertkeys` at the place of its `order`, so the key works at once, and `hidden = true` adds it without that. A key that exists gets the new kind. `paw.insert.remove("M")` removes the key. When an extension unloads, its keys go, and a key that it changed is again as it was.

| Field | Meaning |
| --- | --- |
| `kind` | What the key inserts: `midi`, `audio` (a file, which paw asks for), `region`, `marker`, `automation`, or the name of a kind of clip from `paw.clip_kinds`. |
| `desc` | What the key inserts, in a few words. The box, `K` and `?` show it. |
| `length` | How long the item is: beats as a number, or a text: `"2 bars"`, `"3 steps"` (grid steps), `"8 beats"`, or `"marker"` (to the next marker, or to the start or the end of a region). The default is `paw.opt.clip_length`. |
| `name` | The name of the item. `%d` becomes a number: the number of the clip on its part, of the marker, or of the region. |
| `notes` | The notes that a MIDI clip starts with, as `part:add_clip` takes them. |
| `args` | The words that a kind of clip gets in its `create`. |
| `parts` | The kinds of part that the key works on. `part` is a part of no kind. The default is every part. |
| `per_part` | Changes for a kind of part: `{ vocal = { name = "Vocal %d" } }`. |
| `insert(ctx)` | Inserts the item itself, in place of what `kind` does. It returns the item, or nil and why not. |
| `open(ctx, item)` | What `Enter` does after the item: open it in its editor. |
| `order` | The place of the key in `paw.opt.insertkeys`, and so in the box and the key bar, when `add` puts it there. A lower number comes first, and keys with the same number go by their names. The default is 50. The built-in keys have 10 (`m`), 20 (`a`), 30 (`r`), 40 (`'`) and 50 (`f`). |

`ctx` tells about the place, with the fields below.

| Field | Meaning |
| --- | --- |
| `key` | The key. |
| `spec` | The kind, with the changes of `per_part` for the part. |
| `part` | The id of the part of the cursor. 0 on the master part. Nil when there is no part. |
| `lane` | The id of the automation lane, when the cursor is on a lane row. |
| `beat` | Where the cursor is. |
| `length` | The length in beats, from `length`. |
| `index`, `count` | Which of a count this is: `3m` gives 1, 2 and 3. |
| `name` | The name, with `%d` made a number. |
| `placed(item)` | For a kind that asks first (a file): give the item when it is made. |

The item that `insert` returns has the fields below.

| Field | Meaning |
| --- | --- |
| `what` | A word: `clip`, `marker`, `region`, `point`. |
| `id` | Its id. |
| `start` | Where it starts. |
| `length` | How far the cursor moves after it. Nil moves one grid step. |
| `text` | What the message calls it: `a MIDI clip`. |
| `remove()` | Removes it, for `Backspace`. |

## paw.insert.set

`set` changes a key that exists, also a key that comes with paw. It changes only the fields that you give, and `key` moves the kind to another key.

```lua
-- Regions to the next marker, called Verse 1, Verse 2...
paw.insert.set("r", { name = "Verse %d", length = "marker" })
-- One-bar clips on n, not on m.
paw.insert.set("m", { length = "1 bar", key = "n" })
```

The key gets a changed copy, and `paw.insert.add(key, old)`, with the table that `paw.insert.get(key)` gave before, puts it back.

## Kinds of clip

A kind of clip (`paw.clip_kinds.define`) with an `insert` key gets that key in insert mode, and `Enter` after it calls the `editor` of the kind.

```lua
paw.clip_kinds.define("cue", { title = "Cue clip", insert = "c", ... })
```

## Other functions

| Function | Effect |
| --- | --- |
| `paw.insert.get(key)` | The kind on a key, or nil. |
| `paw.insert.list()` | The kinds of the keys that work, in the order of `paw.opt.insertkeys`. |
| `paw.insert.insert(key, count)` | Inserts what the key inserts at the cursor, as if you typed it. |
| `paw.insert.start()` | Starts insert mode, as `i` does. |
