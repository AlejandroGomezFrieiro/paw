---
type: C4 Component
title: Mixer
status: stable
groma:
  id: mixer
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/mixer.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/mixer.lua](../../../../../../runtime/lua/paw/views/mixer.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/views/mixer.lua](../../../../../../runtime/lua/paw/views/mixer.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/views/mixer.lua](../../../../../../runtime/lua/paw/views/mixer.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track_id | teal |
| [runtime/lua/paw/views/mixer.lua](../../../../../../runtime/lua/paw/views/mixer.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.db_text, paw.draw.g, paw.draw.track_colour, paw.draw.track_hue, paw.draw.track_peak | teal |
| [runtime/lua/paw/views/mixer.lua](../../../../../../runtime/lua/paw/views/mixer.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.vca_words | teal |
| [runtime/lua/paw/views/mixer.lua](../../../../../../runtime/lua/paw/views/mixer.lua) | [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | Invokes supplied callbacks: paw.mixer_rows.current, paw.mixer_rows.describe_row | teal |
| [runtime/lua/paw/views/mixer.lua](../../../../../../runtime/lua/paw/views/mixer.lua) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callback: paw.scope.tracks | teal |
| [runtime/lua/paw/views/mixer.lua](../../../../../../runtime/lua/paw/views/mixer.lua) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.fields | teal |
| [runtime/lua/paw/views/mixer.lua](../../../../../../runtime/lua/paw/views/mixer.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.paint, paw.ui.titlebar, paw.ui.view | teal |
| [runtime/lua/paw/views/mixer.lua](../../../../../../runtime/lua/paw/views/mixer.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
| [runtime/lua/paw/views/mixer.lua](../../../../../../runtime/lua/paw/views/mixer.lua) | [runtime/lua/paw/vca.tl](../../../../../../runtime/lua/paw/vca.tl) | Invokes supplied callbacks: paw.vca.is_vca, paw.vca.members | teal |
