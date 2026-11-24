---
type: C4 Component
title: Media sources
status: stable
groma:
  id: media-sources
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/media/mod.rs
    - scanner: rust
      file: crates/paw-core/src/media/hash.rs
    - scanner: rust
      file: crates/paw-core/src/media/index.rs
    - scanner: rust
      file: crates/paw-core/src/media/sources.rs
    - scanner: rust
      file: crates/paw-core/src/media/table.rs
    - scanner: rust
      file: crates/paw-core/src/media/worker.rs
    - scanner: rust
      file: crates/paw-core/src/session/media.rs
    - scanner: rust
      file: crates/paw-core/src/peaks.rs
    - scanner: rust
      file: crates/paw-core/src/resample.rs
  group: Project model and files
  technology: Rust, BLAKE3
description: Knows the project's sound files by content hash and finds them again when they move.
---

The media table (`media.json`), a local index of hashed files, a background hashing worker, waveform overviews (peaks) and band-limited resampling to the engine rate.
