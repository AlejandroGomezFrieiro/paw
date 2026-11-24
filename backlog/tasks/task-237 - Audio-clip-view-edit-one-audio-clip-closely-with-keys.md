---
id: TASK-237
title: 'Audio clip view: edit one audio clip closely, with keys'
status: To Do
assignee: []
created_date: '2026-11-23T07:13:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-L
  - media
  - views
  - blocked-by-plan
milestone: m-14
dependencies:
  - TASK-313
  - TASK-177
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: medium
ordinal: 295000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician edits one audio clip closely: zooms into the waveform, puts the cursor on a sample-exact point, trims, fades, sets gain on a part, splits at a hit, and moves warp markers. In the arrange view the clip is a few rows high and shares the screen with the other tracks.

**Other DAWs.** Qtractor 1.7.0 added an audio clip editor; Audacity is a full audio editor; REAPER opens an item in a media editor (design doc, section 4.4 "Audio clip editor window", proposed ticket "Audio clip view").

**paw now (checked 2026-11-23).** runtime/lua/paw/frontend/act/clips.tl `A.open_clip`: "an audio clip has none to open". Extensions can add an opener (`paw.frontend.openers`). The arrange view has clip keys for fades (`\fi`, `\fo`, `\fx`), warp markers (`gw`, `gW`) and gain (`:clip.gain`), and draws the waveform in cells (docs/reference/arrange-view.md, media.md). Pictures in the terminal (docs/reference/pictures.md) can draw a waveform as pixels.

**What to build.** The subtasks: a view of one audio clip, warp markers in it, then a spectrogram mode.

**Core or extension.** Core. Audio clips are built-in content, as MIDI clips are, and the piano roll is the core view for MIDI clips. A view for the other built-in content belongs with it, and one view serves both frontends through scenes (AGENTS.md rule 2).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each subtask is done
- [ ] #2 docs/reference has a page for the view, keys.md lists its keys, and the tutor test of keys passes; Vale reports 0 alerts
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Each acceptance criterion is met, and the notes give its evidence
- [ ] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [ ] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [ ] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [ ] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [ ] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [ ] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [ ] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): The audio clip view is an editor of the clip kind audio (paw.editor.define, bundle B7) and draws the built-in kind through the API (bundle B6). architecture-plan.md V2.10 m-14. ADR 0018. Unblocked by: B6 and B7.
<!-- SECTION:NOTES:END -->
