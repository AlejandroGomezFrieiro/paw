---
id: TASK-397
title: Run Linux checks and extended tests in GitHub Actions
status: In Progress
assignee:
  - '@pi'
created_date: '2026-11-25T19:11:00Z'
updated_date: '2026-11-25T19:58:00Z'
labels:
  - ci
dependencies: []
references:
  - flake.nix
  - tests/tools/suite.sh
  - .config/nextest.toml
modified_files:
  - tools/ci-lua.sh
  - .github/workflows/ci.yml
  - .github/workflows/extended-tests.yml
  - docs/how-to/run-the-tests.md
  - .claude/skills/paw-code/SKILL.md
  - tests/runner.lua
ordinal: 466000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Contributors need the same checks on GitHub as in a local checkout. Start with the Linux test tiers and keep cross-platform release work separate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pull requests and main pushes run the Nix flake checks and the full dev Lua suite without deployment permissions.
- [ ] #2 The nightly and manual workflow runs all four combinations of dev and release, serial and shuffled parallel. The run keeps the Lua reports and the seed.
- [x] #3 The test guide names the checks and explains how to read the reports and reproduce a shuffle.
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Use the flake and suite runner for the default checks.
2. Run the four Lua suite configurations nightly and on demand.
3. Check workflow syntax and document the commands and reports.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The workflows passed actionlint, and the shell and guide checks passed. GitHub has not run the workflows yet. Leave required checks off until the hosted baseline is known.

The local dev Lua suite reports failures in the ARA extension and plugin state checks in sampler and attr. Keep these checks active and do not require the workflow for merges until the baseline is green. No paw runtime or native test was modified by this work.

Local nextest result: 181 of 185 parts passed. Failed parts: ARA, sampler, attr, and scene_parity. The last three reported extra plugin state after the tests. No checks were skipped or given retries to hide these failures.

The first hosted Lua suite used indexed colors, a long Nix temporary path and dash as /bin/sh. The CI runner now pins truecolor and a short temporary root. The nested-suite test runs its process limit in Bash. Four representative tests passed through the updated CI runner with the original runner-like environment. The exact process-limit command also passed under dash.
<!-- SECTION:NOTES:END -->
