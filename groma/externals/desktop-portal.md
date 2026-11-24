---
type: C4 System
title: Desktop portal
description: The desktop's own file dialogs, used by the window.
status: stable
groma:
  id: desktop-portal
  technology: XDG desktop portal over D-Bus
---

The graphical window asks `org.freedesktop.portal.FileChooser` for open and save dialogs instead of linking a toolkit.
