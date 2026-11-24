---
type: C4 Actor
title: Musician
description: Records, edits, mixes and renders songs from the keyboard or the mouse.
status: stable
groma:
  id: musician
---

A musician on Linux who wants a modal, keyboard-driven DAW. Works in the terminal with motions, operators and Ex commands, or with the mouse in the graphical window; both show the same views.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [musician](musician.md) | [crates/paw-tui/src/terminal.rs](../../crates/paw-tui/src/terminal.rs) | Plays and edits | Keys in a terminal |
| [musician](musician.md) | [crates/paw-gui/src/main.rs](../../crates/paw-gui/src/main.rs) | Edits with the mouse | Window |
