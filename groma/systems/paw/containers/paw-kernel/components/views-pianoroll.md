---
type: C4 Component
title: Pianoroll
status: stable
groma:
  id: views-pianoroll
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/pianoroll.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.log | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/attr.tl](../../../../../../runtime/lua/paw/attr.tl) | Invokes supplied callback: paw.attr.describe | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.beats, paw.draw.g, paw.draw.hue, paw.draw.jump_scroll, paw.draw.note_style, paw.draw.track_colour, paw.draw.track_hue | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.roll | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, require("paw.events") | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend.chosen_notes, paw.frontend.chosen_text | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony.at, paw.harmony.draw, paw.harmony.fresh, paw.harmony.key | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.jump_serial, paw.keymap.mode, paw.keymap.selection | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callback: paw.layout.clip_named | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.is_black, paw.music.name, require("paw.music") | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/plugins.lua](../../../../../../runtime/lua/paw/plugins.lua) | Invokes supplied callback: paw.plugins.key_names | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/roll_clips.tl](../../../../../../runtime/lua/paw/roll_clips.tl) | Invokes supplied callbacks: paw.roll_clips.context, paw.roll_clips.ids, paw.roll_clips.note_at, paw.roll_clips.notes, paw.roll_clips.only, paw.roll_clips.parts, paw.roll_clips.sounding, paw.roll_clips.span, paw.roll_clips.target, require("paw.roll_clips") | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | Invokes supplied callbacks: paw.roll_draw.bend_of, paw.roll_draw.controls_of, paw.roll_draw.hidden, paw.roll_draw.label, paw.roll_draw.status, paw.roll_draw.stepping | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | Invokes supplied callback: require("paw.statusline") | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callback: paw.tempo.is_bar_line | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.focused, paw.ui.notify, paw.ui.titlebar, paw.ui.view, paw.ui.views | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit, require("paw.util") | teal |
| [runtime/lua/paw/views/pianoroll.tl](../../../../../../runtime/lua/paw/views/pianoroll.tl) | [runtime/lua/paw/vzoom.tl](../../../../../../runtime/lua/paw/vzoom.tl) | Invokes supplied callback: paw.vzoom.key_rows | teal |
