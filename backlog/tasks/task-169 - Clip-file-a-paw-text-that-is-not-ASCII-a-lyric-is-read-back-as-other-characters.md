---
id: TASK-169
title: >-
  Clip file: a paw: text that is not ASCII (a lyric) is read back as other
  characters
status: Done
assignee: []
created_date: '2026-11-22T22:45:00Z'
updated_date: '2026-11-23T02:44:00Z'
labels:
  - tests
  - bug
dependencies: []
priority: high
ordinal: 181000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by reading clipfile.rs for TASK-156. Reader::flex_data pushed each byte of the Flex Data text as one char (b as char), so the UTF-8 of a note's meta (a lyric in Japanese, an ñ) came back as Latin-1 characters after a .midi2 save and load. Fixed on the TASK-156 branch (worktree-agent-a420e3f0b94bb7ce5): the reader keeps bytes and parses them with serde_json::from_slice. Regression test: clipfile::props::a_lyric_that_is_not_ascii_comes_back.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Orchestrator 2026-11-23: the fix and its regression test are on main (b48920a4, batch 7); the batch's Rust tests pass.
<!-- SECTION:NOTES:END -->
