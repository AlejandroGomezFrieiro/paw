---
id: TASK-85.1
title: 'Linked clips 1: duplicate a clip as linked, and unlink'
status: Done
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-23T00:46:00Z'
labels:
  - nondestructive
  - midi
milestone: m-2
dependencies:
  - TASK-7.2
parent_task_id: TASK-85
priority: medium
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: the user duplicates a MIDI clip as a linked copy: an edit of the notes of one changes all of them. `:clip.unlink` makes a clip a plain copy again. (Blender's linked data.)

Decisions (no owner question needed):
- A link is a name. Each clip of a link has `link = "riff"` in its entry in track.json, and the notes and controls of the link are in one file, `linked/riff.midi2`, in the project folder. In memory, the clips of a link share their notes (`Arc`), and each note edit of one clip of a link changes all of them in the same undo step. `Project::validate` checks that the clips of a link have the same notes.
- Keys: `<Space>cl` (`:clip.link`) puts a linked copy after the clip, as `&` puts a plain copy. `<Space>cu` (`:clip.unlink`) makes the clip under the cursor a plain copy. `y` and `p` copy plain clips, as today.
- The arrange view marks a linked clip (`≡` after its name); `K` says `linked: riff, 3 clips`.
- MIDI stays the truth: the notes are MIDI notes in a .midi2 file, and a project opens and plays as usual.
- Not here: overrides for each copy (TASK-85.2), modifier stacks (TASK-75 in m-5), nest links (TASK-7, S10: a nest's blocks link by the nest's id, which is another mechanism).

Read first: backlog/docs/designs/nest.md section 8 (copies share compiled events) and 4.5 (links of nest blocks, for the same words). crates/paw-core/src/model.rs (`Clip`, `ClipContent` near line 622), crates/paw-core/src/model/notes.rs, crates/paw-core/src/session/notes.rs and session/clipops.rs (note edits), crates/paw-core/src/session/folder.rs (`clip_entry` near line 194), runtime/lua/paw/defaults/clips.lua (`clip.duplicate` near line 383), runtime/lua/paw/defaults/keys.lua (`&` near line 374), runtime/lua/paw/views/arrange.lua (the clip label near line 544), docs/reference/project-files.md, docs/reference/arrange-view.md.

Depends on: TASK-7.2 (S2a: copies share compiled events, so one edit compiles one time).
Do not touch: the nest model (TASK-7.x).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: <Space>cl puts a linked copy after the clip (one undo step); a note added in the copy in the piano roll is in the original too; u removes it from both
- [ ] #2 Test: :w writes one linked/riff.midi2 and two clip entries with link = riff; after a reopen both clips are still linked
- [ ] #3 Test: <Space>cu makes the clip a plain copy; a later edit of it does not change the other
- [ ] #4 Test: K on a linked clip gives the link and the count; the arrange label has ≡
- [ ] #5 Rust test: an edit of a link of 10 clips compiles its events one time
- [ ] #6 project-files.md, arrange-view.md and keys.md say it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a4de833bee7ef9c20 (commits 89e59fbe, 562271d8). Clip::link names a link; linked clips share Notes runs; Session::edit spreads a changed clip's notes to its link in the same edit (model/links.rs Links::before/spread). paw.api.clip_link/clip_unlink, clip_get link/link_count. Folder: linked/<link>.midi2, entries keep link; read shares notes per file; JSON load joins links; validate refuses differing links. Keys <leader>cl/<leader>cu, label 'riff ≡', K 'linked: riff, N clips', S unlinks before split. Tests: tests/linked_clips.lua, sync test an_edit_of_a_link_of_ten_clips_compiles_once, model links validation test. NEEDS a build: the Lua tests and apidoc regeneration (api.md, runtime/types) need the new Rust API.

2026-11-23 fixes after the merge run: commits f94a6eeb (links test fixture from Project::default and Track::new, not project JSON) and 9c53ecea (tests/linked_clips.lua compares strings; T.eq is shallow). With bin-851 and a runtime of main+125+6.5+116+7.11 (ec731773) + this branch: linked tests 5/5, 'folder' 32 ok, 'clip' 215 ok. No Rust behavior change: no new binary needed except to run the fixed Rust test.
<!-- SECTION:NOTES:END -->
