---
type: C4 Component
title: Adjust
status: stable
groma:
  id: adjust
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/adjust.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/adjust.tl](../../../../../../runtime/lua/paw/views/adjust.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/views/adjust.tl](../../../../../../runtime/lua/paw/views/adjust.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/views/adjust.tl](../../../../../../runtime/lua/paw/views/adjust.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.adjust, paw.commands.adjusting, paw.commands.panel, paw.commands.run, require("paw.commands") | teal |
| [runtime/lua/paw/views/adjust.tl](../../../../../../runtime/lua/paw/views/adjust.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.defer | teal |
| [runtime/lua/paw/views/adjust.tl](../../../../../../runtime/lua/paw/views/adjust.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.fields | teal |
| [runtime/lua/paw/views/adjust.tl](../../../../../../runtime/lua/paw/views/adjust.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.notify, paw.ui.open, paw.ui.view | teal |
| [runtime/lua/paw/views/adjust.tl](../../../../../../runtime/lua/paw/views/adjust.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.Data, paw.util.clamp, require("paw.util") | teal |
