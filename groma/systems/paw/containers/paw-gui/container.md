---
type: C4 Container
title: paw-gui (graphical window)
status: stable
groma:
  id: paw-gui
  parent: paw
  technology: Rust, egui, winit, OpenGL (glow)
description: 'The graphical frontend: shows the kernel''s views as panes in a window for the mouse.'
---

A client of the kernel's control socket that keeps no project state. With `--socket` it attaches to a running kernel; otherwise it starts a headless `paw` of its own and stops it on exit. The kernel pushes the state and the scenes to draw when they change; each key and gesture goes back to the kernel as a call, so a gesture means the same in every frontend. Draws only when something changes.
