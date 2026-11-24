---
type: C4 Component
title: Audition
status: stable
groma:
  id: audition
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/audition.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_list, paw.api.clip_notes | teal |
| [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callbacks: paw.api.note_off, paw.api.note_on, paw.api.preview_get, paw.api.preview_level, paw.api.preview_play, paw.api.preview_stop, paw.api.transport_get, paw.api.trial_active, paw.api.trial_begin, paw.api.trial_end | teal |
| [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.track_id | teal |
| [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony.default_range, paw.harmony.is_drums, paw.harmony.key, paw.harmony.key_name, paw.harmony.range, paw.harmony.step | teal |
| [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.defer, paw.device_types | teal |
| [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | Invokes supplied callback: paw.midifile.read | teal |
| [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.time | teal |
| [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.changed, paw.options.define, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.keep, require("paw.seats") | teal |
