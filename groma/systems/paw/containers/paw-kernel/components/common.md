---
type: C4 Component
title: Common
status: stable
groma:
  id: common
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/defaults/common.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.clip, paw.cursor.track | teal |
| [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.project | teal |
| [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | Invokes supplied callback: paw.views.files.is_dir | teal |
