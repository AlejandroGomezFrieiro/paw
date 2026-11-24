---
type: C4 Component
title: One-shot tools
status: stable
groma:
  id: utau-one-shot-tools
  parent: paw-utau-engine
  code:
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/Convert.cs
      symbol: Convert
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/Export.cs
      symbol: Export
    - scanner: csharp
      file: extensions/utau/engine/PawUtau.Engine/Install.cs
      symbol: Install
  technology: C#
description: Command-line modes that convert other singing projects to paw, export vocal tracks to `.ustx`, and install singers.
---


