---
type: C4 Container
title: paw (kernel and terminal)
status: stable
groma:
  id: paw-kernel
  parent: paw
  technology: Rust, LuaJIT (mlua), Teal
description: 'The `paw` binary: the kernel, the audio engine, the plugin hosts and the terminal frontend in one process.'
---

The process a musician starts with `paw`. One kernel thread owns the session (project, undo tree, running engine) and the LuaJIT state that runs the built-in Lua runtime, the user's configuration and the extensions; the audio thread and its worker pool play the project. The terminal frontend shows the kernel's cell grid and sends keys back. Without a terminal (`--headless`) the same kernel serves other frontends through its control socket.

The same binary also runs as a helper: started again with the plugin-host arguments it hosts one plugin or one Lua device per process (the Plugin hosting group), and it scans plugins in a helper too. These helpers are separate processes at run time; they share this container because they are the same executable.

The scene, raster, control-client and listen libraries are also linked into the graphical window (and the control client into `paw-mcp`); each is mapped once, here.
