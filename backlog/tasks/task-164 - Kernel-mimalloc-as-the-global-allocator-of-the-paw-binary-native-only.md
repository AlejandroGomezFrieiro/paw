---
id: TASK-164
title: 'Kernel: mimalloc as the global allocator of the paw binary (native only)'
status: Done
assignee: []
created_date: '2026-11-22T21:43:00Z'
updated_date: '2026-11-23T11:13:00Z'
labels: []
milestone: m-3
dependencies: []
priority: high
ordinal: 176000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-114 (2026-11-22). perf on help-index slices over 6 ms (release, glibc): 54% in glibc malloc (malloc_consolidate 21%, _int_free_chunk 17%, unlink_chunk 9%), from the Lua collector freeing many small blocks. With mimalloc 3.3.2 through LD_PRELOAD, slices over 5 ms fell from 7-19 to 2-3 and the longest from 9-16 ms to 6-7 ms (measured under external load). Likely also helps the 'job harmony' slices and TASK-163 (collector pauses after edits). Use the mimalloc crate behind cfg(not(target_family = "wasm")) or a native feature, so that BrowserPod and the web build keep the system allocator; check Windows (TASK-51). The audio thread allocates nothing, so the change is for the kernel thread and the workers. Tools: bench/profile/help.lua (alloc), drive.py LD_PRELOAD.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 paw (native) uses mimalloc; the web build and BrowserPod still build with the default allocator
- [x] #2 bench/RESULTS.md: help-index slices and the slow-key warnings of drive.py repeat on the bench project, glibc against mimalloc, with spread, measured under external load
- [x] #3 The no-allocation check of the audio thread (no_alloc tests) still passes
- [x] #4 nix build and nix flake check pass; the flake package needs no new system library
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a87cdaec58f5a54ab, commit 2e7374c3. paw-tui main.rs: #[global_allocator] mimalloc 0.1.52 (mimalloc 3.3.2, cc, no system lib) under cfg(not(any(target_family=wasm, target_vendor=browserpod))); the pod target is family unix, arch wasm64, so the vendor test is necessary. cargo tree: mimalloc on x86_64 linux and windows-msvc, absent for the pod and wasm32-unknown-unknown. mlua gives LuaJIT (GC64) the Rust global allocator, so Lua's collector uses mimalloc. web/browserpod/Cargo.lock regenerated (it was stale on main too). Bench: bench/profile/allocator.sh <paw glibc> <paw mimalloc> [pairs]; help.lua now gives over_5ms; compare.py counts callbacks over budget. AC2 (RESULTS.md numbers) and AC3/AC4 (no_alloc, nix build, flake check) wait for the orchestrator's build.

PO 2026-11-23 check of main: 2e7374c3 is on main (merge 3f7613ed). AC #1 met: paw-tui main.rs sets mimalloc as the global allocator, not for wasm or BrowserPod. Open: AC #2 (RESULTS.md, glibc against mimalloc with bench/profile/allocator.sh), AC #3 and #4 (no_alloc, nix build, flake check). They wait for the orchestrator's build. Set Done after that.

PO 2026-11-23 (after batch 14): mimalloc is on main since 3f7613ed, and batches 13 and 14 passed the full suite and the flake-equivalent checks with it; flake.nix and nix/ add no system library (the crate builds with cc). Left: AC 2 (run bench/profile/allocator.sh with a glibc build and a mimalloc build of main, write the numbers with spread in bench/RESULTS.md) and a record of nix flake check and the no_alloc tests for AC 3 and 4. This is about one hour of work for the agent or the orchestrator that has the build.

2026-11-23: bench in bench/RESULTS.md (2764a821): mimalloc better in each median; kernel ms of j 8.35 -> 7.52 with ranges apart; others overlap under load 18-29. no_alloc tests passed in the batch 16 check; nix flake check passed before the push of 2f970bba.
<!-- SECTION:NOTES:END -->
