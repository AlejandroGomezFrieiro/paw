---
id: TASK-204
title: 'Extensions: move the other registries onto paw.registry'
status: Done
assignee: []
created_date: '2026-11-23T03:43:00Z'
updated_date: '2026-11-23T06:34:00Z'
labels: []
milestone: m-10
dependencies: []
priority: medium
ordinal: 216000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-103 (2026-11-23): pickers and status line components are on paw.registry (Registry<T>, owner at put, unload by owner). These still use ext.lua's before-and-after copies (M.registries): commands, keys, key_groups, views, keybar, buftypes, textbuf_kinds, track_kinds, clip_kinds, roles; query_fields, ex_fields, ex_views, completers, trackcolumn, trackcolumn_signs, barlabel, insert, grep, curves; addresses, complete, triggers, layers, languages, health, formats, lsp; hooks, options, timers, device_dirs, plugin_dirs; the pencil and bands entries of init.lua. Hooks, timers and keys feed the leak check of tests/suite.lua: do them after TASK-146's runner part. Move in groups; each moved registry gets a row in tests/extensions_api.lua's registries table.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 M.registries in ext.lua is empty, or each entry left has a written reason
- [x] #2 Each moved registry has a row in the registries test
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a170d972f446eddf9, commits 6062c425 (group 1), cb8787e1 (group 2), merge of main da5a4240 7bda25f0, e8c6be0c (tests/cmdwin.lua from main). Moved onto paw.registry: commands (paw.commands.specs), views (paw.ui.views), buftypes (paw.layout.types), textbuf_kinds, track_kinds, clip_kinds, roles (paw.roles.registry = paw.ui.roles); query_fields (keys 'kind name'), ex_fields, ex_views, completers, trackcolumn, trackcolumn_signs, barlabel (paw.ruler.labels), insert (paw.insert.kinds), grep, curves. Public API change: reads are reg:get(name), removals reg:remove(name); paw.commands.put is gone; every caller, test, doc, type changed (paw.ui.views.X was ~430 reads). paw.registry: label may give nil to keep an entry out of :extensions. tools/layers.lua reads paw.x:get('name') as paw.x.name (allow-list: +paw.ex paw.views.arrange, +paw.locators paw.views.devices, which an alias hid before; 4 counts down). Each moved registry has a row in tests/extensions_api.lua 'registries' (+ a test of an extension that moves an insert key). LEFT in ext.lua M.registries, with the reason in a comment there: keys, key_groups, keybar, hooks, timers (leak check, TASK-146); options (undefine puts back the core definition); device_dirs, plugin_dirs (devices_in_use reads them); addresses, complete, triggers, layers, languages, health, formats, lsp (not moved yet: next ticket); init.lua's pencil and bands. Pre-existing on main (also fail on d5127487 under the same filters): 'notation layout: other features place marks...' under 'only kind', 'narrowing to a group shows its tracks alone...' under 'only window'.

Board review 2026-11-23: the registries that this ticket leaves in M.registries go to the follow-up ticket (see TASK-208), so that this ticket can merge with its two criteria as written.

PO check 2026-11-23 on main 7f02e829: #1 ext.lua M.registries keeps keys, key_groups, keybar, addresses, complete, triggers, layers, languages, health, formats, lsp, hooks, options, timers, device_dirs, plugin_dirs, with the reason for each in the comment above it. #2 tests/extensions_api.lua 'registries' has 19 rows (the 17 moved and the two of TASK-103). The rest is TASK-208.
<!-- SECTION:NOTES:END -->
