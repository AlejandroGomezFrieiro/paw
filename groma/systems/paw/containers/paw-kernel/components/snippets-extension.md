---
type: C4 Component
title: Snippets extension
status: stable
groma:
  id: snippets-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/snippets/lua/snippets/init.lua
    - scanner: teal
      file: extensions/snippets/manifest.lua
      symbol: snippets
    - scanner: teal
      file: extensions/snippets/snippets/harmony.lua
    - scanner: teal
      file: extensions/snippets/snippets/patterns.lua
    - scanner: teal
      file: extensions/snippets/snippets/voices.lua
      symbol: groups
  group: Bundled extensions
  technology: Lua
description: Supplies a first set of snippets for chords, parts and voices.
---

Has no init file. The loader reads its snippets/ folder into paw.snippet. The snippets write chords that lead to the next chord, parts from the chords that are already there, and voices for a selection.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/snippets/lua/snippets/init.lua](../../../../../../extensions/snippets/lua/snippets/init.lua) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callback: paw.harmony.tones | teal |
| [extensions/snippets/lua/snippets/init.lua](../../../../../../extensions/snippets/lua/snippets/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/snippets/manifest.lua](../../../../../../extensions/snippets/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
| [extensions/snippets/snippets/harmony.lua](../../../../../../extensions/snippets/snippets/harmony.lua) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony.degree_pitch, paw.harmony.tones | teal |
| [extensions/snippets/snippets/harmony.lua](../../../../../../extensions/snippets/snippets/harmony.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/snippets/snippets/patterns.lua](../../../../../../extensions/snippets/snippets/patterns.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/snippets/snippets/voices.lua](../../../../../../extensions/snippets/snippets/voices.lua) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callback: paw.harmony.step | teal |
