---
type: C4 Component
title: Modal
status: stable
groma:
  id: modal
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/defaults/modal.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callback: paw.api.lane_list | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_list | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.quit | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.alias, paw.commands.run | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.clip | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | Invokes supplied callbacks: paw.defaults.common.overrides_text, require("paw.defaults.common") | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | Invokes supplied callback: paw.freeze.describe | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | Invokes supplied callback: paw.fx.preferred | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.changes, paw.keymap.delmarks, paw.keymap.marks, paw.keymap.push_jump, paw.keymap.registers, paw.keymap.search, paw.keymap.visual_start | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | Invokes supplied callback: paw.nest.describe | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | Invokes supplied callback: paw.track_kinds.describe | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [runtime/lua/paw/trackcolumn.tl](../../../../../../runtime/lua/paw/trackcolumn.tl) | Invokes supplied callback: paw.trackcolumn.describe | teal |
| [runtime/lua/paw/defaults/modal.lua](../../../../../../runtime/lua/paw/defaults/modal.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.input, paw.ui.notify, paw.ui.page, paw.ui.views | teal |
