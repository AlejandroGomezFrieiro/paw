---
type: C4 Container
title: paw-mcp (MCP server)
status: stable
groma:
  id: paw-mcp
  parent: paw
  technology: Rust, rmcp, tokio
description: A Model Context Protocol server that lets an AI assistant read, edit, mix and render a paw project.
---

Runs on stdio for an MCP client and talks to a kernel's control socket: an existing instance, or one it spawns (`--spawn`). Its tools check their arguments against their schemas, turn musical values (note names, `bar.beat`) into kernel calls, and report back as compact text. Because a model cannot listen, it renders the song and reports levels and spectrum. Free Lua evaluation is offered only with `--allow-eval`.
