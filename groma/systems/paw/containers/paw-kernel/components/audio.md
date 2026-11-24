---
type: C4 Component
title: Audio
status: stable
groma:
  id: audio
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/audio.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/audio.lua](../../../../../../runtime/lua/paw/audio.lua) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callbacks: paw.api.audio_devices, paw.api.audio_use, paw.api.engine_get, paw.api.input_levels | teal |
| [runtime/lua/paw/audio.lua](../../../../../../runtime/lua/paw/audio.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/audio.lua](../../../../../../runtime/lua/paw/audio.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_set | teal |
| [runtime/lua/paw/audio.lua](../../../../../../runtime/lua/paw/audio.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.midi, paw.objects.track | teal |
| [runtime/lua/paw/audio.lua](../../../../../../runtime/lua/paw/audio.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [runtime/lua/paw/audio.lua](../../../../../../runtime/lua/paw/audio.lua) | [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | Invokes supplied callbacks: paw.routes.midi_out_form_order, paw.routes.midi_out_forms, paw.routes.midi_out_text | teal |
| [runtime/lua/paw/audio.lua](../../../../../../runtime/lua/paw/audio.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
