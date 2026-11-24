---
type: C4 Component
title: Step
status: stable
groma:
  id: step
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/step.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callbacks: paw.api.engine_follow_always, paw.api.engine_get, paw.api.engine_midi_filter | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.json_decode, paw.api.json_encode | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [crates/paw-core/src/api/midi.rs](../../../../../../crates/paw-core/src/api/midi.rs) | Invokes supplied callback: paw.api.midi_inputs | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.env | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [runtime/lua/paw/audio.lua](../../../../../../runtime/lua/paw/audio.lua) | Invokes supplied callback: paw.audio.pick | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.Context, paw.commands.Result, paw.commands.define, require("paw.commands") | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track_id | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.midi_in, paw.events.kernel.midi_lost, require("paw.events.kernel") | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.defer | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.feed | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.name, require("paw.music") | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, require("paw.options") | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callbacks: paw.pick, paw.pick.sources | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.current, require("paw.seats") | teal |
| [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.grabber, paw.ui.notify | teal |
