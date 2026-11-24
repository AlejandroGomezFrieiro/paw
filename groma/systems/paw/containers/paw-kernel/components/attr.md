---
type: C4 Component
title: Attr
status: stable
groma:
  id: attr
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/attr.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/attr.tl](../../../../../../runtime/lua/paw/attr.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/attr.tl](../../../../../../runtime/lua/paw/attr.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_attr_delay | teal |
