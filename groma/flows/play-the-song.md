---
type: Groma Flow
title: Play the song
groma:
  id: play-the-song
---

Space starts the transport; the audio device calls the engine for each block and the tracks play on the worker pool.

## Steps

| From | To | Action |
| --- | --- | --- |
| [musician](../actors/musician.md) | [terminal-frontend](../systems/paw/containers/paw-kernel/components/terminal-frontend.md) | Press `Space` two times |
| [terminal-frontend](../systems/paw/containers/paw-kernel/components/terminal-frontend.md) | [kernel-loop](../systems/paw/containers/paw-kernel/components/kernel-loop.md) | Pass the keys to the kernel |
| [kernel-loop](../systems/paw/containers/paw-kernel/components/kernel-loop.md) | [lua-api](../systems/paw/containers/paw-kernel/components/lua-api.md) | Run the play command |
| [lua-api](../systems/paw/containers/paw-kernel/components/lua-api.md) | [transport-and-live-input](../systems/paw/containers/paw-kernel/components/transport-and-live-input.md) | Start the transport |
| [transport-and-live-input](../systems/paw/containers/paw-kernel/components/transport-and-live-input.md) | [engine-handle](../systems/paw/containers/paw-kernel/components/engine-handle.md) | Send play to the engine |
| [audio-backends](../systems/paw/containers/paw-kernel/components/audio-backends.md) | [audio-graph](../systems/paw/containers/paw-kernel/components/audio-graph.md) | Ask for each block of sound |
| [audio-graph](../systems/paw/containers/paw-kernel/components/audio-graph.md) | [device-interface](../systems/paw/containers/paw-kernel/components/device-interface.md) | Process each track's chain of devices |
| [audio-backends](../systems/paw/containers/paw-kernel/components/audio-backends.md) | [linux-audio-and-midi](../externals/linux-audio-and-midi.md) | Play the mixed block on the sound device |

