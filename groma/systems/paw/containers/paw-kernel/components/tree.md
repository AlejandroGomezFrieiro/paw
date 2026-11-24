---
type: C4 Component
title: Tree
status: stable
groma:
  id: tree
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/query/tree.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/query/tree.tl](../../../../../../runtime/lua/paw/query/tree.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_notes | teal |
| [runtime/lua/paw/query/tree.tl](../../../../../../runtime/lua/paw/query/tree.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/query/tree.tl](../../../../../../runtime/lua/paw/query/tree.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [runtime/lua/paw/query/tree.tl](../../../../../../runtime/lua/paw/query/tree.tl) | [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | Invokes supplied callbacks: paw.derived.node, require("paw.derived") | teal |
