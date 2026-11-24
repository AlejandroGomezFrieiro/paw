---
type: C4 Component
title: Pick
status: stable
groma:
  id: pick
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/pick.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callbacks: paw.api, require("paw.api") | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.hl_set, paw.api.str_width, paw.api.ui_cursor, paw.api.ui_redraw, paw.api.ui_size | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.read_dir | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callbacks: paw.api.preview_stop, paw.api.trial_active | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_label | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.parse, require("paw.address") | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | Invokes supplied callbacks: paw.audition.asked, paw.audition.file, paw.audition.keep, paw.audition.midi_file, paw.audition.outline_lines, paw.audition.quiet, paw.audition.revert, paw.audition.state, paw.audition.stop, paw.audition.try | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.exec | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.defer, paw.every | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.current, paw.layout.split, paw.layout.tab_new | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | Invokes supplied callback: paw.midifile.is_midi_file | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | Invokes supplied callbacks: paw.pick.sources.registry, paw.pick.sources.walk, require("paw.pick.sources") | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | Invokes supplied callbacks: paw.qf.go, paw.qf.open, paw.qf.set | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/regex.tl](../../../../../../runtime/lua/paw/regex.tl) | Invokes supplied callback: paw.regex.try | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.new, require("paw.registry") | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.keep, require("paw.seats") | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/slices.tl](../../../../../../runtime/lua/paw/slices.tl) | Invokes supplied callbacks: paw.slices.job, paw.slices.run, paw.slices.stop, require("paw.slices") | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callbacks: paw.theme.palette, require("paw.theme") | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.float, paw.ui.focus, paw.ui.input, paw.ui.keybar, paw.ui.locators, paw.ui.notify, paw.ui.open, paw.ui.view | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.Data, paw.util.fit, require("paw.util") | teal |
| [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | Invokes supplied callback: paw.views.files.here | teal |
