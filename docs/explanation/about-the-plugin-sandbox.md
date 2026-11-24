# About the plugin sandbox

paw runs each plugin, and each device written in Lua, in a helper process
of its own. A plugin is code from another vendor that runs inside the audio
program, and in most hosts a plugin that crashes stops the whole program,
and a plugin that hangs stops the sound. The page explains why paw uses
helper processes and what they cost. For the behavior and the flags, see
[Plugins](../reference/plugins.md#processes).

## One process for each plugin

The helper is the `paw` program, started again as a plugin host, so when a
plugin crashes, only its helper stops. paw tells you which plugin stopped
and why, and the part continues. An effect lets the sound through, and an
instrument is silent. `:device.restart` starts the plugin again from the
last state of it that the project has, so the project does not lose work
because of a bad plugin.

## Audio through shared memory

The audio thread and the helper share memory for the audio, and they use a
futex to signal a block. The audio thread waits for the helper for no
longer than about one block, so a slow plugin costs its own part one block
of sound, but the other parts do not drop out. A plugin that gives no
block for two seconds has hung, and paw stops it as if it crashed.

When the plugin is too late to take a block, the events of the block stay
on the side of paw. paw gives them to the plugin at the first frame of the
next block that it takes, so a note that starts while the plugin is late
sounds a little late. A note-off is never lost, because a lost note-off
leaves a note that does not stop.

paw keeps up to 1024 events, and if more come, paw keeps the note-offs
first. It counts the events that it drops with the dropped MIDI events of
the engine.

The cost of the sandbox is the transfer, because each block goes to another
process and back. `--plugins-in-process` removes the transfer and also
removes the protection. The default keeps the protection, because a crash
costs more than the transfer.

## Why Lua devices also run apart

LuaJIT allocates memory while it runs, and the audio thread must never
allocate, because an allocation can wait for a lock. A Lua device therefore
runs in a helper process with a LuaJIT state of its own, like a plugin does.
The engine gives the helper each block through shared memory and waits
inside the block, so a Lua device adds no latency. Lua devices run apart
also with `--plugins-in-process`, because the reason is the allocation and
not the protection.

## Why plugins load in the background

Some plugins take seconds to load, and if paw waited for each plugin, a
large project would open slowly and you could do nothing in the meantime.
The device instead shows at once as `loading`, and helpers make the
plugins, four at a time. The project is available at once, and each plugin
plays when it is ready. A render waits for all devices, because a render
must contain all of the sound.

## Why paw remembers failures

A plugin that crashes during a scan, or during the load of a project, would
crash again at each start. paw therefore records the file of the plugin,
and the next start does not use it until the file changes or you ask for
it. For a project, paw records the failure next to the state of the
project and not in the project file, because the failure belongs to the
computer and not to the project.
