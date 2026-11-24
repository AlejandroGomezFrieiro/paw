---
id: TASK-10
title: 'Media design: parts M4-M12'
status: To Do
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-23T16:15:00Z'
labels:
  - media
milestone: m-5
dependencies: []
references:
  - architecture/decisions/0025-render-with-provenance.md
  - architecture/decisions/0029-outside-programs-in-bake-jobs.md
  - backlog/docs/designs/architecture-plan.md
priority: medium
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Non-destructive media (sources, recipes, plans, bakes) is built to M3 + E1. Remaining parts M4-M12 per the plan. Design: backlog/docs/designs/media.md.
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
Architecture review 2026-11-22 (backlog/docs/designs/architecture-review.md, E4): a WebAssembly baker is a natural third adapter of bake::Bake, for extension render ops that must run on the web.

DAW parity review 2026-11-23 (m-14): part M4 (stretch parts on a fixed cut grid, the part at the playhead first) also removes a parity gap: docs/reference/limits.md says that paw always makes a stretch from the start of its file, so a long clip is silent far into it until the stretch reaches that point. Other DAWs stretch from the playhead. No m-14 ticket was filed for it; when M4 is done, remove that line of limits.md. Source: backlog/docs/designs/daw-feature-comparison.md.

PO 2026-11-23 (plan V2 bundles): Parent of MD4 (TASK-10.1): the bake scheduler with provenance. M6 and M7 (media modifiers) use Modifier { kind, version, on, scope, params } of TASK-75.1. Outside programs are OP (TASK-319).
<!-- SECTION:NOTES:END -->
