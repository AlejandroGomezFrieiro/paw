---
type: C4 Component
title: Screen and scenes
status: stable
groma:
  id: screen-and-scenes
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/grid.rs
    - scanner: rust
      file: crates/paw-core/src/scene.rs
    - scanner: teal
      file: crates/paw-core/src/scene.rs
  group: Scenes and drawing
  technology: Rust
description: The cell grid Lua draws into, and the scene each window of a view becomes for graphical frontends.
---

The grid of styled cells is the whole contract between the UI code and the terminal. For graphical frontends the kernel records what a view draws as a scene of named nodes and sends only the nodes that changed.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-core/src/scene.rs](../../../../../../crates/paw-core/src/scene.rs) | [crates/paw-scene/src/lib.rs](../../../../../../crates/paw-scene/src/lib.rs) | Records scenes | Rust call |
