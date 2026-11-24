---
id: TASK-101
title: 'Rust: paw-measure crate shared by paw-core and paw-mcp'
status: Done
assignee: []
created_date: '2026-11-22T10:38:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels:
  - rust
  - quality
  - mcp
milestone: m-10
dependencies: []
priority: medium
ordinal: 104000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: one measurement crate that paw-core and paw-mcp both use, so that :mix and the MCP tools give the same numbers. Finding F7 of the architecture review (backlog/docs/designs/architecture-review.md).

Today: crates/paw-core/src/measure/ (analysis.rs, 971 lines) measures loudness, true peak, spectrum and stereo. crates/paw-mcp/src/audio.rs has its own WAV reader, RMS and an FFT spectrum in octave bands (analyze, 139 lines). paw-mcp does not depend on paw-core, and it must not.

Change: crate paw-measure with the analyzer of measure/analysis.rs (and peaks.rs if it fits) and its tests; paw-core and paw-mcp use it; paw-mcp keeps the form of its texts and reads the numbers from the analyzer; its own FFT and RMS code goes.

Read first: the review, F7; crates/paw-core/src/measure/; crates/paw-mcp/src/audio.rs and tools/listen.rs; .claude/skills/mixing-mastering (what the numbers mean); .claude/skills/rust-skills/paw-crates.md (loudness: why paw keeps its own).
Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 paw-mcp has no FFT or RMS code of its own; it uses paw-measure
- [ ] #2 A test gives the same file to :mix (paw-core) and to the MCP analysis and compares each measure that both report (sample peak, spectrum)
- [ ] #3 The MCP texts keep their form; paw-mcp tests pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-ad67fb33b743650e9, commit 07f55579 (main merged, up to date). New crate crates/paw-measure (workspace member and default member): the analyzer of paw-core measure/analysis.rs and its tests (moved), plus Levels (sample peak, RMS, DC, full-scale count) that the analyzer now uses for its per-channel totals (same arithmetic). Analysis gains centroid (spectral centroid, Hz); types.tl Measurement has it. paw-core measure/mod.rs and session/render.rs use paw_measure. paw-mcp audio.rs: no FFT or RMS code; channel levels, segments and stems from Levels, stereo line, octave bands and centroid from Analyzer; texts keep their form; realfft dependency removed. Number changes in MCP texts: spectrum now the kernel's (8192 Hann, half overlap, mean removed), clipping threshold 0.99995 (was 0.999). New test protocol.rs analyze_audio_and_mix_give_the_same_numbers (AC#2). Rust tests to run: cargo test -p paw-measure, -p paw-mcp (incl. protocol), -p paw-core. Docs: mixdiag README, paw-mcp README, source-tree.md, paw-crates.md.
<!-- SECTION:NOTES:END -->
