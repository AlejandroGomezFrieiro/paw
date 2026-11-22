# Addresses, diagnostics and lists in Lua

This page describes the addresses of paw and the modules that use them, which are diagnostics, annotations, language servers, the quickfix list and the search of the project.

## `paw.address`

Each thing in the project has an address, which is a URI made from ids.

| URI | What |
| --- | --- |
| `paw://project` | the project |
| `paw://track/12` | a track. `paw://track/0` is the master |
| `paw://track/12/device/3` | a device on the track |
| `paw://track/12/device/3/param/cutoff` | a parameter of the device |
| `paw://track/12/send/5` | the send of the track to track 5 |
| `paw://clip/7` | a clip |
| `paw://clip/7/note/41` | a note, by its id (`note.id`). The id stays with the note through every edit |
| `paw://clip/7/control/cc/74` | the moves of one controller in a clip |
| `paw://lane/9` | an automation lane |
| `paw://tempo`, `paw://marker/5` | the tempo map, a marker |
| `paw://render/<path, %-encoded>` | a rendered file |
| `paw://<kind>/...` | a kind that an extension adds with `paw.address.scheme(kind, { resolve, children, parent, edit })` |

| Function | Effect |
| --- | --- |
| `of(object)` | the address of an object |
| `resolve(uri)` | the data of `paw.api` for the address. A note also gives its `place` |
| `parent(uri)`, `children(uri)` | the address above, the addresses below |
| `within(uri, ancestor)` | true when `uri` is below `ancestor` |
| `track_of(uri)` | the track of an address |
| `matches(pattern, uri)` | `*` matches one level, `**` any number of levels |
| `track(id)`, `device(id)`, `param(device, key)`, `clip(id)`, `note(clip, id)`, `render(path)`, and other | make an address |
| `renders` | the rendered files, by path |
| `edit(changes, label)` | an edit of the workspace. Each change is `{ uri, set = { ... } }`, `{ uri, insert = { ... } }` or `{ uri, delete = true }`. paw checks all the changes first, then makes them as one undo step. It returns nil and the reason when it cannot |

The event `address.changed { uris, revision }` comes after every edit.

## `paw.diagnostic`

`paw.diagnostic` works like `vim.diagnostic`, but it uses locations. A location is `{ uri, selector }`, and the selector is `{ time, notes, pitch, seconds, value }`.

`set(namespace, document, list)` sets the diagnostics of a document. Each diagnostic is `{ location, severity, message, rule, source, fixes }`, with these rules:

- `severity` is 1 to 4, or `"error"`, `"warning"`, `"info"`, `"hint"`.
- A fix is `{ title, edit = { changes } }` or `{ title, apply = fn }`.
- paw also accepts an older form, with a clip as the document and `{ notes = { places }, at, length, fixes = { { title, edits } } }` as each diagnostic.

| Function | Effect |
| --- | --- |
| `get(target, { namespace, severity, note, kind, document })` | the diagnostics of a clip id or an address |
| `count`, `worst(uri)` | how many, and the worst severity |
| `kind(d)`, `about(d, uri)`, `where(d)` | facts about one diagnostic |
| `reset(namespace, document)` | removes diagnostics |
| `config({ virtual_text, signs, underline, severity_sort })` | how diagnostics show |
| `actions(target, place)`, `apply(d, fix)` | the fixes, and apply one |
| `jump(dir)`, `list()` | move to the next or previous one, list them |
| `setqflist({ target, severity, title, open })`, `setloclist(...)` | put them in the quickfix list or a location list |

The event is `diagnostic.changed`.

## `paw.annotation`

`paw.annotation` keeps labels in the way that `paw.diagnostic` keeps diagnostics, with `set(namespace, document, { { location, label, kind } })`, `get(uri)` and `reset`.

## `paw.lsp`

`paw.lsp` follows `vim.lsp`. See [Language servers and diagnostics](language-servers.md).

| Function | Effect |
| --- | --- |
| `config(name, { cmd or server, kind, framing, adapter, attach = { subjects, where }, settings, init_options, restart, timeout_ms, accepts, input, diagnostic })` | defines a server |
| `enable(name, on)`, `clients()`, `restart(name)`, `stop(name)` | control servers |
| `request(name, method, params, function(err, result) end)`, `notify(name, method, params)` | send a message |
| `paw.lsp.handlers[method] = function(client, params) end` | receive a message |
| `subject(name, { targets, build, key, depends, language })` | what a server reads |
| `adapter(name, spec)` | an adapter for a server |
| `hover_at(location, cb)`, `actions_at(location, cb)` | ask at a location |
| `show_hover()`, `code_actions()` | show at the cursor |
| `hover(clip, pitch, beat, cb)`, `complete(ctx, done)` | ask for a note, ask for completions |
| `attach(name, address)` | keep a subject open |
| `settle()` | wait for the servers, for scripts |

The events are `lsp.status` and `lsp.analysis`.

## `paw.qf` and the quickfix list

`paw.qf` is the quickfix list and the location lists of Neovim, but it uses addresses. An entry is `{ address, selector, text, level, source, fix }`, with these rules:

- `address` is a `paw://` address, or a location.
- `level` is `"error"`, `"warning"`, `"info"`, `"hint"` or nil.
- `fix` is `{ title, edit = { changes } }`, `{ title, apply = function(entry) end }`, or a command line that runs with the cursor on the entry.

```lua
paw.qf.feed("tuning", { { address = "paw://clip/4", text = "out of tune", level = "warning",
  fix = { title = "Tune it", apply = function(e) end } } })
paw.qf.set({ { address = paw.address.track(3), text = "too quiet" } }, { title = "Levels" })
```

| Function | Effect |
| --- | --- |
| `set(entries, { title, win, current })` | puts a list in the history and makes it current. The history keeps ten lists. A list with the same title replaces the old one at its place. `win` (the number of a window, or true for the current window) makes it the location list of that window |
| `feed(source, entries)` | replaces the entries of a source in the Problems list, the list that paw keeps |
| `source(name, fn)`, `changed(name)` | paw asks `fn` for the entries of a source only when the list shows next |
| `current(stack)`, `stack()`, `loc_stack(win)`, `fed(source)`, `count(list)` | read the lists |
| `jump(n)`, `step(n)`, `first()`, `last()`, `older(n)`, `newer(n)`, `go(entry)`, `where(entry)` | move in the lists |
| `cdo(line, { per_track })` | run a command at each entry. The command gets the address of the entry as `ctx.target` and its location as `ctx.location` |
| `fix(entries)` | apply the fixes |
| `diagnostics(opts)` | a list of the diagnostics |
| `open({ loc, height })`, `close(loc)` | show or hide the list |

The event is `qf.changed { title }`. The program also listens to `plugins.scanned { notes, name }`, which reports what a plugin scan could not use.

## Search the project

| Function | Effect |
| --- | --- |
| `paw.query(q)` | finds nodes of the tree of the project by a query (`"clip[name~=pizz] > note[pitch>=C5]"`, or a table of steps) |
| `paw.query.select(q)` | selects them |
| `paw.query.field(kind, name, get)` | adds a field to queries |
| `paw.grep.search(pattern, { mode, fields })` | finds text in the project |
| `paw.grep.source(name, function(add) end)` | adds text to the search |
| `paw.regex.compile(text)` | makes a usual regular expression (`re:find(s)`) |

[Motions, operators and modes](grammar.md) describes the syntax, under "Structural queries" and under the search of text.
