---
type: C4 System
title: paw
status: stable
groma:
  id: paw
description: Personal audio workstation for Linux, played from the keyboard like Vim and changed in Lua.
---

paw records, edits, mixes and renders songs. A small Rust kernel plays the sound, keeps the project and hosts plugins. Everything the user touches (views, keys, commands, Ex commands) is Lua and Teal over one API, `paw`, so a configuration (`~/.config/paw/init.lua`) and extensions can change all of it while the song plays.

The terminal is the main frontend; a graphical window shows the same views as scenes that the kernel sends. A project is a folder of text files (one per track and per clip, MIDI clips as `.midi2`). Third-party CLAP, LV2 and VST3 plugins and Lua devices run in helper processes of their own. Scripts, `paw ctl` and AI agents (through `paw-mcp`) drive a running kernel over its control socket.

The Lua/Teal runtime (`runtime/lua/paw`, embedded in the `paw` binary) is mapped by the local `teal` scanner as components of the kernel container, one per module. Each bundled extension (`extensions/*`, its manifest, `init` and `lua/` modules) is one component; they run in the same LuaJIT state, on top of the runtime and the `paw.api` component. Their relationships come from `require()`, the manifest `requires`, and the module members they use.
