# The control protocol
<!-- tags: protocol -->

paw is a server while it runs. Other programs connect to it: the graphical
window, `paw ctl`, `paw attach`, the MCP server and your scripts. They call
functions in it, and it tells them what happens. This page describes the
whole protocol, version 3.

## Connections

The messages are JSON objects, one on each line, in UTF-8, in the two
directions.

| Way in | Who can use it |
| --- | --- |
| A Unix socket: `$XDG_RUNTIME_DIR/paw.sock`, or the path of `--listen <path>`. `--no-listen` opens no socket. | A user who can open the file on that machine. |
| TCP inside TLS, when paw starts with `--listen-tcp <host:port>` | A user who can get to the port and who knows the token. |

### The token

The token is 32 hexadecimal digits in `~/.local/state/paw/token`, or in the
file of `--token-file <path>`. paw makes it the first time that it needs
it. Only its owner can read it. The machines that connect need a copy.

### TLS

TCP is encrypted with TLS 1.3 (or 1.2) from the first byte. The lines of
this page go inside TLS.

- The first time that paw listens on TCP, it makes a self-signed
  certificate. It keeps it in `~/.local/state/paw/tls/`.
- When it starts, it shows the fingerprint of the certificate: the
  SHA-256, in groups of four hexadecimal digits.
- No authority signs the certificate. A client trusts the certificate the
  first time that it connects to an address. After that, it accepts only
  that certificate, as SSH does with host keys.
- The clients of paw remember the certificates in
  `~/.local/state/paw/known_instances`: an address and a fingerprint on
  each line. They refuse a different certificate and show the two
  fingerprints. `--accept-certificate` accepts the new one.
- A client of your own can do the same with a TLS library: accept the
  certificate shown, and compare its fingerprint with the remembered one.

### Without TLS

`--no-tls`, on paw and on its clients, sends the lines without encryption.
Use it only on a network that you trust. `eval` runs any Lua. So a person
who can change the messages can run any program on the machine of paw.

A client without TLS that connects to a port that takes only TLS gets
`{"event": "hello", "payload": {"version": 3, "error": "…"}}`. It gets it
after 1.5 seconds without data, or at once when it sends data first. Its
first request gets that error as its reply.

SSH needs nothing from paw:

```sh
ssh -N -L /tmp/studio.sock:/run/user/1000/paw.sock studio &
paw attach --socket /tmp/studio.sock
paw-gui --socket /tmp/studio.sock
```

## Requests and replies

```json
{"id": 1, "method": "eval", "params": ["return paw.transport.position"]}
{"id": 1, "result": 3.5}
{"id": 2, "method": "nonsense", "params": []}
{"id": 2, "error": "no method `nonsense`"}
```

The client gives the `id`, and the reply has the same `id`. paw replies to
the requests of one connection in their order. A request with
`"id": null` gets a reply with `"id": null`. Send such requests when you do
not need the reply.

| Method | Parameters | Effect |
| --- | --- | --- |
| `hello` | `{ "proof": "…" }` over TCP, `{}` on the Unix socket | Replies `{ "version": 3, "client": n }`. See [`hello` and the token](#hello-and-the-token). |
| `eval` | Lua source, then the values for its `...` | Runs the source in the kernel. Replies what it returns. |
| `cmd` | A command line, as after `:` | Runs the command. |
| `keys` | Keys as typed: `"ggdd"`, `"<C-s>"` | Types the keys. |
| `render` | A path, options | Calls `paw.render`. |
| A `paw.api` function | Its arguments | Calls the function: `track_add`, `transport_get` and other. |
| `subscribe` | Event names or patterns | Sends the events from now on. Replies the list of patterns. |
| `unsubscribe` | Patterns, or nothing for all | Stops the events. |
| `frontend.watch` | `{ "interval": ms, "seat": "own" or "instance" }`. Defaults: 33, `"own"`. | Sends `frontend.state` events from now on. See [`frontend.watch`](#frontendwatch). |
| `frontend.pace` | `ms` | While the song plays, sends what moves at most once in `ms` milliseconds (8 to 1000). See [`frontend.watch`](#frontendwatch). |
| `frontend.unwatch` | | Stops them. |
| `scene.watch` | `{ "cell": { "w", "h" }, "roles": [...], "live": bool }` | Sends `scene.patch` events from now on, and `scene.live` events with `live`. See [Scenes](#scenes). |
| `scene.area` | A window, a width, a height in cell units | Tells the size of a window. 0 by 0 tells that the window does not show. |
| `scene.input` | A window, a pointer event in cell units | Sends the pointer over a window. |
| `scene.blob` | A content key | Replies the drawing of that key. |
| `scene.unwatch` | | Stops the patches. |
| `ui.attach` | A width and a height in cells, options | Makes the connection a terminal: `ui.grid` events from now on. See [A remote terminal](#a-remote-terminal). |
| `ui.input` | One input event | Sends a key, a paste or the pointer to that terminal. |
| `ui.detach` | | Stops the terminal. |
| `file.begin` | `{ "name": "take.wav", "size": bytes }` | Starts to send a file. Replies its upload number. See [Files](#files). |
| `file.chunk` | The upload number, the next bytes in base64 | Replies the number of bytes received. |
| `file.end` | The upload number | Replies the path of the file on the machine of paw. |
| `file.abort` | The upload number | Deletes what was received. |
| `monitor.listen` | | Sends `audio.frame` events from now on. Replies `{ "rate", "channels", "format", "frame_ms" }`. See [Sound](#sound). |
| `monitor.unlisten` | | Stops them. |

An extension adds methods of its own:

```lua
paw.remote.methods["name"] = function(client, ...) return … end
```

### Time limit

Each request that runs Lua has the time limit of a key,
`paw.opt.lua_limit` (2 seconds). These requests do not run Lua: `hello`,
`ui.*`, `file.*` and `monitor.*`. paw stops a request that runs longer, and
replies an error that tells so. paw continues to run. Time that the kernel
waits (a render, a project that opens) does not count. Code sent with
`eval` that needs more time asks for it first: `paw.limit.extend(60000)`.

### Errors

An error is only the message, as Lua or the kernel gave it, without a
stack: ``"no method `nonsense`"``, `"no clip 9"`, `"rpc:1: attempt to
perform arithmetic on a nil value"`. `rpc` is the code sent with `eval`.

### `paw ctl --json`

`paw ctl --json <method> [params...]` is for programs and agents with a
shell. It prints one line of JSON: `{"ok": true, "result": ...}` or
`{"ok": false, "error": "..."}`. It exits with status 1 on an error: the
call failed, the method does not exist, or no instance runs. Without
`--json`, it prints a string result as text and other results as indented
JSON, and it writes an error to stderr.

```sh
paw ctl --json eval 'return paw.project.tempo'     # {"ok":true,"result":120}
paw ctl --json track_get 99                        # {"ok":false,"error":"..."}
```

### `hello` and the token

Over TCP, paw sends the first message:

```json
{"event": "hello", "payload": {"version": 3, "nonce": "9f1c…"}}
```

Then it ignores all other requests until the connection sends the proof
that it knows the token. The proof is the SHA-256, in hexadecimal, of the
token, a colon and the nonce.

```json
{"id": 1, "method": "hello", "params": [{"proof": "sha256(token + ':' + nonce)"}]}
{"id": 1, "result": {"version": 3, "client": 7}}
```

A wrong proof gets an error, and paw closes the connection. On the Unix
socket, `hello` is optional. It gives only the version and the number of
the connection.

### Size limits

| Limit | Value |
| --- | --- |
| Time to send the proof, over TCP | 10 seconds |
| Size of the proof message, over TCP | 4096 bytes |
| Data that waits unread for a connection | 32 MB. paw closes a connection that lets more data wait. |
| Size of a request | 64 MB |

## Events

Events have no `id`:

```json
{"event": "transport.play", "payload": {"position": 0}}
```

A connection gets only the events that it asked for.

### `subscribe`

`subscribe` takes exact names (`track.added`), families (`transport.*`) or
`*`. The events are the events of `paw.on` in Lua, also those of
extensions. Some of them are:

`changed`, `project.loaded`, `project.saved`, `track.added`,
`track.changed`, `track.removed`, `clip.add`, `clip.set`,
`device.changed`, `device.stopped`, `transport.play`, `transport.stop`,
`transport.seek`, `transport.record`, `transport.changed`, `midi.in`,
`render.progress`, `render.done`, `audio.lost`, `audio.restored` and other.
paw does not send an event whose payload is not valid JSON.

### `frontend.watch`

`frontend.watch` is for programs that draw the project. paw sends a
`frontend.state` event at once. After that, it sends one only when
something to draw changed. A key, a call or an edit sends one after its
turn, at most once in 8 milliseconds. While the song plays, and for a
moment after it stops, paw sends what moves at most once in each
`interval` milliseconds (16 or more). At rest, paw looks once a second for
what changes slowly, such as the load of the engine.

`frontend.pace` changes the interval of a connection that watches. It also
sets how often `scene.live` comes. The graphical window sends it with the
time between two of its frames (`paw.opt.window_fps`), so paw does not
make values that the window does not draw.

```json
{"event": "frontend.state", "payload": {
  "revision": 41, "playing": true, "position": 12.5, "time": "4.1.50",
  "levels": [0.31, 0.3, 0, 0], "cpu": 0.075, "modal": { "mode": "n" },
  "sections": { "tracks": [ … ], "clips": [ … ] }
}}
```

The payload has the values that move without a change to the project: the
playhead, the meters, the mode. It is what `paw.frontend.state(known)`
returns when the project did not change.

- `cpu` is the load of the engine, averaged over about one second, in steps
  of 2.5% (`paw.audio.load`). So an idle program does not send a new
  value when one block takes a little longer.
- `levels` and `inputs` are rounded to four decimals.
- `modal.menu` counts the menus that the kernel opened. The window then
  shows `paw.frontend.menu("shown")` at the pointer (see [The graphical
  window in Lua](window-lua.md#pawfrontendact)).
- `modal.hint` is what the pointer is over, or what its drag does, for the
  status line.
- `sections`, when present, has the parts of the project that changed since
  the last event to this connection. Each part comes whole:

| Section | Value |
| --- | --- |
| `project` | The name, the tempo, the loop, the markers and other: `state.project` without `lines`. |
| `lines` | The bar and beat lines: `state.project.lines`. |
| `tracks`, `clips`, `devices` | As in the state. |
| `routing` | The routing of the selected track, or `false` without a selected track. |
| `view` | `{ "selected": track id, "cursor": beat }` |
| `kinds` | The kinds of device. |

An idle program sends nothing.

## Scenes

A graphical frontend shows some windows from their scenes. These are the
panes of its main area that it does not draw itself, and the views in
windows of their own.

A scene (crates/paw-scene) is what a view draws, as nodes in **cell
units**. Each node has a key, so after the first scene paw sends only what
changed. The frontend draws the scene in its own font at its own
resolution. The same scene lowered to cells is the same, cell for cell, as
what a terminal shows. See [About scenes](../explanation/about-scenes.md).

### `scene.watch`

| Parameter | Value |
| --- | --- |
| `cell` | `{ "w", "h" }`: the size of the frontend's cell in pixels. paw draws pictures for it and lays out the main area on it. |
| `roles` | The names of the roles that the frontend paints itself. |
| `live` | `true` to also get `scene.live` events. |

The reply has `theme`, the palette by name (a node's `tone` names one), and
`roles_version`, the version of the roles a frontend can know.

### Windows

A string names a window:

| Window | Name |
| --- | --- |
| A window of the layout | Its number, as `paw.panes.state()` lists it: `"3"` |
| A view in a window of its own | `"view:<name>"`, as `paw.canvas.windows()` lists it |

paw sends nothing about a window until `scene.area` tells its size, in
units (fractions are permitted). Then it sends the whole scene. After each
turn that changed the window, it sends what changed. While the song plays,
it sends at most 30 patches a second.

### `scene.patch`

```json
{"event": "scene.patch", "payload": {
  "win": "3", "rev": 12, "full": false, "cursor": [4, 2],
  "set": [{"k": "t0,1", "t": "run", "text": "count 1", "r": [0, 1, 7, 1], "s": {"fg": "#c9ced8"}}],
  "drop": ["t9,1"]
}}
```

| Field | Value |
| --- | --- |
| `win` | The window. |
| `rev` | The revision of the scene. |
| `full` | `true`: forget the scene of the window first. |
| `set` | The nodes added or changed. |
| `drop` | The keys of the nodes removed. |
| `size` | The size of the scene. Only when it changes. |
| `root` | The keys of the top nodes, in drawing order. Only when it changes. |
| `colors` | `[fg, bg]`, the colors that `default` means. Only when they change. |
| `cursor` | The cursor, or `[]` for none. Only when it changes. |

### Nodes

| Field | Value |
| --- | --- |
| `k` | The key. |
| `t` | The kind: `run`, `fill`, `picture`, `group`, `plane`, `role`. |
| `r` | The rectangle: x, y, width and height, in units of the parent. |
| `text` | The text of a `run`. |
| `ch` | For a `fill`, the character that it writes. Without it, the fill changes only the style. |
| `s` | The style: `fg` and `bg` (`"#rrggbb"`, `"default"` or a number from the 256 colors), and `on` and `off`, the attributes that it sets and clears. |
| `clip` | The rectangle that cuts the node. |
| `kids` | The child nodes. |
| `ops` | The drawing of a `picture` (see `paw.canvas.paint`, music glyphs as glyphs). |
| `px` | The pixel size that the `picture` is drawn for. It is scaled to its rectangle. |
| `under` | The `picture` goes under the text of the cells, over their backgrounds. |
| `blob` | In place of `ops`: a content key for a drawing that is too large to send each time. Ask `scene.blob` for it once. |
| `role`, `props` | The name and the data of a role. |
| `bind` | The live value that moves the node, for example `"meter:4"`. |
| `hit` | The node is a hit region. `hit.kind` and the other fields are its action. |

The attributes are 1 bold, 2 dim, 4 italic, 8 underline, 16 reverse and
32 strike. Runs and fills are written onto cells in their order, as the
terminal does. Reverse and dim are resolved with the cells.

### Roles

A `role` is a named element that a view marked over its rectangle
(`buf:mark`, see [Roles](lua-views.md#roles)). `role` is its name, and
`props` is what it shows, for example `{"role": "fader", "props": {"at":
0.81, "zero": 0.79, "value": -2}}`. Its kids are its cells. A frontend that
does not know the role draws the cells. A frontend that told paw that it
paints the role gets the role without the kids.

| Roles | Owner |
| --- | --- |
| `label`, `button`, `switch`, `knob`, `fader`, `meter`, `peak`, `chip`, `param`, `power`, `band` | The core: the widget roles. |
| `note`, `keyboard`, `playhead`, `scrollbar` | The core: the roles of the piano roll. |
| `clip`, `beats`, `curve`, `hmeter` | The core: the roles of the arrange view. A `clip` names what it shows by `content`, a key that changes when its notes or its waveform change. The frontend gets them with `paw.frontend.preview(id)` or `paw.frontend.peaks(id, points)`, once for each key. |
| Other names | An extension, with `paw.ui.role`. |

A node with `bind` moves with the live values. Its props that the live
values give are not in the scene: a meter's `levels`, `hold` and `clipped`,
a peak's `hold` and `clipped`, and a parameter's `fraction` and `text`. So
a view does not send a new scene for them while the song plays.

A node with `hit` is a hit region. A press, a move or the wheel on it does
what the view tells: `hit.kind` and the other fields are its action.

### Planes

A `plane` places its kids in a domain of its own (`buf:plane`). `x` and `y`
are each `{ "domain", "from", "per" }`. The domain's `from` is at the edge
of the plane. Each unit of the domain is `per` units, backwards when `per`
is negative. A kid's rectangle is in the domain. For example, this note of
the piano roll is a half beat long, from beat 1.5, on pitch 60:

```json
{"k": "roll/note:7:3", "t": "role", "role": "note", "r": [1.5, 60, 0.5, 1],
 "props": {"label": "C4", "color": "#e0a050", "velocity": 90}}
```

A window paints the note there, between cells. Its cells, which the
terminal rounds it to, are also in the domain. Something can draw over a
plane, and then the view can mark the plane again. Then the plane
continues in a new node (`roll#2`), so the drawing order stays correct. Runs and fills drawn after
a painted role, over it, are painted over it again, as the terminal shows
them. A fill that only changes the style is a tint.

### Menus

A right-click on a pane drawn from its scene can open a menu of the
kernel. `frontend.state`'s `modal.menu` counts the menus that the kernel
opened. The window shows `paw.frontend.menu("shown")` at the pointer. It
sends the selected entry with `paw.frontend.act.menu_choose("shown", {},
path)`, or `paw.frontend.act.menu_dismiss()` when the user selects nothing.

### `scene.input`

`scene.input` takes a pointer event as `paw.canvas.pointer` does. Its
fields are `kind` (`down`, `up`, `move`, `hover`, `double` or `wheel`),
`button`, `ctrl`, `shift`, `alt`, `dx` and `dy`. `x` and `y` are in units
from the corner of the window. The kind `leave` tells that the pointer
left the window. Then the status line stops to show the hint of the view.

The kernel finds the hit region under the event in the scene that
it sent (`paw_scene::Scene::hit`). It gives the event, in units, to the
view's gesture for that region, as the terminal gives one in cells. A drag
that starts on a region continues in units until its release. Outside all
regions, the event goes to the view as from a terminal.

### `scene.live`

With `"live": true`, the connection also gets the values that move nodes
without a new scene, when they change:

```json
{"event": "scene.live", "payload": {"position": 12.5, "playing": true, "recording": false,
  "clock": "0:07.0", "cpu": 0.075, "meters": {"4": [0.31, 0.3], "0": [0.4, 0.38]},
  "peaks": {"4": 0.5, "0": 0.6}, "clips": {"4": true}, "inputs": {"4": 0}}}
```

| Field | Value |
| --- | --- |
| `meters` | The level of each side of each track, by its id. The master is `"0"`. |
| `peaks` | The recent peak of each track. |
| `clips` | The tracks whose clip light is on. A click on the peak clears it, as `paw.draw.clear_peak` does. |
| `inputs` | The level at the input of each track. |
| `params` | The parameters that lanes move, by their binding (`param:<device>:<key>`): `fraction`, where the slider is from 0 to 1, and `text`, the value in its unit. The device panel binds a parameter only while a lane moves it. |

## A remote terminal

`ui.attach` makes the connection a terminal of paw, beside the terminal of
paw if it has one. After each turn that changed the screen, paw sends:

```json
{"event": "ui.grid", "payload": {
  "w": 120, "h": 40, "full": false, "cursor": [14, 3],
  "runs": [[0, 0, " NORMAL ", "#101216", "#6aa9e9", 1], [8, 0, " 1.1.00", null, 236, 0]]
}}
```

| Field | Value |
| --- | --- |
| `w`, `h` | The size of the screen in cells. |
| `full` | `true`: clear the screen first. The first event and the event after a change of size have it. |
| `cursor` | The cursor. |
| `runs` | Each run is `[x, y, text, fg, bg, attrs]`: cells of one style on one row. Only the changed runs come. |
| `mouse` | `false`: stop the report of the pointer, and leave the pointer to the terminal's own selection (`paw.opt.mouse` off). Without it, or `true`, report the pointer. |

A color is `null` (the terminal's own color), a number (one of its 256
colors) or `"#rrggbb"`. `attrs` adds 1 bold, 2 dim, 4 italic, 8 underline,
16 reverse and 32 strike. A character two cells wide takes two cells.

### Images

A terminal that shows images tells so with a third parameter of
`ui.attach`:

```json
{"graphics": true, "cell": [10, 20], "pixel_mouse": true, "fg": "#cdd6f4", "bg": "#1e1e2e"}
```

These are its cell size in pixels, its colors, and `true` if it reports
the pointer in pixels. Then it also gets the surfaces that the views keep
for their pixels:

```json
"surfaces": [{"name": "notation", "x": 0, "y": 3, "w": 80, "h": 30,
              "cell": [10, 20], "covered": [[4, 2, 20]], "ops": [...]}]
```

`covered` lists what covers a part of the surface: a column, a row and a
count of columns, from its corner. `ops` is the drawing (see
`paw.canvas.paint`). It comes only when it is different from the last
drawing sent for that name. The client makes the pixels. Without the third
parameter, the views draw in cells for this terminal.

### `ui.input`

`ui.input` takes one of these:

```json
{"key": "<C-s>"}
{"paste": "text"}
{"resize": [100, 30]}
{"mouse": {"kind": "down", "button": "left", "x": 3, "y": 4, "mods": "C"}}
{"cell": [10, 20]}
```

| Field | Value |
| --- | --- |
| `key` | A key, in the notation of the key mappings. |
| `paste` | Pasted text. |
| `resize` | The new size in cells. |
| `mouse.kind` | `down`, `up`, `drag`, `move`, `scroll_up`, `scroll_down`, `scroll_left`, `scroll_right`. |
| `mouse.mods` | Any of `C`, `A`, `S`. |
| `mouse.px`, `mouse.py` | The pointer in pixels from the corner of the screen, from a terminal that reports pixels. |
| `cell` | The new size of a cell in pixels (the font changed). |

`:detach`, or `ui.detach`, releases a remote terminal. paw replies with a
`ui.detached` event and continues to run. `:q` stops paw for all
connections.

## Seats

The project is one. What each person sees and does is their own. A
connection that attaches (`ui.attach`) or watches (`frontend.watch`) has a
seat, unless it asks for `"seat": "instance"`. A seat has its own:

- focused view and visible panels
- edit cursor, mode and selection
- keys typed so far, registers, marks and prompt
- scroll position
- terminal, drawn at its own size.

Each call of that connection (`eval`, `cmd`, `keys`, `paw.frontend.act.*`)
happens in its seat. The seat of paw itself is the seat of its terminal, if
it has one. Each connection without a seat (`paw ctl`, scripts) uses it.

A new seat starts at the cursor of paw, with the panels of paw, in normal
mode. It closes with its connection. The edits of two seats are steps in
the one undo history. The options (`paw.opt`) are shared. In Lua,
`paw.seats.current` is the seat of the current turn. See
`runtime/lua/paw/seats.tl` for how a module keeps state for each seat.

## Files

A client on another machine sends a file into the media folder of the
project. The media folder is beside a saved project, else in a scratch
folder. The client sends `file.begin`, then `file.chunk` messages (1 MB
each is good), then `file.end`. Then it imports the path that `file.end`
replies, as any other path:

```json
{"id": 1, "method": "file.begin", "params": [{"name": "take.wav", "size": 2400044}]}
{"id": 1, "result": 1}
{"id": 2, "method": "file.chunk", "params": [1, "UklGRiw…"]}
{"id": 2, "result": 1048576}
…
{"id": 4, "method": "file.end", "params": [1]}
{"id": 4, "result": "/home/me/songs/media/take.wav"}
{"id": 5, "method": "eval", "params": ["paw.commands.run('import', { ... })", "/home/me/songs/media/take.wav"]}
```

- paw keeps only the last part of the name. If the name is used, it adds
  `-2`, `-3` and other.
- The file gets its name only when it is complete. paw deletes a file that
  is not complete when its connection closes.
- `:upload <path>`, typed in an attached terminal, sends the connection
  `{"event": "file.wanted", "payload": {"path": "…", "import": true}}`.
  The client then sends that file from its own disk. `paw attach` does
  this.

## Sound

`monitor.listen` sends the connection the sound of paw while it plays:

```json
{"event": "audio.frame", "payload": {"seq": 41, "rate": 24000, "channels": 2, "pcm": "…"}}
```

| Field | Value |
| --- | --- |
| `seq` | The number of the frame, from 1. |
| `rate` | Half the rate of the engine. A quarter, at 88.2 kHz and more. |
| `channels` | 2: left and right, interleaved. |
| `pcm` | 20 ms of sound, as 16-bit little-endian samples in base64. |

This is about 770 kbit/s, and about 1 Mbit/s with base64 and JSON. The
engine makes the copy only while a connection listens.

`:listen` sends the connection of a terminal or a window
`{"event": "monitor.toggle"}`. The client then starts or stops to listen.
`paw attach` and `paw-gui` do this. They play the frames through a jitter
buffer that waits for 200 ms and holds at most one second.

## Limits

- The sound is not compressed: the frames are 16-bit samples. No Opus
  encoder in pure Rust is good enough, and paw links no C codec.
- No sound goes from the client to paw. A client cannot record from its
  own microphone.
- Open, Save and Render use the disk of paw, not the disk of the client.
- Plugin windows open on the display of paw.

## In Rust

The crate `paw-proto` is the side of the client. It uses `serde_json`,
`anyhow`, `base64`, `tokio`, and `tokio-rustls` with `rustls` on `ring`.
It does not use OpenSSL. The functions below block. Each process has one
thread, `paw-client`, that does the I/O of all its connections. Do not
call the functions from a task of a `tokio` runtime.

| Name | Effect |
| --- | --- |
| `Connection::unix(path)` | Connects to a Unix socket. |
| `Connection::tcp(address, token)` | Connects over TLS. It remembers the certificate in the state directory. |
| `Connection::tcp_with(address, token, &Wire::…)` | Connects with TLS and a different file of known certificates, or without TLS. |
| `call(method, params)` | Sends a request and waits for its reply. |
| `notify(method, params)` | Sends a request without a reply. |
| `events` | The channel of events. |
| `send_file(path)`, `send_and_import(path)` | Send a file, and import it. |
| `paw_proto::monitor` | Makes and reads `audio.frame` payloads. |

The crate `paw-listen` plays the frames: `Player::device()`, or
`Player::file(path, rate)` to write them to a WAV file.
`paw_core::remote::apply` puts `ui.grid` events into a grid of cells.
