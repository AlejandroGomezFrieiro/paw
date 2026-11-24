---
type: C4 Component
title: Time stretching
status: stable
groma:
  id: time-stretching
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/stretch.rs
    - scanner: rust
      file: crates/paw-core/src/stretched.rs
    - scanner: rust
      file: crates/paw-core/src/warp.rs
    - scanner: rust
      file: crates/paw-core/src/session/stretching.rs
  group: Session operations
  technology: Rust
description: Stretched, warped and pitch-shifted audio clips.
---

Warp markers and the map from file time to stretched time, and the stretched versions of files, made as bakes with a preview while they are made.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-core/src/session/stretching.rs](../../../../../../crates/paw-core/src/session/stretching.rs) | [crates/paw-core/src/stretched.rs](../../../../../../crates/paw-core/src/stretched.rs) | Requests stretched audio | Rust call |
| [crates/paw-core/src/stretched.rs](../../../../../../crates/paw-core/src/stretched.rs) | [crates/paw-core/src/bake/mod.rs](../../../../../../crates/paw-core/src/bake/mod.rs) | Schedules bakes | Rust call |
