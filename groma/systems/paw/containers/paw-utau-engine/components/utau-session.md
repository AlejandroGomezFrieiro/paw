---
type: C4 Component
title: Engine session
status: stable
groma:
  id: utau-session
  parent: paw-utau-engine
  code:
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/Session.cs
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/ProjectMirror.cs
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/NoteMapper.cs
      symbol: NoteMapper
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/Lists.cs
      symbol: Lists
  technology: C#
description: One connection's protocol state and its mirror of the vocal tracks as an OpenUtau project.
---

Maps paw notes and their payloads to OpenUtau notes, applies changes through OpenUtau commands so phonemizers run, and lists singers, phonemizers and renderers.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/utau/engine/PawUtau.Engine/Session.cs](../../../../../../extensions/utau/engine/PawUtau.Engine/Session.cs) | [extensions/utau/engine/PawUtau.Engine/RenderScheduler.cs](../../../../../../extensions/utau/engine/PawUtau.Engine/RenderScheduler.cs) | Schedules renders | C# call |
| [extensions/utau/engine/PawUtau.Engine/Session.cs](../../../../../../extensions/utau/engine/PawUtau.Engine/Session.cs) | [extensions/utau/engine/PawUtau.Protocol/Messages.cs](../../../../../../extensions/utau/engine/PawUtau.Protocol/Messages.cs) | Decodes messages | MessagePack |
