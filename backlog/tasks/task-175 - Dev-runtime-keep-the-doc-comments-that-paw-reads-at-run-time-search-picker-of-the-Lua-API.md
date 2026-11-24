---
id: TASK-175
title: >-
  Dev runtime: keep the doc comments that paw reads at run time (search picker
  of the Lua API)
status: Done
assignee: []
created_date: '2026-11-22T22:58:00Z'
updated_date: '2026-11-23T00:46:00Z'
labels: []
milestone: m-12
dependencies: []
priority: high
ordinal: 187000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-144 and TASK-83 (2026-11-23): 'search: regions, help tags, the Lua API...' (tests/search.lua:270) fails with tools/dev-runtime.sh and passes with the runtime in the binary. cyan gen drops the comments that doc_of reads from the module source; the build (crates/paw-core/build.rs) keeps them some other way, or doc_of reads the .tl in the binary. Every agent sees this failure. Fix it so the dev runtime gives the same result as the built runtime (for example: keep the .tl beside the generated .lua, as tools/apidoc.lua's lua_doc already falls back to, or make doc_of fall back the same way).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 suite.sh only search passes with the shared binary and PAW_RUNTIME from tools/dev-runtime.sh
- [ ] #2 The built runtime is unchanged
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
dev-runtime.sh keeps each .tl beside its generated .lua; doc_of (runtime/lua/paw/pick/project.tl) reads the .tl beside a .lua when it exists (Teal's Lua keeps the lines). Built runtime unchanged: it names the .tl as the chunk source, so the new branch never runs there; no Rust change. suite.sh only search with shared bin 6c3286a3 + dev runtime: 1 failed before, all passed after. Branch worktree-agent-a6073453d83ea5de1, commit 5596dfcf.
<!-- SECTION:NOTES:END -->
