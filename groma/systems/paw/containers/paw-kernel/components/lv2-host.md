---
type: C4 Component
title: LV2 host
status: stable
groma:
  id: lv2-host
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-plugins/src/lv2/mod.rs
    - scanner: rust
      file: crates/paw-plugins/src/lv2/atom.rs
    - scanner: rust
      file: crates/paw-plugins/src/lv2/controller.rs
    - scanner: rust
      file: crates/paw-plugins/src/lv2/device.rs
    - scanner: rust
      file: crates/paw-plugins/src/lv2/factory.rs
    - scanner: rust
      file: crates/paw-plugins/src/lv2/shared.rs
    - scanner: rust
      file: crates/paw-plugins/src/lv2/ui.rs
    - scanner: rust
      file: crates/paw-plugins/src/lv2/urid.rs
    - scanner: rust
      file: crates/paw-plugins/src/lv2/worker.rs
    - scanner: rust
      file: crates/paw-plugins/src/lv2/world.rs
    - scanner: rust
      file: crates/paw-plugins/src/lv2_patch.rs
  group: Plugin hosting
  technology: Rust, lilv
description: 'Hosts LV2 plugins on lilv: discovery, ports, atoms, URIDs, worker, properties and editors.'
---

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-plugins/src/lv2/mod.rs](../../../../../../crates/paw-plugins/src/lv2/mod.rs) | [third-party-plugins](../../../../../externals/third-party-plugins.md) | Loads plugins | LV2 via lilv |
