---
id: TASK-26
title: Groma scanner for Lua and Teal
status: Done
assignee: []
created_date: '2026-11-21T18:39:00Z'
updated_date: '2026-11-23T06:11:00Z'
labels:
  - local-tools
  - groma
  - lua
  - teal
milestone: m-7
dependencies: []
references:
  - lua-api
  - paw-kernel
priority: medium
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A Groma scanner plugin (like @groma/scanner-rust) that reads Lua and Teal, so the runtime (runtime/lua/paw) and the extensions (extensions/*, init.lua/init.tl, manifests) appear in the architecture map as components with their relationships. Check Groma's scanner plugin API first (groma agent-instructions, docs/config.md, an existing scanner's package). Evidence to read: module files and require() edges; Teal type declarations (runtime/types/*.d.tl, contracts.tl) for public shapes; paw.api calls (the kernel boundary); extension manifests (name, requires) and registries (commands, keys, views, clip kinds, insert kinds). Keep the scanner outside the paw repo (a local Groma plugin) unless the owner decides to publish it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 groma scan maps runtime/lua/paw modules and each bundled extension as components
- [x] #2 require() and paw.api use become relationships; the extension components link to the paw.api component
- [x] #3 a second scan creates nothing new (stable ids)
- [x] #4 git status stays clean (groma/ local)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Result (2026-11-22)

The scanner is a local Groma plugin outside the repository:
`~/.groma/plugins-local/scanner-teal/` (`package.json`, `src/index.js`). It has no dependencies and runs no Lua. `groma plugin add` wrote its absolute path into `groma/config.json` (scanner id `teal`).

Config of the `teal` entry in `groma/config.json`:
- include: `runtime/lua/**`, `extensions/**` (`.lua`, `.tl`), the Rust files that define `paw.api` (`crates/paw-core/src/api/*.rs`, `*_api.rs`, `scene.rs`, `measure/mod.rs`), `crates/paw-tui/src/main.rs` and `crates/paw-core/src/kernel.rs`.
- exclude: `*.d.tl`, tests, fixtures, `runtime/lua/tl.lua`, `runtime/lua/compat53/`, extension `tools/`, `demo.lua`, `tutor/make-docs.lua`. `config/` (the sample configuration) is not included.
- settings.entry: the `paw` binary (`main.rs`) embeds `runtime/lua` (`include_dir!` in `kernel.rs`). This entry fact puts the runtime modules in the `paw-kernel` container.

What the scanner reports:
- One component for each runtime module (165, in `paw-kernel`).
- One source unit for each extension folder (25 components, primary `init.*`, else `manifest.lua`). They are in the paw system, group "Unidentified container" (no entry fact: extensions load from disk at run time).
- Operations: a chunk for each module, the module functions, and each `paw.api` function from the Rust `define!` blocks, `api.set("x")` and `helper(lua, api, shared, "x")` (351 names, the same set as `runtime/types/paw/api.d.tl`).
- Invocations with a binding and a member, so core derives rows with its "supplied named callback" rule: `require("m")` with a literal name, manifest `requires`, and member uses through a local alias or the global `paw` table (`paw.x` resolves through the `paw.x = ...` assignments of the runtime). Teal `local type X = require()` and record-type uses are not reported.
- Result: 2954 derived rows (technology `teal`). 22 of 25 extensions link directly to `lua-api` (paw.api); `continue`, `luafx` and `snippets` link only through the runtime. All link to `paw-init` through the manifest (`requires paw ^1.0`). Registries show as rows to `commands`, `keymap`, `ui`, `clip-kinds`, `track-kinds`, `insert`, `options`.
- Statement text: core writes "Invokes supplied callback(s): <members>". A module value from `require()` or `paw.x` is the supplied value. This is the only derived rule of Groma 0.7.8 for direct use (it has no import rule).

Checks: two scans after the first: `created 0`, the groma tree is identical (AC #3). AGENTS.md and CLAUDE.md unchanged; `git status` clean (AC #4).

Known limits: lexer, not compiler. Dynamic requires (`require("paw.views." .. name)`), metatable dispatch and values passed between functions are not reported. The Rust files of `paw.api`, `main.rs` and `kernel.rs` get an extra `scanner: teal` Code link (the outline still comes from `rust`, because `rust` < `teal`). The loader `runtime/lua/paw/ext.lua` loads the extensions by directory listing; no row shows this.

I edited the overviews of `paw` (system) and `project`: they said that the Lua was not mapped.

## Curation proposal (not applied; owner decides)
1. Extensions: move the 25 `<name>-init`/`-manifest` components to `paw-kernel` (they run in its LuaJIT state), rename to `<name>-extension`, group "Bundled extensions".
2. Runtime: combine the 165 module components into skyscrapers by responsibility, for example Views (`views/*`), Defaults (`defaults/*`), LSP client (`lsp/*`), Pickers (`pick*`), Harmony (`harmony*`), Roles (`roles*`), Teal contracts (`contracts`, `types`). Keep separate: `paw-init` (the `paw` module), `ext` (extension loader), `commands`, `keymap`, `ui`, `clip-kinds`, `track-kinds`, `insert`, `objects`, `options`, `events`, `hooks`. Group them as "Lua runtime".
3. Add an authored relation `runtime/lua/paw/ext.lua -> extensions/<x>/init.*` ("Loads the extension at startup") if the owner wants the loader on the map.
4. Write descriptions for the new components after the structure is settled.

Board review 2026-11-23: all four criteria are checked and the result is above. The scanner is at ~/.groma/plugins-local/scanner-teal (package.json, src/index.js), and groma/config.json has the teal entry. The curation proposal stays with the owner (groma curation is a separate request).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The Lua and Teal scanner for Groma is a local plugin outside the repository. It maps the runtime modules and the bundled extensions, with require() and paw.api use as relationships. A second scan creates nothing new. git status stays clean.
<!-- SECTION:FINAL_SUMMARY:END -->
