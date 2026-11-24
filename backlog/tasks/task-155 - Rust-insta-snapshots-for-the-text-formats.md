---
id: TASK-155
title: 'Rust: insta snapshots for the text formats'
status: Done
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies: []
priority: medium
ordinal: 167000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/testing-practices.md, practice R3, gap G2, ticket BT5, rank 5. Owner, 2026-11-22: insta as a dev-dependency.

The scene, the remote protocol, the project file, `.midi2` clips and the undo file are checked field by field, or not at all.

What to do: add insta as a dev-dependency of `paw-scene`, `paw-proto` and `paw-core`. Snapshot tests for a scene of each kind of node, the remote protocol messages, a project folder written to disk (a list of files and their text), a `.midi2` clip and the undo file. Redact ids and paths. CI sets `INSTA_UPDATE=no`.

Read first: backlog/docs/designs/testing-practices.md, sections 2.1 (R3), 4, 5.1 ("Golden files"), 6 (BT5). .claude/skills/rust-testing.

Overlaps: TASK-24 (e2e goldens; a different tier), TASK-98 (workspace lints).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 cargo insta test passes
- [ ] #2 CI fails on a new or changed snapshot that is not committed
- [ ] #3 The skills .claude/skills/lua-testing and .claude/skills/rust-testing name the new helpers and commands in the same commit.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
insta 1.47 dev-dep (workspace; json+filters) of paw-scene, paw-proto, paw-core; cargo-insta in the dev shell; flake tests check sets INSTA_UPDATE=no. Five snapshot tests (scene wire, client protocol transcript with an in-memory kernel, .midi2 clip, project folder, undo folder) and the test helper paw_core::golden (folder_text, settings). Skills rust-testing part 5/15 and lua-testing updated; docs/how-to/run-the-tests.md and docs/reference/nix-package.md. Snapshots NOT yet accepted: orchestrator runs cargo insta test -p paw-scene -p paw-proto -p paw-core, then cargo insta review. Branch worktree-agent-a68ffb5a804a5ab85, commits 6ee5243e + merge 5c1e749f.

At the merge with TASK-173: the one encode call in the clipfile.rs tests needs .unwrap() (encode returns Result).
<!-- SECTION:NOTES:END -->
