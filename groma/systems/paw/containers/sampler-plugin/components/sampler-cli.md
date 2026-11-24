---
type: C4 Component
title: Sampler command line
status: stable
groma:
  id: sampler-cli
  parent: sampler-plugin
  code:
    - scanner: rust
      file: extensions/sampler/native/src/bin/paw-sampler.rs
    - scanner: rust
      file: extensions/sampler/native/src/fixtures.rs
  technology: Rust
description: '`paw-sampler`: describe, render and benchmark instruments, and write the test instruments.'
---

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/sampler/native/src/bin/paw-sampler.rs](../../../../../../extensions/sampler/native/src/bin/paw-sampler.rs) | [extensions/sampler/native/src/engine.rs](../../../../../../extensions/sampler/native/src/engine.rs) | Renders notes | Rust call |
