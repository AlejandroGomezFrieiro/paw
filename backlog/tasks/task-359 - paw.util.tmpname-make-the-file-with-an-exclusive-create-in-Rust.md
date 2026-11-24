---
id: TASK-359
title: 'paw.util.tmpname: make the file with an exclusive create in Rust'
status: To Do
assignee: []
created_date: '2026-11-24T11:59:00Z'
updated_date: '2026-11-24T14:21:00Z'
labels:
  - agent:worker
  - rust
  - api
milestone: m-6
dependencies: []
priority: low
ordinal: 428000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-357 added paw.util.tmpname (runtime/lua/paw/util.tl) because os.tmpname always uses /tmp, which the agent sandbox cannot write. Lua's io.open has no exclusive create, so the helper checks and then creates the name (a race in a shared /tmp). Move it to the core: a paw.* function that uses std::env::temp_dir() (honors TMPDIR) and OpenOptions::create_new with a retry, returning the path or an error with the reason. Keep paw.util.tmpname as the Lua face. Contract: a new paw.* function (architecture skill; small, no ADR unless the reviewer asks).
<!-- SECTION:DESCRIPTION:END -->

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
