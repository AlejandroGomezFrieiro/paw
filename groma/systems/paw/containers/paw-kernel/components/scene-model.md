---
type: C4 Component
title: Scene model
status: stable
groma:
  id: scene-model
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-scene/src/lib.rs
    - scanner: rust
      file: crates/paw-scene/src/cells.rs
    - scanner: rust
      file: crates/paw-scene/src/color.rs
    - scanner: rust
      file: crates/paw-scene/src/props.rs
  group: Scenes and drawing
  technology: Rust
description: 'What every frontend shares of a view: cells, colors, role properties and the scene node tree.'
---

A scene is the drawing of one window of a view as named nodes in cell units; roles (faders, meters, notes) carry their data so a graphical frontend can paint widgets while the terminal draws their cells. Linked into the kernel and the window.
