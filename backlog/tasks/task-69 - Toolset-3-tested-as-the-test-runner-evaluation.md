---
id: TASK-69
title: 'Toolset 3: tested as the test runner (evaluation)'
status: Done
assignee: []
created_date: '2026-11-22T05:45:00Z'
updated_date: '2026-11-22T06:42:00Z'
labels:
  - teal
  - lua
  - tooling
  - tests
milestone: m-8
dependencies: []
priority: medium
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Compare tested with paw's own runner (tests/suite.lua, tests/tools/suite.sh, T.keys real-key tests, guide tests, the extension tests.lua files): what it gives (reporting, filtering, parallelism, Teal tests), what paw's runner has that it lacks (the kernel, a terminal, real keys), and whether to adopt it fully, for pure-Lua unit tests only, or not at all.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision: do not adopt tested; nothing changed. Trial on utau msgpack/kana (pure modules) ran 4 tests in 0.02 s with good reports, filters, tags, TAP/JSON, luacov, Teal tests; but no parallelism (-n is a no-op) and none of what paw's runner is for (kernel, terminal, T.keys, rendering, plugins, guides). Only ~20 modules (6,500 lines) are pure and already covered via the suite. Revisit if pure Teal libraries appear; packaging recipe in backlog/docs/designs/teal-toolset.md. Branch worktree-agent-ae41aa43fc0af79f0 (no commit).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Not adopted: tested runs pure tests well but cannot drive the kernel, terminal and real keys; only ~20 pure modules, already covered. Recipe in backlog/docs/designs/teal-toolset.md.
<!-- SECTION:FINAL_SUMMARY:END -->
