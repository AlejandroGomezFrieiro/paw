---
type: C4 Component
title: Arrange
status: stable
groma:
  id: paw-roles-arrange
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/roles/arrange.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/roles/arrange.tl](../../../../../../runtime/lua/paw/roles/arrange.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/roles/arrange.tl](../../../../../../runtime/lua/paw/roles/arrange.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.str_width | teal |
| [runtime/lua/paw/roles/arrange.tl](../../../../../../runtime/lua/paw/roles/arrange.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.g, paw.draw.meter, paw.draw.meter_shown, paw.draw.stereo_meter, paw.draw.stereo_meter_shown | teal |
| [runtime/lua/paw/roles/arrange.tl](../../../../../../runtime/lua/paw/roles/arrange.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.fit | teal |
