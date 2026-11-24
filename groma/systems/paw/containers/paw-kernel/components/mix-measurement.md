---
type: C4 Component
title: Mix measurement
status: stable
groma:
  id: mix-measurement
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/measure/mod.rs
    - scanner: teal
      file: crates/paw-core/src/measure/mod.rs
  group: Session operations
  technology: Rust
description: Measures loudness, true peak, clipping and spectrum of the mix (`paw.api.measure*`).
---

Renders the mix in memory with the offline engine and measures it to ITU-R BS.1770 / EBU R 128. Extensions such as `mixdiag` and the MCP listening tools build on it.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-core/src/measure/mod.rs](../../../../../../crates/paw-core/src/measure/mod.rs) | [crates/paw-core/src/session/offline.rs](../../../../../../crates/paw-core/src/session/offline.rs) | Renders the mix | Rust call |
