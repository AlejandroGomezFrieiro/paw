---
type: C4 Component
title: Snippet
status: stable
groma:
  id: snippet
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/snippet.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_notes, paw.api.clip_set_notes | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.read_dir | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo_current, paw.api.undo_join, paw.api.undo_label | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | Invokes supplied callback: paw.audition.phrase | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | Invokes supplied callbacks: paw.complete, paw.complete.register | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.g | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.roll | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, paw.events.startup, require("paw.events") | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.project_loaded, require("paw.events.kernel") | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callback: paw.ext.current | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony.key, paw.harmony.notes, paw.harmony.range, paw.harmony.voice | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.selection, paw.keymap.set_mode | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callbacks: paw.limit.untrusted, require("paw.limit") | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.name, require("paw.music") | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callbacks: paw.pick.open, paw.pick.state | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.keep, require("paw.seats") | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.notify, paw.ui.views | teal |
| [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.fit, require("paw.util") | teal |
