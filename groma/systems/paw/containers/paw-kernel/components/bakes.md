---
type: C4 Component
title: Bakes
status: stable
groma:
  id: bakes
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/bake/mod.rs
    - scanner: rust
      file: crates/paw-core/src/bake/helper.rs
    - scanner: rust
      file: crates/paw-core/src/bake/key.rs
    - scanner: rust
      file: crates/paw-core/src/bake/native.rs
    - scanner: rust
      file: crates/paw-core/src/bake/scheduler.rs
    - scanner: rust
      file: crates/paw-core/src/bake/store.rs
  group: Session operations
  technology: Rust
description: Computes derived media (stretched audio, helper outputs) off the kernel thread and caches it for all projects.
---

A scheduler makes what the project needs in the order the user hears it, on native worker threads or through helper programs such as ffmpeg, and keeps the results in one cache (`$XDG_CACHE_HOME/paw/bakes`) keyed by a hash of the job.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-core/src/bake/helper.rs](../../../../../../crates/paw-core/src/bake/helper.rs) | [ffmpeg](../../../../../externals/ffmpeg.md) | Runs helper bakes | Child process |
