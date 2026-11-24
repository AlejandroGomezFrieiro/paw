---
type: C4 Component
title: Control socket
status: stable
groma:
  id: control-socket
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/rpc.rs
    - scanner: rust
      file: crates/paw-core/src/io_runtime.rs
      symbol: handle
    - scanner: rust
      file: crates/paw-core/src/tls.rs
    - scanner: rust
      file: crates/paw-core/src/remote.rs
    - scanner: rust
      file: crates/paw-core/src/upload.rs
    - scanner: rust
      file: crates/paw-core/src/monitor.rs
    - scanner: rust
      file: crates/paw-core/src/session/monitor.rs
  group: Remote access
  technology: Rust, tokio, rustls, JSON lines
description: Lets other processes, local or remote, call a running kernel and hear from it.
---

One JSON object per line over a Unix socket, or over TCP inside TLS with a certificate the instance makes. Pushes state, scenes and terminal cells to attached frontends, streams the instance's audio to listeners, and receives uploaded media files.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-core/src/rpc.rs](../../../../../../crates/paw-core/src/rpc.rs) | [crates/paw-core/src/kernel.rs](../../../../../../crates/paw-core/src/kernel.rs) | Queues calls | Kernel turns |
