---
type: C4 Component
title: Lang
status: stable
groma:
  id: lang
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/lang.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/lang.tl](../../../../../../runtime/lua/paw/lang.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.crc32 | teal |
| [runtime/lua/paw/lang.tl](../../../../../../runtime/lua/paw/lang.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/lang.tl](../../../../../../runtime/lua/paw/lang.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.runtime_file | teal |
| [runtime/lua/paw/lang.tl](../../../../../../runtime/lua/paw/lang.tl) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callbacks: paw.limit.unhurried, require("paw.limit") | teal |
| [runtime/lua/paw/lang.tl](../../../../../../runtime/lua/paw/lang.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
