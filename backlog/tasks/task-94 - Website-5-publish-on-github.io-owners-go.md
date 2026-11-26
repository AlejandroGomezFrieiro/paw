---
id: TASK-94
title: 'Website 5: publish on github.io (owner''s go)'
status: Done
assignee:
  - '@pi'
created_date: '2026-11-22T10:12:00Z'
updated_date: '2026-11-26T20:57:00Z'
labels:
  - agent:worker
milestone: m-9
dependencies: []
references:
  - flake.nix
  - tools/website/build.sh
  - web/browserpod/test.sh
modified_files:
  - web/browserpod/default.nix
  - web/browserpod/Cargo.lock
  - web/browserpod/test.sh
  - web/browserpod/serve.py
  - web/browserpod/test-site.mjs
  - .github/workflows/pages.yml
  - web/browserpod/test-course.mjs
  - docs/how-to/preview-the-manual-as-a-website.md
  - docs/explanation/about-the-website.md
  - web/browserpod/README.md
priority: low
ordinal: 97000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A GitHub Actions workflow (or nix build + gh-pages) that builds the site from main and publishes it to the repository's GitHub Pages; cross-origin isolation headers via a service worker if the interactive demo needs SharedArrayBuffer (TASK-28's coi-sw). Prepare everything; the owner decides when to switch it on.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The complete live website builds and the project path passes the browser checks without server isolation headers.
- [x] #2 Only a manual run from main can publish the tested artifact to GitHub Pages.
- [x] #3 The owner can follow the preview guide and confirm that the public site works.
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Build the complete website with the BrowserPod demo, the course, the how-to examples and the recorded sessions.
2. Test the artifact under /custom_daw/ without server isolation headers, including search, terminal input and sound.
3. Add a Pages deployment from main with a manual first run. Keep deployment separate from pull request checks.
4. Review the branch, guide the owner through GitHub settings, and verify the public site after deployment.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The live build fails before compilation because the BrowserPod source lacks the Lua suite workspace member. Restore the build before deployment.

Refreshed the BrowserPod workspace inputs and lock. The complete site builds locally. Chromium passed all 17 site checks and 11 course checks under /custom_daw/ without isolation headers, including sound and every step of lesson 1. The public deployment and hosted run remain unverified.

GitHub now names the repository paw. The Pages test uses its repository name in Actions and defaults to /paw/ locally. All 28 browser checks also pass under /paw/.

Owner 2026-11-26: the public site on github.io works. AC 2: .github/workflows/pages.yml uploads the Pages artifact and runs the deploy job only when github.event_name is workflow_dispatch and github.ref is refs/heads/main; pull requests only verify. AC 3: the owner followed the guide and confirmed the public site.
<!-- SECTION:NOTES:END -->
