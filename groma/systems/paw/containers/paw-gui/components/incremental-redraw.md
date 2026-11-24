---
type: C4 Component
title: Incremental redraw
status: stable
groma:
  id: incremental-redraw
  parent: paw-gui
  code:
    - scanner: rust
      file: crates/paw-gui/src/damage.rs
    - scanner: rust
      file: crates/paw-gui/src/live.rs
  technology: Rust
description: Repaints only what changed between frames, and moves live values (playhead, meters) without a layout pass.
---


