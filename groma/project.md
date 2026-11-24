---
type: Groma Project
title: paw
groma:
  profile: architecture
description: Architecture of paw, a modal, keyboard-driven audio workstation for Linux with a Rust kernel and a Lua runtime.
---

C4 map of paw: the `paw` kernel and terminal binary with its Lua/Teal runtime, the bundled extensions, the graphical window, the MCP server, and the native parts of the sampler and utau extensions. The Lua and Teal sources are read by a local scanner (`teal`), outside the repository.
