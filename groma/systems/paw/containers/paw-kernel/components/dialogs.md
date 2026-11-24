---
type: C4 Component
title: Dialogs
status: stable
groma:
  id: dialogs
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/frontend/dialogs.tl
      symbol: layout_file
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/frontend/dialogs.tl](../../../../../../runtime/lua/paw/frontend/dialogs.tl) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callbacks: paw.api.engine_get, paw.api.render_formats | teal |
| [runtime/lua/paw/frontend/dialogs.tl](../../../../../../runtime/lua/paw/frontend/dialogs.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.json_decode, paw.api.json_encode | teal |
| [runtime/lua/paw/frontend/dialogs.tl](../../../../../../runtime/lua/paw/frontend/dialogs.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/frontend/dialogs.tl](../../../../../../runtime/lua/paw/frontend/dialogs.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/frontend/dialogs.tl](../../../../../../runtime/lua/paw/frontend/dialogs.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.env | teal |
| [runtime/lua/paw/frontend/dialogs.tl](../../../../../../runtime/lua/paw/frontend/dialogs.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/frontend/dialogs.tl](../../../../../../runtime/lua/paw/frontend/dialogs.tl) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [runtime/lua/paw/frontend/dialogs.tl](../../../../../../runtime/lua/paw/frontend/dialogs.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.completers, require("paw.commands") | teal |
| [runtime/lua/paw/frontend/dialogs.tl](../../../../../../runtime/lua/paw/frontend/dialogs.tl) | [runtime/lua/paw/frontend/core.tl](../../../../../../runtime/lua/paw/frontend/core.tl) | Invokes supplied callbacks: paw.frontend.core.layout_path, paw.frontend.core.render_dialog, paw.frontend.core.software_advice, require("paw.frontend.core") | teal |
| [runtime/lua/paw/frontend/dialogs.tl](../../../../../../runtime/lua/paw/frontend/dialogs.tl) | [runtime/lua/paw/frontend/host.tl](../../../../../../runtime/lua/paw/frontend/host.tl) | Invokes supplied callbacks: paw.frontend.host.paw, require("paw.frontend.host") | teal |
| [runtime/lua/paw/frontend/dialogs.tl](../../../../../../runtime/lua/paw/frontend/dialogs.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt, require("paw.options") | teal |
