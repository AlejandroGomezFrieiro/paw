---
type: C4 Component
title: Engine protocol
status: stable
groma:
  id: utau-protocol
  parent: paw-utau-engine
  code:
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Protocol/CcShape.cs
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Protocol/Framing.cs
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Protocol/Messages.cs
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Protocol/NotePayload.cs
  technology: C#, MessagePack
description: 'The wire protocol between the engine and the `utau` extension: framing, messages, note payloads, curve shapes.'
---

Length-prefixed MessagePack frames; the Lua side is `extensions/utau/lua/utau/proto.lua`.
