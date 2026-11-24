---
type: C4 Component
title: Undofile
status: stable
groma:
  id: paw-undofile
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/undofile.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/undofile.tl](../../../../../../runtime/lua/paw/undofile.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/undofile.tl](../../../../../../runtime/lua/paw/undofile.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo_file_open, paw.api.undo_file_wait, paw.api.undo_file_write | teal |
| [runtime/lua/paw/undofile.tl](../../../../../../runtime/lua/paw/undofile.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.exit, paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/undofile.tl](../../../../../../runtime/lua/paw/undofile.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.project_loaded, paw.events.kernel.project_saved, require("paw.events.kernel") | teal |
| [runtime/lua/paw/undofile.tl](../../../../../../runtime/lua/paw/undofile.tl) | [runtime/lua/paw/loading.lua](../../../../../../runtime/lua/paw/loading.lua) | Invokes supplied callback: paw.loading.project_dir | teal |
| [runtime/lua/paw/undofile.tl](../../../../../../runtime/lua/paw/undofile.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/undofile.tl](../../../../../../runtime/lua/paw/undofile.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
