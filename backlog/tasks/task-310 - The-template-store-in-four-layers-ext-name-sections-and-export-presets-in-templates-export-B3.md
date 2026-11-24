---
id: TASK-310
title: >-
  The template store in four layers, ext/<name>/ sections, and export presets in
  templates/export/ (B3)
status: To Do
assignee: []
created_date: '2026-11-23T16:02:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-10
dependencies:
  - TASK-306
references:
  - architecture/decisions/0021-one-template-store.md
  - architecture/decisions/0020-template-contract-as-teal-record.md
  - architecture/decisions/0032-project-folder-of-parts-and-lanes.md
priority: medium
ordinal: 377000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle B3 of backlog/docs/designs/architecture-plan.md V2.6 and V2.11 (phase 3). One layout templates/<kind>/ in four layers: project, user ($XDG_DATA_HOME/paw/templates/), extension and bundled; the nearer layer wins; the picker shows the origin (ADR 0021). Extension files in ext/<name>/ of the project, kept byte for byte when the extension is absent. The export presets of TASK-222.5 move into the store as template kind export; project.toml [export.presets] goes (no compatibility before a release, ADR 0008).

This ticket has a title and a description only. The product owner adds the acceptance criteria when its phase starts, from backlog/docs/designs/architecture-plan.md and the ADRs in the references. One Opus agent does the bundle.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 (from TASK-222.5 AC 1) Test: a preset of the same name in the project, the user layer and built in: the project's wins, then the user's, then the built-in one; :export.preset lists each preset with its layer
- [ ] #2 (from TASK-222.5 AC 3) Test: :export.preset <name> saves the words of the last :export in the project layer (templates/export/); :export.preset! <name> replaces it; u undoes a save
- [ ] #3 A project with a section in ext/<name>/ of an absent extension saves the same bytes (round trip test)
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
PO 2026-11-23 (plan V2 bundles): AC 1 to 3 came from TASK-222.5 (its branch built the layers in project.toml and init.lua; this bundle moves them into the store). The product owner adds the rest of the criteria when phase 3 starts.
<!-- SECTION:NOTES:END -->
