---
type: C4 Component
title: Eventlist
status: stable
groma:
  id: eventlist
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/eventlist.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/eventlist.lua](../../../../../../runtime/lua/paw/views/eventlist.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/views/eventlist.lua](../../../../../../runtime/lua/paw/views/eventlist.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.redo, paw.api.undo | teal |
| [runtime/lua/paw/views/eventlist.lua](../../../../../../runtime/lua/paw/views/eventlist.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.exec | teal |
| [runtime/lua/paw/views/eventlist.lua](../../../../../../runtime/lua/paw/views/eventlist.lua) | [runtime/lua/paw/controls.lua](../../../../../../runtime/lua/paw/controls.lua) | Invokes supplied callbacks: paw.controls.add, paw.controls.cells, paw.controls.columns, paw.controls.edit, paw.controls.remove_row, paw.controls.rows, require("paw.controls") | teal |
| [runtime/lua/paw/views/eventlist.lua](../../../../../../runtime/lua/paw/views/eventlist.lua) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.fields | teal |
| [runtime/lua/paw/views/eventlist.lua](../../../../../../runtime/lua/paw/views/eventlist.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.input, paw.ui.notify, paw.ui.view, paw.ui.views | teal |
| [runtime/lua/paw/views/eventlist.lua](../../../../../../runtime/lua/paw/views/eventlist.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
