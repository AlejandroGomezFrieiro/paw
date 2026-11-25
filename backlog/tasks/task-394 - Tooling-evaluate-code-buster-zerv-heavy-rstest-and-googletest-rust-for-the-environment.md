---
id: TASK-394
title: >-
  Tooling: evaluate code-buster, zerv, heavy, rstest and googletest-rust for the
  environment
status: To Do
assignee: []
created_date: '2026-11-24T20:26:00Z'
updated_date: '2026-11-25T19:41:00Z'
labels:
  - tooling
  - agent:worker
dependencies: []
priority: low
ordinal: 463000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The owner proposed these tools for the environment of agents and tests (2026-11-24). Evaluate each tool. Adopt only a tool that gives a clear gain over the tools that paw has now.

Tools:
- code-buster: https://github.com/tool-bunker/code-buster
- zerv (versions from git): https://github.com/wislertt/zerv
- heavy: https://github.com/mokevnin/heavy
- rstest (fixtures and cases for Rust tests): https://github.com/la10736/rstest
- googletest-rust (matchers for Rust tests): https://github.com/google/googletest-rust

For each tool, find: what it does; what in paw it replaces or adds to (tools/, .githooks, merge-check, nextest, proptest, the skills rust-testing and paw-crates); the cost (build time, Nix packaging, a dependency of the workspace or a tool only); the licence; maintenance (last release, open issues).
rstest and googletest-rust: choose one or none. Compare them on 3 real tests of paw-core.
The result is a short report in the ticket, and one ticket for each tool to adopt.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each tool has a verdict (adopt, no, later) with a reason
- [ ] #2 rstest and googletest-rust are compared on 3 real tests of paw-core
- [ ] #3 A tool to adopt has its own ticket that names the files and skills it changes
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
zerv: adopt. It prints SemVer from Git tags and history, adds no Cargo workspace dependency, and does not publish. The Nix package and its checks are in TASK-398. Apache-2.0, upstream release 0.8.42 checked.
<!-- SECTION:NOTES:END -->
