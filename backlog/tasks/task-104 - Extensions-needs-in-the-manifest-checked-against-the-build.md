---
id: TASK-104
title: 'Extensions: needs in the manifest, checked against the build'
status: Done
assignee: []
created_date: '2026-11-22T10:39:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels:
  - extensions
  - platforms
  - web
milestone: m-10
dependencies:
  - TASK-99
priority: medium
ordinal: 107000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: a manifest says what an extension needs from the build (needs = { "ffi", "processes", "network", "native" }), and paw refuses to load it with a clear message when the build does not have it. Finding E3 (F11) of the architecture review (backlog/docs/designs/architecture-review.md).

Today: extensions get ffi, io.popen, os.execute and helper programs (crates/paw-core/src/kernel.rs, lines 362 to 366, Lua::unsafe_new). On the web (PUC Lua, no FFI, no processes) and on Windows some bundled extensions cannot work (backlog/docs/designs/web.md, LuaJIT-only features and owner question 5); paw finds out only when the code fails.

Change: paw.api.build() gives what the build has (the Lua VM, the cargo features of TASK-99); the loader compares it with needs; :extensions and :checkhealth extensions say why an extension did not load. Each bundled manifest gets its needs. The docs say that needs is not a security sandbox.

Read first: the review, E3; runtime/lua/paw/ext.lua (manifests); docs/reference/extensions.md (Manifests and versions); backlog/docs/designs/web.md; .claude/skills/paw-extension.
Owner decision (2026-11-22, review question 5): refusal with a clear message, not a warning.
Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 paw.api.build() lists the VM and the features of the build
- [ ] #2 An extension whose needs the build does not have does not load, and :extensions says why; a test covers it
- [ ] #3 Every bundled manifest declares its needs; docs/reference/extensions.md documents the field
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a7ed3ba9e5ffb9620, commits 41722360 and 77219585 (main c8d37454 merged, up to date). paw.api.build() (crates/paw-core/src/api/system.rs) gives { vm, features }. runtime/lua/paw/ext.lua refuses an extension whose manifest needs a feature that the build lacks, with a clear message in :extensions and :checkhealth extensions. paw.ext.build_has(feature) checks one feature. All 25 bundled manifests declare needs. Per the coordinator, notation has needs = {}: its filter ! with a shell command checks build_has('processes') and gives a clear message, and the named filters still work. docs/reference/extensions.md has a Needs column in the table of bundled extensions (a test compares it with the manifests), the needs field, the features and 'not a security sandbox'. Tests: tests/extensions_api.lua, extensions/notation/tests_grammar.lua. The orchestrator must build paw-core first: the old shared binary has no paw.api.build.
<!-- SECTION:NOTES:END -->
