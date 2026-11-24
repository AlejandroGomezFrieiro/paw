---
type: C4 Component
title: Objects
status: stable
groma:
  id: objects
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/objects.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_add, paw.api.lane_add_point, paw.api.lane_add_state, paw.api.lane_get, paw.api.lane_list, paw.api.lane_points, paw.api.lane_remove, paw.api.lane_set, paw.api.lane_set_points, paw.api.lane_states, paw.api.lane_value_at | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_add, paw.api.clip_add_notes, paw.api.clip_controls, paw.api.clip_get, paw.api.clip_list, paw.api.clip_note_add, paw.api.clip_note_at, paw.api.clip_note_remove, paw.api.clip_note_set, paw.api.clip_notes, paw.api.clip_notes_edit, paw.api.clip_peaks, paw.api.clip_remove, paw.api.clip_set, paw.api.clip_set_controls, paw.api.clip_set_notes, paw.api.cue_list | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_add, paw.api.device_editor, paw.api.device_find, paw.api.device_get, paw.api.device_move, paw.api.device_remove, paw.api.device_restart, paw.api.device_set, paw.api.device_set_param, paw.api.device_state | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [crates/paw-core/src/api/midi.rs](../../../../../../crates/paw-core/src/api/midi.rs) | Invokes supplied callbacks: paw.api.midi_close_output, paw.api.midi_close_port, paw.api.midi_inject, paw.api.midi_inject_ump, paw.api.midi_inputs, paw.api.midi_open_output, paw.api.midi_open_port, paw.api.midi_outputs, paw.api.midi_select, paw.api.midi_send, paw.api.midi_ump | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_get, paw.api.project_load, paw.api.project_new, paw.api.project_save, paw.api.project_set | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_add, paw.api.track_get, paw.api.track_list, paw.api.track_meter, paw.api.track_move, paw.api.track_remove, paw.api.track_set | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callbacks: paw.api.note_off, paw.api.note_on, paw.api.transport_get, paw.api.transport_play, paw.api.transport_record, paw.api.transport_seek, paw.api.transport_stop | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callbacks: paw.api.tempo_at, paw.api.tempo_bar_length, paw.api.tempo_bar_of, paw.api.tempo_bar_start, paw.api.tempo_bbt, paw.api.tempo_beat, paw.api.tempo_lines, paw.api.tempo_points, paw.api.tempo_seconds, paw.api.tempo_signature | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands, paw.commands.get | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, require("paw.events") | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.defer | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.pitch, require("paw.music") | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | Invokes supplied callback: paw.routes.set_output | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope, paw.scope.nest, paw.scope.origin, paw.scope.own_time | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [runtime/lua/paw/stretch.lua](../../../../../../runtime/lua/paw/stretch.lua) | Invokes supplied callback: paw.stretch.markers | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.notify, paw.ui.poke | teal |
| [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.merge, require("paw.util") | teal |
