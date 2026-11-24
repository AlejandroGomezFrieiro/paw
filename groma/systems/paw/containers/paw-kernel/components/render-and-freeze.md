---
type: C4 Component
title: Render and freeze
status: stable
groma:
  id: render-and-freeze
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/session/render.rs
    - scanner: rust
      file: crates/paw-core/src/session/encode.rs
    - scanner: rust
      file: crates/paw-core/src/session/tags.rs
    - scanner: rust
      file: crates/paw-core/src/session/offline.rs
      symbol: offline
    - scanner: rust
      file: crates/paw-core/src/freeze.rs
  group: Session operations
  technology: Rust
description: Renders the project or stems to files, and freezes tracks to sound files.
---

Builds an offline engine from the project and renders in the background to WAV and FLAC, with tags; lossy formats (MP3, Ogg, Opus) go through ffmpeg when it is installed. Frozen tracks play from a rendered file instead of their clips and devices.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-core/src/session/render.rs](../../../../../../crates/paw-core/src/session/render.rs) | [crates/paw-engine/src/engine/mod.rs](../../../../../../crates/paw-engine/src/engine/mod.rs) | Renders offline | Offline engine instance |
| [crates/paw-core/src/session/encode.rs](../../../../../../crates/paw-core/src/session/encode.rs) | [ffmpeg](../../../../../externals/ffmpeg.md) | Encodes lossy formats | Child process |
