---
type: C4 Component
title: Engine sync
status: stable
groma:
  id: engine-sync
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/sync/mod.rs
    - scanner: rust
      file: crates/paw-core/src/sync/items.rs
      symbol: item_events
    - scanner: rust
      file: crates/paw-core/src/sync/mapper.rs
    - scanner: rust
      file: crates/paw-core/src/sync/routing.rs
    - scanner: rust
      file: crates/paw-core/src/sync/audio.rs
    - scanner: rust
      file: crates/paw-core/src/sync/automation.rs
    - scanner: rust
      file: crates/paw-core/src/sync/clips.rs
    - scanner: rust
      file: crates/paw-core/src/sync/devices.rs
  group: Session operations
  technology: Rust
description: 'The one path to the engine: turns the difference between two project snapshots into engine messages and change events.'
---

Edits, undo, project loads and offline renders all go through it, so the engine always agrees with the model. Tracks which engine slot each track and device lives in, computes routing and the processing schedule, compiles MIDI clips to events and audio clips to regions, and reports which clips and lanes changed.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-core/src/sync/mod.rs](../../../../../../crates/paw-core/src/sync/mod.rs) | [crates/paw-engine/src/engine/handle.rs](../../../../../../crates/paw-engine/src/engine/handle.rs) | Sends engine messages | Rust call |
| [crates/paw-core/src/sync/clips.rs](../../../../../../crates/paw-core/src/sync/clips.rs) | [crates/paw-engine/src/clip.rs](../../../../../../crates/paw-engine/src/clip.rs) | Compiles clips | Rust call |
