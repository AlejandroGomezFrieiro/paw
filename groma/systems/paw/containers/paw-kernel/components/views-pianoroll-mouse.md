---
type: C4 Component
title: Pianoroll mouse
status: stable
groma:
  id: views-pianoroll-mouse
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/pianoroll_mouse.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.exec | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.g, paw.draw.track_colour | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend.act, paw.frontend.chosen_notes, paw.frontend.chosen_refs | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [runtime/lua/paw/mouse_menus.tl](../../../../../../runtime/lua/paw/mouse_menus.tl) | Invokes supplied callbacks: paw.mouse_menus.note, paw.mouse_menus.roll, require("paw.mouse_menus") | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callbacks: paw.mouse.beat, paw.mouse.gesture, paw.mouse.grab, paw.mouse.has, paw.mouse.hint, paw.mouse.on_grid, paw.mouse.wheel, require("paw.mouse") | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.name, require("paw.music") | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [runtime/lua/paw/roll_clips.tl](../../../../../../runtime/lua/paw/roll_clips.tl) | Invokes supplied callbacks: paw.roll_clips.offset, paw.roll_clips.pick, paw.roll_clips.span | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | Invokes supplied callback: paw.roll_draw.click_step | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.menu, paw.ui.views | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, require("paw.util") | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [runtime/lua/paw/views/pianoroll_strip.tl](../../../../../../runtime/lua/paw/views/pianoroll_strip.tl) | Invokes supplied callbacks: paw.views.pianoroll_strip.press, paw.views.pianoroll_strip.shown, require("paw.views.pianoroll_strip") | teal |
| [runtime/lua/paw/views/pianoroll_mouse.tl](../../../../../../runtime/lua/paw/views/pianoroll_mouse.tl) | [runtime/lua/paw/vzoom.tl](../../../../../../runtime/lua/paw/vzoom.tl) | Invokes supplied callback: paw.vzoom.step | teal |
