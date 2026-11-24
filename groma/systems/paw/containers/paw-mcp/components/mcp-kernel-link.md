---
type: C4 Component
title: Kernel link
status: stable
groma:
  id: mcp-kernel-link
  parent: paw-mcp
  code:
    - scanner: rust
      file: crates/paw-mcp/src/kernel.rs
  technology: Rust
description: Connects `paw-mcp` to a kernel's control socket, or spawns one.
---

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-mcp/src/kernel.rs](../../../../../../crates/paw-mcp/src/kernel.rs) | [crates/paw-proto/src/lib.rs](../../../../../../crates/paw-proto/src/lib.rs) | Connects through | Rust call |
| [crates/paw-mcp/src/kernel.rs](../../../../../../crates/paw-mcp/src/kernel.rs) | [crates/paw-tui/src/main.rs](../../../../../../crates/paw-tui/src/main.rs) | Spawns a kernel | Child process (--spawn) |
