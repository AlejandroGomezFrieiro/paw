---
id: TASK-20
title: Clippy to zero (R13)
status: To Do
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-23T06:12:00Z'
labels:
  - rust
  - quality
milestone: m-6
dependencies: []
priority: low
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
32 clippy warnings left in the workspace (all old). Bring to zero per rust-skills.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 cargo clippy --workspace --all-targets reports 0 warnings
- [ ] #2 The clippy settings are in [workspace.lints] (with TASK-98, or added here if TASK-98 is not merged)
- [ ] #3 The five fn hex go: colors through paw_scene::color::Rgba FromStr, bytes through the hex crate; all tests pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Architecture review 2026-11-22 (backlog/docs/designs/architecture-review.md): TASK-98 adds [workspace.lints]: put the clippy settings there. Also: five fn hex (paw-gui theme.rs:66, paw-plugins vst3.rs:175, paw-proto lib.rs:60, paw-raster vector.rs:132, paw-scene cells.rs:272): colors through paw_scene::color::Rgba FromStr, bytes through the hex crate. Decide on lock().unwrap() (49 uses outside tests): recommended keep (poison = a panic elsewhere).

Owner, 2026-11-22: fold this ticket into TASK-98 when m-10 starts. Both change the workspace lints and clippy.

Board review 2026-11-23: folded into TASK-98 (owner, 2026-11-22: when m-10 starts, take in TASK-20 and archive it). m-10 started. TASK-98 has its criteria now.
<!-- SECTION:NOTES:END -->
