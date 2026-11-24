---
type: C4 Actor
title: Configuration author
description: 'Changes paw with Lua: an init.lua, extensions and scripts.'
status: stable
groma:
  id: configuration-author
---

A user who keeps their tools in a configuration they write. Writes `~/.config/paw/init.lua`, extensions and scripts that call the `paw` API, and drives a running instance with `paw ctl`.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [configuration-author](configuration-author.md) | [crates/paw-core/src/api/mod.rs](../../crates/paw-core/src/api/mod.rs) | Scripts and extends | Lua and Teal: init.lua, extensions |
| [configuration-author](configuration-author.md) | [crates/paw-tui/src/main.rs](../../crates/paw-tui/src/main.rs) | Drives an instance | paw ctl |
