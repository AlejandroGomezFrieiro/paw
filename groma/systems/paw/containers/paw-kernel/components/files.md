---
type: C4 Component
title: Files
status: stable
groma:
  id: files
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/files.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.media_dir, paw.api.media_list | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.read_dir | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callbacks: paw.api.fs_copy, paw.api.fs_create, paw.api.fs_mkdir, paw.api.fs_move, paw.api.fs_sound, paw.api.fs_stat, paw.api.fs_trash | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | Invokes supplied callback: paw.audition.stop | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands, paw.commands.run | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.track | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.every, paw.import_audio, paw.is_audio_file | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.selection, paw.keymap.set, paw.keymap.set_mode | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | Invokes supplied callbacks: paw.midifile.import, paw.midifile.is_midi_file | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick.hear_file | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | Invokes supplied callbacks: paw.textbuf.buf, paw.textbuf.here, paw.textbuf.kind, paw.textbuf.open, paw.textbuf.reload | teal |
| [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
