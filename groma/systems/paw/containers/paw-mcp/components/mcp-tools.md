---
type: C4 Component
title: MCP tools
status: stable
groma:
  id: mcp-tools
  parent: paw-mcp
  code:
    - scanner: rust
      file: crates/paw-mcp/src/tools/mod.rs
    - scanner: rust
      file: crates/paw-mcp/src/tools/read.rs
    - scanner: rust
      file: crates/paw-mcp/src/tools/write.rs
    - scanner: rust
      file: crates/paw-mcp/src/tools/session.rs
    - scanner: rust
      file: crates/paw-mcp/src/tools/escape.rs
    - scanner: rust
      file: crates/paw-mcp/src/music.rs
    - scanner: rust
      file: crates/paw-mcp/src/format.rs
  technology: Rust
description: The tools that read, change and save the project, each change one undo step.
---

Normalizes musical values written by a model (note names, positions, lengths) and formats kernel data as compact text. Escape hatches that run arbitrary code are off unless enabled.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-mcp/src/tools/mod.rs](../../../../../../crates/paw-mcp/src/tools/mod.rs) | [crates/paw-mcp/src/kernel.rs](../../../../../../crates/paw-mcp/src/kernel.rs) | Calls the kernel | Rust call |
