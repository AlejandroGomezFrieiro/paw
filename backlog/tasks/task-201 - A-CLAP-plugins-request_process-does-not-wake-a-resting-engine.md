---
id: TASK-201
title: A CLAP plugin's request_process does not wake a resting engine
status: Done
assignee: []
created_date: '2026-11-23T03:16:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels: []
milestone: m-2
dependencies: []
priority: medium
ordinal: 213000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-197 (2026-11-23): while the transport is stopped and the engine rests (paw-engine/src/engine/rest.rs, after 8 quiet blocks), a CLAP plugin that calls request_process only sets its device's wake flag; the resting engine never checks it. TASK-197 fixed the same gap for a state load with Msg::Wake. Make the host's request_process (and request_callback where it needs a block) wake the engine, without a lock or allocation on the audio thread. Test with the stub CLAP plugin.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A stub plugin that calls request_process while the engine rests gets its next block (a test with the stub)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fix: paw-engine Waker (Arc<AtomicBool>, lock-free) taken at each callback start; EngineHandle::waker, Controller::set_waker given in paw-core put_in via SyncCtx::waker; replaces Msg::Wake (TASK-197). CLAP HostFlags::wake (request_process, state load, stopped) wakes the engine; request_restart now done in ClapController::idle via stopped(), failure reported by health(). Sandbox: helper relays its plugin's wakes in shm Header::wake (offset 1164, size unchanged), DAW controller idle takes it and wakes device+engine; its own wakes after load_state/call wake the engine. request_callback needs no block (idle). Stub: per-instance host in plugin_data, stub.restart, stub.activations. Tests: crates/paw-plugins/tests/stub_wake.rs (2), tests/plugin_state.lua 'a plugin that asks for a block while the engine rests gets its next block' (fails on e4bcd1e3 binary). Docs: docs/reference/engine.md. Gap left: LV2 UI writes and VST3 do not wake a resting engine. Branch worktree-agent-ac94e24220ab3db31, commit d92b3252 (on e4bcd1e3).

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
