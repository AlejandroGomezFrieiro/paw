---
type: C4 Component
title: Arrange track
status: stable
groma:
  id: arrange-track
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/arrange_track.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_notes, paw.api.clip_peaks | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.str_width | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/audio.lua](../../../../../../runtime/lua/paw/audio.lua) | Invokes supplied callbacks: paw.audio.label, paw.audio.level | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.db_text, paw.draw.g, paw.draw.miniroll, paw.draw.mix, paw.draw.pan_text, paw.draw.track_colour, paw.draw.track_peak, paw.draw.waveform | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.changed, paw.events.kernel.device_changed, paw.events.kernel.device_ready, paw.events.kernel.project_loaded, require("paw.events.kernel") | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | Invokes supplied callbacks: paw.folds.count, paw.folds.name, paw.folds.row | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | Invokes supplied callbacks: paw.freeze, paw.freeze.state | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.content_key | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callbacks: paw.groups.depth, paw.groups.folded, paw.groups.is_group, paw.groups.members | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | Invokes supplied callbacks: paw.nest.content_key, paw.nest.notes | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/plot.tl](../../../../../../runtime/lua/paw/plot.tl) | Invokes supplied callbacks: paw.plot.wave, paw.plot.wave_cells | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/stretch.lua](../../../../../../runtime/lua/paw/stretch.lua) | Invokes supplied callbacks: paw.stretch.badge, paw.stretch.repeats, paw.stretch.sounding | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | Invokes supplied callback: paw.takes.badge | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callback: require("paw.theme") | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | Invokes supplied callback: paw.track_kinds.spec | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/trackcolumn.tl](../../../../../../runtime/lua/paw/trackcolumn.tl) | Invokes supplied callback: paw.trackcolumn.shows | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.paint, paw.ui.scene_drawing | teal |
| [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
