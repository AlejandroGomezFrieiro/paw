---
type: C4 Component
title: Curve
status: stable
groma:
  id: curve
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/curve.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo_current, paw.api.undo_join, paw.api.undo_label | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.clip, paw.address.lane, paw.address.param, paw.address.tempo | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callback: paw.canvas.open_view | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.lane_id, paw.cursor.set_track | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | Invokes supplied callbacks: paw.curves.copy, paw.curves.depths, paw.curves.fit, paw.curves.generate, paw.curves.is_curve, paw.curves.quantize, paw.curves.rates, paw.curves.smooth, paw.curves.sorted, paw.curves.splice, paw.curves.target, paw.curves.thin, paw.curves.value_at, paw.curves.waves | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.beats, paw.draw.braille, paw.draw.curve_glyphs, paw.draw.g, paw.draw.sextant, paw.draw.trace, paw.draw.track_colour, paw.draw.track_hue | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.format_value | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.classic, paw.keymap.getreg, paw.keymap.human, paw.keymap.mode, paw.keymap.selection, paw.keymap.set_mode, paw.keymap.setreg, paw.keymap.visual | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | Invokes supplied callbacks: paw.lanes.name, paw.lanes.open | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.buf_create, paw.layout.buf_of, paw.layout.buftype, paw.layout.close, paw.layout.current, paw.layout.enter, paw.layout.get, paw.layout.leaf, paw.layout.show_in, paw.layout.split, paw.layout.windows | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callbacks: paw.mouse.beat, paw.mouse.grab, paw.mouse.has, paw.mouse.hint, paw.mouse.wheel | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.device, paw.objects.time, paw.objects.transport | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/params.lua](../../../../../../runtime/lua/paw/params.lua) | Invokes supplied callback: paw.params.step | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/plot.tl](../../../../../../runtime/lua/paw/plot.tl) | Invokes supplied callback: paw.plot.curve | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.keep | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | Invokes supplied callback: paw.tempolane.shown | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.ask_value, paw.ui.focused, paw.ui.keybar, paw.ui.menu, paw.ui.notify, paw.ui.titlebar, paw.ui.views | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit, paw.util.merge, paw.util.round | teal |
| [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | Invokes supplied callback: require("paw.views.pianoroll_strip") | teal |
