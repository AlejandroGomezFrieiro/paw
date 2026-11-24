---
type: C4 Component
title: Cmdline
status: stable
groma:
  id: cmdline
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/cmdline.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_cursor, paw.api.ui_redraw, paw.api.ui_redraw_line | teal |
| [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_label | teal |
| [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | [runtime/lua/paw/cmdwin.tl](../../../../../../runtime/lua/paw/cmdwin.tl) | Invokes supplied callback: require("paw.cmdwin") | teal |
| [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.keys | teal |
| [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | Invokes supplied callbacks: paw.help, paw.help.topic_of | teal |
| [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.first, paw.keymap.human, paw.keymap.mode, paw.keymap.pending, paw.keymap.set_mode | teal |
| [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callbacks: paw.mouse.overlays, paw.mouse.wheel | teal |
| [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.keep | teal |
| [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.keybar, paw.ui.live, paw.ui.message, paw.ui.messages, paw.ui.notify, paw.ui.view | teal |
| [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
