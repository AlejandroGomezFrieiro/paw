---
id: TASK-196
title: 'api_boundary: the empty-path save test can write a project into the checkout'
status: Done
assignee: []
created_date: '2026-11-23T02:17:00Z'
updated_date: '2026-11-23T07:01:00Z'
labels: []
milestone: m-12
dependencies: []
priority: high
ordinal: 208000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seen by TASK-127 (2026-11-23): tests/api_boundary.lua:302 ('saving the project to an empty path is refused', TASK-157) calls project_save(''). On a binary without the refusal, the save went through and wrote .gitattributes, master/, project.toml, screen.json and tracks/ into the current folder (the checkout). A test must never be able to write outside its scratch folder, even when the code under test is wrong: run that call with the current folder in T.scratch, or check the refusal through a path that resolves inside T.scratch.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With the refusal removed, the test fails and writes nothing outside target/test-scratch
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fixed on branch worktree-agent-a1e19022337ba3fa7, commit 4e6b8664. The product already refuses the empty path (project_save, safe.rs). Open was the test only. tests/api_boundary.lua: pcall_in(dir, fn, ...) changes the current folder (chdir and PWD, LuaJIT FFI) to a folder under T.scratch for the call and puts it back. The empty-path save test and the whole paw.api walk (which also passes "" to each path argument) use it. The save test also checks that its folder stays empty. AC check: with project_save replaced by a fake that writes project.toml relative to the current folder, the test fails ('save to "" fails: got true') and the file is in the scratch folder, not in the checkout. Lua only, no Rust.

PO 2026-11-23 check of main: commit 4e6b8664 is on main (merge 406a8e71). tests/api_boundary.lua runs the empty-path calls in a folder under T.scratch with pcall_in. The agent proved AC #1 with a fake project_save. Met.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The empty-path save test and the paw.api walk run in a scratch folder. A wrong binary writes there, not into the checkout.
<!-- SECTION:FINAL_SUMMARY:END -->
