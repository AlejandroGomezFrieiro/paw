---
type: C4 Component
title: Sampler CLAP plugin
status: stable
groma:
  id: sampler-clap-plugin
  parent: sampler-plugin
  code:
    - scanner: rust
      file: extensions/sampler/native/src/plugin.rs
    - scanner: rust
      file: extensions/sampler/native/src/params.rs
    - scanner: rust
      file: extensions/sampler/native/src/lib.rs
    - scanner: rust
      file: extensions/sampler/native/src/describe.rs
  technology: Rust, CLAP
description: 'The `dev.paw.sampler` CLAP plugin: parameters, state and the instrument description.'
---

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/sampler/native/src/plugin.rs](../../../../../../extensions/sampler/native/src/plugin.rs) | [extensions/sampler/native/src/engine.rs](../../../../../../extensions/sampler/native/src/engine.rs) | Plays voices | Rust call, audio thread |
| [extensions/sampler/native/src/plugin.rs](../../../../../../extensions/sampler/native/src/plugin.rs) | [extensions/sampler/native/src/formats/mod.rs](../../../../../../extensions/sampler/native/src/formats/mod.rs) | Loads instruments | Rust call |
