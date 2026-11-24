---
type: C4 Component
title: Layout
status: stable
groma:
  id: layout
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/layout.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_list | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.json_decode, paw.api.json_encode | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_files, paw.api.project_screen, paw.api.project_screen_set | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.read_dir | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas, paw.canvas.contracts, paw.canvas.inside, paw.canvas.open_views | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.Candidate, paw.commands.Context, paw.commands.Result, paw.commands.completers, paw.commands.get, paw.commands.run, require("paw.commands") | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, paw.events.startup, require("paw.events") | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.project_loaded, require("paw.events.kernel") | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.defer | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.operator, paw.keymap.set, paw.keymap.textobject | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.project, paw.objects.time | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.new, require("paw.registry") | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope, paw.scope.current | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.copy, paw.seats.current, paw.seats.keep, paw.seats.kind, paw.seats.list, paw.seats.within, require("paw.seats") | teal |
| [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui, paw.ui.close, paw.ui.float, paw.ui.focus, paw.ui.focused, paw.ui.layout, paw.ui.notify, paw.ui.page, paw.ui.tab, paw.ui.tabs | teal |
