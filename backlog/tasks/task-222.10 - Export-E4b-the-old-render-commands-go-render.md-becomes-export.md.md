---
id: TASK-222.10
title: >-
  Export E4b+E7: the old render commands go (render.md becomes export.md); MIDI
  and project folders in the grammar (:export project replaces :nest.export and
  :scope.write <folder>)
status: Done
assignee: []
created_date: '2026-11-23T07:06:00Z'
updated_date: '2026-11-23T13:48:00Z'
labels:
  - export
  - render
  - docs
milestone: m-2
dependencies:
  - TASK-222.3
  - TASK-7.14
parent_task_id: TASK-222
priority: high
ordinal: 266000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/export.md (TASK-222), approved by the owner 2026-11-23 with all its recommendations: one command :export; stems = groups, tracks = one file per track; :export tracks taps post; mono (L+R)/2; channels stereo by default, auto in the stems and tracks presets; replace files freely in renders/, elsewhere after the plan or with !; tail 2 s; presets project > init.lua > built-in; :export project inside a subproject's scope replaces :nest.export; :utau.freeze moves onto :freeze later. No compatibility before a release: remove what overlaps. Read the design section of this part before you start.

This part: Removes :render, :render stems, :stems, :render.regions; :render.cancel/.tags become :export.*. Docs and guides change in the same commit. Size L.
This part (E4b, split by the PO on 2026-11-23 from E4): remove what :export (E4a, TASK-222.4) now does. :render, :render stems, :render stems tracks, :stems, :render.regions and <Space>rR go. :render.cancel and :render.tags become :export.cancel and :export.tags. docs/reference/render.md becomes export.md, and the how-to guides that use :render move to :export. Search README.md, docs/, the extension READMEs and doc/ pages, the tutor's lessons, bench/ and .claude/skills for :render, render stems, :stems, render.regions and <Space>rR (export.md section 10), and fix each sentence. The render dialog of the window (crates/paw-gui) reads modal.render: do not change it (paused), and write in the report what it needs later. Size M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The commands :render, :render stems, :stems and :render.regions and the key <Space>rR are gone; :export.cancel and :export.tags replace :render.cancel and :render.tags
- [ ] #2 The tests that used the old commands use :export, and the guide tests (tests/guides*.lua) pass
- [ ] #3 docs/reference/export.md replaces render.md; a search for the old names in README.md, docs/, extensions/, the tutor's lessons, bench/ and .claude/skills finds none, and the report lists the search; Vale reports 0 alerts
- [ ] #4 (TASK-222.7) Test: :export song.mid writes a type 1 Standard MIDI file with one track for each track of the range; :export clip riff.mid writes the clip at the cursor; each=track and each=clip write one file each
- [ ] #5 (TASK-222.7) Test: :export clip riff.midi2 writes the clip as the project keeps it
- [ ] #6 (TASK-222.7) Test: a word of sound on a MIDI target is refused by name (tap= is for sound; song.mid is MIDI)
- [ ] #7 (TASK-222.7) Test: :export project <folder>/ writes the scope of the window (the song, a view, a subproject) as a project folder; :nest.export and :scope.write <folder> are gone, and :scope.write keeps only its meaning of saving a view as a subproject
- [ ] #8 (TASK-222.7) subprojects.md, project-files.md and the export docs say it; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a8ce7c82dc7d139f3. Commits: 3a57c3b4 (merge of 222.2 into 222.3), ccfd0de2 (the ticket), d4d05757 (merge of main). :render, :render stems, :stems, :render.regions and <Space>rR are gone. :export.cancel and :export.tags take their place. :export writes MIDI files (.mid with clip, each=track and each=clip, and .midi2 as the clip is kept), and refuses a word of sound by name. :export project <folder>/ writes the song (new Rust API song_export in session/export.rs and api/tracks.rs), a subproject (nest_export) or a view (scope_export). :nest.export and :scope.write <folder> are gone. render.md is now export.md, and render-stems.md is now export-stems.md. After the build, regenerate apidoc and replace the SongExport cast in nest.tl with api.song_export. Until the build, these tests fail: nest.lua ':export project in the song', and media.lua 'a render takes a range...' and 'a mono render...' (channels enum of 222.2).

Landed on main in batch 17 (deb79a0f), with the merge fixes of 2026-11-23 (clock rounding, export leader domain, goldens, MCP render_stems).
<!-- SECTION:NOTES:END -->
