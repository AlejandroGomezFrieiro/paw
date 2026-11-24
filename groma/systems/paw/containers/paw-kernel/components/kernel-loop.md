---
type: C4 Component
title: Kernel loop
status: stable
groma:
  id: kernel-loop
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/kernel.rs
    - scanner: teal
      file: crates/paw-core/src/kernel.rs
    - scanner: rust
      file: crates/paw-core/src/lib.rs
    - scanner: rust
      file: crates/paw-core/src/watchdog.rs
  group: Kernel and Lua bridge
  technology: Rust, mlua (LuaJIT)
description: The one kernel thread that owns the session and the Lua state and takes turns with input, RPC calls and timers.
---

Everything user-facing runs here: input from the terminal or the socket goes to Lua, Lua calls `paw.api`, and the resulting edits go to the session. A watchdog stops Lua that runs away, from outside it.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-core/src/kernel.rs](../../../../../../crates/paw-core/src/kernel.rs) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Runs Lua over | mlua (LuaJIT) |
