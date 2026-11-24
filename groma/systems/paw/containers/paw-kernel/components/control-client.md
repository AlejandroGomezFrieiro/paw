---
type: C4 Component
title: Control client
status: stable
groma:
  id: control-client
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-proto/src/lib.rs
    - scanner: rust
      file: crates/paw-proto/src/dirs.rs
    - scanner: rust
      file: crates/paw-proto/src/runtime.rs
      symbol: handle
    - scanner: rust
      file: crates/paw-proto/src/tls.rs
    - scanner: rust
      file: crates/paw-proto/src/monitor.rs
  group: Remote access
  technology: Rust, tokio, rustls
description: The client side of the control protocol, for programs that talk to a kernel without linking it.
---

Connects over a Unix socket or TCP with TLS (trust on first use), finds the default socket, and receives the instance's audio stream. Used by `paw ctl`/`attach`, the window and `paw-mcp`.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-proto/src/lib.rs](../../../../../../crates/paw-proto/src/lib.rs) | [crates/paw-core/src/rpc.rs](../../../../../../crates/paw-core/src/rpc.rs) | Calls the kernel | JSON lines over Unix socket or TLS |
