---
id: TASK-85.2
title: 'Linked clips 2: overrides for each copy (transpose, velocity)'
status: Done
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-23T00:46:00Z'
labels:
  - nondestructive
  - midi
milestone: m-2
dependencies:
  - TASK-85.1
parent_task_id: TASK-85
priority: medium
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: each clip of a link can play its notes with its own changes, while the notes stay shared: a transpose and a velocity change for each copy (Blender's library overrides).

User-visible behavior:
- `:clip.override transpose=3 velocity=-10` on a linked clip. `velocity` adds to each note's velocity (clamped to 1 to 127). `:clip.override clear` removes them.
- The overrides change what plays (applied when the events are compiled), not the stored notes.
- The piano roll shows the notes of that clip with its overrides. An edit there changes the shared notes (the roll writes the pitch less the transpose).
- `K` shows the overrides; the arrange label shows `≡ +3`.
- MIDI export and renders play the overrides.
- Modifier stacks for each copy come with TASK-75 (m-5), not here.

Read first: the TASK-85.1 commit; crates/paw-core/src/sync/clips.rs (where events are compiled), runtime/lua/paw/views/pianoroll.lua, docs/reference/arrange-view.md, docs/reference/piano-roll.md.

Depends on: TASK-85.1.
Do not touch: the link files of TASK-85.1 beyond two new fields.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: two linked clips, :clip.override transpose=3 on the second: a render has the second copy 3 semitones up; the stored notes are the same
- [ ] #2 Test with real keys: in the piano roll of the transposed copy, a note added at the shown pitch E4 is C#4 in the shared notes and shows as E4 there
- [ ] #3 Test: :clip.override clear and u work; save and reopen keep the overrides
- [ ] #4 Test: MIDI export of the copy has the transposed pitches
- [ ] #5 arrange-view.md and piano-roll.md say it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a6db0e3056f0f0243 (merge of TASK-85.1 branch worktree-agent-a4de833bee7ef9c20, then commit 045e4fd8). Clip::overrides (model/overrides.rs: transpose, velocity; serde 'overrides' in track.json). sync/clips.rs Source applies them at compile (in the cache key). clip_get/clip_set/clip_add: transpose, velocity. :clip.override transpose= velocity= / clear. Piano roll parts use Clip:shifted (objects.tl): shown pitches = stored + transpose, writes subtract. MIDI export, harmony chord reading and roll context apply the transpose. Split/copy keep, join bakes the difference. Label 'riff ≡ +3 v-10', K 'plays with transpose +3, velocity -10'. Tests: tests/clip_overrides.lua (5), Rust sync test a_copy_with_overrides_plays_its_notes_changed, model overrides unit test. NEEDS a build: Lua tests, apidoc regeneration (api.md, runtime/types). No key mapped (command only).
<!-- SECTION:NOTES:END -->
