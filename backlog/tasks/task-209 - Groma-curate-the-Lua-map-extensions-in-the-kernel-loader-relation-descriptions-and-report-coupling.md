---
id: TASK-209
title: >-
  Groma: curate the Lua map (extensions in the kernel, loader relation,
  descriptions) and report coupling
status: Done
assignee: []
created_date: '2026-11-23T06:30:00Z'
updated_date: '2026-11-23T06:42:00Z'
labels: []
milestone: m-7
dependencies: []
references:
  - ara-extension
  - articulations-extension
  - columnplus-extension
  - continue-extension
  - doctor-extension
  - drums-extension
  - interop-extension
  - launcher-extension
  - luafx-extension
  - midilsp-extension
  - mixdiag-extension
  - musicops-extension
  - notation-extension
  - pattern-extension
  - plugstate-extension
  - projdiff-extension
  - rulerplus-extension
  - sampler-extension
  - sections-extension
  - snippets-extension
  - templates-extension
  - tutor-extension
  - undotree-extension
  - utau-extension
  - vinput-extension
  - ext
modified_files:
  - groma/systems/paw/containers/paw-kernel/components/ara-init.md
  - groma/systems/paw/components/ara-init.md
  - groma/systems/paw/containers/paw-kernel/components/articulations-init.md
  - groma/systems/paw/components/articulations-init.md
  - groma/systems/paw/containers/paw-kernel/components/columnplus-init.md
  - groma/systems/paw/components/columnplus-init.md
  - groma/systems/paw/containers/paw-kernel/components/continue-init.md
  - groma/systems/paw/components/continue-init.md
  - groma/systems/paw/containers/paw-kernel/components/doctor-init.md
  - groma/systems/paw/components/doctor-init.md
  - groma/systems/paw/containers/paw-kernel/components/drums-init.md
  - groma/systems/paw/components/drums-init.md
  - groma/systems/paw/containers/paw-kernel/components/interop-init.md
  - groma/systems/paw/components/interop-init.md
  - groma/systems/paw/containers/paw-kernel/components/launcher-init.md
  - groma/systems/paw/components/launcher-init.md
  - groma/systems/paw/containers/paw-kernel/components/luafx-manifest.md
  - groma/systems/paw/components/luafx-manifest.md
  - groma/systems/paw/containers/paw-kernel/components/midilsp-init.md
  - groma/systems/paw/components/midilsp-init.md
  - groma/systems/paw/containers/paw-kernel/components/mixdiag-init.md
  - groma/systems/paw/components/mixdiag-init.md
  - groma/systems/paw/containers/paw-kernel/components/musicops-init.md
  - groma/systems/paw/components/musicops-init.md
  - groma/systems/paw/containers/paw-kernel/components/notation-init.md
  - groma/systems/paw/components/notation-init.md
  - groma/systems/paw/containers/paw-kernel/components/pattern-init.md
  - groma/systems/paw/components/pattern-init.md
  - groma/systems/paw/containers/paw-kernel/components/plugstate-init.md
  - groma/systems/paw/components/plugstate-init.md
  - groma/systems/paw/containers/paw-kernel/components/projdiff-init.md
  - groma/systems/paw/components/projdiff-init.md
  - groma/systems/paw/containers/paw-kernel/components/rulerplus-init.md
  - groma/systems/paw/components/rulerplus-init.md
  - groma/systems/paw/containers/paw-kernel/components/sampler-init.md
  - groma/systems/paw/components/sampler-init.md
  - groma/systems/paw/containers/paw-kernel/components/sections-init.md
  - groma/systems/paw/components/sections-init.md
  - groma/systems/paw/containers/paw-kernel/components/snippets-manifest.md
  - groma/systems/paw/components/snippets-manifest.md
  - groma/systems/paw/containers/paw-kernel/components/templates-init.md
  - groma/systems/paw/components/templates-init.md
  - groma/systems/paw/containers/paw-kernel/components/tutor-init.md
  - groma/systems/paw/components/tutor-init.md
  - groma/systems/paw/containers/paw-kernel/components/undotree-init.md
  - groma/systems/paw/components/undotree-init.md
  - groma/systems/paw/containers/paw-kernel/components/utau-init.md
  - groma/systems/paw/components/utau-init.md
  - groma/systems/paw/containers/paw-kernel/components/vinput-init.md
  - groma/systems/paw/components/vinput-init.md
  - groma/systems/paw/containers/paw-kernel/components/ara-extension.md
  - >-
    groma/systems/paw/containers/paw-kernel/components/articulations-extension.md
  - groma/systems/paw/containers/paw-kernel/components/columnplus-extension.md
  - groma/systems/paw/containers/paw-kernel/components/continue-extension.md
  - groma/systems/paw/containers/paw-kernel/components/doctor-extension.md
  - groma/systems/paw/containers/paw-kernel/components/drums-extension.md
  - groma/systems/paw/containers/paw-kernel/components/interop-extension.md
  - groma/systems/paw/containers/paw-kernel/components/launcher-extension.md
  - groma/systems/paw/containers/paw-kernel/components/luafx-extension.md
  - groma/systems/paw/containers/paw-kernel/components/midilsp-extension.md
  - groma/systems/paw/containers/paw-kernel/components/mixdiag-extension.md
  - groma/systems/paw/containers/paw-kernel/components/musicops-extension.md
  - groma/systems/paw/containers/paw-kernel/components/notation-extension.md
  - groma/systems/paw/containers/paw-kernel/components/pattern-extension.md
  - groma/systems/paw/containers/paw-kernel/components/plugstate-extension.md
  - groma/systems/paw/containers/paw-kernel/components/projdiff-extension.md
  - groma/systems/paw/containers/paw-kernel/components/rulerplus-extension.md
  - groma/systems/paw/containers/paw-kernel/components/sampler-extension.md
  - groma/systems/paw/containers/paw-kernel/components/sections-extension.md
  - groma/systems/paw/containers/paw-kernel/components/snippets-extension.md
  - groma/systems/paw/containers/paw-kernel/components/templates-extension.md
  - groma/systems/paw/containers/paw-kernel/components/tutor-extension.md
  - groma/systems/paw/containers/paw-kernel/components/undotree-extension.md
  - groma/systems/paw/containers/paw-kernel/components/utau-extension.md
  - groma/systems/paw/containers/paw-kernel/components/vinput-extension.md
  - groma/systems/paw/containers/paw-kernel/components/ext.md
priority: medium
ordinal: 237000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The owner approved the curation of TASK-26's proposal on 2026-11-23 ('if it helps keep things clean'). Do steps 1, 3 and 4. Hold step 2 (group the 165 runtime modules) until after TASK-206, which moves modules. Then use the curated map to report undesired coupling.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The 25 extensions are in the kernel container, named <name>-extension, group 'Bundled extensions'
- [x] #2 An authored relation shows that ext.lua loads each extension
- [x] #3 Each new or moved component has a description
- [x] #4 A report lists undesired coupling found on the map, each with evidence and a proposed ticket
- [x] #5 AGENTS.md, CLAUDE.md and tracked files unchanged; groma stays local
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Result (2026-11-23)

### Curation (steps 1, 3 and 4 of the TASK-26 proposal)

- Step 1: the 25 extension components moved from the system (group "Unidentified container") into `paw-kernel`, because they run in its LuaJIT state. New IDs `<name>-extension` (`groma edit --parent`, then `--id`). All 25 are in the group "Bundled extensions" (address `paw-kernel/bundled-extensions`).
- Step 3: 25 authored relations from `runtime/lua/paw/ext.lua` to the entry file of each extension: `init.lua` or `init.tl`, and `manifest.lua` for `luafx` and `snippets` (they have no init file). Description "Loads the extension at startup", technology "Lua: manifest and init".
- Step 4: each of the 25 components has a title (for example "Singing extension"), a one-sentence description, an overview and a technology (Lua, Teal, or both). The text comes from the manifests, the READMEs and the code.
- Step 2 (group the runtime modules into skyscrapers by responsibility) is NOT done. It waits until after TASK-206: the improvement run moves and splits modules, and a grouping before it would go stale.
- The modified-file list of this ticket has the groma paths of the structural commands.

### Scan check

- One scan before the relations: `created 75`. These are NOT from the curation. They are Rust files that are new on main since the last scan, and the files of `fuzz/` (four new containers: `paw-remote`, `paw-clip-file`, `paw-project-folder`, `paw-terminal-keys`). About 35 Rust components are now in the system group "Unidentified container" (for example `session-document`, `clap-*`, `vst3-*`, `model-links`). This needs a Rust curation pass and an exclude of `/fuzz/` in groma/config.json (not in this ticket).
- interop and plugstate became Teal (`init.tl`) since the last scan. The scan put the new files in the same extension components (source unit by folder).
- Two scans after the curation: `created 0` each time. The 25 IDs, the group, the 25 relations and the descriptions stay. No `-init` or `-manifest` component came back.
- git status is clean. AGENTS.md and CLAUDE.md are not changed.

### Coupling report (ranked by cost)

1. Upward references in the runtime: 204 lines, 283 names in tools/layers-allowed.txt. Six targets get 211 of 283 (75 %): `paw` (init, boot layer) 67, `paw.frontend` 48, `paw.ui` 44, `paw.keymap` 20, `paw.commands` 16, `paw.pick` 16. A few names cause most of them: `paw.notify` 25, `paw.command` 17, `paw.defer` 16, `paw.cancel` 12, `paw.commands` 16, `paw.frontend.act` 10, `paw.pick` 10, `paw.frontend.format_value` 7, `paw.try` 5, `paw.every` 4. The timers (`defer`, `cancel`, `every`, `try`) are defined in paw/init.lua (boot layer) and `notify` in paw/ui.tl (screen layer), but low-layer modules need them. Move the timers to a module in the kernel layer and give `notify` a message sink in the data layer: about 79 lines go (28 %). The command registry (`paw.command`, `paw.commands`, 33) is the next. By layer pair: project>screen 48, project>input 31, views>frontends 30, input>views 30. The sources with the most: paw.fx 14, paw.autosave 11, paw.scope 10.
2. Cycles in the runtime: 147 of 192 modules are in one strongly connected component. Most of it goes through `paw` (init) and the global table; without `paw`, `paw.ui` and `paw.frontend` there is still one of 98 modules and 42 mutual pairs, for example paw.draw <-> paw.util (util is in the data layer), paw.events <-> paw.limit <-> paw.options, paw.commands <-> paw.keymap, paw.objects <-> paw.scope, paw.remote <-> paw.scene <-> paw.frontend.state, paw.render <-> paw.stems. Many are lazy reads at call time, not load cycles, but a change in one still can break the other. Item 1 removes the largest part.
3. Extensions that use internal runtime modules or state (no entry in api.md): `paw.theme` (articulations roll.lua:13, sections ui.lua:376, utau editor.lua:18 and strips.lua:18), `paw.mouse_menus` (launcher view.lua:308), `paw.views.curve` (articulations linked.lua:139), `paw.views.cmdline` (articulations commands.lua:511, notation popover.lua:20), `paw.lsp.rpc` (midilsp adapter.lua:43). They also write `paw.state.last_cmdline` (articulations commands.lua:510, notation popover.lua:146), which paw/defaults/keys.lua:95 reads for `@:`: an undocumented protocol. The Teal type requires (`paw.types`, `paw.contracts`) and `paw.dsp`, `paw.events.kernel` are documented in docs/ and are not a problem. The map shows the same rows (for example `launcher-extension -> mouse-menus`). TASK-132 covers this (its criterion 2); add paw.theme (a public palette) and the `last_cmdline` write to it.
4. Undeclared dependencies between extensions. All 25 manifests require only `paw`. articulations -> notation (`require("notation.marks")`, articulations/lua/articulations/notation.lua:8; init.lua:18 polls `package.loaded["notation.marks"]` with a defer and an event; the map has the row). tutor -> sections (tutor/lua/tutor/lessons/extensions.lua:71; map row). interop -> sections (pcall require, interop/lua/interop/init.tl:168; the scanner does not see it). musicops -> utau by view name: it adds text objects and keys to the `utau` view and looks for the utau `<C-a>` map (musicops/lua/musicops/keys.lua:17, 399, 620). The manifest has no field for an optional dependency, so each of these works around it. Proposed fix: an `optional`/`wants` field in the manifest (load order, and an event when the other loads), and an extension point in notation for marks instead of a poll.
5. Core that knows one extension: paw/query.tl:120-127 and 563 reads `meta.notation.art`, the data that the notation extension keeps in note meta (also used by grep.tl:211 and pick/project.tl:281). paw/help.tl:443 adds the alias `tutor-course`; paw/views/arrange.tl:1262 shows `:tutor` on the start lines when the command exists; roll_draw.tl:1321 names `:ext.load articulations` in a message. The first is a real break of "core changes for an extension are generic": give query a registry of articulation sources that notation fills. The others are small and only text.
6. Extensions put themselves in the `paw.` namespace of package.loaded: ara, articulations, mixdiag, sampler, utau, plugstate (`package.loaded["paw.<name>"]`, for example utau/init.lua:17); plugstate README documents `require("paw.plugstate")`. A later core module of the same name breaks them. Cost low. Fix: use the extension name (`require("plugstate")`), as vinput and templates do.
7. Rust: the crate graph has no cycle (cargo refuses one). paw-core is 50 k lines of 12 crates' 112 k; its `api` module reads 25 sibling modules (expected for the Lua bridge). paw-engine makes 25 of its 26 modules `pub`, and paw-core reaches into them from 57 files, including the data model (model.rs:12 `TempoMap`, `Attr`, `launch::Quantize`, `midi_form::Form`; model/nest.rs:31): the model needs the engine crate. Mutual module pairs in paw-core: session <-> sync, model <-> sync (one helper, model/nest/time.rs:223 `sync::repeats`), history <-> model, api <-> kernel, kernel <-> rpc, io_runtime <-> session. paw-tui uses only the entry points it needs (main.rs: `paw_engine::backend` options, `paw_luadev` helper entry, `session::panic`, `clipfile`); that is a composition root and is acceptable. TASK-95 (paw-model crate) and TASK-98 (pub(crate)) cover the model and the interface; add "TempoMap and Attr move to a crate that both model and engine use" to TASK-95 if it is not there.

### Proposed tickets (not created)

- Runtime: timers and a message sink in the kernel layer, so ~79 upward references go (m-10, medium).
- Runtime: the command registry below the project layer (m-10, low), after the one above.
- Extensions: optional dependencies in the manifest, and an extension point in notation for marks (m-2 or the extensions milestone, medium).
- Query: articulation sources as a registry, no `meta.notation` in core (m-10, low).
- Extensions: no `paw.<name>` in package.loaded (m-10, low).
- groma: curate the new Rust components and exclude `/fuzz/` (m-7, low).
- groma: step 2 of the TASK-26 proposal after TASK-206 (m-7, low).

TASK-206 (through TASK-132, TASK-95, TASK-98, TASK-208) covers items 3 and most of 7. It does not name items 1, 2, 4, 5 and 6; its untangle skill can find 1 and 2 as hidden links, but a ticket makes them sure.
<!-- SECTION:NOTES:END -->
