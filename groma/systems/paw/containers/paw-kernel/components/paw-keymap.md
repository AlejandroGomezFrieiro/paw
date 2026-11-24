---
type: C4 Component
title: Keymap
status: stable
groma:
  id: paw-keymap
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/keymap.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.ui_redraw, paw.api.ui_redraw_line, paw.api.ui_redraws | teal |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callbacks: paw.api.now, paw.api.timer_start, paw.api.timer_stop | teal |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo, paw.api.undo_checkpoint, paw.api.undo_current, paw.api.undo_join, paw.api.undo_label | teal |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.exec, paw.commands.owner | teal |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.defer, paw.try | teal |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [runtime/lua/paw/keymap/marks.tl](../../../../../../runtime/lua/paw/keymap/marks.tl) | Invokes supplied callbacks: paw.keymap.marks.Place, paw.keymap.marks.change, paw.keymap.marks.changes, paw.keymap.marks.delmarks, paw.keymap.marks.goto_mark, paw.keymap.marks.jump, paw.keymap.marks.mark, paw.keymap.marks.marks, paw.keymap.marks.push_change, paw.keymap.marks.push_jump, paw.keymap.marks.shada_project, paw.keymap.marks.shada_set_project, require("paw.keymap.marks") | teal |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [runtime/lua/paw/keymap/registers.tl](../../../../../../runtime/lua/paw/keymap/registers.tl) | Invokes supplied callbacks: paw.keymap.registers.getreg, paw.keymap.registers.play, paw.keymap.registers.record, paw.keymap.registers.recording, paw.keymap.registers.registers, paw.keymap.registers.setreg, paw.keymap.registers.stop, paw.keymap.registers.typed, require("paw.keymap.registers") | teal |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callback: paw.limit.named | teal |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.changed, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.keep | teal |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | Invokes supplied callback: paw.statusline.winbar | teal |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.grabber, paw.ui.notify, paw.ui.rects, paw.ui.views | teal |
| [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.copy | teal |
