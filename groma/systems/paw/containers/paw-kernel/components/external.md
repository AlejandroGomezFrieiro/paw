---
type: C4 Component
title: External
status: stable
groma:
  id: external
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/external.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/external.lua](../../../../../../runtime/lua/paw/external.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_changed_files, paw.api.project_get, paw.api.project_keep_changes, paw.api.project_reload | teal |
| [runtime/lua/paw/external.lua](../../../../../../runtime/lua/paw/external.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_label | teal |
| [runtime/lua/paw/external.lua](../../../../../../runtime/lua/paw/external.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/external.lua](../../../../../../runtime/lua/paw/external.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.on_next_key | teal |
| [runtime/lua/paw/external.lua](../../../../../../runtime/lua/paw/external.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: require("paw.options") | teal |
| [runtime/lua/paw/external.lua](../../../../../../runtime/lua/paw/external.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [runtime/lua/paw/external.lua](../../../../../../runtime/lua/paw/external.lua) | [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | Invokes supplied callback: require("paw.views.cmdline") | teal |
