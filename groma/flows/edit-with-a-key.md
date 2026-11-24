---
type: Groma Flow
title: Edit with a key
groma:
  id: edit-with-a-key
---

A key in the terminal becomes one undoable edit, and the engine catches up through the one sync path.

## Steps

| From | To | Action |
| --- | --- | --- |
| [musician](../actors/musician.md) | [terminal-frontend](../systems/paw/containers/paw-kernel/components/terminal-frontend.md) | Press a key (for example `dd` on a clip) |
| [terminal-frontend](../systems/paw/containers/paw-kernel/components/terminal-frontend.md) | [kernel-loop](../systems/paw/containers/paw-kernel/components/kernel-loop.md) | Pass the key to the kernel |
| [kernel-loop](../systems/paw/containers/paw-kernel/components/kernel-loop.md) | [lua-api](../systems/paw/containers/paw-kernel/components/lua-api.md) | Run the Lua key mapping, which calls `paw.api` |
| [lua-api](../systems/paw/containers/paw-kernel/components/lua-api.md) | [session](../systems/paw/containers/paw-kernel/components/session.md) | Change the project as one undo step |
| [session](../systems/paw/containers/paw-kernel/components/session.md) | [project-model](../systems/paw/containers/paw-kernel/components/project-model.md) | Keep the new snapshot in the undo tree |
| [session](../systems/paw/containers/paw-kernel/components/session.md) | [engine-sync](../systems/paw/containers/paw-kernel/components/engine-sync.md) | Flush the difference between the two snapshots |
| [engine-sync](../systems/paw/containers/paw-kernel/components/engine-sync.md) | [engine-handle](../systems/paw/containers/paw-kernel/components/engine-handle.md) | Send only the engine messages that changed |
| [engine-handle](../systems/paw/containers/paw-kernel/components/engine-handle.md) | [audio-graph](../systems/paw/containers/paw-kernel/components/audio-graph.md) | Apply the messages between blocks on the audio thread |
| [terminal-frontend](../systems/paw/containers/paw-kernel/components/terminal-frontend.md) | [screen-and-scenes](../systems/paw/containers/paw-kernel/components/screen-and-scenes.md) | Show the cells Lua drew again |

