---
type: C4 Component
title: Textbuf
status: stable
groma:
  id: textbuf
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/textbuf.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo, paw.api.undo_checkpoint, paw.api.undo_label | teal |
| [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas.open_view, paw.canvas.open_views | teal |
| [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.complete, paw.commands.define, paw.commands.exec, paw.commands.line_handlers, paw.commands.run, paw.commands.used, require("paw.commands") | teal |
| [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, paw.events.pattern, require("paw.events") | teal |
| [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.changed, paw.keymap.getreg, paw.keymap.last_visual, paw.keymap.mode, paw.keymap.mode_changed, paw.keymap.normal, paw.keymap.selection, paw.keymap.set_mode, paw.keymap.setreg | teal |
| [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.buf_create, paw.layout.buf_of, paw.layout.buffers, paw.layout.buftype, paw.layout.current, paw.layout.enter, paw.layout.get, paw.layout.leaf, paw.layout.powers, paw.layout.show_in, paw.layout.split, paw.layout.windows | teal |
| [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callback: paw.mouse.wheel | teal |
| [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.new, require("paw.registry") | teal |
| [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.fields, paw.seats.keep | teal |
| [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui, paw.ui.notify | teal |
| [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.Data, paw.util.clamp, paw.util.fit, paw.util.merge, require("paw.util") | teal |
