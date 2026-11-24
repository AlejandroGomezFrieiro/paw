---
type: C4 Component
title: Engine host
status: stable
groma:
  id: utau-engine-host
  parent: paw-utau-engine
  code:
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/Program.cs
      symbol: Program
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/Options.cs
      symbol: Options
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/EngineHost.cs
      symbol: EngineHost
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/Bootstrap.cs
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/Connection.cs
      symbol: Connection
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/IEngineConnection.cs
      symbol: IEngineConnection
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/PumpScheduler.cs
      symbol: PumpScheduler
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/InternalAccess.cs
      symbol: OuInternals
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/ToolMirror.cs
  technology: C#
description: 'Process lifetime: bootstraps OpenUtau, connects to the extension''s socket and serves frames.'
---

Runs OpenUtau's document manager on a single pump thread in place of its UI thread, reaches the few OpenUtau internals it needs by validated reflection, and links the user's resampler and wavtool folders.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/utau/engine/PawUtau.Engine/EngineHost.cs](../../../../../../extensions/utau/engine/PawUtau.Engine/EngineHost.cs) | [extensions/utau/engine/PawUtau.Engine/Session.cs](../../../../../../extensions/utau/engine/PawUtau.Engine/Session.cs) | Serves frames | C# call |
| [extensions/utau/engine/PawUtau.Engine/Program.cs](../../../../../../extensions/utau/engine/PawUtau.Engine/Program.cs) | [extensions/utau/engine/PawUtau.Engine/Convert.cs](../../../../../../extensions/utau/engine/PawUtau.Engine/Convert.cs) | Runs one-shot modes | C# call |
