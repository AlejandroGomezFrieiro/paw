---
id: TASK-93
title: 'Website 4: interactive paw in the page'
status: Done
assignee: []
created_date: '2026-11-22T10:12:00Z'
updated_date: '2026-11-23T20:11:00Z'
labels:
  - docs
  - website
  - web
  - interactive
milestone: m-9
dependencies:
  - TASK-106
  - TASK-108
priority: medium
ordinal: 96000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Let a visitor try paw without installing, from the landing page. Embed paw running in the browser (the customized BrowserPod image of TASK-108; later the wasm build of m-0) behind a 'Try paw' button, with a small demo project, sound through Web Audio if available (else silent with a note). Also cheaper interactive parts where a live paw does not help: recorded terminal sessions (asciinema-style casts from the docs/images/make scripts) that the reader can pause and copy keys from.

Not here: the Make music course with a live paw (TASK-107) and the how-to guides with a live paw (TASK-109).

Depends on: TASK-108 (the image), TASK-106 (split escape sequences, done).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The landing page has a 'Try paw' button that loads the pod only when pressed, with a 'Powered by BrowserPod' credit and a privacy note (CDN load)
- [x] #2 The demo project opens and plays in the page; with no Web Audio the page says that it is silent
- [x] #3 At least one recorded terminal session is on the landing page, made by a script in docs/images/make
- [x] #4 Vale reports 0 alerts on the changed pages
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
- [x] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [x] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [x] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [x] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [x] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [x] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [x] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a20379d5d735b81e5 (base 0d19ed40), commits 4aff99d4, 306df49d, 2c48274b, 781610e9. Landing page: 'Try paw' panel (shared web/browserpod/site/paw-live.js, the same file as TASK-107), 'Play or stop the song' button, credit and load note; silent note without Web Audio; recorded session docs/images/cast-basics.cast made by docs/images/make/cast-basics.sh + cast.py, played by tools/website/paw-cast.js. Test: web/browserpod/test.sh SITE OUT --site (test-site.mjs), 14/14 with and without isolation headers. Also fixed: paw-pod-bin fileset needs fuzz/; docs/README projdiff anchor.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main (2c48274b, 781610e9). The landing page has a Try paw panel that loads the pod on a press, the BrowserPod credit and a load note, a silent note without Web Audio, and the recorded session cast-basics.cast. web/browserpod/test.sh --site: 14/14. Follow-up: TASK-321 (the cast keys).
<!-- SECTION:FINAL_SUMMARY:END -->
