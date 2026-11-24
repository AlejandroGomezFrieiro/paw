---
type: C4 Component
title: Preview
status: stable
groma:
  id: preview
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/pick/preview.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/pick/preview.tl](../../../../../../runtime/lua/paw/pick/preview.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_notes, paw.api.clip_peaks | teal |
| [runtime/lua/paw/pick/preview.tl](../../../../../../runtime/lua/paw/pick/preview.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/pick/preview.tl](../../../../../../runtime/lua/paw/pick/preview.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.hl_set, paw.api.ui_size | teal |
| [runtime/lua/paw/pick/preview.tl](../../../../../../runtime/lua/paw/pick/preview.tl) | [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | Invokes supplied callback: paw.audition.outline_lines | teal |
| [runtime/lua/paw/pick/preview.tl](../../../../../../runtime/lua/paw/pick/preview.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [runtime/lua/paw/pick/preview.tl](../../../../../../runtime/lua/paw/pick/preview.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/pick/preview.tl](../../../../../../runtime/lua/paw/pick/preview.tl) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callbacks: paw.theme.palette, require("paw.theme") | teal |
