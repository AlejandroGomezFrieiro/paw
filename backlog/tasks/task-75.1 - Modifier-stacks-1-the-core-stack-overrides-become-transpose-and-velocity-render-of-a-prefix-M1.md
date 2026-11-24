---
id: TASK-75.1
title: >-
  Modifier stacks 1: the core stack, overrides become transpose and velocity,
  render of a prefix (M1)
status: Done
assignee: []
created_date: '2026-11-23T16:01:00Z'
updated_date: '2026-11-24T10:19:00Z'
labels:
  - nondestructive
  - midi
  - bundle
  - agent:builder
milestone: m-5
dependencies:
  - TASK-301
references:
  - architecture/decisions/0014-generic-modifier.md
  - architecture/decisions/0022-modifier-stack-ux.md
  - architecture/decisions/0025-render-with-provenance.md
  - backlog/docs/designs/architecture-plan.md
  - backlog/docs/designs/midi-modifier-stacks.md
parent_task_id: TASK-75
priority: high
ordinal: 366000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle M1 of the architecture plan, version 2 (backlog/docs/designs/architecture-plan.md V2.15; section 6.3 gives the base criteria). Child of TASK-75.

One Stack type on a clip (a lane stack comes with LA and M4). Pure Rust: no Lua kind yet (that is TASK-75.3). The word is "render", not "apply" (ADR 0025): render takes only a prefix of the stack, never one entry in the middle (ADR 0022).

Before LA, render writes the notes into the clip and keeps the recipe in the undo step only. When LA is on main, render makes a new source take with provenance: LA adds this.

Read first: the skill .claude/skills/architecture (after batch 19 it is on main), architecture/08-concepts.md and 13-roadmap.md, the ADRs in the references, and backlog/docs/designs/architecture-plan.md (the sections that this ticket names). An Opus agent does the whole bundle in one branch, with its tests and docs in the same commits. Also backlog/docs/designs/midi-modifier-stacks.md 3.3, 3.4, 4.3, 4.4, 4.7, 4.8 and 6.3 (version 2 replaces it where they differ), and rust-architecture.md 4.2 to 4.4.

Size: L. It needs the kinds core of A1.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Modifier { kind, version, on, scope, params }, enum Builtin (transpose, velocity), ModImpl, ChainKey (128-bit BLAKE3), evaluate and ModError (thiserror) are in model/modifiers.rs; the ModifierFamily built-ins have the owner paw.modifiers
- [ ] #2 Clip.overrides is gone; a clip has a Stack. The loader folds an old overrides field into two entries and does not write it. tests/clip_overrides.lua and the sync test of copies pass with no change of keys
- [ ] #3 The sync keys compiled events by the last ChainKey; copies with the same notes and the same stack compile one time (a count)
- [ ] #4 A change of entry 3 runs entries 3 to the end only (a count)
- [ ] #5 :clip.stack add|set|on|off|move|rm, :clip.render [n] and :clip.render! [n] work, each one undo step with its message. A render of an entry that is not in a prefix, and a render on a linked clip, are refused with a clear message
- [ ] #6 :clip.override sets the transpose and velocity entries
- [ ] #7 paw.api.clip_get gives modifiers; Clip:shifted keeps its name
- [ ] #8 The clip file writes modifiers with sorted keys; a change of one parameter is one line in git diff
- [ ] #9 A bench scenario stacks in bench/edit.lua; no time in a test
- [ ] #10 Docs: the project files reference, the arrange view and the piano roll references (the parts on overrides) are true; Vale reports 0 alerts
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Wave 23 (2026-11-24), base 9cecbfdc (batches 20-22 + W1).

Sweep add-on (2026-11-24): CORE-1 items 1-6 inside model.rs and model/overrides.rs (constant serde helpers → struct #[serde(default)] + one impl Default, newtypes where the reports say, shared is_default), CORE-0 item 3-4 (move sync::repeats into model, played_notes returns impl Iterator; you touch sync/clips.rs), and CORE-2 pattern 1 (lookup then unwrap → part_in/clip_in with ?) in the session files you already change. Saved bytes must not change.

Agent finished 2026-11-24 (231d1340, 0092f0fc on 9cecbfdc); rebasing onto 433ab0ee (T96 typed clip patch). AC1-AC10 evidence in its report. Follow-ups: M3 clears the Results cache when kinds change; local per-run memo (M2); ExternJob runs not wired; :clip.stack cannot set a scope (API only). Sweep: CORE-1 items 1-6 done in attr_map.rs, model/chain.rs, model/custom.rs, model.rs, overrides.rs; CORE-0 3-4 done; CORE-2 item 1 (part_in, clip_in, device_in). A custom clip with version 0 is now refused at read.

Review 2026-11-24 (M1): merge after H1 (i64::MIN abs panic, sent back with S1/S4/S5). Follow-ups: S2 clip.render drains off entries without a word (say it in the message, or skip them); S3 sync/stacks.rs serializes all controls each sync, add a bench/edit.lua scenario with many controls; S6 defaults/clips.lua got ~190 lines of Lua, port it or the stack commands to Teal (rule 8); S7 Rendered in types.tl by hand, derive JsonSchema.

On local main (0aa72d12 with the merge 5bfb56fe, 2026-11-24, not pushed). Merge-check green: apidoc, clippy 0, nextest 692/692, suite words all passed. The meter fix 0aa72d12 (stale peak on a reused engine slot) came from the golden screens of G3 run after M1's tests.
<!-- SECTION:NOTES:END -->
