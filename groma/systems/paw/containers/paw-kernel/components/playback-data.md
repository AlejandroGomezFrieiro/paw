---
type: C4 Component
title: Playback data
status: stable
groma:
  id: playback-data
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-engine/src/clip.rs
    - scanner: rust
      file: crates/paw-engine/src/event.rs
    - scanner: rust
      file: crates/paw-engine/src/automation.rs
    - scanner: rust
      file: crates/paw-engine/src/tempo.rs
    - scanner: rust
      file: crates/paw-engine/src/launch.rs
  group: Audio engine
  technology: Rust
description: 'What the engine plays: note and controller events, audio regions, automation, the tempo map and launched cues.'
---

Plain data laid out in beats, built by the engine sync on the main thread. The tempo map gives exact conversions between beats, seconds and bars.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-engine/src/clip.rs](../../../../../../crates/paw-engine/src/clip.rs) | [crates/paw-engine/src/samples.rs](../../../../../../crates/paw-engine/src/samples.rs) | Holds decoded audio | Memory or mapped cache |
