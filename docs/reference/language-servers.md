# Language servers and diagnostics

<!-- tags: lsp language-servers -->

A language server reads a part of the project and reports problems in it.
Examples are a parallel fifth, a fader that clips, a master louder than
the delivery target, and a render without dither. The modules are `paw.lsp` and
`paw.diagnostic`, after `vim.lsp` and `vim.diagnostic` in Neovim. For the
design, see [About language servers](../explanation/about-language-servers.md).
For the steps to write a server, see
[How to write a language server](../how-to/write-a-language-server.md).

## What a server gives

| Feature | Where it goes |
| --- | --- |
| diagnostics | the views, `:diagnostics`, the status line |
| fixes and actions | `<Space>ca`, one undo step for each |
| hover | `gK` |
| chords and keys | `paw.harmony` (see [Harmony](harmony.md)) |
| suggestions | `paw.complete`, as a source (see [Completion](completion.md)) |
| labels (annotations) | next to the thing that they name, for example a loudness value on a mixer strip |

## How diagnostics show

The terminal shows diagnostics first. The graphical window shows the same
diagnostics.

| Subject of the diagnostic | Terminal | Graphical window |
| --- | --- | --- |
| notes | a line under the notes in the piano roll, in the color of the severity, the message after the last note, a mark on the ruler | an outline around the notes, the message in the hint line |
| a track | a sign before the name in the track header, and at the end of the name on the mixer strip | the same |
| a device or a parameter | a sign and the message after the device name in the device panel, a sign before the parameter name | the same |
| a part of the song | a mark on the ruler of the arrange view | the same |
| a render | a line under Renders in `:diagnostics`, with fixes that render again | the same |

The severity colors are red (error), amber (warning), blue (information)
and gray (hint). The status line counts the diagnostics (`E1 W2`) of the
clip in the piano roll. If no clip is open, it counts the diagnostics of
the project. A label of a server on a track shows on the peak row of the
mixer strip.

## Keys and commands

| Keys, command | Effect |
| --- | --- |
| `]d` `[d` | Go to the next or previous diagnostic in the focused view (piano roll, arrange view, mixer, device panel). |
| `gK` | Show what is known about the thing under the cursor: diagnostics, labels, and the hover of each server. |
| `<Space>ca` | Show the fixes and actions for the thing under the cursor. `Enter` applies one, as one undo step. |
| `:diagnostics` | List every diagnostic, grouped by subject. `Enter` goes to one. `:diagnostics clip`: only the clip in the piano roll. |
| `:lsp info`, `:lsp` | Show each server: how it runs, its subjects, its features, its last error. |
| `:lsp start`, `:lsp stop`, `:lsp restart` | Start, stop or restart a server (with a name: only that server). |
| `:lsp log` | Open the log of the servers. |

In the graphical window, Ctrl and a right click on a note opens its fixes
and "What the language servers say about it".

## Addresses

Each thing in the project has an address, a URI made from ids. An address
stays correct after edits. The module is `paw.address` (see
[The Lua interface](scripting.md) for every kind).

| Address | Thing |
| --- | --- |
| `paw://project` | the project |
| `paw://track/12` | a track (`paw://track/0` is the master) |
| `paw://track/12/device/3` | a device |
| `paw://track/12/device/3/param/cutoff` | a parameter |
| `paw://track/12/send/5` | a send |
| `paw://clip/7` | a clip |
| `paw://clip/7/note/41` | a note |
| `paw://lane/9` | an automation lane |
| `paw://tempo` | the tempo map |
| `paw://marker/5` | a marker |
| `paw://render/<path>` | a rendered file |

Extensions can add kinds of address.

Each note has an id. paw gives the id when it makes the note, and the id
stays with the note through each move and change. A copy of a note is a
different note with its own id.

### Locations

A location is an address, and optionally a part of the thing: `{ uri,
selector }`.

| Selector | Part |
| --- | --- |
| `{ time = { from, to } }` | a time range, in beats |
| `{ notes = { ids } }` | some notes |
| `{ pitch = { lo, hi } }` | a pitch range |
| `{ seconds = { from, to } }` | a time range in a render, in seconds |
| `{ value = x }` | a value |

### Workspace edits

A workspace edit is a list of changes. paw checks all the changes before it
applies one, and applies them as one undo step. Every fix and every edit
that a server asks for is a workspace edit.

| Change | Effect |
| --- | --- |
| `{ uri, set = { ... } }` | Set fields of the thing. |
| `{ uri, insert = { ... } }` | Insert a thing. |
| `{ uri, delete = true }` | Delete the thing. |

The changes that paw accepts:

- a note: pitch, start, length, velocity
- a clip: insert notes
- a track: volume, pan, mute, solo, name, output, insert a device
- a device: bypass, parameters
- a parameter: value
- a send: level
- a render: render again with other options

## Subjects

A server gets subjects. A subject is a part of the project as plain data,
in a document named by its address. If the subject is not the usual
subject of the address, the name has `#subject` at the end.

| Subject | Document | Contents | With `focus` |
| --- | --- | --- | --- |
| `clip` | `paw://clip/7` | The notes in ticks (960 to the beat) with their ids, the track and its devices, the time signature and the bar where the clip starts, the tempo map over the clip, the key, the controller moves, and as `context` the notes of other tracks that sound with it. This is the format of MIDI LSP. | the clips open in a piano roll |
| `track` | `paw://track/3` | The fader, pan, mute, solo, output and sends, the devices with the values and ranges of their parameters, and the clips. | the track at a cursor |
| `mix` | `paw://project#mix` | Each track as above with its address, the master, the tempo and time signatures, the sample rate, the loudness targets, the options of the last render. | |
| `project` | `paw://project` | A summary: the tracks with their number of clips and devices, the markers, the tempo, the length. | |
| `render` | `paw://render/...` | A rendered file: its path, format, rate, bits, channels, length, measured peak and loudness, its render options, the devices of the master. | |

The loudness targets of the `mix` subject are `paw.opt.loudness_target`
(-14 LUFS) and `paw.opt.true_peak_target` (-1 dBTP).

paw sends a document when a server attaches to it. paw sends it again when
an address that it uses changes and the document is different. The send
waits until the edits stop for 250 ms. paw closes the
document when the thing goes.

A server attaches to subjects in this order:

1. by the `attach` field of its config:
   `attach = { subjects = { "mix", "render" }, where = { focus = true, tracks = { "Flute*" }, drums = false } }`
2. else, by the subjects that it asks for in its `initialize` answer
   (`capabilities.paw.subjects`)
3. else, to clips.

With `focus = true`, the server gets only what a person looks at: the clip
in the piano roll, the track at the cursor. Without it, a server of the mix
or of renders gets the full subject at all times.

## Server config

`paw.lsp.config(name, config)` tells paw how to start a server.
`paw.lsp.enable(name)` starts it.

```lua
paw.lsp.config("mixcheck", {
  cmd = { "python3", "/path/to/mixcheck.py" },  -- or a function that gives it
  framing = "lines",                       -- or "headers" (Content-Length)
  attach = { subjects = { "mix" } },
  init_options = { target = -14 },         -- sent once, at initialize
  settings = { strict = true },            -- sent at initialize, and again when they change
  restart = { max = 3, within_s = 60 },    -- restarts after it stops (none by default)
})
paw.lsp.enable("mixcheck")
```

| Field | Value |
| --- | --- |
| `cmd` | The program and its arguments, or a function that gives them. |
| `framing` | `"lines"`: one message for each line. `"headers"`: LSP `Content-Length` headers. |
| `attach` | The subjects, and `where` (see Subjects). |
| `init_options` | Sent once, in `initialize`. |
| `settings` | Sent in `initialize`, and again when they change. |
| `restart` | `{ max, within_s }`: restarts after the server stops. Default: no restart. |
| `kind` | `"oneshot"` for a one-shot command. |
| `timeout_ms` | The time limit of a one-shot command. |
| `server` | A Lua table of handlers, for a server in the kernel process. |
| `adapter` | The name of an adapter, for a server that speaks a different protocol. |

### Kinds of server

- **A process.** It speaks JSON-RPC on its standard input and output, one
  message for each line, or with LSP `Content-Length` headers. Its errors
  go to `$XDG_STATE_HOME/paw/lsp-<name>.log`.
- **A one-shot command** (`kind = "oneshot"`). paw runs it once for each
  version of each subject, with a time limit (`timeout_ms`).
  - In `cmd`, paw replaces `{file}` (the path of a render), `{input}` (a
    file with the subject as JSON, or what `input(doc)` makes of it),
    `{uri}`, `{subject}` and each setting. If a word is only a placeholder
    with no value, paw removes it and the option before it.
  - paw also writes the subject to the standard input of the command.
  - The command prints
    `{ "findings": [ { "rule", "severity", "message", "time_s"? } ] }`.
    paw ignores findings with the severity `off`.
  - `diagnostic(finding, doc)` in the config can give a location and fixes.
    `accepts(doc)` tells which documents the command takes.
  - If the command prints `{ "error": ... }`, or text that is not JSON, the
    server fails. `:lsp info` shows the reason.
- **A Lua table** in the kernel process (`server = { initialize = fn, ...
  }`). paw calls its handlers directly with the parameters and a `ctx`.
  `ctx.notify(method, params)` sends a notification to paw.
  `ctx.request(method, params)` sends a request to paw. A server in Lua
  gets the subject as a table in `p.textDocument.data`.

### Protocol

The protocol is LSP. The locations and workspace edits of paw are in the
`data` fields that LSP does not use.

| Message | Direction | Contents |
| --- | --- | --- |
| `initialize` | to the server | paw offers `capabilities.paw = { subjects, addresses, workspaceEdit, features }`. The server answers with its capabilities, for example `{ "capabilities": { "hoverProvider": true, "codeActionProvider": true, "paw": { "subjects": ["mix"], "annotations": true } } }`. |
| `textDocument/didOpen` | to the server | `{ textDocument: { uri, languageId: "paw-mix", version, text } }`. `text` is the subject as JSON. |
| `textDocument/didChange` | to the server | The full text again. |
| `textDocument/didClose` | to the server | The document closed. |
| `textDocument/publishDiagnostics` | to paw | The diagnostics of a document. Each has `data.location` and `data.fixes` (`{ title, edit }`). |
| `paw/publishAnnotations` | to paw | `{ uri, annotations: [ { location, label, kind } ] }`: labels on things. |
| `paw/publishAnalysis` | to paw | `{ uri, chords, keys, key }` in project beats, for `paw.harmony`. |
| `textDocument/hover` | request to the server | `params.paw.location` is the thing. |
| `textDocument/codeAction` | request to the server | `params.paw.location` is the thing. An action is `{ title, edit: { paw: changes } }` or `{ title, command }`. |
| `textDocument/completion` | request to the server | On clips: `params.paw.at`. The items give notes in `data.notes`. |
| `workspace/applyEdit` | request to paw | `{ edit: { paw: changes }, label }`. |

A diagnostic, as the server publishes it:

```json
{ "uri": "paw://project#mix",
  "diagnostics": [ { "severity": 2, "code": "hot-fader", "source": "mixcheck",
    "message": "Bass's fader is at +3.0 dB: it may clip",
    "data": { "location": { "uri": "paw://track/4" },
              "fixes": [ { "title": "Bring Bass to 0 dB",
                           "edit": [ { "uri": "paw://track/4", "set": { "volume": 0 } } ] } ] } } ] }
```

Complete examples: `tests/fixtures/mix_lint.py` is a server for the mix,
and `tests/fixtures/range_lint.py` is a server for clips.

### Adapters

A server that speaks a different protocol gets an adapter:
`paw.lsp.adapter(name, spec)`, and `adapter = name` in its config. An
adapter is a set of small functions. They change the subject into the
messages of the server, and the answers into locations and workspace
edits. `runtime/lua/paw/lsp/standard.lua` shows the fields of an adapter.
The `midi/*` protocol of MIDI LSP has an adapter in
`extensions/midilsp/lua/midilsp/adapter.lua`.

## Diagnostics from Lua

Any Lua code can publish diagnostics with `paw.diagnostic.set`. It does not
need to be a server.

```lua
paw.diagnostic.set("mylint", "mylint", {
  { location = { uri = "paw://track/3" }, severity = "warning", message = "too loud",
    fixes = { { title = "Lower it", edit = { { uri = "paw://track/3", set = { volume = -6 } } } } } },
})
```

The older form for the notes of a clip also works. It names the notes by
their position in the clip at the time of the call:

```lua
paw.diagnostic.set("mylint", clip, { { notes = { 3 }, message = "...", fixes = { { title, edits = { { note = 3, pitch = 72 } } } } } })
```

## Servers that come with paw

- **MIDI LSP** (`extensions/midilsp`, see its [README](../../extensions/midilsp/README.md)).
  Its engine checks voice leading (a technical name), counterpoint, ranges, rhythm and form,
  finds chords and keys, and suggests melodies, velocities and controller
  curves. The extension starts it as two servers on clips, in the `midi/*`
  protocol: `midi-lsp` (the language role) and `midi-lsp-suggest` (the
  suggestion role, `paw.opt.midilsp_suggest`). It starts when the
  extension loads (`paw.opt.midilsp_autostart`). The engine is
  `paw.opt.midilsp_cmd`, else `$MIDI_LSP_ENGINE`, else `reaper-midi-lsp` on
  the PATH. The preset and the rules are saved with the project, and paw
  sends them to the engine when they change.
- **MIDI LSP render checks.** With `paw.opt.midilsp_render_checks` (on by
  default), two one-shot servers check each render, if their programs are
  installed next to the engine:
  - `midilsp-delivery` runs `reaper-midi-lsp-delivery` on each WAV render.
    It checks the integrated loudness, the true peak, clipped samples, the
    loudest passage and the loudness range against
    `paw.opt.midilsp_delivery_target` (`spotify`, `ebu-r128`, or empty for
    information only). If the render is too loud or above the true-peak
    ceiling, a fix lowers the master by the difference.
  - `midilsp-settings` runs `reaper-midi-lsp-settings` on the render
    settings. paw makes these settings from the render options and the
    devices of the master. It finds these problems:
    - a 16-bit render without dither (fix: render again with dither)
    - normalization on
    - a rate that is not the rate of the project (fix: render again at
      that rate)
    - a limiter on the master that is bypassed (fix: enable it) or not
      last. Its messages
    name the render dialog of REAPER, where paw has the render options.
- **mixdiag** (`extensions/mixdiag`) is a server in Lua. Its results
  become diagnostics on the tracks that they name. If a result gives the
  number of dB to lower a fader, the diagnostic has a fix. So its report
  and `:diagnostics` agree.
