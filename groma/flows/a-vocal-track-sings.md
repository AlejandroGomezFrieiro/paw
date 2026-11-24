---
type: Groma Flow
title: A vocal track sings
groma:
  id: a-vocal-track-sings
---

The utau extension starts its singing engine as a helper; the engine mirrors the vocal notes into OpenUtau and sends rendered phrases back.

## Steps

| From | To | Action |
| --- | --- | --- |
| [lua-api](../systems/paw/containers/paw-kernel/components/lua-api.md) | [helper-processes](../systems/paw/containers/paw-kernel/components/helper-processes.md) | The extension starts the engine through `paw.api` |
| [helper-processes](../systems/paw/containers/paw-kernel/components/helper-processes.md) | [utau-engine-host](../systems/paw/containers/paw-utau-engine/components/utau-engine-host.md) | Start `paw-utau-engine`, which connects to the extension's socket |
| [utau-engine-host](../systems/paw/containers/paw-utau-engine/components/utau-engine-host.md) | [utau-session](../systems/paw/containers/paw-utau-engine/components/utau-session.md) | Serve the note and lyric frames |
| [utau-session](../systems/paw/containers/paw-utau-engine/components/utau-session.md) | [utau-protocol](../systems/paw/containers/paw-utau-engine/components/utau-protocol.md) | Decode the messages and mirror the notes |
| [utau-session](../systems/paw/containers/paw-utau-engine/components/utau-session.md) | [utau-rendering](../systems/paw/containers/paw-utau-engine/components/utau-rendering.md) | Render the changed phrases and push their audio back |

