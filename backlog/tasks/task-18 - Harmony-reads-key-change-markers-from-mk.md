---
id: TASK-18
title: Harmony reads key-change markers from mk
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-22T17:38:00Z'
labels:
  - harmony
  - insert-mode
milestone: m-4
dependencies: []
priority: medium
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: key changes that the user writes are the truth for the harmony reading. The pencil's `mk` writes markers named `key D minor`; today only the pencil reads them. paw.harmony, the ruler and the piano roll read them too.

Decision (no owner question needed): a key change is a marker whose name is `key <name of a key>` (as `mk` writes it). The key at a beat is, in this order: the last key marker at or before the beat; else the project's key (`project.key`, from the start); else the key read from the notes. A region with a `key` field (nest.md 3.9, owner decision Q27: a promoted subproject keeps its key there) is a key over its time, inside the markers' rule.

User-visible behavior:
- `paw.harmony.key(beat)` and `paw.harmony.keys()` give the marked keys. Chord names and numerals use them (Bb in F major).
- The piano roll's key at the left edge and the ruler show the marked key.
- `:key D minor at 17` adds a key marker at bar 17 (one undo step). `:key D minor` alone sets the project's key, as today.
- The pencil's chords use `paw.harmony.key` (its own scan of the markers goes away).
- A change of a key marker does not read the notes again: only the key map changes.

Read first:
- runtime/lua/paw/harmony.tl: `project_key` (near line 436), the reading's cache and its signature, `key_in`, `key` (near line 927), `keys` (near line 933).
- runtime/lua/paw/harmony/song.tl (the stamp of the reading).
- runtime/lua/paw/roll_draw.tl: `key_of_marker` and `key_here` (near line 855), the `k` mark (near line 902).
- runtime/lua/paw/markers.tl (`list`, `add`).
- docs/reference/harmony.md, docs/reference/markers.md, docs/explanation/about-the-harmony-reading.md.
- extensions/midilsp and extensions/notation: check if they read the key through paw.harmony; if not, list it in the commit message.

Depends on: nothing.
Do not touch: the nest code (scope.tl), roll_draw.tl outside the key functions.

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test (tests/harmony.lua): project key C major and a marker 'key D minor' at bar 9: paw.harmony.key at bar 10 is D minor, at bar 2 C major; keys() gives two spans
- [ ] #2 Test: no project key and a marker 'key G major' at the start: chord names use F#, not Gb
- [ ] #3 Test: moving the key marker changes key() and does not read the notes again (the song stamp does not change)
- [ ] #4 Test with real keys: :key D minor at 9 adds the marker in one undo step
- [ ] #5 Test: the pencil's chord at bar 10 is in D minor (the existing pencil test, changed to use the marker)
- [ ] #6 Test: a region with key = 'E minor' gives E minor inside it
- [ ] #7 harmony.md and markers.md document it; docs/reference/api.md is generated again; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-ad385106b14aa73c0 (committed, main merged in). harmony.tl: written key map (key markers + region key) from the markers, own signature part; key_in order marker, project key, reading; keys() merges them; paw.harmony.marked_key. markers.tl: key field. roll_draw key_here uses paw.harmony.key. musicops :key X at N. Tests in tests/harmony.lua, extensions/musicops/tests.lua. Docs: harmony.md, markers.md, musicops README, api.md.
<!-- SECTION:NOTES:END -->
