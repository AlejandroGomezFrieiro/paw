---
id: TASK-376
title: >-
  MCP: an extension declares safe commands with typed arguments, and paw-mcp
  shows them as tools without --allow-eval
status: To Do
assignee: []
created_date: '2026-11-24T15:28:00Z'
labels:
  - mcp
  - extensions
  - api
  - agent:builder
milestone: m-10
dependencies:
  - TASK-344
priority: medium
ordinal: 445000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-24. Today an agent reaches an extension's commands only through run_command or lua, which run arbitrary code and need --allow-eval. Goal: an extension declares commands in its manifest (or a paw.* registration) with a name, a description, typed arguments as a schema (the typed API's schema machinery, crates/paw-core/src/api_schema.rs), and the promise of one undo step with a message. paw-mcp lists these as tools (name prefixed by the extension, e.g. ext_<name>_<command>), checks the arguments against the schema before the call, and runs them through the kernel like the typed tools. :ext.unload removes the tools (tools/list_changed). Generic: no code for any one extension (AGENTS.md rule 5). This is a contract (the manifest field, the paw.* function, the MCP tool shape): it goes before the API lock; update the architecture docs. Keep the mcpscore gate (tools/mcpscore.sh).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An extension declares a command with typed arguments, and paw-mcp lists it as a tool with a JSON schema made from that declaration
- [ ] #2 A call with bad arguments is refused before the command runs, with a message that names the argument
- [ ] #3 The command runs as one undo step with a message, without --allow-eval
- [ ] #4 Unloading the extension removes its tools, and the server says the tool list changed
- [ ] #5 One example extension in the tree declares at least one command; docs name the manifest field and the MCP behaviour; mcpscore stays at or above its gate
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
