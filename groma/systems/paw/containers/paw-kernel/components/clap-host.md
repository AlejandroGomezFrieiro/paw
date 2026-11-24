---
type: C4 Component
title: CLAP host
status: stable
groma:
  id: clap-host
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-plugins/src/clap.rs
    - scanner: rust
      file: crates/paw-plugins/src/attach.rs
  group: Plugin hosting
  technology: Rust, CLAP
description: 'Hosts CLAP plugins: factory, instance, callbacks, processing, and attachments that extensions ship.'
---

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-plugins/src/clap.rs](../../../../../../crates/paw-plugins/src/clap.rs) | [third-party-plugins](../../../../../externals/third-party-plugins.md) | Loads plugins | CLAP |
| [crates/paw-plugins/src/clap.rs](../../../../../../crates/paw-plugins/src/clap.rs) | [extensions/sampler/native/src/plugin.rs](../../../../../../extensions/sampler/native/src/plugin.rs) | Loads the sampler | CLAP |
