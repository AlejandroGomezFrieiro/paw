---
type: C4 Component
title: Tempo
status: stable
groma:
  id: tempo
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/tempo.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callbacks: paw.api.signature_remove, paw.api.signature_set, paw.api.tempo_at, paw.api.tempo_bar_of, paw.api.tempo_bar_start, paw.api.tempo_bbt, paw.api.tempo_beat, paw.api.tempo_from_bbt, paw.api.tempo_is_bar_line, paw.api.tempo_lines, paw.api.tempo_points, paw.api.tempo_remove, paw.api.tempo_seconds, paw.api.tempo_set, paw.api.tempo_set_points, paw.api.tempo_signature | teal |
| [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.beat | teal |
| [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.project, paw.objects.time | teal |
| [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope, paw.scope.bar_offset, paw.scope.nest | teal |
| [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | Invokes supplied callbacks: paw.tempolane.add, paw.tempolane.point_at, paw.tempolane.ramp, paw.tempolane.remove, paw.tempolane.signature_remove, paw.tempolane.signature_set | teal |
| [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
