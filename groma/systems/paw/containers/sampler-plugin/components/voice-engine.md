---
type: C4 Component
title: Voice engine
status: stable
groma:
  id: voice-engine
  parent: sampler-plugin
  code:
    - scanner: rust
      file: extensions/sampler/native/src/engine.rs
    - scanner: rust
      file: extensions/sampler/native/src/interp.rs
    - scanner: rust
      file: extensions/sampler/native/src/m2.rs
  technology: Rust
description: The real-time voice engine that plays an instrument, with MIDI 2.0 articulation choice per note.
---

Programs are built off the audio thread; voices interpolate samples and pick regions by the M2-123 articulation code with its fallback order.
