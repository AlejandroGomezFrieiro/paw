---
type: Groma Flow
title: Edit in the graphical window
groma:
  id: edit-in-the-graphical-window
---

The window holds no project state: a gesture goes to the kernel as a call, and the kernel pushes back the scenes that changed.

## Steps

| From | To | Action |
| --- | --- | --- |
| [musician](../actors/musician.md) | [window-shell](../systems/paw/containers/paw-gui/components/window-shell.md) | Drag a clip with the mouse |
| [window-shell](../systems/paw/containers/paw-gui/components/window-shell.md) | [kernel-connection](../systems/paw/containers/paw-gui/components/kernel-connection.md) | Send the gesture as a `paw.frontend.act` call |
| [kernel-connection](../systems/paw/containers/paw-gui/components/kernel-connection.md) | [control-client](../systems/paw/containers/paw-kernel/components/control-client.md) | Send the call |
| [control-client](../systems/paw/containers/paw-kernel/components/control-client.md) | [control-socket](../systems/paw/containers/paw-kernel/components/control-socket.md) | Deliver one JSON line |
| [control-socket](../systems/paw/containers/paw-kernel/components/control-socket.md) | [kernel-loop](../systems/paw/containers/paw-kernel/components/kernel-loop.md) | Queue the call for the kernel's turn |
| [kernel-loop](../systems/paw/containers/paw-kernel/components/kernel-loop.md) | [lua-api](../systems/paw/containers/paw-kernel/components/lua-api.md) | Run the gesture's Lua, which snaps and edits |
| [lua-api](../systems/paw/containers/paw-kernel/components/lua-api.md) | [session](../systems/paw/containers/paw-kernel/components/session.md) | Make the undo step |
| [screen-and-scenes](../systems/paw/containers/paw-kernel/components/screen-and-scenes.md) | [scene-model](../systems/paw/containers/paw-kernel/components/scene-model.md) | Record the redrawn view as scene nodes |
| [window-shell](../systems/paw/containers/paw-gui/components/window-shell.md) | [scene-painter](../systems/paw/containers/paw-gui/components/scene-painter.md) | Paint the changed scene nodes |

