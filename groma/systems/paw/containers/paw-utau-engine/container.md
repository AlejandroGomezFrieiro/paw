---
type: C4 Container
title: paw-utau-engine (singing engine)
status: stable
groma:
  id: paw-utau-engine
  parent: paw
  technology: C#, .NET 10, OpenUtau.Core, MessagePack
description: The .NET program that sings vocal tracks for the `utau` extension, hosting OpenUtau.Core.
---

Native part of the `utau` extension. The extension starts it and it connects to the extension's listening Unix socket, then mirrors the vocal tracks into an OpenUtau project, phonemizes and renders phrases with OpenUtau's engines (classic UTAU voicebanks, DiffSinger, ENUNU, Vogen, VOICEVOX) and pushes the audio back. It also has one-shot modes to convert, export and install singers.
