---
id: TASK-306
title: >-
  Kind families: one contract for clip, stream, part and meta kinds; StreamType
  with properties; Part.kind, Part.parent and Note.lyric in the model (A2)
status: In Progress
assignee: []
created_date: '2026-11-23T16:01:00Z'
updated_date: '2026-11-24T18:54:00Z'
labels:
  - agent:builder
  - architecture
  - kinds
  - bundle
milestone: m-10
dependencies:
  - TASK-304
  - TASK-208
  - TASK-133
  - TASK-96
references:
  - architecture/decisions/0018-parts-and-typed-lanes.md
  - architecture/decisions/0010-extension-clip-kinds.md
  - architecture/decisions/0028-typed-lanes-and-converters.md
  - architecture/decisions/0005-small-core-extensions.md
  - backlog/docs/designs/architecture-plan.md
priority: high
ordinal: 369000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle A2 of the architecture plan, version 2 (backlog/docs/designs/architecture-plan.md V2.3, V2.7 step 2 and V2.15; section 6.3 gives the base criteria; m10-generalization-review.md 2.1 and 2.2; containers.md C2).

The built-in clip kinds become entries of the owner paw.clips. RESERVED and ClipKindId go. A lane type is a base stream kind plus properties (ADR 0028): StreamType { base, props }. meta.kind becomes Part.kind, meta.group becomes Part.parent, meta.lyric becomes Note.lyric. Takes do not move here (LA does that). The drawing of clips does not move here (B6 does that). The families are the types of A1. The ParamSchema of properties comes from T96 (TASK-96).

Read first: the skill .claude/skills/architecture (after batch 19 it is on main), architecture/08-concepts.md and 13-roadmap.md, the ADRs in the references, and backlog/docs/designs/architecture-plan.md (the sections that this ticket names). An Opus agent does the whole bundle in one branch, with its tests and docs in the same commits.

Size: L. One family for each commit, each with a round trip test of the folder.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 paw.kinds.define(family, name, spec) puts the spec in the family's paw.registry and mirrors it into Kinds<F, S> through one paw.api.kinds_put. Clip, stream, part and meta kinds use it. A test defines a clip kind from Lua, unloads its extension, and the project still opens and plays its kept sound
- [ ] #2 midi, audio, nest and curve are entries of the owner paw.clips, each with gives = its stream kind. RESERVED and ClipKindId are gone (git grep)
- [ ] #3 StreamFamily has midi, audio, curve and state, each with a ParamSchema of properties, a time base and records. StreamType and Props round trip. A test defines a stream kind with a property from Lua
- [ ] #4 Part.kind: Option<KindId<PartFamily>> and Part.parent: Option<PartId>; the part kinds and paw.groups read the fields; no runtime file reads meta.kind or meta.group (git grep). A group still sums
- [ ] #5 paw.meta.define(key, spec) declares a key with a version; K names the owner of each declared key; an undeclared key stays as it is
- [ ] #6 Note.lyric is a model field. midifile.tl writes it with no read of meta, and names no device kind of an extension (a device kind field drum_channel, from TASK-218). utau reads and writes the field
- [ ] #7 Each family moves in its own commit with a round trip test of the project folder
- [ ] #8 Docs: about-core-and-extensions.md, the project files reference and the extension skill are true; an explanation page About kinds exists; Vale reports 0 alerts
- [ ] #9 model/kinds.rs moves to paw-types/src/kinds.rs; the inherent impl on Kinds<SplitFamily, SplitImpl> in model/chain/kinds.rs becomes a trait or free functions; paw-types gets serde, serde_json and thiserror, and the wasm32 check still passes
- [ ] #10 A kind spec may give a data schema (ParamSchema words); paw.api lists each kind with its schema for paw-mcp; a kind with no schema is read only for MCP (the MCP tools themselves are TASK-376)
- [ ] #11 No part kind in core: drums, sampler and utau own theirs; a part of an absent kind shows its kind name as a label, plays what it keeps, and a save keeps all of it (test with the extension unloaded)
- [ ] #12 Part.parent: groups nest to any depth; a move that makes a cycle is refused with a message; a group is a full part (lanes, chain) that sums its children; tests for depth 3 and for the cycle
- [ ] #13 paw.meta.define: a key no one declared is kept with no message; :checkhealth lists such keys and their files
- [ ] #14 On open, a converter moves meta.kind, meta.group and meta.lyric into Part.kind, Part.parent and Note.lyric; the next save writes only the new fields; a comment and a TASK in m-18 say it goes at the first release
- [ ] #15 paw.clip_kinds.define and paw.part_kinds.define are gone with no aliases (git grep); drums, sampler and utau use paw.kinds.define
- [ ] #16 MIDI export writes Note.lyric as lyric events; MIDI import puts each lyric event on the note at its tick (or the next note), and its report names each lyric moved or dropped; a round trip test
- [ ] #17 Note.lyric is plain text; utau keeps phonemes and voice data in meta keys that it declares
- [ ] #18 A part's kind can change (a command such as :part.kind <name>, and clear) in one undo step; lanes, clips and devices stay; test with real keys
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
Lane heads (HD, TASK-323): move the field head from paw.track_kinds and paw.clip_kinds to the part and clip families of paw.kinds; the Head record does not change (design: backlog/docs/designs/lane-heads.md)

Owner question for the A2 interview (2026-11-24): when an extension registers a clip, lane or part kind, it also gives the schema of its data, so paw-mcp can list kinds and add_clip/get_clip can take kind + data checked against that schema (today MCP sees only MIDI and audio clips).

Owner interview 2026-11-24: all 11 recommended answers accepted; recorded in architecture/13-roadmap.md, section The A2 interview. ACs #10 to #18 added from it.

Started 2026-11-24: branch kind-families, base 582ae3a5.

Owner, 2026-11-24: lyrics are standard MIDI (SMF FF 05, MIDI 2.0 Flex Data Performance Text Events / Lyrics). They stay core MIDI data that notation, search and .mid import and export share, and the .midi2 clip file saves them as standard Flex Data Lyrics messages at the note-on, not in paw's private paw: text. utau keeps only its own data (phonemes, pitch curves, flags) in a kind or meta keys that extend midi. Added to the A2 fix round.
<!-- SECTION:NOTES:END -->
