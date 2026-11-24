---
type: C4 Component
title: Audio backends
status: stable
groma:
  id: audio-backends
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-engine/src/backend.rs
    - scanner: rust
      file: crates/paw-engine/src/backend/cpal.rs
  group: Audio engine
description: Drive the engine from a real audio device, or from a clock thread with no device.
---

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-engine/src/backend.rs](../../../../../../crates/paw-engine/src/backend.rs) | [crates/paw-engine/src/engine/mod.rs](../../../../../../crates/paw-engine/src/engine/mod.rs) | Calls each block | Rust call, audio thread |
| [crates/paw-engine/src/backend/cpal.rs](../../../../../../crates/paw-engine/src/backend/cpal.rs) | [linux-audio-and-midi](../../../../../externals/linux-audio-and-midi.md) | Plays and records | cpal |
