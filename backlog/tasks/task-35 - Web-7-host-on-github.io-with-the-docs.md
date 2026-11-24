---
id: TASK-35
title: 'Web 7: host on github.io with the docs'
status: To Do
assignee: []
created_date: '2026-11-21T19:32:00Z'
updated_date: '2026-11-23T16:15:00Z'
labels:
  - web
  - wasm
  - release
milestone: m-0
dependencies:
  - TASK-94
  - TASK-29
  - TASK-30
  - TASK-31
  - TASK-32
  - TASK-33
priority: low
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A GitHub Pages build (workflow) that publishes the docs and the web app together, with a 'Try paw in your browser' link from README and docs. GitHub Pages cannot set COOP/COEP headers: use a service worker (coi-serviceworker style) for cross-origin isolation. Offline after the first load (service worker cache). The owner decides when to publish.

The docs site goes live first through TASK-94 (its workflow). This ticket adds the web app to the same site.

Depends on: TASK-94 (the docs site workflow), TASK-29 to TASK-33 (the browser build of m-0).

## Part of TASK-110: Host the full web app (emscripten build)

Owner 2026-11-22: host paw's full browser build (the emscripten path of m-0, offline-capable, no third-party runtime) somewhere public so people can use paw in the web: e.g. the repository's GitHub Pages under /app with the coi service worker, a service-worker cache for offline use, projects in OPFS. Depends on m-0 (TASK-29..33). Publishing is the owner's go.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The site build puts the web app under /app next to the docs; the docs and the README link 'Try paw in your browser'
- [ ] #2 A service worker gives cross-origin isolation (SharedArrayBuffer works on GitHub Pages) and keeps the app for offline use after the first load
- [ ] #3 (110) The app is the emscripten build with no third-party runtime; projects stay in OPFS on the user's machine
- [ ] #4 Nothing is published until the owner says so
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
Prior art: openDAW (opendaw.org, github.com/andremichelle/openDAW) is a browser DAW hosted statically; study its hosting, cross-origin isolation, offline and storage choices (TASK-28 web.md has a section).

Product owner review 2026-11-22: TASK-110 merged into this ticket (same goal: host the browser build on github.io with a coi service worker and offline cache).
<!-- SECTION:NOTES:END -->
