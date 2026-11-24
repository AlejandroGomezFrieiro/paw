---
type: C4 Component
title: Phrase rendering
status: stable
groma:
  id: utau-rendering
  parent: paw-utau-engine
  code:
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/RenderScheduler.cs
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/AiPitch.cs
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/Unison.cs
  technology: C#
description: Renders phrases one at a time and pushes the audio back to the extension, with AI pitch and unison voices.
---


