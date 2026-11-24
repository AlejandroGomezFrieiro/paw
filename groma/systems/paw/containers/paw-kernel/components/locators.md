---
type: C4 Component
title: Locators
status: stable
groma:
  id: locators
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/locators.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/locators.tl](../../../../../../runtime/lua/paw/locators.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_note_at | teal |
| [runtime/lua/paw/locators.tl](../../../../../../runtime/lua/paw/locators.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/locators.tl](../../../../../../runtime/lua/paw/locators.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/locators.tl](../../../../../../runtime/lua/paw/locators.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [runtime/lua/paw/locators.tl](../../../../../../runtime/lua/paw/locators.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.clip, paw.address.device, paw.address.find_note, paw.address.location, paw.address.note, paw.address.param, paw.address.parse, paw.address.track, paw.address.track_of | teal |
| [runtime/lua/paw/locators.tl](../../../../../../runtime/lua/paw/locators.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.clip, paw.cursor.set_beat, paw.cursor.set_track, paw.cursor.track_id | teal |
| [runtime/lua/paw/locators.tl](../../../../../../runtime/lua/paw/locators.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.clip | teal |
| [runtime/lua/paw/locators.tl](../../../../../../runtime/lua/paw/locators.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.locator, paw.ui.locators, paw.ui.views | teal |
