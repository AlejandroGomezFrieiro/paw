---
type: C4 Component
title: Engine handle
status: stable
groma:
  id: engine-handle
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-engine/src/engine/handle.rs
    - scanner: rust
      file: crates/paw-engine/src/engine/msg.rs
    - scanner: rust
      file: crates/paw-engine/src/engine/apply.rs
    - scanner: rust
      file: crates/paw-engine/src/engine/shared.rs
    - scanner: rust
      file: crates/paw-engine/src/engine/stats.rs
    - scanner: rust
      file: crates/paw-engine/src/slot.rs
  group: Audio engine
  technology: Rust, lock-free queues
description: 'The main thread''s end of the audio engine: messages in, freed data and published state out.'
---

The main thread builds everything the audio thread uses and sends it through a lock-free queue; the audio thread applies the messages between blocks, sends back what it no longer uses to be freed, and publishes position, meters and timing statistics.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-engine/src/engine/handle.rs](../../../../../../crates/paw-engine/src/engine/handle.rs) | [crates/paw-engine/src/engine/mod.rs](../../../../../../crates/paw-engine/src/engine/mod.rs) | Drives the audio thread | Lock-free queue |
