# Pickers

<!-- tags: pick telescope -->

A picker chooses one thing from many, and you type some letters of the thing to find it. `<Space>f:` runs a command by name, and the other pickers are under `<Space>f` (`<Space>` is the leader). The key after `<Space>f` is the key of the same thing on the leader, so `<Space>fc` finds clips and `<Space>cf` fades a clip, `<Space>fd` finds the devices of the track and `<Space>dd` shows them, and `<Space>fr` finds regions and `<Space>rn` makes one.

## The pickers

| Keys | Command | Lists | `Enter` |
| --- | --- | --- | --- |
| `<Space>f:` | `pick.commands` | every command, with its key. A match in the name ranks above a match in the description, and a name that is the typed word, or starts with it, ranks above the others (`arrange` finds `:arrange`). Among equal matches, the commands that you ran from here come first, and then those that the focused view has keys for. | runs it. `Ctrl-e` types it on the command line, for arguments. |
| `?` `<Space>fk` | `pick.keys` | every key of the focused view and the global keys, written as `Alt-h`, `Space at` and `Ctrl-w o`. Each has a tag for where it works, and for whether it is a motion, an operator, a text object, or a key for a selection or insert mode. The keys of the view come first and then the global keys, and plain keys come before operators, motions and the others, and short keys before long keys. Keys that do the same share one line (`Ctrl-z, u`). The right side shows the section of the manual for the chosen key. The keys of the other views come last, with a tag (`arrange view`), so `send` in the mixer finds `<Space>ts` of the arrange view. | runs it. A key of a different view goes to that view. |
| `<Space>ft` | `pick.tracks` | the tracks | moves the cursor to the track |
| `<Space>fc` | `pick.clips` | every clip, with its track | goes to it |
| `<Space>da` | `pick.devices` | the devices and plugins that you can add | adds it to the track of the cursor |
| `<Space>fd` | `pick.track_devices` | the devices on the track | shows it in the device panel. `Ctrl-e` opens the window of the plugin. |
| `<Space>f'` | `pick.marks` | the marks | goes to the mark |
| `<Space>f"` | `pick.registers` | the registers | pastes it at the cursor, or plays a macro |
| `<Space>fl` | `pick.messages` | the earlier messages, newest first | shows the full message |
| `<Space>ff` | `pick.files` | projects, audio and MIDI files under the working directory | opens the project, adds the audio at the cursor, or adds the tracks of the MIDI file there |
| `<Space>fo` | `pick.options` | the options and their values | switches a true or false option, or asks for a new value |
| `<Space>pr` | `recent` | the recent projects, with their place and when each was last opened. `Alt-d` removes one. | opens it |
| `<Space>fh` | `pick.help` | every help tag, with its page | goes to it |
| `<Space>fm` | `pick.markers` | the markers, with what plays there | goes to it |
| `<Space>fr` | `pick.regions` | the regions, with what plays there | goes to it |
| `<Space>fg` | `pick.grep` | every text in the project, which means the names of tracks, clips, markers and devices, lyrics, articulations, comments and the tags of the project. It is a live grep, and it starts in exact mode. | goes to it |
| `<Space>fn` | `pick.notes` | every note, with its pitch, velocity, lyric, articulations, clip and place, and with the clip drawn next to it. You hear a note when the selection stops on it. | goes to it |
| `<Space>fa` | `pick.media` | the sound files of the project, and the clips that play each | adds it at the cursor |
| `<Space>fq` | `pick.quickfix` | the entries of the quickfix list | goes to it |
| `<Space>fu` | `pick.undo` | the states of the undo history, newest first, with what each state changes | goes there |
| `<Space>fe` | `pick.extensions` | the extensions, loaded or not, with their README | shows its help, or loads it |
| `<Space>fs` | `pick.symbols` | every function of the Lua API, with its parameters and its comment | shows its help |
| `<Space>fP` | `pick.presets` | the presets of the device (as `:preset`) | loads it |
| `<Space>fp` | `pick` | every picker | opens it |
| `<Space>f.` | `pick.resume` | the last picker as it was, with the typed text, the mode and the line (`:pick resume`) | |

`:pick tracks` opens a picker by name, and `:pick devices query=reverb` or `:pick.devices reverb` opens it with text typed.

## The device picker

`a` in the arrange view and the device panel, and `:device.add` with no name, choose the device in a picker. The picker lists your favorites first (`Ctrl-f` marks one, with `★`), then the devices that you added last, and then the others.

| Typed | Filter |
| --- | --- |
| `@instrument`, `@instr` | instruments |
| `@effect`, `@fx` | effects |
| `@clap` `@lv2` `@vst3` `@builtin` | a plugin format, or the built-in devices |
| `@fav` | the favorites |
| `@` and the start of the name of a vendor | the devices of that vendor (`@surge`) |

`Ctrl-t` steps between instruments, effects and both. A match in the name of a device ranks above a match only in its vendor, the full name ranks first, and the device that you chose for the same words last time comes first.

The "Add a device" box of the graphical window takes the same words and gives the same order, and it marks a favorite with the `☆` next to each line. paw keeps the favorites, the recent devices and those choices in `~/.local/state/paw/devices.json`. A plugin is an instrument if it says so (CLAP features, VST3 subcategories, LV2 classes), and the scan cache keeps this.

## Keys in a picker

The text that you type filters the list. The best match is at the top and selected, marked `▶`, and the letters that match are highlighted.

| Keys | Effect |
| --- | --- |
| `Ctrl-n` `Ctrl-p`, `Ctrl-j` `Ctrl-k`, arrows | Move. |
| `PageUp` `PageDown` | Move a page. |
| `Enter` | Chooses. |
| `Esc` | Cancels. |
| `Backspace`, `Ctrl-w` | Delete a character, a word. |
| `Ctrl-u` | Clears the text. |

The bottom of a picker lists its own keys. If the picker has a preview, a pane on the right shows more about the selected line, e.g., the notes of a clip as a small piano roll with the chosen note drawn `▓`, the waveform of an audio clip, a help page, or the comment of a function.

### Keys of every picker

The keys below work in every picker. The own keys of a picker come before them, e.g., `Ctrl-t` in the device picker steps between instruments and effects.

| Keys | Effect |
| --- | --- |
| `Tab` `Shift-Tab` | Mark the line and move (`+` marks it). |
| `Ctrl-a` | Marks every line that matches, or none. |
| `Ctrl-v` `Ctrl-x` `Ctrl-t` | Open the chosen thing in a window next to this one, below it, or in a new tab: a MIDI clip or a note in the piano roll, a device in the device panel, the others in the arrange view, and a help tag as a page. |
| `Ctrl-q` | Sends the marked lines (or every line that matches) to the quickfix list, with the picker and the typed text as its title, and opens its window. |
| `Ctrl-l` | Sends them to the location list of the window. |
| `Ctrl-y` | Types the line on the command line (for a Lua function, `lua paw.x(`). |
| `Alt-d` | Deletes the marked things, or the thing of the line: tracks, clips, notes, markers, recent projects. The picker stays open, and `u` undoes the deletion. |
| `Ctrl-r` | The next mode: fuzzy, exact, regex. |
| `Ctrl-Up` `Ctrl-Down` | The text typed before in this picker, newest first. |
| `Ctrl-Space` | Starts or stops the audition (below). |

## Match rules

The match is fuzzy, so the typed letters must be in the line in that order, but not necessarily together, and `dfh` finds `Dragonfly Hall`.

- A line ranks higher when the letters are consecutive, when they start words (after a space, `/`, `:`, `.`, `_`, `-`, or at a capital letter inside a word), and when the line is shorter.
- Words separated by a space must each match, in any order, e.g., `hall drag`.
- Lowercase matches each case. A word with a capital matches case exactly.
- `'hall` matches as written, `^drag` at the start of the line, `hall$` at its end, `!plate` not in it.

`Ctrl-r` steps the mode, and the modes are in this table.

| Mode | Effect |
| --- | --- |
| fuzzy | as above |
| exact | each word as written, anywhere. `<Space>fg` starts in this mode. |
| regex | the whole typed line is a regular expression: `. * + ? {n,m} ^ $ [a-z] \d \w \s`, `\|` between alternatives, `( )` around alternatives. Lowercase ignores case. |

A mode that is not fuzzy shows next to the count, and a picker keeps the mode that it had last. A regular expression that paw cannot read shows the reason in place of the list.

The notes of a thousand tracks open in less than a second, and each key takes tens of milliseconds, because each key filters the last matches and paw draws only the lines on the screen.

## Audition

<!-- tags: audition pickers-you-can-hear -->

In the pickers in this table, you hear the item under the selection when the selection stops on it for `paw.opt.audition_delay` ms (150). The top of the pane says what plays, as in `▶ Soft pad · loop bar 5`.

| Picker | What you hear |
| --- | --- |
| presets (`:preset`) | The preset loaded into the device, with the notes of the track, which are the bar of its MIDI clip at the cursor (or the last bar before it with notes), again and again. A track without notes plays a built-in phrase in the key of the song (a beat on a drum track). When you move, paw loads the next preset over the same loop. |
| devices (`<Space>da`) | The device added to the track of the cursor, with the same phrase. paw makes a plugin in a separate process, so the selection stops on it for 600 ms first, and the pane shows `… loading` until the plugin plays. |
| files (`<Space>ff`, and the file picker of `:import`) | A sound file alone, from its start, over everything else at `paw.opt.audition_level` dB (-12), with its outline and the place that it plays. A MIDI file plays its first two bars, at its own tempo, through the track of the cursor if it has an instrument, and otherwise through a synth (and a kit for its drums) that paw adds for this. |
| beats (`:drums.beat`) | The beat written into the clip, its first bar again and again. |
| snippets (`Ctrl-s` in the piano roll) | What the snippet writes, one time, with what the other pitched tracks play over the same beats. |
| tracks, clips, notes, media | With `Ctrl-Space`: the first two bars of a clip through its track, a note with the chord that it starts, an audio file. The tracks picker starts with audition off. |

What you try on the project is a trial, which paw makes so that you hear and see it as any edit. `Esc` puts everything back exactly as it was, with no undo step, and the project is not marked as changed. `Enter` on the item that you hear keeps it, as the one undo step of the choice, and paw keeps the plugin that it loaded and does not make it again.

- No phrase plays while the transport runs, and you then hear the song, with the preset or device in it.
- `Ctrl-Space` turns audition off and on for that kind of picker, and paw remembers the setting until it stops.
- `♪` marks what plays, in the pane and in place of the cursor arrow on its row, and the pane says so when audition starts.

## In the graphical window

The graphical window shows a picker as it shows any float, through `paw.frontend.float`. The selected line has the mark `▶` as well as a color, and the preview pane shows with its piano roll and waveform.

## Lua

```lua
paw.pick({
  title = "Tracks",
  items = { { text = "Bass", id = 3 }, { text = "Drums", id = 4 } },   -- or a function that gives the list; an item can be a string
  format = function(item) return item.text end,   -- optional: the line that shows and matches
  on_choose = function(item) paw.cursor.set_track(item.id) end,
  on_cancel = function() end,                     -- optional: Esc
})
```

`on_choose` gets the item itself, as it was given, and if `items` is a function, paw calls it each time that the picker opens.

| Field | Effect |
| --- | --- |
| `query` | Text typed at the start. |
| `preview(item, width, height)` | Lines for a pane next to the list: strings, or `{ text = ..., style = "Title" }`. It gets the size of the pane. |
| `actions` | Other keys: `{ ["<C-e>"] = function(item, query) end }`, or `{ fn = ..., desc = "edit", keep = true }` to list the key at the bottom and keep the picker open. |
| `multi` | `Tab` marks several lines. `on_choose_multi(items)` gets them, and otherwise paw calls `on_choose` for each. With `multi = false`, `Tab` does not mark. |
| `empty` | The message when there is nothing to choose. |
| `more(ms)` | For a picker with many items. paw calls it again and again after the picker opens, in slices between keys (the job `pick` of `paw.slices`). It reads for at most `ms` milliseconds and gives the next items, true when there are no more, and a note for the query line, for example `reading…`. paw filters and draws what it read at most every 100 ms and at the end. |
| `boost(item)` | A number (up to 120) added to the score of an item that matches, e.g., for things used often, or things of the focused view. |
| `primary(item)` | The part of the line that counts first: lines that match there rank above lines that match only elsewhere. |
| `audition(item)` | Makes the item audible when the selection stops on it. It gives the label of the pane, or `{ label, loading = function, keep = function(item) }`: `keep` runs in place of `on_choose` when you choose the item that plays, and keeps its trial. `audition_key` names the setting that `Ctrl-Space` keeps. `audition_default = false` starts with audition off. `audition_delay(item, ms)` waits longer on a slow item. |
| `location(item)` | The address (`paw://clip/7`) or location of the item. `Ctrl-v`, `Ctrl-x`, `Ctrl-t` open it, and `Ctrl-q` sends it to the quickfix list. |
| `open(item, how)` | Opens the item in its own way, where `how` is `"vsplit"`, `"split"` or `"tab"`. It replaces `location`. |
| `delete(items)` | `Alt-d`: deletes them (the marked items, or the line). |
| `insert(item)` | `Ctrl-y` uses it in place of the line on the command line. |
| `mode` | `"exact"` or `"regex"` at the start, in place of `"fuzzy"`. |
| `prompt`, `width`, `height` | The prompt and the size of the picker. |

| Function | Effect |
| --- | --- |
| `paw.pick.sources` | The pickers by name, in a registry (see [Extensions](extensions.md#registries)). `paw.pick.sources:put(name, source)` adds one, `:get(name)` gives one and `:remove(name)` takes one away. A source has the fields above and a `desc`, or is a function that gives them. See [How to add a picker](../how-to/add-a-picker.md). |
| `paw.pick.show(location, how)` | Opens a location next to, below or in a tab, as `Ctrl-v` does. |
| `paw.pick.match(query, line, true, mode)` | Gives the score and the positions that match. |
| `paw.pick.filter(query, items, format, primary, mode)` | Gives the items that match, best first. |
| `paw.pick.state()` | Gives the query, mode, matches, marked items and selection of the open picker. |
| `paw.pick.resume()` | Opens the last picker again, as it was. |
| `paw.pick.keys` | The keys of every picker. |
| `require("paw.pick.preview").clip(id, width, height, note_id)` | Draws a clip as the clips picker does. |

### `paw.audition`

The pickers use `paw.audition`, as in this example.

```lua
paw.audition.try(function() paw.fx.load(device, "Plate") end)   -- an edit that can be undone
paw.audition.through(track.id)        -- play the bar of the track at the cursor through it, again and again
paw.audition.phrase(track.id, { { pitch = 60, start = 0, length = 1, velocity = 100 } }, { length = 4 })
paw.audition.file("/samples/kick.wav")  -- alone, at paw.opt.audition_level
paw.audition.keep()                     -- the trial becomes one undo step
paw.audition.stop()                     -- silence, and the trial is undone
paw.audition.state()                    -- what plays: the notes of a phrase, or the place and outline of a file
```

Under it, `api.trial_begin()` and `api.trial_end(keep)` surround the edits. `api.preview_play(path)`, `api.preview_stop()`, `api.preview_get()` and `api.preview_level(db)` control the preview bus, which is a voice in the engine after the master, and paw never records, renders or saves it.
