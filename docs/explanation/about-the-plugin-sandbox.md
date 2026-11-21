# About the plugin sandbox

A plugin is code from a different vendor that runs inside the audio
program. In most hosts, a plugin that crashes stops the full program, and
a plugin that hangs stops the sound. paw runs each plugin, and each device
written in Lua, in a helper process of its own. This page tells why, and
what this costs. For the behavior and the flags, see
[Plugins](../reference/plugins.md#processes).

## One process for each plugin

The helper is the `paw` program, started again as a plugin host. When a
plugin crashes, only its helper stops. paw tells which plugin stopped and
why, and the track continues: an effect lets the sound through, an
instrument is silent. `:device.restart` starts the plugin again from the
last state that the project has of it. The project does not lose work
because of a bad plugin.

## Audio through shared memory

The audio thread and the helper share memory for the audio, and use a
futex to signal a block. The audio thread waits for the helper for no
longer than about one block. A slow plugin then costs its own track one
block of sound, but the other tracks do not drop out. A plugin that gives
no block for two seconds has hung, and paw stops it as if it crashed.

The events of the blocks that the plugin is too late to take stay on the
side of paw. paw gives them to the plugin at the first frame of the next
block that it takes. So a note that starts while the plugin is late
sounds a little late. A note-off is not lost: a lost note-off leaves a
note that does not stop.

paw keeps up to 1024 events. If more come, paw
keeps the note-offs first. It counts the events that it drops with the
dropped MIDI events of the engine.

The cost is the transfer: each block goes to a different process and
back. `--plugins-in-process` removes the transfer and also removes the
protection. The default keeps the protection: a crash costs more than the
transfer.

## Why Lua devices also run apart

LuaJIT allocates memory while it runs. The audio thread must never
allocate, because an allocation can wait for a lock. So a Lua device runs
in a helper process, with a LuaJIT state of its own, as a plugin does. The
engine gives the helper each block through shared memory and waits inside
the block, so a Lua device adds no latency. This is true also with
`--plugins-in-process`, because the reason is the allocation, not the
protection.

## Why plugins load in the background

Some plugins take seconds to load. If paw waited for each plugin, a large
project would open slowly, and the person could do nothing during that
time. So the device shows immediately as `loading`, and helpers make the
plugins, four at a time. The project is available immediately, and each
plugin plays when it is ready. A render waits for all devices, because a
render must contain all of the sound.

## Why paw remembers failures

A plugin that crashes during a scan, or during the load of a project,
would crash again at each start. So paw records the file of the plugin,
and the next start does not use it until the file changes or you ask for
it. For a project, paw records the failure next to the state of the
project, not in the project file. The failure belongs to this computer,
not to the project.
