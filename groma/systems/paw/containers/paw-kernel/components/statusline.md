---
type: C4 Component
title: Statusline
status: stable
groma:
  id: statusline
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/statusline.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callbacks: paw.api.engine_get, paw.api.engine_load, paw.api.render_status | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_playhead | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callback: paw.api.tempo_bbt | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/audio.lua](../../../../../../runtime/lua/paw/audio.lua) | Invokes supplied callback: paw.audio.load | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.clip, paw.cursor.track | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | Invokes supplied callbacks: paw.derived.progress, require("paw.derived") | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | Invokes supplied callbacks: paw.diagnostic, paw.diagnostic.status | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.g | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.midi_in, require("paw.events.kernel") | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | Invokes supplied callbacks: paw.folds, paw.folds.time_at | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.defer | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.pending, paw.keymap.recording, paw.keymap.selection, paw.keymap.visual | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callback: paw.mouse.hint_text | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | Invokes supplied callbacks: paw.qf, paw.qf.status | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.new, require("paw.registry") | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/ruler.tl](../../../../../../runtime/lua/paw/ruler.tl) | Invokes supplied callback: paw.ruler.bars_of | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope, paw.scope.breadcrumb, paw.scope.current, paw.scope.format, paw.scope.span | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | Invokes supplied callback: paw.textbuf.buf | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.float, paw.ui.focused, paw.ui.transport, paw.ui.views | teal |
| [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.fit, paw.util.merge, require("paw.util") | teal |
