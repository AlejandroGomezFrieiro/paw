---
type: C4 Component
title: Plugin sandbox stand-in
status: stable
groma:
  id: plugin-sandbox
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-plugins/src/sandbox/mod.rs
    - scanner: rust
      file: crates/paw-plugins/src/sandbox/controller.rs
    - scanner: rust
      file: crates/paw-plugins/src/sandbox/device.rs
    - scanner: rust
      file: crates/paw-plugins/src/sandbox/factory.rs
    - scanner: rust
      file: crates/paw-plugins/src/sandbox/shm.rs
    - scanner: rust
      file: crates/paw-plugins/src/sandbox/wire.rs
  group: Plugin hosting
  technology: Rust, shared memory, futex
description: 'The kernel''s side of a plugin in a helper process: starts the helper and stands in for the plugin.'
---

The stand-in is a device on the audio thread and a controller on the main thread. Audio crosses shared memory with a futex handshake, waiting at most about one block; control (parameters, state, editor) goes over a wire of requests and answers. A plugin that crashes or hangs stops alone and can be restarted from the project's state.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-plugins/src/sandbox/device.rs](../../../../../../crates/paw-plugins/src/sandbox/device.rs) | [crates/paw-engine/src/device.rs](../../../../../../crates/paw-engine/src/device.rs) | Stands in for plugins | Rust trait |
| [crates/paw-plugins/src/sandbox/factory.rs](../../../../../../crates/paw-plugins/src/sandbox/factory.rs) | [crates/paw-plugins/src/sandbox/serve.rs](../../../../../../crates/paw-plugins/src/sandbox/serve.rs) | Runs plugins in helpers | Child process, shared memory, futex |
