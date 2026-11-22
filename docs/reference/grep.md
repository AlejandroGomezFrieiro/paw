# Search the text of the project

<!-- tags: vimgrep :vimgrep :lvimgrep project-grep paw.grep searching-the-projects-text -->

`:vimgrep /pattern/` finds every text in the project that matches a regular expression (the way the regex mode of the pickers reads it). It puts the places in the quickfix list, as the `:vimgrep` of Vim does with files, and goes to the first place.

The text that it searches is the following.

- The names of tracks, clips, markers, regions and devices.
- The lyrics and articulations of notes.
- Comments (`meta.comment` on a track or a clip).
- The tags of the project.
- The text that extensions add. For example, the notation extension adds the text and the dynamics written over its staves.

## Commands

| Command | Effect |
| --- | --- |
| `:vimgrep /pizz/` | Finds every text that holds pizz. Each entry gives its kind of text: `clip: pizz 2`, `lyric: la`. |
| `:vimgrep /^la$/ lyric` | Finds only in the named fields: `track`, `clip`, `marker`, `region`, `device`, `lyric`, `art`, `comment`, `tag`, and `text` and `dynamic` of the notation extension. `Tab` completes them. |
| `:vimgrep /verse/j` | With `j`, the cursor stays where it is. |
| `:lvimgrep /…/` | Puts the places in the location list of the window. |
| `:vimgrepadd /…/` | Adds the places to the current list. |

You can then use the list like any quickfix list, with `]q` and `[q`, and `:copen`. `:cdo` and `:cfdo` run a command on every place, as one undo step. For example, `:vimgrep /^Viol/ track` and then `:cdo track.mute` mutes every track whose name starts with Viol. [The quickfix list](quickfix.md) has the details.

`<Space>fg` shows the same text in a picker that filters while you type, and `Ctrl-q` sends the lines that match to the list. The picker reads the text in short steps after it opens, and the query line says `reading…` until it has all of it.

## Lua

| Function | Effect |
| --- | --- |
| `paw.grep.search(pattern, opts)` | Gives the records found, `{ text, field, location, where }`. `opts`: `{ mode = "regex", fields = { lyric = true } }`. |
| `paw.grep.records()` | Gives all records. |
| `paw.grep.reader()` | Gives a function `read(ms)` that reads the records in steps. Each call gives the records found in about `ms` milliseconds, and true when all are read. |
| `paw.grep.source(name, fn)` | Adds a source of text. `fn(add)` calls `add` with each record. |

```lua
paw.grep.source("chords", function(add)
  add({ text = "Cmaj7", field = "chord", location = "paw://clip/4", where = "Verse 5.1.00" })
end)
```
