---
id: TASK-242
title: 'Plugins in a folder that an extension adds: LV2 as well as CLAP and VST3'
status: To Do
assignee: []
created_date: '2026-11-23T07:15:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-S
  - plugins
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 304000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** An extension ships its own LV2 plugins (as the utau and sampler extensions ship CLAP plugins) or a user keeps LV2 plugins in a folder outside the standard paths. paw must find them as it finds CLAP and VST3 plugins there.

**Other DAWs.** Every LV2 host reads LV2_PATH; Ardour and Qtractor let the user add folders (design doc, gap 4).

**paw now (checked 2026-11-23). The gap is real.** crates/paw-plugins/src/lib.rs `add_dir` scans only CLAP and VST3 in the new folder (`scan_in::<clap::Clap>` and `scan_in::<vst3::Vst3>`). LV2 is read as one lilv world (crates/paw-plugins/src/lv2). docs/reference/limits.md says it twice ("`paw.plugins.add_dir` finds CLAP and VST3 plugins, not LV2 plugins").

**What to build.** `paw.plugins.add_dir(dir)` also loads the LV2 bundles in `dir` into the lilv world and registers them. `paw.plugins.remove_dir` takes them away. The plugin cache and the sandbox treat them as the other LV2 plugins.

**Core or extension.** Core: the plugin hosts are core.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test: a stub LV2 bundle (a test fixture built by the test or in the repository, not a plugin of the machine) in a scratch folder registers after add_dir and goes after remove_dir
- [ ] #2 Test: a rescan keeps it while the folder is added
- [ ] #3 No test reads the LV2 folders of the machine (LV2_PATH points to an empty scratch folder, as tests/tools/env.sh sets it)
- [ ] #4 limits.md loses both lines; docs/reference/plugins.md says it; Vale reports 0 alerts
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
