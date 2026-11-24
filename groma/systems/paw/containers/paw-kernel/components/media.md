---
type: C4 Component
title: Media
status: stable
groma:
  id: media
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/media.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/media.tl](../../../../../../runtime/lua/paw/media.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_edit_add, paw.api.clip_edits, paw.api.clip_edits_clear, paw.api.clip_glue, paw.api.clip_normalize, paw.api.clip_reverse, paw.api.media_collect, paw.api.media_list, paw.api.media_missing, paw.api.media_relink, paw.api.media_search, paw.api.media_store | teal |
| [runtime/lua/paw/media.tl](../../../../../../runtime/lua/paw/media.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/media.tl](../../../../../../runtime/lua/paw/media.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.clip_collect, paw.api.project_get, paw.api.track_collect | teal |
| [runtime/lua/paw/media.tl](../../../../../../runtime/lua/paw/media.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.Context, paw.commands.Result, paw.commands.define, require("paw.commands") | teal |
| [runtime/lua/paw/media.tl](../../../../../../runtime/lua/paw/media.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.clip | teal |
| [runtime/lua/paw/media.tl](../../../../../../runtime/lua/paw/media.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/media.tl](../../../../../../runtime/lua/paw/media.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.chain_copied, paw.events.kernel.clip_copied, paw.events.kernel.track_copied, require("paw.events.kernel") | teal |
| [runtime/lua/paw/media.tl](../../../../../../runtime/lua/paw/media.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.changed, paw.options.define, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/media.tl](../../../../../../runtime/lua/paw/media.tl) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callbacks: paw.pick.file, paw.pick.open | teal |
| [runtime/lua/paw/media.tl](../../../../../../runtime/lua/paw/media.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.notify, paw.ui.page | teal |
