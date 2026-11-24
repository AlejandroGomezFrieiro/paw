---
type: C4 Component
title: Window shell
status: stable
groma:
  id: window-shell
  parent: paw-gui
  code:
    - scanner: rust
      file: crates/paw-gui/src/main.rs
    - scanner: rust
      file: crates/paw-gui/src/args.rs
      symbol: renderer_choice
    - scanner: rust
      file: crates/paw-gui/src/runner.rs
    - scanner: rust
      file: crates/paw-gui/src/app.rs
    - scanner: rust
      file: crates/paw-gui/src/keys.rs
  technology: Rust, winit, egui, glutin
description: 'The window''s entry point and event loop: command line, frame loop and key input.'
---

Starts or attaches to a kernel, runs winit/egui/OpenGL directly so the window draws only on change, keeps the last state the kernel sent, and passes keys in the kernel's key notation.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-gui/src/main.rs](../../../../../../crates/paw-gui/src/main.rs) | [crates/paw-gui/src/client.rs](../../../../../../crates/paw-gui/src/client.rs) | Connects to a kernel | Rust call |
| [crates/paw-gui/src/app.rs](../../../../../../crates/paw-gui/src/app.rs) | [crates/paw-gui/src/scene.rs](../../../../../../crates/paw-gui/src/scene.rs) | Paints panes | Rust call |
| [crates/paw-gui/src/app.rs](../../../../../../crates/paw-gui/src/app.rs) | [crates/paw-gui/src/live.rs](../../../../../../crates/paw-gui/src/live.rs) | Redraws live values | Rust call |
| [crates/paw-gui/src/app.rs](../../../../../../crates/paw-gui/src/app.rs) | [crates/paw-gui/src/chrome.rs](../../../../../../crates/paw-gui/src/chrome.rs) | Draws the chrome | Rust call |
