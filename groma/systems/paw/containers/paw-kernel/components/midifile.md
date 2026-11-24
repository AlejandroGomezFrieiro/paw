---
type: C4 Component
title: Midifile
status: stable
groma:
  id: midifile
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/midifile.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_controls, paw.api.clip_get, paw.api.clip_notes | teal |
| [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_get, paw.api.project_mark_saved, paw.api.project_new, paw.api.project_set | teal |
| [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.midi2_read, paw.api.midi2_write, paw.api.undo_reset | teal |
| [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor, paw.cursor.index, paw.cursor.set_track | teal |
| [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callbacks: paw.markers.add, paw.markers.list | teal |
| [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.clip, paw.objects.track, paw.objects.tracks | teal |
| [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callbacks: paw.tempo.at, paw.tempo.points, paw.tempo.set_points, paw.tempo.signature_at, paw.tempo.signatures | teal |
| [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.views | teal |
