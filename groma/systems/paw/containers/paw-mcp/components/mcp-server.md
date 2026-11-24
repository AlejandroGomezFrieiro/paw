---
type: C4 Component
title: MCP server
status: stable
groma:
  id: mcp-server
  parent: paw-mcp
  code:
    - scanner: rust
      file: crates/paw-mcp/src/main.rs
    - scanner: rust
      file: crates/paw-mcp/src/server.rs
    - scanner: rust
      file: crates/paw-mcp/src/schema.rs
    - scanner: rust
      file: crates/paw-mcp/src/check.rs
    - scanner: rust
      file: crates/paw-mcp/src/resources.rs
    - scanner: rust
      file: crates/paw-mcp/src/reference.rs
  technology: Rust, rmcp
description: 'The MCP protocol handler: tool schemas, argument checks, resources and the API reference.'
---

Exposes the tools with their input schemas, rejects bad arguments before anything runs, and serves the manual's pages and an API reference built from the source as resources.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-mcp/src/server.rs](../../../../../../crates/paw-mcp/src/server.rs) | [crates/paw-mcp/src/tools/mod.rs](../../../../../../crates/paw-mcp/src/tools/mod.rs) | Dispatches tool calls | Rust call |
