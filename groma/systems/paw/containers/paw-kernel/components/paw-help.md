---
type: C4 Component
title: Help
status: stable
groma:
  id: paw-help
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/help.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.read_dir | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callbacks: paw.api.log, paw.api.now, paw.api.real_ms | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.scheme, require("paw.address") | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.define, paw.commands.get, paw.commands.run, require("paw.commands") | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.event, paw.events.on, paw.events.startup, require("paw.events") | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callback: require("paw.events.kernel") | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callbacks: paw.ext.bundled_dir, paw.ext.list, paw.ext.loaded | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/formats.tl](../../../../../../runtime/lua/paw/formats.tl) | Invokes supplied callback: paw.formats.help_text | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.defer | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.every, paw.keymap.human, paw.keymap.push_jump, paw.keymap.set | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.buf_create, paw.layout.buf_of, paw.layout.current, paw.layout.enter, paw.layout.show_in, paw.layout.split, paw.layout.windows | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/markdown.tl](../../../../../../runtime/lua/paw/markdown.tl) | Invokes supplied callbacks: paw.markdown.parse, paw.markdown.plain, paw.markdown.render, paw.markdown.width, require("paw.markdown") | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.list, require("paw.options") | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | Invokes supplied callbacks: paw.qf.jump, paw.qf.set | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.keep, require("paw.seats") | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/slices.tl](../../../../../../runtime/lua/paw/slices.tl) | Invokes supplied callbacks: paw.slices.job, paw.slices.stop, require("paw.slices") | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | Invokes supplied callbacks: paw.textbuf.buf, paw.textbuf.here, paw.textbuf.kind | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.keybar, paw.ui.notify, paw.ui.size, paw.ui.views | teal |
| [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.merge, paw.util.wrap, require("paw.util") | teal |
