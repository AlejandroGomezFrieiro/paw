---
type: C4 Component
title: Project exchange extension
status: stable
groma:
  id: interop-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/interop/init.tl
    - scanner: teal
      file: extensions/interop/lua/interop/dawproject/export.tl
    - scanner: teal
      file: extensions/interop/lua/interop/dawproject/import.tl
    - scanner: teal
      file: extensions/interop/lua/interop/dawproject/init.tl
    - scanner: teal
      file: extensions/interop/lua/interop/dawproject/vst3.tl
    - scanner: teal
      file: extensions/interop/lua/interop/dawproject/xmlio.tl
    - scanner: teal
      file: extensions/interop/lua/interop/init.tl
    - scanner: teal
      file: extensions/interop/lua/interop/report.tl
    - scanner: teal
      file: extensions/interop/lua/interop/rpp/export.tl
    - scanner: teal
      file: extensions/interop/lua/interop/rpp/format.tl
    - scanner: teal
      file: extensions/interop/lua/interop/rpp/fx.tl
    - scanner: teal
      file: extensions/interop/lua/interop/rpp/import.tl
    - scanner: teal
      file: extensions/interop/lua/interop/rpp/init.tl
    - scanner: teal
      file: extensions/interop/lua/interop/rpp/midi.tl
    - scanner: teal
      file: extensions/interop/manifest.lua
      symbol: interop
  group: Bundled extensions
  technology: Teal, Lua
description: Opens and writes REAPER and DAWproject projects.
---

Reads and writes REAPER projects (.rpp) and DAWproject files (Bitwig Studio, Studio One, Cubase), so a song can move between paw and other programs in both directions.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/interop/lua/interop/dawproject/export.tl](../../../../../../extensions/interop/lua/interop/dawproject/export.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_list, paw.api.lane_points, paw.api.lane_shapes | teal |
| [extensions/interop/lua/interop/dawproject/export.tl](../../../../../../extensions/interop/lua/interop/dawproject/export.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_controls, paw.api.clip_list, paw.api.clip_notes, paw.api.cue_list | teal |
| [extensions/interop/lua/interop/dawproject/export.tl](../../../../../../extensions/interop/lua/interop/dawproject/export.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_state | teal |
| [extensions/interop/lua/interop/dawproject/export.tl](../../../../../../extensions/interop/lua/interop/dawproject/export.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [extensions/interop/lua/interop/dawproject/export.tl](../../../../../../extensions/interop/lua/interop/dawproject/export.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.sound_envelope | teal |
| [extensions/interop/lua/interop/dawproject/export.tl](../../../../../../extensions/interop/lua/interop/dawproject/export.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [extensions/interop/lua/interop/dawproject/export.tl](../../../../../../extensions/interop/lua/interop/dawproject/export.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [extensions/interop/lua/interop/dawproject/export.tl](../../../../../../extensions/interop/lua/interop/dawproject/export.tl) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_sound | teal |
| [extensions/interop/lua/interop/dawproject/export.tl](../../../../../../extensions/interop/lua/interop/dawproject/export.tl) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callbacks: paw.api.tempo_points, paw.api.tempo_seconds | teal |
| [extensions/interop/lua/interop/dawproject/export.tl](../../../../../../extensions/interop/lua/interop/dawproject/export.tl) | [runtime/lua/paw/bytes.tl](../../../../../../runtime/lua/paw/bytes.tl) | Invokes supplied callback: paw.bytes.unbase64 | teal |
| [extensions/interop/lua/interop/dawproject/export.tl](../../../../../../extensions/interop/lua/interop/dawproject/export.tl) | [runtime/lua/paw/zip.tl](../../../../../../runtime/lua/paw/zip.tl) | Invokes supplied callback: paw.zip.write | teal |
| [extensions/interop/lua/interop/dawproject/import.tl](../../../../../../extensions/interop/lua/interop/dawproject/import.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_add, paw.api.lane_points, paw.api.lane_set_shapes | teal |
| [extensions/interop/lua/interop/dawproject/import.tl](../../../../../../extensions/interop/lua/interop/dawproject/import.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_add, paw.api.clip_set | teal |
| [extensions/interop/lua/interop/dawproject/import.tl](../../../../../../extensions/interop/lua/interop/dawproject/import.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_add, paw.api.device_get, paw.api.device_set, paw.api.device_set_param | teal |
| [extensions/interop/lua/interop/dawproject/import.tl](../../../../../../extensions/interop/lua/interop/dawproject/import.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.tempo_from_seconds | teal |
| [extensions/interop/lua/interop/dawproject/import.tl](../../../../../../extensions/interop/lua/interop/dawproject/import.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_get, paw.api.project_new, paw.api.project_set | teal |
| [extensions/interop/lua/interop/dawproject/import.tl](../../../../../../extensions/interop/lua/interop/dawproject/import.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_add, paw.api.track_get, paw.api.track_set | teal |
| [extensions/interop/lua/interop/dawproject/import.tl](../../../../../../extensions/interop/lua/interop/dawproject/import.tl) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [extensions/interop/lua/interop/dawproject/import.tl](../../../../../../extensions/interop/lua/interop/dawproject/import.tl) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callbacks: paw.api.tempo_at, paw.api.tempo_beat, paw.api.tempo_seconds, paw.api.tempo_set_points | teal |
| [extensions/interop/lua/interop/dawproject/import.tl](../../../../../../extensions/interop/lua/interop/dawproject/import.tl) | [runtime/lua/paw/bytes.tl](../../../../../../runtime/lua/paw/bytes.tl) | Invokes supplied callback: paw.bytes.base64 | teal |
| [extensions/interop/lua/interop/dawproject/import.tl](../../../../../../extensions/interop/lua/interop/dawproject/import.tl) | [runtime/lua/paw/xml.tl](../../../../../../runtime/lua/paw/xml.tl) | Invokes supplied callback: paw.xml.encode | teal |
| [extensions/interop/lua/interop/dawproject/import.tl](../../../../../../extensions/interop/lua/interop/dawproject/import.tl) | [runtime/lua/paw/zip.tl](../../../../../../runtime/lua/paw/zip.tl) | Invokes supplied callback: paw.zip.read | teal |
| [extensions/interop/lua/interop/dawproject/vst3.tl](../../../../../../extensions/interop/lua/interop/dawproject/vst3.tl) | [runtime/lua/paw/bytes.tl](../../../../../../runtime/lua/paw/bytes.tl) | Invokes supplied callbacks: paw.bytes.le32, paw.bytes.u32, paw.bytes.vst3_join, paw.bytes.vst3_split | teal |
| [extensions/interop/lua/interop/dawproject/xmlio.tl](../../../../../../extensions/interop/lua/interop/dawproject/xmlio.tl) | [runtime/lua/paw/xml.tl](../../../../../../runtime/lua/paw/xml.tl) | Invokes supplied callbacks: paw.xml.decode, paw.xml.element, paw.xml.encode | teal |
| [extensions/interop/lua/interop/init.tl](../../../../../../extensions/interop/lua/interop/init.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_find | teal |
| [extensions/interop/lua/interop/init.tl](../../../../../../extensions/interop/lua/interop/init.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.tempo_from_seconds | teal |
| [extensions/interop/lua/interop/init.tl](../../../../../../extensions/interop/lua/interop/init.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_get, paw.api.project_set | teal |
| [extensions/interop/lua/interop/init.tl](../../../../../../extensions/interop/lua/interop/init.tl) | [runtime/lua/paw/bytes.tl](../../../../../../runtime/lua/paw/bytes.tl) | Invokes supplied callbacks: paw.bytes.vst3_join, paw.bytes.vst3_split | teal |
| [extensions/interop/lua/interop/init.tl](../../../../../../extensions/interop/lua/interop/init.tl) | [runtime/lua/paw/formats.tl](../../../../../../runtime/lua/paw/formats.tl) | Invokes supplied callback: paw.formats.register | teal |
| [extensions/interop/lua/interop/init.tl](../../../../../../extensions/interop/lua/interop/init.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
| [extensions/interop/lua/interop/rpp/export.tl](../../../../../../extensions/interop/lua/interop/rpp/export.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_list, paw.api.lane_points, paw.api.lane_shapes | teal |
| [extensions/interop/lua/interop/rpp/export.tl](../../../../../../extensions/interop/lua/interop/rpp/export.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_controls, paw.api.clip_list, paw.api.clip_notes, paw.api.cue_list | teal |
| [extensions/interop/lua/interop/rpp/export.tl](../../../../../../extensions/interop/lua/interop/rpp/export.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [extensions/interop/lua/interop/rpp/export.tl](../../../../../../extensions/interop/lua/interop/rpp/export.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [extensions/interop/lua/interop/rpp/export.tl](../../../../../../extensions/interop/lua/interop/rpp/export.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [extensions/interop/lua/interop/rpp/export.tl](../../../../../../extensions/interop/lua/interop/rpp/export.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [extensions/interop/lua/interop/rpp/export.tl](../../../../../../extensions/interop/lua/interop/rpp/export.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [extensions/interop/lua/interop/rpp/export.tl](../../../../../../extensions/interop/lua/interop/rpp/export.tl) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callbacks: paw.api.tempo_at, paw.api.tempo_points, paw.api.tempo_seconds | teal |
| [extensions/interop/lua/interop/rpp/fx.tl](../../../../../../extensions/interop/lua/interop/rpp/fx.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_add, paw.api.device_get, paw.api.device_set, paw.api.device_set_param, paw.api.device_state | teal |
| [extensions/interop/lua/interop/rpp/fx.tl](../../../../../../extensions/interop/lua/interop/rpp/fx.tl) | [runtime/lua/paw/bytes.tl](../../../../../../runtime/lua/paw/bytes.tl) | Invokes supplied callbacks: paw.bytes.base64, paw.bytes.le32, paw.bytes.u32, paw.bytes.unbase64, paw.bytes.vst3_join, paw.bytes.vst3_split | teal |
| [extensions/interop/lua/interop/rpp/import.tl](../../../../../../extensions/interop/lua/interop/rpp/import.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_add, paw.api.lane_points, paw.api.lane_set_shapes | teal |
| [extensions/interop/lua/interop/rpp/import.tl](../../../../../../extensions/interop/lua/interop/rpp/import.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_add, paw.api.clip_get, paw.api.clip_remove, paw.api.clip_set | teal |
| [extensions/interop/lua/interop/rpp/import.tl](../../../../../../extensions/interop/lua/interop/rpp/import.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_add, paw.api.device_get | teal |
| [extensions/interop/lua/interop/rpp/import.tl](../../../../../../extensions/interop/lua/interop/rpp/import.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.tempo_from_seconds | teal |
| [extensions/interop/lua/interop/rpp/import.tl](../../../../../../extensions/interop/lua/interop/rpp/import.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_new, paw.api.project_set | teal |
| [extensions/interop/lua/interop/rpp/import.tl](../../../../../../extensions/interop/lua/interop/rpp/import.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_add, paw.api.track_get, paw.api.track_set | teal |
| [extensions/interop/lua/interop/rpp/import.tl](../../../../../../extensions/interop/lua/interop/rpp/import.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_set | teal |
| [extensions/interop/lua/interop/rpp/import.tl](../../../../../../extensions/interop/lua/interop/rpp/import.tl) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callbacks: paw.api.tempo_at, paw.api.tempo_beat, paw.api.tempo_seconds, paw.api.tempo_set_points | teal |
| [extensions/interop/lua/interop/rpp/import.tl](../../../../../../extensions/interop/lua/interop/rpp/import.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.project | teal |
| [extensions/interop/lua/interop/rpp/midi.tl](../../../../../../extensions/interop/lua/interop/rpp/midi.tl) | [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | Invokes supplied callbacks: paw.midifile.encode, paw.midifile.parse, require("paw.midifile") | teal |
| [extensions/interop/manifest.lua](../../../../../../extensions/interop/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
