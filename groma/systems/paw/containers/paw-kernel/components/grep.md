---
type: C4 Component
title: Grep
status: stable
groma:
  id: grep
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/grep.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callbacks: paw.api.log, paw.api.now | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.clip, paw.address.device, paw.address.marker, paw.address.note, paw.address.project, paw.address.track, require("paw.address") | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.Context, paw.commands.Result, paw.commands.alias, paw.commands.define, require("paw.commands") | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | Invokes supplied callbacks: paw.derived.node, require("paw.derived") | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callback: paw.markers.list | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick.match | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | Invokes supplied callbacks: paw.qf.current, paw.qf.jump, paw.qf.loc_stack, paw.qf.set, paw.qf.stack | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | Invokes supplied callback: paw.query.articulations | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [runtime/lua/paw/query/tree.tl](../../../../../../runtime/lua/paw/query/tree.tl) | Invokes supplied callbacks: paw.query.tree.clip, paw.query.tree.notes, paw.query.tree.same_data, paw.query.tree.same_list, paw.query.tree.track, require("paw.query.tree") | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [runtime/lua/paw/regex.tl](../../../../../../runtime/lua/paw/regex.tl) | Invokes supplied callback: paw.regex.compile | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.new, require("paw.registry") | teal |
| [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
