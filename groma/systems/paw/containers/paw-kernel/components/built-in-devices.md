---
type: C4 Component
title: Built-in devices
status: stable
groma:
  id: built-in-devices
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-engine/src/devices/mod.rs
    - scanner: rust
      file: crates/paw-engine/src/devices/drums.rs
    - scanner: rust
      file: crates/paw-engine/src/devices/dsp.rs
    - scanner: rust
      file: crates/paw-engine/src/devices/dynamics.rs
    - scanner: rust
      file: crates/paw-engine/src/devices/eq.rs
    - scanner: rust
      file: crates/paw-engine/src/devices/fx.rs
    - scanner: rust
      file: crates/paw-engine/src/devices/limiter.rs
    - scanner: rust
      file: crates/paw-engine/src/devices/meter.rs
    - scanner: rust
      file: crates/paw-engine/src/devices/modulation.rs
    - scanner: rust
      file: crates/paw-engine/src/devices/panel.rs
    - scanner: rust
      file: crates/paw-engine/src/devices/reverb.rs
    - scanner: rust
      file: crates/paw-engine/src/devices/sampler.rs
    - scanner: rust
      file: crates/paw-engine/src/devices/synth.rs
    - scanner: rust
      file: crates/paw-engine/src/devices/utility.rs
  group: Audio engine
  technology: Rust
description: 'The devices that ship with the engine: synth, drum kit, sample kit, EQ, dynamics, limiter, reverb, modulation, meters.'
---

Effects and instruments written in Rust on shared DSP building blocks. Some report curves, gain reduction or loudness to the main thread for their panels.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-engine/src/devices/mod.rs](../../../../../../crates/paw-engine/src/devices/mod.rs) | [crates/paw-engine/src/device.rs](../../../../../../crates/paw-engine/src/device.rs) | Implements devices | Rust trait |
