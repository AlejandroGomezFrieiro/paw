---
type: C4 Component
title: Autosave
status: stable
groma:
  id: autosave
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/autosave.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/autosave.lua](../../../../../../runtime/lua/paw/autosave.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [runtime/lua/paw/autosave.lua](../../../../../../runtime/lua/paw/autosave.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_backup, paw.api.project_get, paw.api.project_load, paw.api.project_recover | teal |
| [runtime/lua/paw/autosave.lua](../../../../../../runtime/lua/paw/autosave.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.read_dir | teal |
| [runtime/lua/paw/autosave.lua](../../../../../../runtime/lua/paw/autosave.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/autosave.lua](../../../../../../runtime/lua/paw/autosave.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.trial_active | teal |
| [runtime/lua/paw/autosave.lua](../../../../../../runtime/lua/paw/autosave.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [runtime/lua/paw/autosave.lua](../../../../../../runtime/lua/paw/autosave.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/autosave.lua](../../../../../../runtime/lua/paw/autosave.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.every, paw.import_audio, paw.try | teal |
| [runtime/lua/paw/autosave.lua](../../../../../../runtime/lua/paw/autosave.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.project, paw.objects.tracks | teal |
| [runtime/lua/paw/autosave.lua](../../../../../../runtime/lua/paw/autosave.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/autosave.lua](../../../../../../runtime/lua/paw/autosave.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [runtime/lua/paw/autosave.lua](../../../../../../runtime/lua/paw/autosave.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.notify, paw.ui.page | teal |
| [runtime/lua/paw/autosave.lua](../../../../../../runtime/lua/paw/autosave.lua) | [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | Invokes supplied callbacks: paw.views.files, paw.views.files.is_dir, paw.views.files.path | teal |
