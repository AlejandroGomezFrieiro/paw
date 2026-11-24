---
id: TASK-75
title: MIDI modifier stacks (design)
status: To Do
assignee: []
created_date: '2026-11-22T08:09:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - nondestructive
  - midi
  - design
milestone: m-5
dependencies: []
references:
  - architecture/decisions/0014-generic-modifier.md
  - architecture/decisions/0022-modifier-stack-ux.md
  - architecture/decisions/0025-render-with-provenance.md
  - backlog/docs/designs/architecture-plan.md
priority: high
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Blender-style non-destructive stack on each MIDI clip: transpose, quantize, humanize, arpeggiate, velocity curve, perform's articulations, the pencil's transforms. Each modifier can be toggled, reordered and applied; the clip's own notes never change until 'apply'. MIDI stays the truth: the stored notes are the source, the stack is a recipe (extend the media design's recipe/bake model to MIDI, backlog/docs/designs/media.md); a project opens and plays without the extension that defined a modifier (its last result kept as a bake). Questions: what the piano roll shows and edits (source vs result), undo, export, performance (cache by source + stack hash). Design first, owner approves.
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
PO 2026-11-23 (plan V2 bundles): Design approved by the owner (round 5, ADR 0022). This ticket is the parent of TASK-75.1 to 75.6 (bundles M1 to M6). midi-modifier-stacks.md is replaced by architecture-plan.md where they differ; the word is render, not apply (ADR 0025).
<!-- SECTION:NOTES:END -->
