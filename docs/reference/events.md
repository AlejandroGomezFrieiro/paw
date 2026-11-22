# Events

<!-- tags: scripting-events -->

Every event of paw is listed below, with the payload that its handler gets.

## Listen and send

| Function | Effect |
| --- | --- |
| `paw.on(name, fn)` | calls `fn(payload, name)` for the event |
| `paw.on("family.*", fn)` | listens to a family of events, for example `clip.*` |
| `paw.on("*", fn)` | listens to all events |
| `paw.emit(name, payload)` | sends an event of your own |
| `paw.flush()` | delivers the change events now |

## When events arrive

- Change events come from the kernel. paw delivers them when the current command or callback returns, or at `paw.flush()`, and the other events arrive when they occur.
- A command or a key press is one undo step. A handler can answer an edit with edits of its own, and those edits join the same undo step.
- Events from undo, redo, the undo tree or `project.loaded` have `restored = true`, because that state already holds the answers of the handlers.
- Some events ask a question, namely `edit.before`, `project.saving` and `key.pre`. A handler that returns `false, "why"` refuses the action, and `paw.emit` then returns `false, "why"` to the code that sent the event.
- paw calculates `edit.before`, `edit.after`, `selection.changed`, `view.opened` and `view.closed` at the end of each turn, and it sends `key.pre`, `undo` and `redo` when they occur.
- paw sends those eight events only when a handler listens to them by name or by family, so `paw.on("*")` alone does not get them.

## Every event

| Event | Payload | When |
| --- | --- | --- |
| `changed` | `{}` | something in the project changed in this turn. paw draws the screen again |
| `project.changed` | `{}` | a field of the project changed: tempo, signature, name, meta |
| `project.loaded` | `{ path }` | a project opened, or a new project started |
| `project.saving` | `{ path }` | paw will write a project. A handler can refuse |
| `project.saved` | `{ path, written, unused, moved }` | paw wrote the project; for a project folder, the files written, moved to `unused/` and moved |
| `files.changed` | `{ paths }` | files of the project changed outside paw (see [Project files](project-files.md#changes-from-outside-paw)) |
| `track.added`, `track.changed`, `track.removed` | `{ id }` | a track, by its id |
| `track.moved` | `{ order }` | the order of the tracks changed |
| `track.frozen`, `track.thawed` | `{ id, file }` | a track is rendered to a file and plays from it, or plays live again |
| `device.added`, `device.changed`, `device.removed` | `{ id, track }` | a device in the project |
| `device.added_by_hand` | `{ id, kind }` | the user added a device (not a script) |
| `device.ready`, `device.stopped`, `device.invalid` | `{ id, track, name, ... }` | a plugin is ready, stopped (it crashed or went offline), or cannot be used |
| `preset.loaded` | `{ id, name }` | a preset loaded into a device |
| `param.touched` | `{ device, param, from }` | a parameter moved in the editor of the plugin |
| `clip.added`, `clip.changed`, `clip.removed` | `{ id, track }` | a clip |
| `clip.copied` | `{ clip, name, origin }` | the first edit of a clip from a file outside the project made it the project's own |
| `track.copied`, `chain.copied` | `{ track, name, origin }` | the first edit of a track from a track folder outside the project, or of a chain from a chain file outside it, made it the project's own |
| `lane.added`, `lane.changed`, `lane.removed` | `{ id, track }` | an automation lane |
| `lanes.changed` | `{}` | the shown lanes changed |
| `cue.changed` | `{ track }` | the clips off the timeline of a track, which cues play ([About cues](../explanation/about-cues.md)) |
| `edit.before` | `{ changes }` | a turn edited the project, and the edit will become an undo step. `changes` is a list of `{ name, payload }`: the events above that make the edit. A handler can refuse: paw then puts the project back as the turn found it. Edits of a handler join the step |
| `edit.after` | `{ changes, state }` | paw made the step. `state` is its id in the undo tree. Edits made here are a separate edit |
| `undo`, `redo` | `{ from, to, how, label }` | a move in the undo tree. `from` and `to` are states, `label` the step. `how` is `undo`, `redo`, `goto`, `step` or `travel`. A jump to an older state is an `undo` |
| `transport.play`, `transport.stop` | `{ position, count_in }` | the transport started (after the count-in) or stopped |
| `transport.seek` | `{ position }` | the playhead moved |
| `transport.record` | `{ ... }` | recording started, or a take started |
| `transport.changed` | `{}` | the loop, the punch, the metronome or a similar setting changed |
| `midi.in` | `{ port, ... }` | a MIDI message arrived |
| `midi.lost`, `midi.returned` | `{ port, tracks }` | a MIDI port disappeared, or is available again |
| `audio.lost`, `audio.restored` | `{ device, ... }` | the audio device disappeared, or is available again |
| `engine.started` | engine info | the audio engine started or started again |
| `bake.progress` | `{ running, waiting, fraction }` | paw makes sound for clips (stretches) in the background: at most 4 times each second, and one time when all are done |
| `media.missing` | `{ files, found }` | the sound files of a project are not at their paths |
| `proc.output` | `{ id }` | a helper process wrote output (see [Timers, programs and other modules](lua-other.md#helper-programs)) |
| `render.before` | `{ path, opts }` | a render will start |
| `render.progress` | `{ path, fraction, ... }` | a render in the background moved forward |
| `render.done`, `render.failed`, `render.cancelled` | `{ path, ... }` | a render in the background stopped |
| `render.finished` | render info | `paw.render` returned |
| `mode.changed` | `{ mode, old }` | the mode of the keymap changed |
| `key.pre` | `{ key, mode, view }` | a key, before the keymap gets it. A handler can refuse: then the key does nothing more |
| `escape` | `{}` | Escape had nothing to cancel |
| `cursor.changed` | `{ track, beat, lane }` | the cursor moved. In Teal, its descriptor is `paw.cursor.changed` |
| `selection.changed` | `{ view, kind, region, clips, notes }` | the selection changed. `kind` is `region` (visual mode, `region` as an operator gets it), `clips` (ids, selected with the pointer), `notes` (notes of the clips that the piano roll edits, `{ clip, place }`) or nil |
| `command.pre`, `command.post` | `{ name, command, args }` | before and after a command |
| `option.changed` | `{ name, value, old }` | an option got a different value |
| `view.focused` | `{ view, old }` | another view gets the keys |
| `view.opened`, `view.closed` | `{ name }` | a view came on the screen, or went off the screen |
| `pianoroll.opened` | `{ clip }` | the piano roll opened a clip |
| `roll_clips.changed` | `{ active, count }` | the clips that the piano roll edits changed |
| `win.enter`, `win.leave` | `{ win }` | the keys went into a window, or left it |
| `win.resized` | `{ win }` | a window changed size |
| `win.option` | `{ win, name, value }` | a window option changed |
| `buf.enter`, `buf.leave` | `{ buf, name }` | a window shows a different buffer |
| `tab.enter` | `{ tab }` | a different tab |
| `ui.resized` | `{ width, height }` | the screen changed size |
| `ui.focus` | `{ focused }` | the terminal (mode 1004) or the window got the focus of the desktop, or lost it |
| `scope.changed` | `{ scope }` | the tab shows a different scope (`paw.scope`), or the whole song. `scope` is the innermost group of the scope, if any |
| `seat.opened`, `seat.closing` | `{ seat }` | a terminal or a graphical window attached, or will go |
| `address.changed` | `{ uris, revision }` | things with addresses changed (`paw/address.tl`). In Teal, its descriptor is `paw.address.changed` |
| `annotation.changed`, `diagnostic.changed` | `{ namespace, document, ... }` | annotations or diagnostics changed. In Teal, the descriptor of `diagnostic.changed` is `paw.diagnostic.changed` |
| `qf.changed` | `{ title, win }` | the quickfix list or a location list changed. In Teal, its descriptor is `paw.qf.event`: `paw.qf.changed` is a function |
| `lsp.status` | `{ client, status, document }` | a language server started, failed or stopped. In Teal, its descriptor is `paw.lsp.status_changed` |
| `lsp.analysis` | `{ clip, client }` | the analysis of a clip arrived from a language server. In Teal, its descriptor is `paw.lsp.analysed` |
| `harmony.changed` | `{ provider }` | the chords that paw hears changed |
| `complete.changed` | `{ shown }` | suggestions appeared or disappeared. In Teal, its descriptor is `paw.complete.changed` |
| `snippet.expanded`, `snippet.finished` | `{ name, clip }` | a snippet. In Teal, the descriptors are `paw.snippet.expanded` and `paw.snippet.finished` |
| `plugins.scanned` | `{ notes, ... }` | a scan for plugins ended |
| `luadev.checked` | the results | paw checked the devices in Lua again |
| `ext.loaded` | `{ name, ok }` | an extension loaded, or failed to load |
| `ext.unloading`, `ext.unloaded` | `{ name }` | paw will unload an extension, and unloaded it |
| `startup` | `{}` | the runtime, the extensions and the configuration loaded |
| `exit` | `{}` | the program will stop |
