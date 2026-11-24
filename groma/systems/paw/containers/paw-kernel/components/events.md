---
type: C4 Component
title: Events
status: stable
groma:
  id: events
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/events.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.log | teal |
| [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.try | teal |
| [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callback: paw.limit.named | teal |
