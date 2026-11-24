---
type: C4 Component
title: Collector
status: stable
groma:
  id: collector
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/collector.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/collector.tl](../../../../../../runtime/lua/paw/collector.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/collector.tl](../../../../../../runtime/lua/paw/collector.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/collector.tl](../../../../../../runtime/lua/paw/collector.tl) | [runtime/lua/paw/slices.tl](../../../../../../runtime/lua/paw/slices.tl) | Invokes supplied callbacks: paw.slices.job, paw.slices.run, require("paw.slices") | teal |
