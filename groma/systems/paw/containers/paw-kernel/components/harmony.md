---
type: C4 Component
title: Harmony
status: stable
groma:
  id: harmony
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/harmony.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_get, paw.api.project_set | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.g | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.changed, paw.events.kernel.project_loaded, require("paw.events.kernel") | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [runtime/lua/paw/harmony/read.tl](../../../../../../runtime/lua/paw/harmony/read.tl) | Invokes supplied callbacks: paw.harmony.read.ReadModule, paw.harmony.read.by_quality, paw.harmony.read.chords, paw.harmony.read.keys, paw.harmony.read.qualities, require("paw.harmony.read") | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [runtime/lua/paw/harmony/song.tl](../../../../../../runtime/lua/paw/harmony/song.tl) | Invokes supplied callbacks: paw.harmony.song.busy, paw.harmony.song.notes, paw.harmony.song.reading, paw.harmony.song.reset, paw.harmony.song.setup, paw.harmony.song.stamp, paw.harmony.song.update, require("paw.harmony.song") | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [runtime/lua/paw/harmony/voice.tl](../../../../../../runtime/lua/paw/harmony/voice.tl) | Invokes supplied callbacks: paw.harmony.voice.VoiceModule, require("paw.harmony.voice") | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callback: paw.markers.list | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.scales | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [runtime/lua/paw/slices.tl](../../../../../../runtime/lua/paw/slices.tl) | Invokes supplied callbacks: paw.slices.job, paw.slices.run, require("paw.slices") | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.fit, require("paw.util") | teal |
