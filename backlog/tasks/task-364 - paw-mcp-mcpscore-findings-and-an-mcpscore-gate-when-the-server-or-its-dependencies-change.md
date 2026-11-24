---
id: TASK-364
title: >-
  paw-mcp: mcpscore findings, and an mcpscore gate when the server or its
  dependencies change
status: Done
assignee: []
created_date: '2026-11-24T13:32:00Z'
updated_date: '2026-11-24T14:21:00Z'
labels:
  - tooling
  - mcp
  - agent:builder
milestone: m-6
dependencies: []
priority: high
ordinal: 433000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-24: run mcpscore (github.com/mcp-box/mcpscore, PyPI mcpscore 1.34.0) against paw-mcp, fix what it finds, and make it a routine check whenever paw-mcp or its dependencies change.
Baseline 2026-11-24 (main 3e1b74c1, debug build): 155/166, stdio, spec 2025-11-25 negotiated, 2026-07-28 readiness 33/33. Run in the sandbox with a scratch HOME/XDG_*/UV_CACHE_DIR under $TMPDIR: uvx mcpscore --json --stdio <paw-mcp> --spawn --paw <paw> --root <scratch> -- --audio null --clean --no-plugins. Failed rules:
- tools/list, resources/list, resources/templates/list return a page for an invalid cursor instead of JSON-RPC -32602 (spec bug: fix).
- 2 resources without a title; 2 resource templates without a title and a description (fix).
- capabilities.tools.listChanged / resources.listChanged not true (declare only if the server sends the notifications; else say why not).
- serverInfo websiteUrl and icons absent (optional: add websiteUrl; icons only if cheap).
Gate: a script (tools/mcpscore.sh or a flake app) that runs a PINNED mcpscore with --fail-under at the new score, sealed (scratch home, --audio null, private kernel). Prefer packaging mcpscore in the flake so nix flake check runs it offline; if the Python deps make that unreasonable, run pinned uvx from merge-check and the pre-push checks, and say why. It runs when the diff touches crates/paw-mcp, a crate that paw-mcp depends on (cargo metadata), or Cargo.lock. Document it in the paw-code skill part 7 and docs/how-to/run-the-tests.md, and paw-mcp's README if user-visible.
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
