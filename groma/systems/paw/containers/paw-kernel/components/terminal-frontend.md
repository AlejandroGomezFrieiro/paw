---
type: C4 Component
title: Terminal frontend
status: stable
groma:
  id: terminal-frontend
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-tui/src/terminal.rs
    - scanner: rust
      file: crates/paw-tui/src/graphics.rs
  group: Terminal frontend
  technology: Rust, crossterm
description: Shows the kernel's cell grid in the terminal and turns terminal events into kernel input.
---

The main frontend. Draws the cells that changed since the last frame, sends keys, mouse and resize events to the kernel, and shows view drawings as pixels in terminals that support the kitty graphics protocol.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-tui/src/terminal.rs](../../../../../../crates/paw-tui/src/terminal.rs) | [crates/paw-core/src/kernel.rs](../../../../../../crates/paw-core/src/kernel.rs) | Sends input | Rust call, in process |
| [crates/paw-tui/src/terminal.rs](../../../../../../crates/paw-tui/src/terminal.rs) | [crates/paw-core/src/grid.rs](../../../../../../crates/paw-core/src/grid.rs) | Shows cells | Rust call, in process |
| [crates/paw-tui/src/graphics.rs](../../../../../../crates/paw-tui/src/graphics.rs) | [crates/paw-raster/src/lib.rs](../../../../../../crates/paw-raster/src/lib.rs) | Rasterizes drawings | Rust call |
