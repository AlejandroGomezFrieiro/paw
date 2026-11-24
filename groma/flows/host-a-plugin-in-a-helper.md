---
type: Groma Flow
title: Host a plugin in a helper
groma:
  id: host-a-plugin-in-a-helper
---

A third-party plugin runs in its own `paw` helper process, so a crash or hang stops only that plugin.

## Steps

| From | To | Action |
| --- | --- | --- |
| [audio-graph](../systems/paw/containers/paw-kernel/components/audio-graph.md) | [device-interface](../systems/paw/containers/paw-kernel/components/device-interface.md) | Process the plugin's device in the track chain |
| [plugin-sandbox](../systems/paw/containers/paw-kernel/components/plugin-sandbox.md) | [device-interface](../systems/paw/containers/paw-kernel/components/device-interface.md) | Stand in for the plugin on the audio thread |
| [plugin-sandbox](../systems/paw/containers/paw-kernel/components/plugin-sandbox.md) | [plugin-host-server](../systems/paw/containers/paw-kernel/components/plugin-host-server.md) | Hand the block over shared memory and wait at most about one block |
| [plugin-host-server](../systems/paw/containers/paw-kernel/components/plugin-host-server.md) | [clap-host](../systems/paw/containers/paw-kernel/components/clap-host.md) | Process the block in the hosted CLAP plugin |
| [clap-host](../systems/paw/containers/paw-kernel/components/clap-host.md) | [third-party-plugins](../externals/third-party-plugins.md) | Call the plugin's process function |

