---
type: C4 System
title: Language servers
description: Programs such as MIDI LSP that extensions start to report problems in the music.
status: stable
groma:
  id: language-servers
  technology: LSP over a child process
---

The `midilsp` extension registers MIDI LSP as an entry of `paw.lsp`; the kernel starts it as a helper process and the Lua runtime talks to it.
