---
type: C4 Component
title: Window chrome
status: stable
groma:
  id: window-chrome
  parent: paw-gui
  code:
    - scanner: rust
      file: crates/paw-gui/src/chrome.rs
    - scanner: rust
      file: crates/paw-gui/src/menu.rs
    - scanner: rust
      file: crates/paw-gui/src/dialogs.rs
    - scanner: rust
      file: crates/paw-gui/src/portal.rs
    - scanner: rust
      file: crates/paw-gui/src/widgets.rs
    - scanner: rust
      file: crates/paw-gui/src/icons.rs
    - scanner: rust
      file: crates/paw-gui/src/theme.rs
  technology: Rust, egui
description: Transport bar, status line, menus, dialogs, widgets, icons and the theme of the window.
---

Menus come from the kernel (`paw.frontend.menu`); file dialogs are asked of the desktop through the XDG portal.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-gui/src/portal.rs](../../../../../../crates/paw-gui/src/portal.rs) | [desktop-portal](../../../../../externals/desktop-portal.md) | Asks for file dialogs | D-Bus |
