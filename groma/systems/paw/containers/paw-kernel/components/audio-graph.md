---
type: C4 Component
title: Audio graph
status: stable
groma:
  id: audio-graph
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-engine/src/engine/mod.rs
    - scanner: rust
      file: crates/paw-engine/src/engine/process.rs
    - scanner: rust
      file: crates/paw-engine/src/engine/schedule.rs
    - scanner: rust
      file: crates/paw-engine/src/engine/track.rs
    - scanner: rust
      file: crates/paw-engine/src/engine/work.rs
    - scanner: rust
      file: crates/paw-engine/src/engine/guarded.rs
    - scanner: rust
      file: crates/paw-engine/src/engine/regions.rs
    - scanner: rust
      file: crates/paw-engine/src/engine/click.rs
    - scanner: rust
      file: crates/paw-engine/src/engine/device_rt.rs
    - scanner: rust
      file: crates/paw-engine/src/lib.rs
    - scanner: rust
      file: crates/paw-engine/src/pool.rs
    - scanner: rust
      file: crates/paw-engine/src/host.rs
    - scanner: rust
      file: crates/paw-engine/src/guard.rs
    - scanner: rust
      file: crates/paw-engine/src/preview.rs
  group: Audio engine
  technology: Rust
description: 'Processes one audio callback: tracks, routing, device chains and the metronome, on the audio thread and its worker pool.'
---

Cuts each callback into blocks, runs tracks that do not feed each other on real-time worker threads and sums them in a fixed order so renders are bit-identical. Compensates device latency across all paths, guards each device (a panic stops the device, NaN becomes silence) and never locks or allocates. Also plays picker previews.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-engine/src/engine/work.rs](../../../../../../crates/paw-engine/src/engine/work.rs) | [crates/paw-engine/src/device.rs](../../../../../../crates/paw-engine/src/device.rs) | Processes devices | Rust trait, audio thread |
| [crates/paw-engine/src/engine/mod.rs](../../../../../../crates/paw-engine/src/engine/mod.rs) | [crates/paw-engine/src/record.rs](../../../../../../crates/paw-engine/src/record.rs) | Captures takes | Rust call |
| [crates/paw-engine/src/engine/track.rs](../../../../../../crates/paw-engine/src/engine/track.rs) | [crates/paw-engine/src/clip.rs](../../../../../../crates/paw-engine/src/clip.rs) | Plays clips | Rust call |
