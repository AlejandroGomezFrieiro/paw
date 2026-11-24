---
type: C4 Component
title: Helper processes
status: stable
groma:
  id: helper-processes
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/io.rs
  group: Kernel and Lua bridge
  technology: Rust, tokio
description: 'Child processes and Unix sockets that extensions drive from Lua: renderers, language servers, engines.'
---

Starts a program, feeds it and reads its output on the kernel's I/O runtime, and opens sockets for it. The `utau` extension starts its singing engine this way and `midilsp` its language server.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-core/src/io.rs](../../../../../../crates/paw-core/src/io.rs) | [language-servers](../../../../../externals/language-servers.md) | Starts servers | Child process, stdio |
| [crates/paw-core/src/io.rs](../../../../../../crates/paw-core/src/io.rs) | [extensions/utau/engine/PawUtau.Engine/EngineHost.cs](../../../../../../extensions/utau/engine/PawUtau.Engine/EngineHost.cs) | Starts the singing engine | Child process, Unix socket |
