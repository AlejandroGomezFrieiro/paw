---
id: TASK-107
title: 'Docs: the Make music course as one page with a live paw'
status: Done
assignee: []
created_date: '2026-11-22T11:00:00Z'
updated_date: '2026-11-23T20:11:00Z'
labels:
  - docs
  - website
  - web
  - interactive
milestone: m-9
dependencies:
  - TASK-106
  - TASK-90
  - TASK-92
  - TASK-108
priority: medium
ordinal: 110000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-22: the small song tutorial (docs/tutorials/make-music and the tutor's course) becomes a single page with an embedded BrowserPod instance running paw (a customized image, TASK-108) next to the steps, so a reader works through it in the browser; the same page says how to do it locally (install, nix run). Steps stay testable (tests/guides*.lua); the page loads the pod only when the reader presses a button (CDN, privacy note, 'Powered by BrowserPod' credit). Depends on TASK-106 (split ESC), TASK-90/92 (site), TASK-108.
<!-- SECTION:DESCRIPTION:END -->

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
Branch worktree-agent-af409ea433257b7b0, commit 2a9405b9 on 0d19ed40. The tutor writes docs/tutorials/course/in-the-browser.md (docs.lua ported to docs.tl): every lesson on one page, Open lesson and Type it buttons, browser_lacks for a lesson (recording) or a step (utau). Shared component web/browserpod/site/paw-live.js (same bytes in the TASK-93/109 branch). Headless test web/browserpod/test.sh SITE OUT --course: 0 failed, all 16 lessons with buttons pass. Pod fixes: kernel recv_timeout polls in the pod (timers fire without a key), portable.lua table.new and bit, no MIDI warnings without MIDI, <A-x> in sendKeys, fuzz in the pod fileset. nix build .#website-live makes the site with the pod. Rust: paw-core, paw-engine (run their tests).

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): The branch also fixes TASK-300 (no MIDI warning in the pod build).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main (2a9405b9). The tutor writes docs/tutorials/course/in-the-browser.md with all lessons on one page and a live paw beside the steps (paw-live.js). Headless course test: 16 lessons pass. Also fixed TASK-300 (no MIDI warning in the pod).
<!-- SECTION:FINAL_SUMMARY:END -->
