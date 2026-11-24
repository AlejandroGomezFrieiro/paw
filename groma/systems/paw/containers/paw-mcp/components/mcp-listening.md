---
type: C4 Component
title: Listening tools
status: stable
groma:
  id: mcp-listening
  parent: paw-mcp
  code:
    - scanner: rust
      file: crates/paw-mcp/src/tools/listen.rs
    - scanner: rust
      file: crates/paw-mcp/src/audio.rs
  technology: Rust
description: Render and measure the song or a file, so a model can judge levels and spectrum without ears.
---

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-mcp/src/tools/listen.rs](../../../../../../crates/paw-mcp/src/tools/listen.rs) | [crates/paw-mcp/src/kernel.rs](../../../../../../crates/paw-mcp/src/kernel.rs) | Renders and measures | Rust call |
