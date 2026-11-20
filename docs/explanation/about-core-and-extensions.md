# About the core and extensions

<!-- tags: extensions-core-and-plugins -->

paw keeps two things apart: the core and the extensions. This page tells
where the line between them is, why it is there, and how far an extension
can go. [Extensions](../reference/extensions.md) describes the interface.

## The rule

**The core** is what an extension could not add. It is the audio engine,
the project model, the plugin hosts and the `paw.api` functions. It is
also the runtime in `runtime/lua/paw`, which makes objects, commands, keys
and views from them. It is compiled into the binary, and it is the same for each
user.

**An extension** is all that can be written against that interface. It
lives in a directory of its own. paw loads it only when you ask. You can
delete it, and the rest of paw does not change. The core never requires an
extension.

## What is in the core, and why

| In the core | Why |
| --- | --- |
| Tracks, routing, sends before or after the fader, buses | the engine mixes them |
| Clips, notes, controller moves, fades, automation lanes | they are the model, and what the engine plays |
| Delay compensation, the limiter and the other built-in devices | the engine runs them |
| The hosts of CLAP, LV2 and VST3 plugins, plugin windows | native code, and the audio thread |
| MIDI 1.0 and 2.0 input, recording, the recording offset | ports, and the audio thread |
| Rendering: stems, dither, normalization | the engine, offline |
| Undo as a tree, safety copies and recovery | the model, and the safety of your work |
| Modal keys, the picker, the views | all other parts use them |
| The key of the song (`project.key`) | the harmony, the LSP and many extensions read it |
| Base64, deflate, CRC-32, ZIP archives (`paw.bytes`, `paw.zip`) | the file formats of several extensions use them |
| XML and TOML (`paw.xml`, `paw.toml`) | MusicXML, DAWproject, the states of JUCE plugins and the articulation maps use them |
| The formats of other programs' files (`paw.formats`), and MIDI files | `:import`, `:open` and `:export` take each format that an extension registers |
| The levels of a sound file, a WAV file from samples (`paw.api.sound_envelope`, `sound_write`) | the doctor and the articulations measure sound with them |
| Finding an installed plugin (`paw.api.device_find`) | each importer of projects finds plugins, without the list of all of them |
| A tempo map from points in seconds (`paw.api.tempo_from_seconds`) | REAPER and DAWproject files keep times in seconds |
| Files without a shell (`paw.api.fs_*`, `which`) | an extension makes folders, copies and finds programs without running a shell |
| Buttons and hit lists of a window (`paw.canvas.button`, `paw.canvas.hit_list`) | the windows of several extensions have buttons |

Two extensions that need the same thing do not each keep a copy. Some
data of an extension is read by the core or by other extensions, such as
the key of the song. That data moves into the project model. When extensions
read and write the same file format, such as ZIP or base64, the codec
moves into the core. An extension keeps only its own data in `meta`.

Sometimes an extension needed something that only the core could give.
Examples are a fast measurement of loudness, a tree of undo states, and
data for each instance of a device. Then that one thing went into the core as an API function,
general enough for any extension. The rest stayed outside.

## One interface, both frontends

An extension writes a view one time. The terminal draws its cells, and the
graphical window shows the same view with no code of its own. An
extension that wants more than cells in the window adds a `paint`
function. The terminal continues to draw cells. So an extension never has
to choose between the terminal and the window, and the terminal always
comes first.

The same is true for pictures. A view keeps a strip of pixels under its
cells, and each frontend draws the strip in its own way. The terminal
sends images with the kitty protocol, and keeps each piece by a hash. So
a scroll sends nothing new.

The graphical window gets the strip as a
part of the scene. Nothing in the graphical window knows about strips.
See [Pictures in the terminal](../reference/pictures.md).

## How far an extension goes: a voice that sings

The synthesis of a voice is an extension, engine included. The core of paw
has no code for it. The utau extension brings the vocal editor, the kind of track,
the device that plays the voice, and the engine that sings. A Nix
configuration that names the extension gets all of them.

```
extensions/utau/
  init.lua, lua/utau/   the editor, the commands, the talk with the engine
  devices/utau.lua      the device that plays the voice (Lua, in its own process)
  engine/               the C# source of the engine, on OpenUtau.Core
  nix/                  how the engine and the extension are built and packaged
```

The core gives it parts that any extension can use:

- devices in Lua that get data from scripts
- kinds of track
- helper programs
- plugins in directories of the extension
- renamed kinds of device
- Nix packages with parts to build

The utau device shows how these parts work together. The extension writes
each phrase from the engine to a file, and posts the list of files of each
voice to all the utau devices. Each device plays the files at their
place. Playback and a render give the same result, bit for bit.

## Why Lua has a time limit

An extension is Lua that runs in the kernel. If a handler loops forever,
the program stops. So paw stops Lua that runs for more than two seconds
without a return, and the program continues.

The usual way to do this is a hook that counts instructions. That hook
costs time in each call, and LuaJIT cannot compile the code.

paw does a different thing. Nothing in Lua watches the clock. A thread in the
kernel knows when the call must return. When that time is past, the
thread sets a hook from outside. The LuaJIT in paw is built to see that
hook inside compiled loops (`LUAJIT_ENABLE_CHECKHOOK`, in
`.cargo/config.toml`). So the limit costs nothing, and LuaJIT compiles
all code, extensions included.

A build without that flag uses the count hook. It keeps code that is not
part of the runtime in the interpreter of LuaJIT.
