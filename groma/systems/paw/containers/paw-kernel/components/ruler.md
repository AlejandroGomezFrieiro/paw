---
type: C4 Component
title: Ruler
status: stable
groma:
  id: ruler
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/ruler.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/ruler.tl](../../../../../../runtime/lua/paw/ruler.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/ruler.tl](../../../../../../runtime/lua/paw/ruler.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/ruler.tl](../../../../../../runtime/lua/paw/ruler.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.g | teal |
| [runtime/lua/paw/ruler.tl](../../../../../../runtime/lua/paw/ruler.tl) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callback: paw.ext.caller | teal |
| [runtime/lua/paw/ruler.tl](../../../../../../runtime/lua/paw/ruler.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/ruler.tl](../../../../../../runtime/lua/paw/ruler.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/ruler.tl](../../../../../../runtime/lua/paw/ruler.tl) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.new, require("paw.registry") | teal |
| [runtime/lua/paw/ruler.tl](../../../../../../runtime/lua/paw/ruler.tl) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope, paw.scope.bar_offset | teal |
| [runtime/lua/paw/ruler.tl](../../../../../../runtime/lua/paw/ruler.tl) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callback: paw.tempo.is_bar_line | teal |
