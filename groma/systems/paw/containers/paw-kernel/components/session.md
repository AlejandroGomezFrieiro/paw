---
type: C4 Component
title: Session
status: stable
groma:
  id: session
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/session.rs
    - scanner: rust
      file: crates/paw-core/src/session/editing.rs
    - scanner: rust
      file: crates/paw-core/src/session/tracks.rs
    - scanner: rust
      file: crates/paw-core/src/session/clips.rs
    - scanner: rust
      file: crates/paw-core/src/session/clipops.rs
    - scanner: rust
      file: crates/paw-core/src/session/notes.rs
    - scanner: rust
      file: crates/paw-core/src/session/devices.rs
    - scanner: rust
      file: crates/paw-core/src/session/ports.rs
    - scanner: rust
      file: crates/paw-core/src/session/posts.rs
      symbol: device_post
    - scanner: rust
      file: crates/paw-core/src/session/loading.rs
    - scanner: rust
      file: crates/paw-core/src/session/automation.rs
    - scanner: rust
      file: crates/paw-core/src/session/statelanes.rs
    - scanner: rust
      file: crates/paw-core/src/session/tempo.rs
    - scanner: rust
      file: crates/paw-core/src/session/undo.rs
    - scanner: rust
      file: crates/paw-core/src/session/keep.rs
  group: Session operations
  technology: Rust
description: Edits the project and turns each user action into one undo step.
---

The session holds the project, its undo history and the running engine. Its operations change tracks, clips, notes, devices, automation, state lanes and the tempo map, move in the undo tree, and flush each change to the engine through the engine sync. Plugins are made off the main loop and appear as `loading` until ready.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-core/src/session.rs](../../../../../../crates/paw-core/src/session.rs) | [crates/paw-core/src/model.rs](../../../../../../crates/paw-core/src/model.rs) | Snapshots the project | Rust call |
| [crates/paw-core/src/session.rs](../../../../../../crates/paw-core/src/session.rs) | [crates/paw-core/src/sync/mod.rs](../../../../../../crates/paw-core/src/sync/mod.rs) | Flushes changes | Rust call |
| [crates/paw-core/src/session.rs](../../../../../../crates/paw-core/src/session.rs) | [crates/paw-core/src/session/folder.rs](../../../../../../crates/paw-core/src/session/folder.rs) | Opens and saves | Rust call |
| [crates/paw-core/src/session.rs](../../../../../../crates/paw-core/src/session.rs) | [crates/paw-core/src/media/mod.rs](../../../../../../crates/paw-core/src/media/mod.rs) | Resolves sound files | Rust call |
