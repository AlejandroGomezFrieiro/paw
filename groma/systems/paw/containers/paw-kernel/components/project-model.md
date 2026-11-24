---
type: C4 Component
title: Project model
status: stable
groma:
  id: project-model
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/model.rs
    - scanner: rust
      file: crates/paw-core/src/history.rs
    - scanner: rust
      file: crates/paw-core/src/edits.rs
    - scanner: rust
      file: crates/paw-core/src/attr_map.rs
    - scanner: rust
      file: crates/paw-core/src/model/clips.rs
    - scanner: rust
      file: crates/paw-core/src/model/notes.rs
    - scanner: rust
      file: crates/paw-core/src/model/custom.rs
  group: Project model and files
  technology: Rust
description: The project as plain data, cheap to clone, and the undo tree of its snapshots.
---

Tracks, devices and clips behind `Arc`; an edit copies only what it changes, so the undo tree keeps every state (branches included) while sharing the unchanged parts. Also holds audio clip edit lists, custom clip kinds defined by extensions and the attribute maps that bring MIDI 2.0 articulations to instruments.
