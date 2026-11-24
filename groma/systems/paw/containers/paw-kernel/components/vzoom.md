---
type: C4 Component
title: Vzoom
status: stable
groma:
  id: vzoom
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/vzoom.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/vzoom.tl](../../../../../../runtime/lua/paw/vzoom.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/vzoom.tl](../../../../../../runtime/lua/paw/vzoom.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/vzoom.tl](../../../../../../runtime/lua/paw/vzoom.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.define, require("paw.commands") | teal |
| [runtime/lua/paw/vzoom.tl](../../../../../../runtime/lua/paw/vzoom.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.lane_id, paw.cursor.row | teal |
| [runtime/lua/paw/vzoom.tl](../../../../../../runtime/lua/paw/vzoom.tl) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callback: paw.groups.rows | teal |
| [runtime/lua/paw/vzoom.tl](../../../../../../runtime/lua/paw/vzoom.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.selection, paw.keymap.set_mode | teal |
| [runtime/lua/paw/vzoom.tl](../../../../../../runtime/lua/paw/vzoom.tl) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.bound, paw.layout.current | teal |
| [runtime/lua/paw/vzoom.tl](../../../../../../runtime/lua/paw/vzoom.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/vzoom.tl](../../../../../../runtime/lua/paw/vzoom.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.drawing_win, paw.ui.focused, paw.ui.notify, paw.ui.views | teal |
