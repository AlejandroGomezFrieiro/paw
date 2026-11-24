---
type: C4 Component
title: paw.api (Lua bridge)
status: stable
groma:
  id: lua-api
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/api/automation.rs
      symbol: install
    - scanner: teal
      file: crates/paw-core/src/api/automation.rs
    - scanner: rust
      file: crates/paw-core/src/api/clips.rs
    - scanner: teal
      file: crates/paw-core/src/api/clips.rs
    - scanner: rust
      file: crates/paw-core/src/api/devices.rs
      symbol: install
    - scanner: teal
      file: crates/paw-core/src/api/devices.rs
    - scanner: rust
      file: crates/paw-core/src/api/engine.rs
    - scanner: teal
      file: crates/paw-core/src/api/engine.rs
    - scanner: rust
      file: crates/paw-core/src/api/formats.rs
    - scanner: teal
      file: crates/paw-core/src/api/formats.rs
    - scanner: rust
      file: crates/paw-core/src/api/kind_data.rs
    - scanner: rust
      file: crates/paw-core/src/api/midi.rs
    - scanner: teal
      file: crates/paw-core/src/api/midi.rs
    - scanner: rust
      file: crates/paw-core/src/api/mod.rs
    - scanner: teal
      file: crates/paw-core/src/api/mod.rs
    - scanner: rust
      file: crates/paw-core/src/api/processes.rs
      symbol: install
    - scanner: teal
      file: crates/paw-core/src/api/processes.rs
    - scanner: rust
      file: crates/paw-core/src/api/project.rs
      symbol: install
    - scanner: teal
      file: crates/paw-core/src/api/project.rs
    - scanner: rust
      file: crates/paw-core/src/api/screen.rs
    - scanner: teal
      file: crates/paw-core/src/api/screen.rs
    - scanner: rust
      file: crates/paw-core/src/api/system.rs
    - scanner: teal
      file: crates/paw-core/src/api/system.rs
    - scanner: rust
      file: crates/paw-core/src/api/timers.rs
    - scanner: teal
      file: crates/paw-core/src/api/timers.rs
    - scanner: rust
      file: crates/paw-core/src/api/tracks.rs
    - scanner: teal
      file: crates/paw-core/src/api/tracks.rs
    - scanner: rust
      file: crates/paw-core/src/api/transport.rs
      symbol: install
    - scanner: teal
      file: crates/paw-core/src/api/transport.rs
    - scanner: rust
      file: crates/paw-core/src/api/undo.rs
      symbol: install
    - scanner: teal
      file: crates/paw-core/src/api/undo.rs
    - scanner: rust
      file: crates/paw-core/src/codec.rs
    - scanner: rust
      file: crates/paw-core/src/events.rs
    - scanner: rust
      file: crates/paw-core/src/ext_api.rs
    - scanner: rust
      file: crates/paw-core/src/fs_api.rs
    - scanner: teal
      file: crates/paw-core/src/fs_api.rs
    - scanner: rust
      file: crates/paw-core/src/luadev_api.rs
    - scanner: teal
      file: crates/paw-core/src/luadev_api.rs
    - scanner: rust
      file: crates/paw-core/src/tempo_api.rs
    - scanner: teal
      file: crates/paw-core/src/tempo_api.rs
    - scanner: rust
      file: crates/paw-core/src/toml_api.rs
    - scanner: rust
      file: crates/paw-core/src/xml.rs
  group: Kernel and Lua bridge
  technology: Rust, mlua
description: 'The flat, plain-data interface between the kernel and Lua: every function the Lua runtime and extensions call.'
---

Groups of functions for tracks, clips, notes, devices, automation, transport, undo, the project, the screen, timers, processes and the file system, plus helpers extensions share (TOML, XML, base64/deflate codecs, sound-file levels). Only plain data crosses it, so the control socket can send the same data. It also defines the events the kernel reports to Lua (`paw.on`). The doc comments here generate `docs/reference/api.md` and the type declarations.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | [crates/paw-core/src/session.rs](../../../../../../crates/paw-core/src/session.rs) | Edits the project | Rust call |
| [crates/paw-core/src/api/processes.rs](../../../../../../crates/paw-core/src/api/processes.rs) | [crates/paw-core/src/io.rs](../../../../../../crates/paw-core/src/io.rs) | Starts helpers | Rust call |
| [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | [crates/paw-core/src/grid.rs](../../../../../../crates/paw-core/src/grid.rs) | Draws views | Rust call |
| [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | [crates/paw-core/src/session/transport.rs](../../../../../../crates/paw-core/src/session/transport.rs) | Controls the transport | Rust call |
