---
id: TASK-234
title: 'Find the hits and the tempo of an audio clip: warp markers, slices and tempo'
status: To Do
assignee: []
created_date: '2026-11-23T07:13:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-L
  - media
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: medium
ordinal: 288000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician brings in a drum loop or a recorded take that was not played to a click. paw finds the hits (onsets) and the tempo, so that the clip follows the song tempo, or the song follows the clip, or the clip is cut into slices. Today each warp marker is put by hand.

**Other DAWs.** REAPER (transient detection, dynamic split, tempo detection), Qtractor (Rubber Band), Ableton and Bitwig (warp markers at transients). Design doc: gap 2 of section 4.1, matrix row "Warp by onsets, tempo detect".

**paw now (checked 2026-11-23).** docs/reference/limits.md: "paw does not find warp markers at onsets, so you put each marker by hand." Warp markers: `:clip.warp`, `gw`, `gW`, `:clip.warp snap` (docs/reference/stretch.md). Follow the tempo: `:clip.tempo`. paw-measure (crates/paw-measure) measures loudness, levels and spectrum, not onsets. The articulations extension has its own onset finder by level only (`:art.measure`).

**What to build.** The subtasks: a generic onset and tempo measurement, then commands on top of it.

**Core or extension.** The measurement is core, in paw-measure, as the loudness measurement is: more than one part uses it (stretch, slices, the articulations extension), and it must be fast (docs/explanation/about-core-and-extensions.md: "a fast measurement of loudness ... went into the core as an API function"). The commands extend the core command families of stretch.md (`:clip.warp`, `:clip.tempo`) and of the clip split, so they stay in the core with them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each subtask is done
- [ ] #2 docs/reference/stretch.md, a how-to guide (fit a drum loop to the song) and limits.md say it; Vale reports 0 alerts
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
