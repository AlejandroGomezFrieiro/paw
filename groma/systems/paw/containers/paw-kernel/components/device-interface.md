---
type: C4 Component
title: Device interface
status: stable
groma:
  id: device-interface
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-engine/src/device.rs
  group: Audio engine
  technology: Rust
description: 'The trait every device implements: built-in devices, hosted plugins and their stand-ins.'
---

A device sits in a track's chain and makes or changes sound on the audio thread; its controller is the main-thread half for parameters, state and editors. Device factories make both halves.
