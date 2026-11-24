---
type: C4 Component
title: Help
status: stable
groma:
  id: views-help
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/help.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/help.lua](../../../../../../runtime/lua/paw/views/help.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/views/help.lua](../../../../../../runtime/lua/paw/views/help.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [runtime/lua/paw/views/help.lua](../../../../../../runtime/lua/paw/views/help.lua) | [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | Invokes supplied callbacks: paw.help.complete, paw.help.open | teal |
| [runtime/lua/paw/views/help.lua](../../../../../../runtime/lua/paw/views/help.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.has, paw.keymap.human, paw.keymap.list | teal |
| [runtime/lua/paw/views/help.lua](../../../../../../runtime/lua/paw/views/help.lua) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.fields | teal |
| [runtime/lua/paw/views/help.lua](../../../../../../runtime/lua/paw/views/help.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.open, paw.ui.view | teal |
| [runtime/lua/paw/views/help.lua](../../../../../../runtime/lua/paw/views/help.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
