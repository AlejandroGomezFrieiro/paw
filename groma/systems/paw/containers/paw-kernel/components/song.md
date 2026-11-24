---
type: C4 Component
title: Song
status: stable
groma:
  id: song
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/harmony/song.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/harmony/song.tl](../../../../../../runtime/lua/paw/harmony/song.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_notes | teal |
| [runtime/lua/paw/harmony/song.tl](../../../../../../runtime/lua/paw/harmony/song.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/harmony/song.tl](../../../../../../runtime/lua/paw/harmony/song.tl) | [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | Invokes supplied callbacks: paw.derived.node, paw.derived.run, paw.derived.stats, require("paw.derived") | teal |
| [runtime/lua/paw/harmony/song.tl](../../../../../../runtime/lua/paw/harmony/song.tl) | [runtime/lua/paw/harmony/read.tl](../../../../../../runtime/lua/paw/harmony/read.tl) | Invokes supplied callbacks: paw.harmony.read.Part, paw.harmony.read.Weights, paw.harmony.read.bar_part, paw.harmony.read.decode, paw.harmony.read.finish, paw.harmony.read.key_path, paw.harmony.read.merge, paw.harmony.read.part, paw.harmony.read.run, require("paw.harmony.read") | teal |
