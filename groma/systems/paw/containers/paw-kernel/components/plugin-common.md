---
type: C4 Component
title: Plugin scan and shared hosting
status: stable
groma:
  id: plugin-common
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-plugins/src/lib.rs
    - scanner: rust
      file: crates/paw-plugins/src/presets.rs
    - scanner: rust
      file: crates/paw-plugins/src/echo.rs
    - scanner: rust
      file: crates/paw-plugins/src/libs.rs
    - scanner: rust
      file: crates/paw-plugins/src/window.rs
  group: Plugin hosting
  technology: Rust
description: The plugin scan and its cache, presets, editor windows and library loading shared by all formats.
---


