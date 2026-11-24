---
id: TASK-370
title: >-
  A File System Access folder bridge for paw in the browser (demo and doc
  examples)
status: To Do
assignee: []
created_date: '2026-11-24T14:16:00Z'
updated_date: '2026-11-24T14:16:00Z'
labels:
  - web
  - research
  - agent:builder
milestone: m-0
dependencies:
  - TASK-367
priority: medium
ordinal: 439000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner goal 2026-11-24, independent of the unkernel choice. The browser demo and the doc examples must open a project folder on the user's disk with showDirectoryPicker (Chromium) and read and write it. Related to the unkernel spike, whose step 4 tests the same bridge into a 9p mount: this ticket sets the bridge as a part that works with BrowserPod (web/browserpod/) or with unkernel, and falls back to OPFS where the API is missing (Firefox, Safari). Needs a design: the guest side (mount or file calls), sync of changes back to the disk, permission prompts, and what the page says when the browser cannot do it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A short design in the notes: the guest interface, the sync rules, the permission flow, the fallback to OPFS, and which runtime it fits
- [ ] #2 A proof: open a project folder from disk in the demo page, change one note, and see the file on disk change (Chromium)
- [ ] #3 Firefox and Safari show a clear message and use OPFS
- [ ] #4 Docs: the web how-to says what the browser build can reach on the disk
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
