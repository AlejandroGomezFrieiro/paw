---
id: TASK-191
title: >-
  Surge XT snapshot test failed once in a full plugins run: 'an octave up: got
  0, want 1'
status: Done
assignee: []
created_date: '2026-11-23T01:26:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels: []
milestone: m-12
dependencies: []
priority: medium
ordinal: 203000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Batch 6 full run (2026-11-23): 'a plugin takes a snapshot back at rest, and the echo of its values is no edit (each format)' failed at tests/plugin_state.lua:114 (vst3:Surge XT: an octave up: got 0, want 1). It passed alone twice and with all plugin tests once. A flaky test is a bug in the test: find what it waits for (the plugin's echo of a parameter) and wait for that state, not for a block count.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The test waits for the state it checks
- [ ] #2 The cause is named in the notes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cause: a race in paw, not in the test. The CLAP and VST3 hosts read a plugin's values back after the first block that ended after a state load (reread). A block under way at the load began before the state came; Surge XT takes a state on only at the start of a block, so that block did not take it. The host read the old values (octave 0), cleared the reread, and never read again; holds() then returned in silence after 2 s and the eq failed (got 0, want 1). Fix: paw-plugins echo::Blocks counts blocks begun (before process) and done (after); a load marks the blocks begun, and the reread waits until a block after the mark is done (vst3.rs, clap.rs). Test: crates/paw-plugins/tests/stub_state.rs holds a stub block (new stub.hold, stub.quiet) and gives the state during it (fails on the old code by reasoning: not run, cargo test is for the orchestrator). tests/plugin_state.lua holds() waits with T.until_ (no silent deadline); timing-allowed api.wait 6->5. Branch worktree-agent-af789a4ae527f7b06, commit bbbe0774.

Ported onto batch 8 (f5adec5e, hosts split into clap/ and vst3/): merge commit 619a84fa. cargo check and clippy of paw-plugins --tests --examples clean.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
