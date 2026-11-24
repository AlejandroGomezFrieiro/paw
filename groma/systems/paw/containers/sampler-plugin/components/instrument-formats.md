---
type: C4 Component
title: Instrument formats
status: stable
groma:
  id: instrument-formats
  parent: sampler-plugin
  code:
    - scanner: rust
      file: extensions/sampler/native/src/model.rs
    - scanner: rust
      file: extensions/sampler/native/src/error.rs
    - scanner: rust
      file: extensions/sampler/native/src/audio.rs
    - scanner: rust
      file: extensions/sampler/native/src/formats/mod.rs
    - scanner: rust
      file: extensions/sampler/native/src/formats/sfz.rs
    - scanner: rust
      file: extensions/sampler/native/src/formats/dspreset.rs
  technology: Rust
description: Reads SFZ and Decent Sampler instruments and their samples into one instrument model.
---


