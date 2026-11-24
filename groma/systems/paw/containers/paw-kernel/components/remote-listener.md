---
type: C4 Component
title: Remote listener
status: stable
groma:
  id: remote-listener
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-listen/src/lib.rs
  group: Remote access
  technology: Rust
description: Plays the sound of a kernel on another machine where a terminal or window is attached.
---

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-listen/src/lib.rs](../../../../../../crates/paw-listen/src/lib.rs) | [crates/paw-proto/src/monitor.rs](../../../../../../crates/paw-proto/src/monitor.rs) | Receives audio frames | audio.frame events |
| [crates/paw-listen/src/lib.rs](../../../../../../crates/paw-listen/src/lib.rs) | [linux-audio-and-midi](../../../../../externals/linux-audio-and-midi.md) | Plays remote sound | cpal |
