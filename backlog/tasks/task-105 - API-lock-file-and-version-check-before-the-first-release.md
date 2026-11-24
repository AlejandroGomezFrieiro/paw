---
id: TASK-105
title: 'API: lock file and version check before the first release'
status: To Do
assignee: []
created_date: '2026-11-22T10:39:00Z'
updated_date: '2026-11-24T14:22:00Z'
labels:
  - extensions
  - release
  - blocked-by-plan
  - agent:builder
milestone: m-10
dependencies:
  - TASK-132
priority: low
ordinal: 108000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: before the first tagged release, a lock file of the API makes each change of paw.api and the paw modules visible and ties it to API_VERSION. Finding E5 (F12) of the architecture review (backlog/docs/designs/architecture-review.md). Not before: the owner wants no compatibility before a release.

Today: API_VERSION is "1.0.0" (crates/paw-core/src/api/mod.rs:208) and did not change since commit b129ebce, while api/ had 15 commits in November 2026.

Change: tools/apidoc.lua writes api.lock (each function of paw.api and paw.* with its Teal type); the apidoc check fails when the lock changes and the version does not (removal or change: major; addition: minor). :help shows the version that added a function.

Read first: the review, E5; tools/apidoc.lua; docs/reference/extensions.md (Manifests and versions).
Size: S. Do it at the release check (TASK-42).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 apidoc writes api.lock; apidoc check fails when the lock and API_VERSION disagree
- [ ] #2 docs/reference/extensions.md says how the version moves
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
Board review 2026-11-23: moved from m-10 to m-6 (quality and release readiness). The ticket says: do it at the release check, not before (no compatibility before a release). In m-10 it kept the milestone open and so blocked TASK-206. It needs the @internal tag of TASK-132 first, so that the lock lists only the public API.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): Part of LOCK: the API lock comes after the V2 bundles, because paw.kinds, paw.chain, paw.parts, paw.lanes, paw.editor, paw.templates, paw.render and paw.bakes are new (architecture-plan.md V2.14). Unblocked by: the V2 bundles (LOCK last).

PO 2026-11-24: roadmap lists the API lock under LOCK. It must not start before all other bundles land. Close m-6 without it only if the owner moves it to m-10.
<!-- SECTION:NOTES:END -->
