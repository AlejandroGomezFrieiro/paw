---
type: C4 Component
title: VST3 host
status: stable
groma:
  id: vst3-host
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-plugins/src/vst3.rs
  group: Plugin hosting
  technology: Rust, VST3
description: Hosts VST3 plugins over the COM bindings.
---

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-plugins/src/vst3.rs](../../../../../../crates/paw-plugins/src/vst3.rs) | [third-party-plugins](../../../../../externals/third-party-plugins.md) | Loads plugins | VST3 |
