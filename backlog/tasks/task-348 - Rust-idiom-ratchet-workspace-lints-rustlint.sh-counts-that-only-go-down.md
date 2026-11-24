---
id: TASK-348
title: 'Rust idiom ratchet: workspace lints, rustlint.sh, counts that only go down'
status: Done
assignee: []
created_date: '2026-11-24T10:39:00Z'
updated_date: '2026-11-24T14:15:00Z'
labels:
  - agent:worker
  - quality
dependencies: []
priority: high
ordinal: 417000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Retro 2026-11-24 (second). The pre-commit hook runs tools/rustlint.sh if it exists; it does not exist, and the workspace lints were planned inside TASK-342 (a refactor of 100+ files), so no idiom check runs. Pedantic clippy on paw-core + paw-engine at 0aa72d12: 2387 findings, about 1100 casts (truncation, sign loss, precision): the class of the M1 panic (a saturating f64-as-i64 cast, then i64::MIN.abs()). This ticket lands the mechanism first; TASK-342 pays the counts down.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Cargo.toml [workspace.lints.clippy] warns on: cast_possible_truncation, cast_sign_loss, cast_possible_wrap, cast_precision_loss, cast_lossless, allow_attributes, allow_attributes_without_reason, float_cmp, too_many_lines (threshold 100 in clippy.toml), fn_params_excessive_bools, struct_excessive_bools, unwrap_used and expect_used outside tests (allow them in tests via clippy.toml)
- [x] #2 tools/rustlint-allowed.txt keeps a count per crate and per lint (format like tools/partlint-allowed.txt: '<crate> <lint> <count>'); a ratchet script fails when a count goes up and prints how to lower the file when a count goes down
- [x] #3 The ratchet runs in .orchestrator-independent places: nix flake check (a check next to clippy) and a script that the merge check can call; it excludes paw-gui
- [x] #4 tools/rustlint.sh (fast, no build, for the pre-commit hook): fails on a new fn that only returns a constant, a serde(default = "...") helper, and model/ naming sync, session, api or kernel; with a test or a self-check of each rule
- [x] #5 docs/how-to/run-the-tests.md (or the page that lists the checks) and the skill paw-code part 7 name the new checks; CODING_STANDARDS.md keeps judgement only
- [x] #6 No behavior change: goldens, snapshots, wire JSON and error texts do not change; the counts file starts at today's counts
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
- [x] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [x] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [x] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [x] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [x] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [x] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [x] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design change 2026-11-24 (owner: community tools): ratchet = module-level #![expect(clippy::lint, reason)] + clippy -D warnings (unfulfilled_lint_expectations removes paid debt) in place of a counts file; pattern rules = ast-grep (sgconfig.yml, tools/ast-grep/rules, ast-grep test) behind tools/rustlint.sh; plus cargo-machete and cargo-deny in the flake checks. Not adopted: cargo-pup (0.1.x, young), cargo-dylint (not in nixpkgs; ast-grep covers the rules), a clippy baseline tool (none mature). Later, not on the shared machine during agent work: cargo-mutants (test quality).

On local main (fabe6c16, 2026-11-24, not pushed), merged with the other of 342/348. Reviews: merge (342 after the H1 lost-events and H2 RESET_ON_FORK fixes). Merge-check: apidoc 0, workspace clippy -D warnings clean, nextest 709/709, suite words all passed, ast-grep rules pass, expect debt 631. Follow-ups: TASK-350, TASK-354, rule gaps on TASK-352.
<!-- SECTION:NOTES:END -->
