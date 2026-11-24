---
id: TASK-181
title: 'Subproject with its own meter: <Space>zw inside it reads the song''s meter'
status: Done
assignee: []
created_date: '2026-11-23T00:04:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels: []
milestone: m-2
dependencies: []
priority: medium
ordinal: 193000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-178 (2026-11-23): nest.tl meter_over (the <Space>zw path inside a meter=own subproject) still reads the song's meter, not the subproject's own. Also left: the arrange view's tempo lane inside a scope shows the song's tempo, and frontend (paused window) sends the song's lines.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 <Space>zw inside a meter=own 6/8 subproject uses 6/8, by a test with real keys
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a5e4a508eb3b558cf (holds TASK-178 branch worktree-agent-a4d1fef7eb87b9328 merged in), commit 8b722cc8. nest.tl meter_over reads the window's map (paw.time.own():points() / paw.time.signature_at): <Space>zw inside a meter=own 6/8 subproject saves 6/8; message bars via paw.time.song_beat. Tempo lane: new paw.time.tempo_points (window's tempo points); arrange draw_tempo_row uses it and paw.time.tempo_at; paw.tempolane.range over them. Tests in tests/nest.lua (both fail on the old code). Docs: subprojects.md, arrange-view.md, api.md regenerated. Left: lane edits by mouse inside a scope still write the song's map at window beats; frontend.tl (paused window) still sends song tempo points and lines, with range now window's. tests/search.lua 'search: regions, help tags...' fails on the base too (not this ticket).
<!-- SECTION:NOTES:END -->
