---
id: TASK-287
title: >-
  Devices graph: tools of the chain language for people and agents (lints,
  command line, language server, MCP, render checks) (G14)
status: To Do
assignee: []
created_date: '2026-11-23T11:58:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-16
dependencies:
  - TASK-281
  - TASK-280
  - TASK-303
documentation:
  - backlog/docs/designs/devices-graph.md
priority: medium
ordinal: 349000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The chain language must be easy to edit right, by a person and by an agent, and always testable. Design sections 10.3 to 10.6: five levels of correctness (parse, check, lint, format, render), the rev guard against a stale edit, and the same diagnostics in paw, in another editor, on the command line and through MCP.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The lints L001 to L010 of the design, each with a test that fires and one that does not; -- allow turns one off; paw.chain.lint.add adds a lint from Lua
- [ ] #2 paw chain print, check, fmt [--check], lint, test and apply [--dry-run] work on a project and on a file, each with --json diagnostics (line, column, code, fix)
- [ ] #3 The checks block runs by rendering a test signal through the graph offline with the null audio device: latency, gain, peak, no NaN
- [ ] #4 apply with a stale rev is refused; --force ignores it
- [ ] #5 paw-mcp has chain_read, chain_check and chain_apply; chain_apply is one undo step and returns what changed
- [ ] #6 The suite runs paw chain test on the bundled templates
- [ ] #7 A tree-sitter grammar for colors
- [ ] #8 chain-lsp is a standalone language server (its own binary and crate, no dependency on paw) on stdio: diagnostics, lints with code actions, formatting, completion, hover with the schema of a parameter, go to definition of an #id or a linked rack. It reads the host schema from a file or a path the client gives
- [ ] #9 A standalone chain command (check, fmt [--check], lint, each with --json) for any host, with no paw; paw chain test and apply (render checks, rev, undo) stay in paw
- [x] #10 An extension extensions/chainlsp adds chain-lsp as an entry of paw.lsp, as midilsp does: opt-in with :ext.load chainlsp, the server found by paw.opt.chainlsp_cmd, then $CHAIN_LSP, then chain-lsp on the PATH; paw passes its schema. Without the extension paw works the same
- [ ] #11 Tests: an LSP session over stdio in Rust against a schema file with no paw, and a Lua test with real keys in paw with the extension loaded; a how-to for Neovim, tested
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
The language server itself moved to TASK-281 (owner 2026-11-23: bundled with the DSL). This ticket adds the lints and code actions to it.

Owner 2026-11-23: the server is generic and pluggable, not part of paw and not on by default. The lints live in chain-syntax (generic); paw adds its own lints through the schema or paw.chain.lint.add.

Commit 04b59771 on worktree-agent-a032bbeadcd8a3d41: the crate chain-lsp (lsp-server + lsp-types, no paw crate), complete/hover/definition in chain-syntax, paw.api.chain_schema, the extension chainlsp for the *.chain files of the project (the buffer paw://track/<n>/devices waits for TASK-279), docs and a Neovim how-to. After a build: run tools/apidoc.lua to give chain_schema to runtime/types and api.md, then tools/tlcheck.sh and the suite only chainlsp, extensions, lsp. Not done: go to definition into a linked rack, lint code actions (wait for the lints).

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): Plan 6.1 asks for an optional host context (chain_context, JSON, empty by default), no lint that assumes each port is audio, and the codes E213 to E218 and W302 kept free. If the branch does not have the host context, bundle CL2 adds it (CL2 AC 6).

PO 2026-11-23 (after batch 18+19, c04f8ae9): on main: the crate chain-lsp (stdio, diagnostics, formatting, completion, hover), paw.api.chain_schema, the extension chainlsp (AC 10), a Neovim how-to. Left: the lints L001 to L010 and paw.chain.lint.add (AC 1), the paw chain commands and the standalone chain command (AC 2, 9), the checks block (AC 3, needs G2), apply with rev (AC 4), the MCP tools (AC 5), paw chain test on the templates (AC 6), tree-sitter (AC 7), go to definition into a linked rack and lint code actions (AC 8), and the Lua real-keys test of AC 11 if it is not there. Order: the rest starts after CL2 (TASK-303), so that each lint is written one time for grammar 2, and after G2 (TASK-280) for the checks block. CL2 no longer waits for this ticket.

Reuse from CL2 (05b4a95e), do not write again: chain_syntax::check(doc, schema, Option<&Context>) and check_text; Context::from_json; chain_lsp::read_context; complete(text, offset, schema, Option<&Context>); Code::ALL (page order); the golden harness tests/it/bad.rs (a no-context* file runs without a context); fixtures tests/fixtures/schema.json and context.json; Document::graph_nodes(), wires(), to_version_2(); Schema::ports(kind), insert(kind), graph_kind(role, kind). Also build 'paw chain context <track>' (ChainCommand::Context in paw-tui args.rs, a kernel request that builds chain_syntax::Context from the part's lanes and other parts' lanes and strips, print via Context::to_json) unless A1's follow-up does.
<!-- SECTION:NOTES:END -->
