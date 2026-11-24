---
type: C4 Component
title: Profile
status: stable
groma:
  id: profile
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/profile.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/profile.tl](../../../../../../runtime/lua/paw/profile.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/profile.tl](../../../../../../runtime/lua/paw/profile.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.real_ms | teal |
| [runtime/lua/paw/profile.tl](../../../../../../runtime/lua/paw/profile.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.scheme, require("paw.address") | teal |
| [runtime/lua/paw/profile.tl](../../../../../../runtime/lua/paw/profile.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.Context, paw.commands.Result, paw.commands.define, require("paw.commands") | teal |
| [runtime/lua/paw/profile.tl](../../../../../../runtime/lua/paw/profile.tl) | [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | Invokes supplied callbacks: paw.qf.open, paw.qf.set | teal |
| [runtime/lua/paw/profile.tl](../../../../../../runtime/lua/paw/profile.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
