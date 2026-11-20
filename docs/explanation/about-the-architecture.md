# About the architecture

<!-- tags: architecture -->

paw has a small kernel in Rust and a runtime in Lua. The kernel holds the
project, the audio engine and the plugin hosts. The Lua runtime holds the
views, the keys and the commands. The frontends (the terminal and the
graphical window) show what Lua draws and send the input to the kernel. This
page tells how these parts connect and why. The diagram shows the two
threads and the data that moves between them.

```
            ┌────────────── main thread ──────────────┐        ┌─ audio thread ─┐
 terminal ─▶│ keys ─▶ Lua runtime ─▶ paw.api          │  msgs  │                │
 socket   ─▶│         (views, keys,   │               │ ─────▶ │    Engine      │
            │          commands)      ▼               │        │ tracks,devices │
 terminal ◀─│ cell grid ◀── render   Session          │ ◀───── │ clips,transport│
            │                 project ─▶ sync ────────┼─ garbage, meters, position
            └─────────────────────────────────────────┘        └────────────────┘
```

The kernel is `paw-core`. It drives the audio engine (`paw-engine`) and
the plugin hosts (`paw-plugins`). The terminal frontend and the `paw`
binary are `paw-tui`. The graphical window is `paw-gui`, a client of the
control socket. [The source tree](../reference/source-tree.md) lists every
crate and folder.

The design obeys these rules:

- **The project is plain data.** Tracks, devices and clips are behind `Arc`,
  and an edit makes a copy of only what it changes. Undo is a tree of
  snapshots that share all the unchanged parts. If you undo and then make a
  change, paw starts a new branch and keeps the old one.
- **One path to the engine.** `sync` compares two snapshots and sends engine
  messages and change events. Edits, undo, project loads and offline renders
  all go through `sync`. So the engine always agrees with the model.
- **The audio thread never allocates.** The main thread builds all that the
  audio thread uses and sends it through a lock-free queue. The audio thread
  sends back what it does not use, and the main thread frees it.
- **Many threads, one sound.** Worker threads process the tracks that do not
  feed each other at the same time. Then one thread adds their outputs in a
  fixed order. So a rendered file has the same bytes on one thread or on
  sixteen threads.
- **The screen is a grid of cells.** Lua draws into the grid and a frontend
  shows it. A frontend must only show cells and send the input. The
  graphical window gets the same drawing as scenes. A scene that is lowered
  to cells is the same grid.
- **`paw.api` passes plain data only.** So the socket can send the data
  as it is. When Lua loads again, no reference to old Lua data stays.
