---
type: C4 Component
title: Drawing rasterizer
status: stable
groma:
  id: rasterizer
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-raster/src/lib.rs
    - scanner: rust
      file: crates/paw-raster/src/fonts.rs
    - scanner: rust
      file: crates/paw-raster/src/pixels.rs
    - scanner: rust
      file: crates/paw-raster/src/vector.rs
    - scanner: rust
      file: crates/paw-raster/src/tiles.rs
    - scanner: rust
      file: crates/paw-raster/src/kitty.rs
    - scanner: rust
      file: crates/paw-raster/src/probe.rs
  group: Scenes and drawing
  technology: Rust, tiny-skia, SMuFL fonts
description: Turns view drawings (`paw.canvas`) into pixels with built-in music fonts, the same in the terminal and the window.
---

Paints vector drawings and pictures, exports SVG or PDF, and shows pixels in a terminal through the kitty graphics protocol in tiles that are sent again only when they change. Probes the terminal's colors and cell size. Linked into the kernel and the window.
