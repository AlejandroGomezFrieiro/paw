---
type: C4 Component
title: Hooks
status: stable
groma:
  id: hooks
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/hooks.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/hooks.tl](../../../../../../runtime/lua/paw/hooks.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/hooks.tl](../../../../../../runtime/lua/paw/hooks.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/hooks.tl](../../../../../../runtime/lua/paw/hooks.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo_checkpoint, paw.api.undo_current, paw.api.undo_discard, paw.api.undo_pending, paw.api.undo_tree | teal |
| [runtime/lua/paw/hooks.tl](../../../../../../runtime/lua/paw/hooks.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.listened, require("paw.events") | teal |
| [runtime/lua/paw/hooks.tl](../../../../../../runtime/lua/paw/hooks.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend.chosen_clips, paw.frontend.chosen_refs | teal |
| [runtime/lua/paw/hooks.tl](../../../../../../runtime/lua/paw/hooks.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.flush | teal |
| [runtime/lua/paw/hooks.tl](../../../../../../runtime/lua/paw/hooks.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.selection | teal |
| [runtime/lua/paw/hooks.tl](../../../../../../runtime/lua/paw/hooks.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.arrange, paw.ui.float, paw.ui.focused, paw.ui.notify | teal |
