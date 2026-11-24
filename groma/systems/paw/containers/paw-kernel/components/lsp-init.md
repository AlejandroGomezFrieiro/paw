---
type: C4 Component
title: Init
status: stable
groma:
  id: lsp-init
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/lsp/init.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_note_at, paw.api.clip_notes | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.json_decode | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callbacks: paw.api.lsp_procs, require("paw.api") | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [crates/paw-core/src/api/processes.rs](../../../../../../crates/paw-core/src/api/processes.rs) | Invokes supplied callbacks: paw.api.proc_close_input, paw.api.proc_kill, paw.api.proc_read, paw.api.proc_spawn, paw.api.proc_status, paw.api.proc_write | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.env | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callbacks: paw.api.log, paw.api.now, paw.api.real_ms, paw.api.wait | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.changed, paw.address.clip, paw.address.edit, paw.address.location, paw.address.note, paw.address.parse, paw.address.resolve, paw.address.within, require("paw.address") | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/annotation.lua](../../../../../../runtime/lua/paw/annotation.lua) | Invokes supplied callbacks: paw.annotation, paw.annotation.get, paw.annotation.reset, paw.annotation.set | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | Invokes supplied callbacks: paw.complete, paw.complete.register | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.changed | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | Invokes supplied callbacks: paw.diagnostic.actions, paw.diagnostic.apply, paw.diagnostic.format, paw.diagnostic.get, paw.diagnostic.group, paw.diagnostic.reset, paw.diagnostic.set, paw.diagnostic.where | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.exit, paw.events.on, paw.events.startup, require("paw.events") | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.proc_output, require("paw.events.kernel") | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony, paw.harmony.invalidate, paw.harmony.provide | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.defer, paw.version | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/lsp/document.tl](../../../../../../runtime/lua/paw/lsp/document.tl) | Invokes supplied callbacks: paw.lsp.document.release, paw.lsp.document.string, require("paw.lsp.document") | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/lsp/rpc.tl](../../../../../../runtime/lua/paw/lsp/rpc.tl) | Invokes supplied callbacks: paw.lsp.rpc.encode, paw.lsp.rpc.frame, paw.lsp.rpc.object, paw.lsp.rpc.reader, require("paw.lsp.rpc") | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/lsp/standard.tl](../../../../../../runtime/lua/paw/lsp/standard.tl) | Invokes supplied callbacks: paw.lsp.standard.CommandFn, paw.lsp.standard.Which, require("paw.lsp.standard") | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | Invokes supplied callbacks: paw.lsp.subjects.define, paw.lsp.subjects.list, paw.lsp.subjects.split, paw.lsp.subjects.uri, require("paw.lsp.subjects") | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/roll_clips.tl](../../../../../../runtime/lua/paw/roll_clips.tl) | Invokes supplied callbacks: paw.roll_clips.changed, require("paw.roll_clips") | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats, paw.seats.current, paw.seats.within | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.location, paw.ui.notify, paw.ui.page | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: require("paw.util") | teal |
| [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | Invokes supplied callbacks: paw.views.pianoroll.opened, require("paw.views.pianoroll") | teal |
