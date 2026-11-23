# paw-mcp

paw-mcp is a [Model Context Protocol](https://modelcontextprotocol.io)
server for paw, which lets an assistant such as Claude read a project and
work in it. The assistant can make a song, edit it, mix it and render it.
It then reads the levels and the spectrum of the rendered file, because it
cannot listen.

## Try it

1. Build paw and the server:

   ```sh
   nix develop -c cargo build --release -p paw-tui -p paw-mcp
   ```

2. Start a headless kernel on a socket:

   ```sh
   paw --headless --listen /tmp/paw.sock --audio null &
   ```

3. Add the server to Claude Code:

   ```sh
   claude mcp add paw -- /path/to/paw/target/release/paw-mcp --socket /tmp/paw.sock
   ```

4. Ask Claude "Add a bass part with a four-bar riff." The answer gives
   the ids of the new part and clip.
5. Type `paw ctl --socket /tmp/paw.sock eval 'return #paw.parts()'`. The
   number includes the new part.

## How to

### How to connect to paw that is open

Start the server with no `--socket` and no `--spawn`. It then connects
where `paw ctl` connects, which is `$PAW_SOCKET`, or else
`$XDG_RUNTIME_DIR/paw.sock`.

### How to give the assistant a private session

Start the server with `--spawn`. It starts a headless kernel of its own,
and it stops the kernel when the server stops. Arguments after `--` go to
`paw`:

```sh
target/release/paw-mcp --spawn song.json -- --audio null
```

### How to add the server to Claude Code

The server does not register itself, so run one of the following
commands:

```sh
# Connect to paw that is open:
claude mcp add paw -- /path/to/paw/target/release/paw-mcp

# Or a private headless session, with the escape hatches:
claude mcp add paw -- /path/to/paw/target/release/paw-mcp --spawn --allow-eval -- --audio null
```

To have the server in every project, add `--scope user`. You can also put
the same settings in the `.mcp.json` of a project:

```json
{
  "mcpServers": {
    "paw": {
      "command": "/path/to/paw/target/release/paw-mcp",
      "args": ["--spawn", "--", "--audio", "null"]
    }
  }
}
```

Claude Code starts the server in the project folder, so relative paths
start there, and the server saves and renders only there (see `--root`).

### How to add the server to Claude Desktop

1. Open Settings, then Developer, then Edit Config.
2. Add the server to `claude_desktop_config.json`:

   ```json
   {
     "mcpServers": {
       "paw": {
         "command": "/path/to/paw/target/release/paw-mcp",
         "args": ["--root", "/home/you/music", "--socket", "/run/user/1000/paw.sock"]
       }
     }
   }
   ```

3. Restart Claude Desktop.

Claude Desktop does not start servers in a folder that you choose, so give
`--root`. Use the socket path of paw (`echo $XDG_RUNTIME_DIR/paw.sock`),
or `"--spawn"` in place of `"--socket", ...`.

## Reference

### Flags

| Flag | Effect |
| --- | --- |
| `--socket <path>` | connects to the kernel at this socket |
| `--spawn [project] [-- paw options]` | starts a headless kernel, and stops it at exit |
| `--paw <path>` | the `paw` binary for `--spawn` |
| `--root <dir>` | where relative paths start and where the server can write files. Default: the current directory |
| `--allow-eval` | offers `lua`, `run_command` and `send_keys` |
| `--allow-any-path` | lets `render` and the save of `project_file` write outside `--root` |
| `--timeout <secs>` | how long to wait for the kernel for each call (default 600) |

The server speaks MCP on stdin and stdout, and it logs to stderr. It
connects when the first tool needs the kernel. If the kernel stops, calls
fail with a message, and the server connects again when a kernel is back.
A kernel started with `--spawn` that stops starts again on the next call,
and that call tells you that the previous session is lost.

With `--spawn`, the server looks for the `paw` program in the following
order:

1. `--paw <path>`, then `$PAW_BIN`.
2. The program beside `paw-mcp`.
3. `paw` on the path.

The kernel uses your configuration, your extensions and the default audio
device, unless you give `--clean` or `--audio null` after `--`.

### Tools

Positions are beats (quarter notes) from the start, as JSON numbers, or
strings that count bars and beats from 1, e.g., `"5.1"`, `"5:1"`,
`"bar 5 beat 1"` or `"2.3.50"`. Notes can be objects, or short strings such
as `"C4 2.5 1/8 90"` or `"C4+E4+G4 1:3 2"`, which give the pitch or chord,
the start in beats or `bar:beat` in the clip, the length and the velocity.
Middle C is C4. Parts and markers can have names in place of numbers.

| Tool | Effect |
| --- | --- |
| `get_project` | the full session: tempo, signature, key, length, transport, markers and regions, parts with routing, sends, devices, clips (position, notes, range) and automation |
| `get_part` | one part in full, with the parameter values of each device, automation points and the live meter of the engine |
| `get_clip` | the notes of a clip with their ids (filtered by time and pitch), or the file, offset and gain of an audio clip |
| `get_device` | the parameters of a device with value, range, default, unit and choices. A filter helps for big plugins |
| `find_devices` | finds the built-in devices and installed plugins that you can add |
| `get_status` | the transport, the audio engine, unsaved changes, recent messages of paw |
| `find` | parts, clips, notes and other nodes by a `paw.query` selector (`clip[name~=riff] > note[pitch>=c5]`) |
| `diagnose` | empty parts, silent MIDI parts, empty clips, notes past their clip, missing plugins, orphan or muted sends, automation out of range. With `measure`, silence and clipping in a render |
| `add_part` | a part with its devices, clips and notes, routing and sends, in one call |
| `set_part` | name, volume, pan, mute, solo, color, position, output, sends |
| `add_clip` | a MIDI clip with all its notes, or an audio clip from a file |
| `edit_clip` | moves, resizes, renames, mutes a clip. Removes notes, changes single notes by id, transposes (semitones or scale degrees in the key), scales or sets velocities, replaces or adds notes |
| `duplicate_clip`, `repeat_bars` | copies a clip. Repeats a part of the song, to arrange |
| `add_device` | an instrument or an effect (by kind or by search words) with parameter values |
| `set_device` | parameters (by key or name, choices by name), bypass, move in a chain or between chains |
| `automate` | points of volume, pan or parameter automation. Makes, clears, disables or removes a lane |
| `set_project` | tempo, time signature, key, name, tempo and signature changes |
| `marker` | markers and regions: add, rename, move, remove, list |
| `remove` | parts, clips, devices, automation lanes and markers, any number in one call |
| `batch` | several of the tools that write, as one named undo step, all or nothing |
| `transport` | play, stop, seek, loop range and switch (or loop a region), metronome. Undo does not apply |
| `undo` | undo or redo, with what each step was. `list` shows the history. Fails when there is nothing to undo |
| `project_file` | save, open, new. Open and new refuse to drop unsaved changes, unless `discard` |
| `render` | renders to WAV, FLAC (MP3, Ogg, Opus with ffmpeg), a region, some parts or stems, to a LUFS target. Measures it: LUFS, true peak, and for WAV peak, RMS, clipping, stereo, level of each bar, octave-band spectrum |
| `analyze_audio` | the same measurements for any audio file (LUFS for any format, the rest for WAV) |
| `lua` | runs Lua in the kernel. Only with `--allow-eval` |
| `run_command` | runs a `:` command line. Only with `--allow-eval` |
| `send_keys` | types keys in the notation of Neovim. Only with `--allow-eval` |

Each result is short text with each id that the next call can need, and
the same data as JSON in `structuredContent`. Both show the state after the
change, so a model does not need to read again.

Each failure is a tool error (`isError`), with the message and
`{"error": ...}` as its structured content, and that includes an unknown
tool and `undo` with nothing to undo. Only a malformed request is a
protocol error.

Each call that writes is one undo step named `mcp: <tool> <subject>`, and
`batch` makes any number of them one step.

Tool schemas use `anyOf` for values of two kinds, and plain arrays with one
`items` schema, because some clients do not read a list of types or
`prefixItems` correctly. For example, an automation point is
`[position, value]`, and a pitch is a name or a number. `lua` and
`run_command` are annotated as destructive and open-world, so a client asks
before it runs them.

Loudness (integrated and short-term LUFS, loudness range, true peak) is the
measurement of the kernel (`paw.api.measure`). The other values are plain
signal measurements, which are the sample peak, the RMS in dBFS, the stereo
correlation and the share of energy in each octave band. The server and the
kernel use the same code for these measurements, the crate `paw-measure`.
So a file gives the same numbers here as in `:mix`.

### What an assistant can do

Without flags, an assistant reads the full session, and it changes the
session only through the typed tools:

- It changes parts, clips, notes, devices and plugins (a plugin loads into
  the kernel process), parameters, routing, automation, tempo and
  signature, the transport, undo and redo.
- It reads any project file, WAV or audio file that the user of the server
  can read, also by absolute path.
- It opens or starts a project, which replaces the session and clears
  undo, but only when there are no unsaved changes, or when it gives
  `discard`.
- It writes files only under `--root`, which means renders (which replace a
  file with the same name) and saved projects (`.json`, with a `media`
  folder beside it when the project has recordings).

It cannot run code, commands or keys, and it cannot quit the kernel. The
server checks paths after it resolves `..` and symbolic links.

`--allow-eval` adds the escape hatches, which run code in the kernel
process with the rights of the user. They are Lua with the full `paw`
interface and the `io`, `os` and `ffi` of LuaJIT, commands (with `:lua`,
`:w <path>` and `:q`), and keys.

**Warning:** With `--allow-eval`, an assistant can read and write any file,
start programs, and quit paw, because `--root` does not apply to the escape
hatches. A failed call is one undo step for what it changed in the
project, but the server does not roll it back.

`--allow-any-path` lets `render` and the save of `project_file` write
anywhere that the user can.

### Protocol

The server speaks JSON-RPC 2.0 over stdio, with one message on each line,
through `rmcp`.

`initialize` answers with the revision asked for, when it is one of
`2024-11-05`, `2025-03-26`, `2025-06-18` or `2025-11-25`, and otherwise it
answers `2025-11-25`. The server also answers `notifications/initialized`,
`ping`, `tools/list` and `tools/call`.

The `2026-07-28` revision has no handshake. The server answers requests
with `_meta["io.modelcontextprotocol/protocolVersion"]` without state, with
`resultType: "complete"`, and `server/discover` answers too. A revision
that the server does not support gets error `-32022` with the supported
list.

Unknown methods get `-32601`, and requests without a tool name get
`-32602`. The server passes over a line that is not JSON, and an unknown
tool is a tool error.

Tool definitions have `title` and `annotations` (read-only, destructive,
open-world), and results are a text block and `structuredContent`. The
server answers `resources/list`, `resources/templates/list` and
`resources/read`, and it has no prompts.

| Resource | Contents |
| --- | --- |
| `paw://help/<page>` | a page of the manual, from the docs of the kernel |
| `paw://reference/api` | each `paw.api` function, with the comment above it in `crates/paw-core/src/api/` |
| `paw://reference/lua/<module>` | the documented functions of a module of `runtime/lua/paw`. `paw://reference/lua` lists them |

The references come from the source that the server was built from.

### Tests

`tests/protocol.rs` speaks the protocol to the server, with a headless
kernel on the null backend. It tests the following:

- The handshake for each revision, and the tool schemas.
- A song made with the typed tools only, read back, rendered and measured.
- Undo, a call that rolls back, the argument errors and the escape hatches.
- A kernel that stops and returns.

Run it with `nix develop -c cargo test -p paw-mcp`, which builds `paw` if
it is not built.

### Limits

Calls run one at a time and to the end, so a long render holds `ping`.
The server ignores `notifications/cancelled`, and it sends no progress
notifications.

The level of each bar, stereo and the spectrum are only for WAV files, and
a FLAC or MP3 render gets the loudness numbers only. The meter of
`get_part` is the live peak of the engine, which is -120 dB when nothing
plays, so use `diagnose` with `measure` to find the parts that clip.

A `batch` reads `bar.beat` positions with the time signature at its start,
and its steps name earlier results by name, not by id. Note names have
sharps (`A#4`).

The typed tools have no recording, MIDI input, audio inputs, input
monitors, plugin editor windows, cursor, marks or selections, but the
escape hatches can do those things.

`unsaved changes` counts from saves through this server, or from its first
run in the kernel, because the kernel only reports whether the project has
any history.

Only the test client of the server tested it, and nobody tested it with
Claude Code or Claude Desktop.

## About

The server is a client of the control socket, as `paw ctl` and the
graphical frontend are, and it adds nothing to the kernel. It sends each
tool call as one `eval` of [mcp.lua](src/tools/mcp.lua) with the arguments
of the tool. A call is therefore one turn of the kernel, every change goes
through `paw.api`, and a call that writes is exactly one undo step. A call
that fails part way rolls back.

The server speaks MCP through `rmcp`, the official Rust SDK. Each tool is
one entry of the table in [src/tools](src/tools/mod.rs), with its schema and
its code.
