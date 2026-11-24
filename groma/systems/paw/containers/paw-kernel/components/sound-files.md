---
type: C4 Component
title: Sound files
status: stable
groma:
  id: sound-files
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-engine/src/wav.rs
    - scanner: rust
      file: crates/paw-engine/src/probe.rs
      symbol: probe
    - scanner: rust
      file: crates/paw-engine/src/envelope.rs
    - scanner: rust
      file: crates/paw-engine/src/samples.rs
  group: Audio engine
  technology: Rust, memmap2
description: Reads sound file headers and levels, holds decoded audio in memory or disk-backed caches, and writes WAV.
---

Long recordings are decoded once into a disk cache and memory-mapped, so the audio thread never waits for the disk.
