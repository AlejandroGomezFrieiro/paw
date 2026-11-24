---
type: C4 Component
title: Kernel connection
status: stable
groma:
  id: kernel-connection
  parent: paw-gui
  code:
    - scanner: rust
      file: crates/paw-gui/src/client.rs
    - scanner: rust
      file: crates/paw-gui/src/model.rs
  technology: Rust
description: The window's connection to the control socket and the pushed state it draws from.
---

Calls the kernel and receives `frontend.watch` state and scenes; spawns a headless kernel when none is given; can hear a remote kernel through the remote listener.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-gui/src/client.rs](../../../../../../crates/paw-gui/src/client.rs) | [crates/paw-proto/src/lib.rs](../../../../../../crates/paw-proto/src/lib.rs) | Calls the kernel | Rust call |
| [crates/paw-gui/src/client.rs](../../../../../../crates/paw-gui/src/client.rs) | [crates/paw-tui/src/main.rs](../../../../../../crates/paw-tui/src/main.rs) | Spawns a headless kernel | Child process |
| [crates/paw-gui/src/client.rs](../../../../../../crates/paw-gui/src/client.rs) | [crates/paw-listen/src/lib.rs](../../../../../../crates/paw-listen/src/lib.rs) | Hears the kernel | Rust call |
