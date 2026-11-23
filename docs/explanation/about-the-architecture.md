# About the architecture

<!-- tags: architecture -->

paw has a small kernel written in Rust and a runtime written in Lua. The
kernel holds the project, the audio engine and the plugin hosts, and the
Lua runtime holds the views, the keys and the commands. The frontends, which
are the terminal and the graphical window, show what Lua draws and send your
input to the kernel. The page explains how the parts connect and why they
are split the way they are. The diagram shows the two threads and the data
that moves between them.

```
            ┌────────────── main thread ──────────────┐        ┌─ audio thread ─┐
 terminal ─▶│ keys ─▶ Lua runtime ─▶ paw.api          │  msgs  │                │
 socket   ─▶│         (views, keys,   │               │ ─────▶ │    Engine      │
            │          commands)      ▼               │        │ parts,devices │
 terminal ◀─│ cell grid ◀── render   Session          │ ◀───── │ clips,transport│
            │                 project ─▶ sync ────────┼─ garbage, meters, position
            └─────────────────────────────────────────┘        └────────────────┘
```

The kernel is the `paw-core` crate, and it drives the audio engine
(`paw-engine`) and the plugin hosts (`paw-plugins`). The terminal frontend
and the `paw` program are in `paw-tui`. The graphical window is `paw-gui`,
and it is a client of the control socket. [The source tree](../reference/source-tree.md)
lists every crate and folder.

## The project is plain data

Parts, devices and clips are kept behind `Arc`, which is Rust's shared
pointer, so an edit makes a copy of only the part that it changes. Undo is
a tree of snapshots that share all the parts that did not change. If you
undo and then make a change, paw starts a new branch and keeps the old one.

## One path to the engine

All changes go to the engine through one function, `sync`, which compares
two snapshots and sends the engine messages and change events. Edits, undo,
project loads and offline renders all go through `sync`, so the engine
always agrees with the project.

## The audio thread never allocates memory

The main thread builds everything that the audio thread uses, and it sends
it through a queue that has no locks. The audio thread sends back what it
no longer uses, and the main thread frees it.

## Worker threads and a fixed order of the mix

Worker threads process the parts that do not feed each other at the same
time. Then one thread adds their outputs in a fixed order, so a rendered
file has the same bytes on one thread or on sixteen threads.

## The screen is a grid of cells

Lua draws into a grid of cells, and a frontend shows the grid. A frontend
only shows cells and sends input. The graphical window gets the same
drawing as scenes, and a scene that is turned into cells gives the same
grid.

## Lua passes only plain data to the kernel

The `paw.api` functions take and return plain data only, so the socket can
send the data without changes. When the Lua runtime loads again, no
reference to old Lua data is left behind.
