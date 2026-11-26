---
id: TASK-398
title: Package zerv for local build versioning
status: Done
assignee:
  - '@pi'
created_date: '2026-11-25T19:40:00Z'
updated_date: '2026-11-26T20:57:00Z'
labels:
  - tooling
dependencies: []
references:
  - flake.nix
  - https://github.com/wislertt/zerv
modified_files:
  - nix/zerv.nix
  - flake.nix
  - docs/reference/nix-package.md
ordinal: 467000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Provide the same zerv on both Linux systems without a global install. The owner chose zerv to derive build versions from Git. A later change decides the first version tag and connects the release jobs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The Nix flake runs a pinned zerv on Linux.
- [x] #2 A disposable repository shows that a tagged commit and its review build get distinct SemVer versions.
- [x] #3 The setup creates no tag or release in paw.
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
1. Package the pinned upstream binaries with Nix.
2. Run the CLI against tagged and post-tag fixture commits.
3. List the tool in the Nix reference.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified zerv 0.8.42 on x86_64 Linux. The Nix wrapper finds Git without PATH. The aarch64 package evaluates and its upstream binary matches the pinned hash. A scratch repo returned 0.1.0 on the tag and an alpha version on a branch after it. On paw, flow requires a first reachable version tag. No tag, release, or CI change was made.

Orchestrator 2026-11-26: on main as 5b4f370c. nix run .#zerv -- --version prints zerv 0.8.42. docs/reference/nix-package.md lists .#zerv. The repository has no version tag (only pre-lanes and pre-parts), so the first tag and the release jobs stay for a later ticket.
<!-- SECTION:NOTES:END -->
