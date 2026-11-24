---
type: C4 System
title: AI assistant
description: An assistant such as Claude Code that works on a project through paw-mcp.
status: stable
groma:
  id: ai-assistant
  technology: MCP client
---

Starts `paw-mcp` as an MCP server on stdio and uses its tools to make, edit, mix and render songs.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [ai-assistant](ai-assistant.md) | [crates/paw-mcp/src/server.rs](../../crates/paw-mcp/src/server.rs) | Uses tools | MCP over stdio |
