---
type: Groma Flow
title: An assistant works on a song
groma:
  id: an-assistant-works-on-a-song
---

An AI assistant uses paw-mcp's tools; each change goes to the kernel through the control socket and is one undo step.

## Steps

| From | To | Action |
| --- | --- | --- |
| [ai-assistant](../externals/ai-assistant.md) | [mcp-server](../systems/paw/containers/paw-mcp/components/mcp-server.md) | Call a tool, for example add a track with a riff |
| [mcp-server](../systems/paw/containers/paw-mcp/components/mcp-server.md) | [mcp-tools](../systems/paw/containers/paw-mcp/components/mcp-tools.md) | Check the arguments and run the tool |
| [mcp-tools](../systems/paw/containers/paw-mcp/components/mcp-tools.md) | [mcp-kernel-link](../systems/paw/containers/paw-mcp/components/mcp-kernel-link.md) | Call the kernel |
| [mcp-kernel-link](../systems/paw/containers/paw-mcp/components/mcp-kernel-link.md) | [control-client](../systems/paw/containers/paw-kernel/components/control-client.md) | Send the call |
| [control-client](../systems/paw/containers/paw-kernel/components/control-client.md) | [control-socket](../systems/paw/containers/paw-kernel/components/control-socket.md) | Deliver one JSON line |
| [control-socket](../systems/paw/containers/paw-kernel/components/control-socket.md) | [kernel-loop](../systems/paw/containers/paw-kernel/components/kernel-loop.md) | Queue the call for the kernel's turn |
| [kernel-loop](../systems/paw/containers/paw-kernel/components/kernel-loop.md) | [lua-api](../systems/paw/containers/paw-kernel/components/lua-api.md) | Run the edit |
| [lua-api](../systems/paw/containers/paw-kernel/components/lua-api.md) | [session](../systems/paw/containers/paw-kernel/components/session.md) | Change the project as one undo step |

