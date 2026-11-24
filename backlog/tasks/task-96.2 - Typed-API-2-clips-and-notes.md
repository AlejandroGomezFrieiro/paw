---
id: TASK-96.2
title: >-
  Typed API 2: clips, notes, devices, lanes, transport and project, with their
  MCP schemas
status: Done
assignee: []
created_date: '2026-11-23T06:14:00Z'
updated_date: '2026-11-24T07:44:00Z'
labels:
  - architecture
  - api
milestone: m-10
dependencies:
  - TASK-96
parent_task_id: TASK-96
priority: medium
ordinal: 233000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-96 (one typed source for the shapes of paw.api). Read its description first, and backlog/docs/designs/architecture-review.md (F2, Owner decisions). .claude/skills/rust-skills and teal. Keep the error texts that Lua or a user sees, and nil for absent fields in Lua.

The same change as TASK-96.1 for the clip views and patches (session/clips.rs, api/clips.rs), and for notes and controls where they cross paw.api.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No json! and no serde_json::Value in the clip path of paw.api
- [ ] #2 The Teal records of clips are generated; apidoc check and tools/tlcheck.sh pass
- [ ] #3 An unknown key in a clip patch gives a clear error that names the key; a test covers it
- [ ] #4 The full Lua suite passes with no change of behavior
- [ ] #5 (TASK-96.3) No json! and no serde_json::Value in these paths of paw.api
- [ ] #6 (TASK-96.3) Their Teal records are generated; apidoc check and tools/tlcheck.sh pass
- [ ] #7 (TASK-96.3) An unknown key in each kind of patch gives a clear error that names the key; a test covers each
- [ ] #8 (TASK-96.3) The full Lua suite passes with no change of behavior
- [ ] #9 The paw-mcp schemas of these areas come from schemars (as TASK-96 does for tracks); the hand schemas of these areas are gone
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
Merged from TASK-96.3 (Typed API 3: devices, lanes, transport and project) by the PO on 2026-11-23.

Its description:
The same change as TASK-96.1 for the views and patches of devices, lanes, the transport and the project. Split it in two when an agent starts it, if it is more than a day.

Size: M to L.

PO 2026-11-23: Bundle: the same change as the track area for all other areas of paw.api. Also make their paw-mcp schemas with schemars (TASK-96.4 says: add each area when it is typed). Size L: split by area at the start if more than two days.

PO 2026-11-23 (after batch 14): the views and patches are now in crates/paw-core/src/session/document/ (clips.rs, notes.rs, devices.rs, automation.rs, project.rs), with thin wrappers on Session. Start after TASK-96 (the track pattern) merges.

PO 2026-11-23 (plan V2 bundles): Part of bundle T96 with its parent TASK-96: one agent does both.

Wave 23 (2026-11-24), base 9cecbfdc (batches 20-22 + W1).

Sweep add-on (2026-11-24, owner: fix sweep findings in the next batch): CORE-1 item 9 (MidiEventOpts.kind as an enum, error for an unknown type, api/midi.rs) and the constant serde default in crates/chain-syntax/src/schema.rs:298. Rules of TASK-342 apply.

Agent finished 2026-11-24 (90d4d067): clips + ParamSchema + typed clip patch + MidiType enum + chain schema v3 (sweep items done). ACs #5-#9 and TASK-96 #11 second half split into the follow-up tickets (typed API 3, paw-mcp schemars, Teal ParamSpec). Visible change: unknown clip key error is serde's 'unknown field , expected one of ...' (owner question). The 'ara: \an makes a MIDI clip' quarantine line can go (passed).

On local main (762ccf02, 2026-11-24, not pushed). Review: merge (0 hard, soft items on TASK-344). Checks: apidoc, hygiene, lints, clippy 0, nextest 676/676, suite words all passed.
<!-- SECTION:NOTES:END -->
