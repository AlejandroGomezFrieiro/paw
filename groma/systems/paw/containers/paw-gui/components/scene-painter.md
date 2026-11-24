---
type: C4 Component
title: Scene painter
status: stable
groma:
  id: scene-painter
  parent: paw-gui
  code:
    - scanner: rust
      file: crates/paw-gui/src/scene.rs
    - scanner: rust
      file: crates/paw-gui/src/roles.rs
    - scanner: rust
      file: crates/paw-gui/src/timeline.rs
    - scanner: rust
      file: crates/paw-gui/src/panes.rs
    - scanner: rust
      file: crates/paw-gui/src/canvas.rs
    - scanner: rust
      file: crates/paw-gui/src/pictures.rs
  technology: Rust, egui
description: 'Paints the kernel''s scenes: panes and tabs as the kernel lays them out, roles as widgets, the arrange timeline, canvases and clip pictures.'
---

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-gui/src/scene.rs](../../../../../../crates/paw-gui/src/scene.rs) | [crates/paw-scene/src/lib.rs](../../../../../../crates/paw-scene/src/lib.rs) | Reads scenes | Rust call |
| [crates/paw-gui/src/scene.rs](../../../../../../crates/paw-gui/src/scene.rs) | [crates/paw-raster/src/lib.rs](../../../../../../crates/paw-raster/src/lib.rs) | Rasterizes drawings | Rust call |
