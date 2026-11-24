---
type: C4 Component
title: Chords
status: stable
groma:
  id: chords
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/chords.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/chords.tl](../../../../../../runtime/lua/paw/chords.tl) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony.chord_name, paw.harmony.chord_roman, paw.harmony.parse_key, paw.harmony.read, paw.harmony.step | teal |
| [runtime/lua/paw/chords.tl](../../../../../../runtime/lua/paw/chords.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
