---
type: C4 Component
title: Phrase completion extension
status: stable
groma:
  id: continue-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/continue/init.lua
    - scanner: teal
      file: extensions/continue/lua/continue.lua
    - scanner: teal
      file: extensions/continue/manifest.lua
      symbol: continue
  group: Bundled extensions
  technology: Lua
description: Suggests how the phrase before the cursor continues.
---

A small completion source for the piano roll and an example of a source for paw.complete. It reads only the notes and the key, so it is fast and gives the same suggestions each time.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/continue/init.lua](../../../../../../extensions/continue/init.lua) | [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | Invokes supplied callback: paw.complete.register | teal |
| [extensions/continue/init.lua](../../../../../../extensions/continue/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/continue/manifest.lua](../../../../../../extensions/continue/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
