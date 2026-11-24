---
id: TASK-344
title: >-
  Typed API 3: patches and view schemas for devices, lanes, transport, project
  and parts
status: In Progress
assignee: []
created_date: '2026-11-24T06:30:00Z'
updated_date: '2026-11-24T15:22:00Z'
labels:
  - api
  - types
  - agent:builder
milestone: m-10
dependencies: []
priority: medium
ordinal: 413000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-96.2 (ACs #5 to #8): apply the Patch<T> + api_schema + generated types.tl region pattern of the clip path to devices, lanes, transport, project and parts. No serde_json::Value or json! on those paths except meta. Also generate the Control and Note records.
<!-- SECTION:DESCRIPTION:END -->

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
From the T96 review (2026-11-24, soft): (1) ClipPatch field keys live in 4 lists (struct, changes, ClipChange::key, is_playing) in session/document/clips.rs: one table (macro) instead; (2) values.rs Patch::value message 'it is not nil' → '`name` cannot be nil'; (3) chain-syntax param_schema.rs ParamError::Misplaced: name the parameter key, print the type without JSON quotes; (4) paw-core/Cargo.toml:23 comment names api/shapes.rs (file is src/api_schema.rs); (6) notes.rs NoteChange to Patch<T> with the notes area; (7) offset change with the same value on a nest clip now errors (edge); (8) meta stays serde_json::Map: free extension data by design.

Builder report 2026-11-24 (branch typed-api-3, 7ac2d7d1 + a3a7ac2d): done. Review items 1, 2, 3, 4, 6, 7 fixed; item 8: meta stays a Map. Setters read typed patches (macro patch!), getters give typed views (macro view!); 22 hand records of types.tl replaced by generated ones, with Note and Control. Left: device_types (type_json) still json!; chain.rs and nest_set still use de/holds; device_set makes an undo step on no change (old behavior).
<!-- SECTION:NOTES:END -->
