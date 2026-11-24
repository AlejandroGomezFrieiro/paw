---
type: C4 Component
title: Pianoroll strip
status: stable
groma:
  id: views-pianoroll-strip
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/pianoroll_strip.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | [runtime/lua/paw/controls.lua](../../../../../../runtime/lua/paw/controls.lua) | Invokes supplied callbacks: paw.controls.chosen, paw.controls.fraction, paw.controls.is | teal |
| [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.g, paw.draw.track_colour, paw.draw.track_hue | teal |
| [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.act | teal |
| [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | [runtime/lua/paw/mouse_menus.tl](../../../../../../runtime/lua/paw/mouse_menus.tl) | Invokes supplied callbacks: paw.mouse_menus.strip, require("paw.mouse_menus") | teal |
| [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callbacks: paw.mouse.beat, paw.mouse.gesture, paw.mouse.grab, paw.mouse.has, paw.mouse.hint, require("paw.mouse") | teal |
| [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | [runtime/lua/paw/plot.tl](../../../../../../runtime/lua/paw/plot.tl) | Invokes supplied callback: paw.plot.curve | teal |
| [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.keep, require("paw.seats") | teal |
| [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callbacks: paw.theme.palette, require("paw.theme") | teal |
| [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.menu, paw.ui.views | teal |
| [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, require("paw.util") | teal |
