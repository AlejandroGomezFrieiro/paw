# The devices graph: a design

Superseded where it differs by [architecture-plan.md](architecture-plan.md) (2026-11-23).

Status: design only, for the owner's approval. Date: 2026-11-23.
Writer: a design agent. Style: ASD-STE100 (internal text).

The owner asked for a new `devices` view. The view must support a graph of
devices, as Paranormal FX Router does in REAPER. The owner asked for three
things:

- (a) a Vim-like grammar for graphs,
- (b) a good display in the terminal,
- (c) the same power as the current device panel, and more.

The sections below give the research, the design, the sketches and the plan.
The HTML sketch is in the scratchpad (`devices-graph/sketch.html`).

## Rust refinement (2026-11-23)

[The Rust refinement](rust-architecture.md) changes the Rust shapes of this design. What changed:

- Ids are `newtypes` (`DeviceId`, `NodeId`); a link target is `(DeviceId, ParamKey)`, not `(Id, String)`.
- A split kind is an open name, `KindId<SplitFamily>`; the compiler resolves it in the registry (`SplitImpl`). No `enum` of kinds in the model; no `meta` on a split.
- `GraphPlan` keeps all buffers in one `Box<[f32]>`, uses a `Buf` `newtype`, and only `compile` makes one.
- The graph module knows no track: edits take a graph and give a graph, and the engine message names a processor slot.
- The chain crate is `chain-syntax` on `rowan` with a hand-written parser that recovers, and `lsp-server` for the language server. The grammar header names no track.

## 1. Summary of the decisions

1. **A tree, not free cables.** The chain of a track becomes a
   series-parallel tree: serial nodes, and containers that split the
   signal into branches and sum it again. Each DAW that we studied uses
   this model for its chain (Bitwig containers, Ableton racks, REAPER
   containers, Paranormal, Snap Heap, `Multipass`, PatchWork). A tree has no
   crossed cables. It maps to Vim: a branch is a line, a container is a
   pair of brackets, a part of the tree is a text object. A free graph with cables
   (Bitwig Grid, Pd) is a different tool. It can come later as an
   extension.
2. **One split, many kinds.** A container is a split with a kind:
   `chain`, `layer`, `band`, `ms`, `lr`, `key`, `vel`, `select` and
   `outs`. A kind is a splitter (a device with N output pairs) and a
   merger (`sum`, `ms`, `lr`). So an extension can add a kind (a transient
   split, a gate split) with a Lua or `Wasm` device that has N outputs. This
   is the generic core change.
3. **The topology is separate from the devices.** `Track.devices` stays
   the flat list of devices. A new `Track.graph` holds the topology by
   device ids. `None` means "serial, in the order of the list". So all the
   code that reads `devices` today (freeze, history, routing, lanes,
   attachments) continues to work.
4. **The engine runs a plan.** The main thread compiles the tree into a
   flat plan of operations on buffers that it allocates. It sends the
   plan with one message (`Msg::SetGraph`), as `Msg::SetChain` does
   today. The audio thread only reads the plan. The old plan comes back as
   garbage. No lock, no allocation, no wait.
5. **One view, two layouts.** The `devices` view draws a **flow** layout
   (signal from left to right, branches as stacked lanes) when the window
   is 72 columns wide or more. It draws an **outline** layout (an
   indented tree with rails, as `git log --graph` draws lanes) in a narrow
   window. An **inspector** under the graph shows the parameters of the
   node under the cursor. The inspector is the current panel. It keeps all
   its rows, keys and pictures.
6. **The grammar follows Vim and the key rule.** `h l` go along the
   signal, `j k` go across branches. `w b e` go from device to device in
   signal order. `%` jumps between a split and its merge. `[(` and `])` go
   to the start and the end of the container around the cursor. Text
   objects: `in` (a node), `ib` `ab` (a branch), `is` `as` (a split).
   Operators: `d y c p`, `gs` wraps in a split (as vim-surround `ys`),
   `ds` unwraps, `cs` changes the kind. `o` `O` add a parallel branch.
   `<<` `>>` and the operators `<` `>` move a node earlier or later in
   the signal: the order of the signal is its time. `H` `L` stay free.
   The five modes of paw keep their meaning: normal moves and changes
   values, insert adds nodes at a caret, visual selects, and the
   inspector is a window of its own (section "Modes").
7. **A text form.** `:e chain://Bass` opens the graph as text, one node
   on a line, with indents for branches. You edit it as text, and `:w`
   applies the change as one undo step, as oil.nvim does for files. The
   ids in the text keep the state, the lanes and the links of each device.
8. **Modulation in the containers.** Each container (also the root) has a
   modulation lane: macros, LFOs, envelope followers, MIDI sources. A
   link goes from a source to a parameter in the same container, with a
   depth. `gm` links. `]` `[` on a modulated parameter change the depth.
   CLAP plugins get the modulation as `CLAP_EVENT_PARAM_MOD`, which does
   not change the saved value.
9. **Racks and templates for large chains.** A rack is a named group of
   devices in series that folds to one card, with its own macros.
   Containers start folded, and the top level wraps like text, so a chain
   of 20 devices fits in a few rows. A template is a saved rack with the
   keys that it needs. A load is a copy, or a linked rack on request.
   The section "Evaluation with three metal chains" gives the reasons.

## 2. What exists today

### 2.1 The current view

`runtime/lua/paw/views/devices.lua` (598 lines) and
`runtime/lua/paw/device_rows.lua` give the device panel. The panel is one
column of rows: the heading of a device, its picture (EQ curve, gain
reduction, loudness, tuner), its parameters, then the add line, the output
and the sends. A real screen of a track with five devices (120 x 40):

```text
│▌ Devices  Bass                      5
│▌▾ Synth ▾                  ↑ ↓ ×  on
│  wave         ━━━●──────      saw A L
│  attack       ━━●───────     5 ms A L
│  ...          (10 rows of the synth)
│ ▾ EQ ▾                     ↑ ↓ ×  on
│                               +18 dB
│  🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭🬭
│  1 On         ●─────────      Off A L
│  ...          (42 rows of the EQ)
│ + add a device
│ → Master ▾                    + send
│ ↗ Reverb   ━━━━━━━━●──  -9.0 dB  pre×
```

What we saw on the screen:

- The panel shows the synth and a part of the EQ. The compressor, the
  saturation and the delay are below the screen. You cannot see the chain
  as a whole.
- The panel is good for one device. It is bad for the shape of the chain.
- A side-chain and the further outputs are words on the heading of a
  device (`key Kick`, `outs 2/6`). You do not see them as connections.

### 2.2 What the current view can do (the parity list)

The new view must keep each of these. The parity table (section "Parity") maps each one.

| Group | Features |
| --- | --- |
| Motion | `j k`, `w b e`, `gg G`, `f` (find a parameter), `t` (the last parameter changed) |
| Values | `+ -` with counts, `c` (type a value: `-6`, `+=2`), `x` (default), `A` (automate), `Enter`/`gC` (curve), learn (`L`) |
| Devices | `a` (add), `dd`, `yy`, `p P`, `y` over parameters then `p` (copy settings), `gcc` (bypass), `V`, `.`, `Alt-j Alt-k` (move), `:device.copy_to`, `:device.move_to` |
| Presets | `c` on a device, `[p ]p`, `<Space>dw`, `<Space>dW` |
| Routing | `gS` (side-chain), `O` (further outputs), `:device.spread`, the output and sends rows |
| Windows | `ge` (plugin window), `K`, `s` (solo the track), `\p` (pin), `devices://Bass` in more windows |
| Display | pictures (EQ curve, GR, loudness, tuner), live values of automated parameters, wet on the heading, state chips (`offline`, `stopped`) |
| Pointer | click, drag of a slider (touch automation), double-click (default), wheel, drag a device to move or copy it, menus |

### 2.3 The model in the kernel and the engine

- `paw-core/src/model.rs`: `Track.devices: Vec<Arc<DeviceInst>>`. A
  `DeviceInst` has `sidechain: Option<Id>`, `sidechain_pre`, and
  `outputs: BTreeMap<u32, Id>` (pair number to track).
- The host puts `fx_wet` and `fx_gain` around each device
  (`paw-engine/src/host.rs`). The dry signal waits for the latency of the
  device.
- `paw-engine/src/engine/msg.rs`: `Msg::SetChain { track, chain:
  Box<[DeviceSlot]> }`. `work.rs::run_chain` runs the slots in order on the
  two buffers of the track. Devices at rest sleep through silence.
- `Msg::SetKey` and `Msg::SetOutputs` give a device its side-chain buffer
  and its further output buffers.
- Delay compensation works between tracks (sends, outputs, side-chains).
  It does not work inside a chain, because a chain has one path.
- On disk: `tracks/<name>/devices.json` holds the chain, with a `.state`
  file for each plugin. A chain file can come from outside the project.
- The model has no container, no split and no modulator today. TASK-86
  (drivers) and TASK-75 (MIDI modifier stacks) are near. The modulation section
  tells how this design relates to them.

## 3. Research: how others do it

Sources are at the end of the section. "Keys" means how well it works
from the keyboard.

| Product | Model | What it does well (power) | Keys |
| --- | --- | --- | --- |
| Paranormal FX Router (REAPER script by `Sexan`, v1.46) | A drawing of REAPER 7 containers and parallel FX, top to bottom. `+` adds in series, `\|\|` adds in parallel. | Split kinds: frequency (2 to 5 bands), mid-side setup, transient, gate, envelope splitters. Volume, pan and dry/wet per lane. Solo in lane, mute. Enclose in a container, explode a container, collapse and expand. LFOs. Zoom. Drag to move, copy or replace. | Mouse first. A few keys (`Z`, `C`, `B`, `Del`, `Home`, `Space`). |
| Bitwig containers | Chain, FX Layer, FX Selector, `Multiband` FX-2 and FX-3, Mid-Side Split, Stereo Split, XY FX, Instrument Layer and Selector, Note FX Layer. | A small set of kinds that cover most needs. A mixer per chain. Modulators on any device, with their targets inside it. Selector modes: manual, round-robin, keyswitch, CC, program change. | Mouse first. |
| Bitwig Grid | A modular patch: any output to any input. Pre-cords make common links. | Full freedom, audio-rate modulation, 230+ modules. | Mouse only. |
| Ableton racks | Chains in a list. Zones by key, velocity and chain select. 16 macros, variations, randomize. Racks nest. | Chain select as one value that a macro can move. Macros as the face of a rack. A rack folds into a title bar. | Arrow keys go through the chain list. Grouping is an item of a menu. |
| REAPER | FX chain, parallel FX (`\|\|` marker), FX containers (nest), the pin connector with 64 channels per track. | The pin connector can do any routing. Parameter modulation and links on any parameter. | Many actions, but the pin connector is a grid of pins for the mouse. |
| SideFX (REAPER 7) | Racks of up to 16 parallel chains, each a container, summed by a mixer JSFX. | Volume, pan, mute and solo per chain. LFOs with a mod matrix (depth, two-sided, bake to automation). Presets of the full chain with its modulators. | Mouse first. |
| `Kilohearts` Snap Heap and `Multipass` | Lanes from left to right (Snap Heap: up to 7). `Multipass`: up to 5 bands, a lane before and a lane after. | One split for all bands keeps the phase. A modulation lane at the bottom: LFOs, envelopes, macros, pitch tracker, MIDI. | Mouse only. |
| Blue Cat PatchWork | 8 slots before, up to 8 parallel chains, 8 slots after. | Gain, solo and phase per chain. Side-chain input. Macros. | Mouse only. |
| Reason rack | The rack has a front and a back. `Tab` turns it. Cables on the back. Auto-routing makes the usual cables. | The back panel shows each connection. Auto-routing makes the common case free. | `Tab` to turn the rack, the rest is the mouse. |
| Renoise | A DSP chain under each track. `Doofer` (a container with macros), Splitter (two chains). | A tracker: the effects also have columns in the pattern. | Keyboard first, but the DSP chain is a mouse area. |
| Pd | A patch is a text file: `#X obj` lines and `#X connect a o b i` lines. | The graph is text, so a script can make it. | Not made to edit by hand. |
| `git log --graph`, `tig` | Lanes of a DAG as rails in text: `\| * \|`, `\|/`. | A graph with parallel lines in a grid of cells, readable at 80 columns. | A display only. |
| Orca | A grid of letters. Each letter is an operator. Operators act on their neighbors. | A grid editor that works in a terminal. | Keyboard only, with a cursor and a selection. |

What we take:

- From **Paranormal**: the two inserts (serial and parallel), "enclose"
  and "explode", solo in lane, a volume per lane, splitters as a list of
  kinds, collapse.
- From **Bitwig**: the short list of container kinds, modulators that
  live in a container and act on its inside, and the selector.
- From **Ableton**: macros as the face of a container, zones by key and
  velocity, chain select, and a fold to one line.
- From **`Multipass`**: one crossover for all bands, and a modulation lane
  under the lanes.
- From **SideFX**: a mod matrix with depth, polarity and bake, and a
  preset of a whole graph with its modulators.
- From **Reason**: show the connections (side-chain, outputs) as wires,
  but make the usual connections without a gesture.
- From **`git log --graph`**: rails in cells for the narrow layout.
- From **Pd** and **oil.nvim**: the graph is text that you can edit.
- No product has a keyboard grammar for its graph. This is the gap that
  paw fills.

Sources:

- Paranormal FX Router: the script source,
  <https://github.com/GoranKovac/ReaScripts/tree/master/ParanormalFX>
  (`Sexan_ParaNormal_FX_Router.lua` v1.46 and `Modules/`); Sound On Sound,
  <https://www.soundonsound.com/techniques/reaper-7-comparing-plug-ins-paranormal>;
  the REAPER forum thread on tree views,
  <https://forums.cockos.com/showthread.php?p=2725230>.
- Bitwig containers: <https://www.bitwig.com/userguide/latest/container>.
  The Grid: <https://www.bitwig.com/the-grid/>.
- Ableton racks: <https://www.ableton.com/en/manual/instrument-drum-and-effect-racks/>.
- SideFX: <https://conceptual-machines.github.io/SideFX/>.
- `Kilohearts`: <https://kilohearts.com/docs/multipass>,
  <https://kilohearts.com/docs/snap_heap>.
- Blue Cat PatchWork: <https://www.bluecataudio.com/Products/Product_PatchWork/>.
- Reason: <https://docs.propellerheads.se/reason9/RoutingAudioAndCV.15.5.html>,
  <https://docs.propellerheads.se/reason9/RoutingAudioAndCV.15.4.html>.
- Renoise: <https://tutorials.renoise.com/wiki/Doofer,_Splitter_%26_Notepad>.
- Pd file format: <https://github.com/sebpiq/pd-fileutils/blob/master/README.md>.
- Orca: <https://github.com/hundredrabbits/Orca>.

## 4. The model

### 4.1 Nodes

The graph of a track is a tree. Each node has a stable id.

| Node | What it is | Its values |
| --- | --- | --- |
| device | A device, as today. | Its parameters, `fx_wet`, `fx_gain`, bypass. |
| split | A container. It splits the signal into branches, runs each branch, and merges them. | `kind`, the values of the kind (crossovers, zones, index), `mix` (dry/wet of the whole container), `gain`, a name, macros, modulators. |
| branch | One path in a split: a list of nodes in series. | A name, `gain` (dB), `pan`, `mute`, `solo`, and for some kinds its zone or band. |

The root of a track is a split of kind `chain` with one branch. So the
root also has macros and modulators.

### 4.2 Split kinds

| Kind | Splitter | Merger | Branches | Values |
| --- | --- | --- | --- | --- |
| `chain` | none (one branch) | none | 1 | mix, gain |
| `layer` | copy | sum | 1 to 16 | gain, pan, mute, solo per branch |
| `band` | Linkwitz-Riley 24 dB/oct crossover, one for the whole split | sum | 2 to 6 | the crossovers (`120 Hz, 2 kHz`) |
| `ms` | mid and side | mid-side decode | 2 | |
| `lr` | left and right | each to its side | 2 | |
| `key` | copy of the audio, notes by key zone | sum | 1 to 16 | a key range per branch (`C1-B2`) |
| `vel` | copy of the audio, notes by velocity zone | sum | 1 to 16 | a velocity range per branch |
| `select` | one branch hears the input, with a fade | sum | 1 to 16 | `index` (it can have a lane), `fade` (ms), a mode: manual, round-robin, keyswitch, CC |
| `outs` | the output pairs of the node before the split (a drum plugin with a pair for each drum) | sum | one for each pair | |

- MIDI goes to each branch. `key` and `vel` filter the notes. So an
  instrument at the start of each branch of a `layer` is an instrument
  layer, and a `key` split is a keyboard split.
- A kind is a splitter device with N output pairs and a merger. The
  built-in kinds are built-in devices in `paw-engine/src/devices/split.rs`.
  An extension adds a kind with a device that has N outputs (a Lua device
  or, later, `Wasm`) and a merger from the three built-in mergers. For
  example: a transient split, a gate split, an envelope split, an XY
  morph. This is the generic core change that an extension needs.
- `outs` replaces the need to make tracks for the outputs of a drum
  plugin, when you only want effects on each drum. `:device.spread` stays
  for the case where you want faders.

### 4.3 Data on disk and in the kernel

```rust
pub struct Track {
    pub devices: Vec<Arc<DeviceInst>>,   // as today: every device of the track
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub graph: Option<Arc<Graph>>,       // None: serial, in the order of `devices`
    // ...
}

pub struct Graph { pub root: Split, pub mods: Vec<Modulator> }
pub struct Split { pub id: Id, pub kind: SplitKind, pub values: SplitValues,
                   pub branches: Vec<Branch>, pub macros: Vec<Macro>,
                   pub mods: Vec<Modulator>, pub meta: Map<String, Value> }
pub struct Branch { pub id: Id, pub name: String, pub gain: f64, pub pan: f64,
                    pub mute: bool, pub solo: bool, pub nodes: Vec<Node> }
pub enum Node { Device(Id), Split(Split) }
pub struct Link { pub source: Id, pub target: (Id, String), pub depth: f64,
                  pub bipolar: bool }
```

- A check in the kernel (`Graph::validate`) makes sure that each device
  of `devices` is in the graph one time, and that each id in the graph is
  a device of the track. A device that the graph does not name goes at
  the end of the root. So a script that adds a device to `devices` still
  works.
- `devices.json` gets a `graph` field. One node is one object. No change
  of format for a serial chain.
- Undo: the graph is part of the track, in an `Arc`, so the history keeps
  it as it keeps the rest. One user action is one undo step.
- Lanes: a branch value (`gain`, `pan`), a split value (`mix`, a
  crossover, `index`) and a macro have lanes, as a device parameter has.
  The lane target is `split:<id>:<key>`, beside the `param` target.

### 4.4 The engine: a plan, not a tree

The main thread compiles the tree into a `GraphPlan`:

```rust
pub struct GraphPlan {
    bufs: Box<[[Vec<f32>; 2]]>,          // allocated here, MAX_BLOCK each
    events: Box<[EventBuf]>,             // a copy of the notes for each branch
    ops: Box<[Op]>,                       // run in order on the audio thread
    delays: Box<[Delay]>,                 // latency compensation in branches
}
enum Op {
    Run { device: DeviceSlot, buf: u8, events: u8 },
    Copy { from: u8, to: u8 },
    Split { splitter: DeviceSlot, from: u8, to: Range<u8> },
    Filter { zone: Zone, from_events: u8, to_events: u8 },
    Delay { buf: u8, delay: u16 },
    Merge { merger: Merger, from: Range<u8>, to: u8, gains: GainSlot },
    Mix { dry: u8, wet: u8, mix: GainSlot },
    Tap { buf: u8, key: DeviceSlot },     // a side-chain from inside the graph
    Modulate { mods: Range<u16> },
}
```

- `Msg::SetGraph { track, plan: Box<GraphPlan> }` replaces
  `Msg::SetChain`. A serial chain compiles to `Run` ops on buffer 0, so it
  is the same work as today. A null test proves that the sound is the
  same to the bit.
- The state that must live through an edit (crossover filters, the fade
  of a selector, the smoothing of branch gains) is in device slots, not in
  the plan. A splitter is a device in a slot. So a new plan keeps the
  filter state, and a change of a value is a `SetParam`, not a new plan.
- A new plan is needed only when the topology changes. Then the track
  fades out and in over 5 ms, as a bypass does. A change of a value does
  not make a new plan.
- Buffers: the plan needs one stereo buffer for each branch that is open
  at the same time. The compiler reuses buffers along the depth of the
  tree. A graph of 64 nodes with 3 levels of splits uses about 8 buffers
  (8 x 2 x 2048 x 4 bytes = 128 kB).
- Latency: the compiler sums the latency of each branch. At a merge, it
  delays the shorter branches to the longest. The split reports its total
  latency to the track, so the delay compensation between tracks
  continues to work. The `mix` of a split delays its dry signal by the
  same amount, as the host does for one device.
- Devices at rest: the plan keeps the rule of `run_chain`. A branch whose
  input is silent and has no events lets its devices sleep. A branch that
  a `select` does not choose sleeps after its fade.
- Meters per node: the engine writes the peak of each device slot to a
  table of atomics that the main thread allocated (one writer for each
  slot, as `device_ran`). The view reads it as a live value.
- Threads: a track still runs on one thread. A wide split can run its
  branches on the pool later (open question 9). Not in the first version.

### 4.5 Side-chains, outputs and taps

- A side-chain from another track stays as it is (`DeviceInst.sidechain`).
- New: a **tap**. A device can take its key from a node of the same
  graph: `key=@7` takes the output of node 7. Example: a compressor in the
  low band that listens to the full signal before the split. The compiler
  puts a `Tap` op after node 7. It refuses a tap that comes later in the
  plan than its listener, with a clear message.
- A split can also have a key input: the side-chain of the split goes to
  each device in it that asks for a key and has none of its own.
- Further outputs to tracks stay as they are (`O`). The `outs` split gives
  the same pairs to branches in the graph.

### 4.6 Modulation

- Each split (also the root) has a modulation lane. A modulator is a node
  in that lane. A link goes from a modulator to a parameter of a node in
  the same split, at any depth. A link has a depth and a polarity.
- Kinds in the core: `macro` (a value with a lane, a name and a range),
  `lfo` (rate or sync, shape, phase, restart on a note), `follower` (an envelope
  follower on the input of the split, or on its key), `midi` (velocity,
  key, CC, pressure, pitch bend, MPE per note), `random` (sample and
  hold, with a smooth). An extension adds more (MSEG, step sequencer)
  with a Lua device that has a control output.
- The engine runs the modulators each 32 samples on the audio thread
  (`Op::Modulate`), and adds the result to the values of the targets:
  - built-in devices: an offset that the device reads with its smoother;
  - CLAP plugins: `CLAP_EVENT_PARAM_MOD`, which does not change the saved
    value;
  - VST3, LV2 and Lua devices: a new value each 32 samples, from the base
    value. The project keeps the base value.
- A macro is also a source for a lane, an assignment of a MIDI controller
  (`L`) and a control surface.
- `:mod.bake` writes a link as automation over a time selection, as
  SideFX does, and removes the link.
- TASK-86 (drivers) stays different: a driver is an expression on the
  main thread (time, tempo, another value). A modulator runs on the audio
  thread. A driver can have a macro as its target.

## 5. The grammar

The view has a cursor on a **node**: a device, a split, a branch head, a
modulator, or (in the inspector) a parameter. `Tab` moves the keyboard
between the graph and the inspector of the node. In the narrow outline
layout, the parameters open under the node with `zo`, as they do today.

### 5.1 Motions (only movement, with counts, also after an operator)

| Keys | Flow layout | Outline layout |
| --- | --- | --- |
| `l` `h` | The next and the previous node along the signal. At the end of a branch, `l` goes to the merge. At the start of a branch, `h` goes to the split. | Into the node (the first branch of a split, the parameters of a device) and out to its parent, as a file tree does. |
| `j` `k` | The same column in the next and the previous branch. Out of a split, the branch below or above, then the modulation lane. | The next and the previous row (signal order, depth first). |
| `w` `b` `e` | The next and the previous device in signal order, depth first. `e` the last device of this branch. The same in both layouts. | |
| `0` `^` `$` | The split at the start of this branch, its first device, its last node. | |
| `gg` `G` | The input and the output of the graph. | |
| `%` | From a split to its merge, and back (as `%` on a bracket). | |
| `[(` `])` | The split and the merge of the container around the cursor. A count goes out more levels: `2[(`. | |
| `Ctrl-d` `Ctrl-u` | Four branches down and up. | Half a screen. |
| `f` `t` | Find a parameter. The last parameter that you changed. As today. | |
| `/` `n` `N` | Find a node by name or kind (`/comp`). | |
| `` ` `` `'` | Marks on nodes (`ma`, `'a`), as in the other views. | |

### 5.2 Text objects

| Object | What it takes |
| --- | --- |
| `in` | The node under the cursor (a device, or a split with all its inside). |
| `ib` | The nodes of the branch, without the branch. `dib` empties the branch. |
| `ab` | The branch: its head and its nodes. `dab` removes the branch. |
| `is` | The inside of the split: all the branches, without the split. |
| `as` | The split, with its inside. `2as` the split around it. |
| `im` | The links of the parameter or the modulator under the cursor. |
| `ir` `ar` | The inside of the rack around the cursor, and the rack. |
| `ie` | The entire graph. |

In visual mode, the same object again takes one more, as in the other
views (`vab` then `ab` takes two branches).

### 5.3 Operators and actions

| Keys | Effect |
| --- | --- |
| `d` | Cut into a register: `dd` the node, `3dd` three nodes in series, `dab` the branch, `das` the split. On a parameter, `dd` sets the default (as today). On a link row, removes the link. |
| `y` | Copy into a register: `yy`, `yab`, `yas`. Over parameters, their settings (as today). |
| `p` `P` | Paste the register in series after or before the node. A register of parameter settings goes onto the device (as today). |
| `gp` `gP` | Paste the register as a new branch below or above. Out of a split, wrap the node in a `layer` first. |
| `a` | Add one device after the node, from the picker, in normal mode. (Today `a` adds at the end of the chain. In the arrange view and the mixer, `a` still adds at the end.) |
| `i` | Start insert mode before the node (see "Modes"). |
| `o` `O` | Add a new parallel branch below or above, and start insert mode in it. Out of a split, wrap the node in a `layer` with the node in branch 1 (the `\|\|` of Paranormal). |
| `gs{motion}{kind}` | Wrap in a split, as vim-surround `ys`: `gsinb` wraps the node in a band split, `gs3lr` wraps three nodes in a rack and asks for its name, `gsibl` wraps the inside of the branch in a `layer`. In visual mode: `gs{kind}`. The kind letters: `r` rack, `l` layer, `b` band, `m` mid/side, `s` stereo L/R, `k` key, `v` velocity, `x` select, `o` outs. A count gives the branches: `gsin3b` makes three bands. |
| `ds` | Unwrap the split around the cursor: keep the branch under the cursor in its place. The other branches go into the register. One undo step. |
| `cs{kind}` | Change the kind of the split: `csb` from layer to band. The branches stay. A kind that cannot take the number of branches gives a message. |
| `c` | An operator: cut what the motion takes, start insert mode at its place and open the picker. `cin` replaces a device and keeps its links and lanes where the parameters match. `cs{kind}`: see above. `cc` on a device: choose a preset (the key rule). `cc` on a container: a preset or a template. `cc` on a branch head: rename. |
| `>>` `<<` | Move the node later or earlier in the signal, in its branch. At the end of a branch, out of the split. Counts work: `3>>`. (Today `Alt-j` `Alt-k`.) `H` `L` stay free. |
| `>` `<` | The same as operators: `>ib`, `>ar`, and on a selection. |
| `Alt-j` `Alt-k` | Move the node to the next and the previous branch. In the outline layout, down and up (as today). |
| `+` `-` `Ctrl-a` `Ctrl-x` | The main value: a parameter; the wet mix of a device; the gain of a branch (dB); the mix of a split; the depth of a link; a macro. With a count. On a selection: on all of it. |
| `]` `[` | The second value: the output gain of a device; the pan of a branch; the upper crossover of a band branch; the index of a select split; the depth of the modulation of a parameter (when it has one link). |
| `=` | Gain match: set the output gain of the node so that its output is as loud as its input over the last 3 seconds of play (as the `L` button of a Bitwig Chain). `==` the node, `=ib` each node of a branch. |
| `gc` | Bypass: `gcc` the node, `gcab` mute the branch, `gcas` bypass the split. |
| `\s` | Solo the branch, alone (exclusive, as Paranormal). Again: no solo. `\S`: the solo follows the cursor, so `j` `k` compare the branches. |
| `s` `M` `r` | Solo, mute, arm the track (as in every view). |
| `gM` | Make the parameter a macro of the container around it, named after the parameter. In visual mode over parameters, one macro for all of them. |
| `\b` | Bypass the whole chain and keep the state of each node. Again: back. Level-matched with `paw.opt.ab_match`. |
| `\a` | Flip between two stored variants A and B of the chain. `:ab.store` stores the current state as the other variant. |
| `\i` | Show all the rows of the node in the inspector, not only the main ones. |
| `gm` | Modulate, an operator over parameters (in the inspector) or nodes (in the graph): choose a source of the container in a picker, and link it at 25 %. In visual mode, all of the selection. `.` links the next one. |
| `gS` `O` | The side-chain and the further outputs (as today). `gS` also lists the taps (`@node`) of the graph. |
| `ge` `K` `A` `gC` | As today: the plugin window, describe, automate, the curve. `K` also describes a split, a branch and a link (see "`K` on a split"). |
| `Enter` `Tab` | Go to the inspector window of the node (see "Modes"). |
| `x` `~` | Cut the node. Bypass the node. |
| `za` `zo` `zc` `zM` `zR` | Fold a container to one card, open it. A fold is part of the window, not an undo step. Containers start folded; the path to the cursor opens. |
| `/` `n` `N` | Find a device, a container, a branch or a kind by name. Opens the folds on the way. |
| `znn`, `zn{obj}` | Enter the split as a scope: the window shows only its inside, with a path at the top (`Bass › Smash › 2 Crush`). `zW` goes out. As the scopes of the arrange view. |
| `v` `V` `Ctrl-v` | Visual: `v` nodes in series in one branch. `V` whole branches. `Ctrl-v` a block: the same columns in several branches, for example the compressor of each band. Then `+` `-` `gc` `d` `y` `gs` act on all of it. On a block of devices of the same kind, the inspector shows one set of parameters, and a change moves them all by the same step. |
| `.` | Repeats the last change, as today. |
| `u` `Ctrl-r` | Undo and redo. One action is one step. |

### 5.4 Ex commands

| Command | Effect |
| --- | --- |
| `:wrap band 120 2k` | Wrap the node (or the selection) in a split. `:wrap layer 3` makes three branches. |
| `:unwrap`, `:unwrap all` | Unwrap and keep the branch of the cursor. `all`: put all the branches in series. |
| `:branch add Name`, `:branch remove`, `:branch solo` | Branches. |
| `:xover 120 2k` | Set the crossovers of a band split. |
| `:zone C1-B2`, `:zone 64-127` | Set the zone of a branch of a `key` or `vel` split. |
| `:mod lfo 1/4`, `:mod link Reverb.mix 20`, `:mod.bake` | Modulators and links. |
| `:macro Drive`, `:macro.link saturation.drive 12` | Macros. |
| `:rack.save [user\|project] Smash`, `:rack.load Smash` | Save a container (with its devices, links, macros and keys to fill) as a template, and load it. |
| `:rack.link`, `:rack.unlink`, `:rack.update`, `:rack.reset` | Link a rack to its template, make it a copy, pull a newer template into a copy, remove the overrides of a linked rack. |
| `:chain.copy Dbl`, `:chain.link Dbl` | Copy the whole graph to another track, or link the two. |
| `:keys` | List each key of the chain and where it comes from. |
| `:chain.save`, `:import ~/chains/amp/devices.json` | A whole graph, as the chain files of today. |
| `:e chain://Bass` | The graph as text (see "The text form"). |

Each command completes with `Tab`, says what it did, and gives a clear
message when it cannot act.

### 5.5 The text form

The section "The chain language" makes this text form a language of its
own, and changes the parser (Rust, not Teal) and the file on disk
(`devices.chain`, not `devices.json`). The rest of this section stays.

`:e chain://Bass` (also `chain://3`, `chain://` for the cursor track)
opens a text buffer. One node is one line. Indent shows the inside of a
split. A line that starts with `|` is a branch head. `#n` is the id.
`mods` lists the modulators of the split above it.

```text
# chain of Bass · :w applies · a line without #id is a new device
synth #1 wave=saw cutoff=4kHz
eq #2 b1.on=on b1.freq=80Hz
layer #7 "Smash" mix=100%
  | Dry gain=0dB
  | Crush gain=-6dB pan=0.1
    saturation #3 drive=12dB curve=tube
    reverb #4 mix=30% key=@2
band #8 xover=120Hz,2kHz
  | Low
    compressor #5 ratio=4 threshold=-18dB key=Kick
  | Mid
  | High
    saturation #6 drive=6dB
limiter #9 ceiling=-1dB
mods
  lfo #10 sync=1/4 shape=sine -> reverb#4.mix +20%, band#8.xover.2 +10%
  macro #11 "Crush" 35% -> saturation#3.drive +12dB, layer#7|Crush.gain +6dB
```

- `:w` compares the text with the graph and applies the difference as one
  undo step. A moved line moves the device with its state, lanes and
  links. A line without an id is a new device. A removed id is a removed
  device. A parameter that a line does not name keeps its value.
- An error names the line and the reason (`line 9: no device "compresor";
  did you mean compressor?`), and `:w` changes nothing.
- The parser is a Teal module (`paw/graph_text.tl`). A test reads and
  writes many graphs and requires the same text again (round trip).
- On disk, `devices.json` stays the truth (open question 2). A git
  `textconv` driver (`diff=paw-chain`, as `diff=paw-midi2` for clips)
  shows the text form in `git diff`.

### 5.6 Modes

The owner asked for a clear separation of modes in the graph, congruent
with the other views. paw has five modes in `paw.keymap`: normal (`n`),
visual (`x`, with the kinds `v`, `V`, `Ctrl-v`), after an operator
(`o`), insert (`i`) and a prompt (`c`). The graph adds no new mode. It
gives each of the five a clear meaning in the graph, as the piano roll
gives insert mode its pencil. A view state that changes what you hear is
not a mode: it shows as a chip in the header (see "States that are not
modes" below).

**The rule of the modes in the graph.**

- **Normal** moves over nodes and changes their values. It never adds a
  node. The only keys that add a node from normal mode are `a` (one
  device from the picker, as `a` does in every view) and `p` `P` `gp`
  (the register).
- **Insert** adds nodes. Each key inserts one node at a caret on a wire,
  as each key of the arrange view's insert mode inserts one item. All
  that you insert from the start to `Esc` is one undo step.
- **Visual** selects nodes, branches or a block, and then a key acts on
  all of the selection.
- **After an operator** a motion or a text object says what the
  operator acts on.
- **A prompt** (the picker, the command line, the keys to fill of a
  template) has the keyboard until `Enter` or `Esc`.

Each mode looks different, so you always know where you are:

| Mode | Status line | Cursor | Title of the view |
| --- | --- | --- | --- |
| Normal | `NORMAL` | The card under the cursor is filled in the color of the selection. | `Devices · Vocal` |
| Insert | `INSERT`, in the green of insert mode | A caret `┃` on the wire between two nodes. No card is filled. | `INSERT before ▣ Level · Vocal`, as the piano roll shows `DRAW C4 end` |
| Visual | `VISUAL`, `V-LINE`, `V-BLOCK` | The selected cards have the color of a selection, and the cursor card is filled. | `3 nodes`, `2 branches`, `3 x 1 block` |
| After an operator | `PENDING` | As in normal mode. | The operator: `d…` |
| Prompt | `COMMAND` | In the prompt. | As before the prompt |

#### Normal mode

The keys in "Operators and actions" are normal-mode keys, with these
changes for the modes:

| Keys | Effect | The same as |
| --- | --- | --- |
| `i` | Start insert mode with the caret before the node. On `out`, at the end of the chain. On an empty branch, in the branch. | `i` in the arrange view and in Vim. |
| `a` | Add one device after the node from the picker, and stay in normal mode. On `out`, at the end of the chain. | `a` in the arrange view, the mixer and the panel: "a device after". |
| `o` `O` | Add a new branch below or above, and start insert mode in it. Out of a split, wrap the node in a layer first, with the node in branch 1. `Esc` at once leaves an empty branch, which is the dry signal. | `o` in Vim. In the arrange view `o` adds a track below. |
| `c{motion}` | Cut what the motion takes into the register, start insert mode at its place, and open the picker. `cin` replaces a device; the new device keeps the links and lanes of the parameters with the same names. `cab` replaces a branch. | `c` in the arrange view: empties the time and opens a clip to enter notes. |
| `cc` | On a device: choose a preset. On a container: choose a preset or a template. On a branch head: rename. | The key rule: "On a device, choose a preset". |
| `x` | Cut the node into the register. | `x` on the row of a device in the panel. |
| `~` | Bypass the node, or let it play. | `~` switches a property; `gcc` does the same. |
| `Enter` | Go to the inspector window of the node (see "The inspector is a window"). | `Enter` opens what is under the cursor: a clip in the piano roll. |
| `Tab` | Go to the next window, so to the inspector. | `Tab` in the arrange view. |

#### Insert mode

Insert mode adds nodes at a caret. The caret is on a wire, before the
node where insert mode started. A node that you insert goes at the
caret, and the caret moves past it, so `ces` inserts a compressor, an EQ
and a saturation in series. A container goes at the caret, and the caret
moves into its first branch. The devices play as soon as you insert
them, so you hear each step.

| Key | Inserts or does |
| --- | --- |
| `c` `e` `s` `g` `l` | A compressor, an EQ, a saturation, a gate, a limiter. |
| `d` `r` `u` `m` | A delay, a reverb, a utility, a meter. |
| `R` | A rack. paw asks for its name on a short prompt; `Enter` keeps "Rack 1". |
| `L` `B` `M` `S` | A layer, a band split, a mid/side split, a left/right split. A count gives the branches: `3B` makes three bands. |
| `\|` | A new branch in the split around the caret, and the caret goes into it. Out of a split, it wraps what is before the caret in a layer (the `\|\|` of Paranormal). |
| `Tab` | The picker: devices, presets, racks and templates, with the preview. The choice goes at the caret. As `Tab` opens the snippets in the piano roll. |
| `Ctrl-r` and a register | The nodes of the register, at the caret. As in the piano roll. |
| `1` to `9` | A count for the next key. |
| The arrow keys | Move the caret along the wires and across branches. `→` at the end of a branch goes past the merge. The letters only insert, as in every insert mode. |
| `Backspace` | Take back the node that you inserted last. The caret goes back. |
| `Ctrl-u` | Take back all that this insert mode added. |
| `Ctrl-o` | One normal-mode command, then back to insert mode. |
| `K` | Show the insert keys and what each one adds. |
| `Enter` | Go to the inspector of the node that you inserted last, and stop insert mode. |
| `Esc` | Stop insert mode. paw says what it did: `inserted 3 devices, 1 band split`. |

- After a short time a box shows the insert keys, as in the arrange view.
- `paw.opt.graph_insertkeys` lists the keys that work. `paw.insert.add`
  takes `view = "devices"`, a device or a template and a preset, so
  `paw.insert.add("C", {view = "devices", template = "Parallel crush"})`
  puts a template on `C`.
- `.` in normal mode inserts the same nodes again at the cursor, as Vim
  repeats an insert.
- A letter with no node gives a message and the box. `h` `j` `k` `l` say
  "use the arrow keys, or `Esc` and move".

#### Visual mode

| Keys | What it selects | Example |
| --- | --- | --- |
| `v` | Nodes in series, in one branch, along the signal. | `v2w` the node and the next two. |
| `V` | Whole branches: the rows of the graph. | `Vj` two bands. |
| `Ctrl-v` | A block: the same columns in several branches. | The compressor of each band. |

On a selection: `d` `y` `x` cut and copy, `p` replaces it, `~` and `gc`
bypass, `+` `-` `]` `[` change the main and the second value of each
node, `>` `<` move it in the signal, `gs{kind}` wraps it, `gM` makes a
macro of a parameter that each node has, `gm` links a source to it, `=`
matches the gain, `J` joins selected branches into one series, `o` goes
to the other end, `gv` selects again, `:` starts `:'<,'>`. A block of
devices of the same kind shows one set of parameters in the inspector.

#### After an operator

The operators of the graph are `d` `y` `c` `>` `<` `=` `gc` `gs` `gm`
`gM` `zf` `zn`. The motions and text objects of "Motions" and "Text
objects" follow them. `Esc` cancels the operator.

#### The inspector is a window

v1 drew the inspector under the graph, in the same window, and the keys
had to guess where the cursor was. The inspector is now a window of its
own, under the graph. It is the device panel of today, narrowed to the
node under the cursor of the graph. So:

- In the graph window the keys act on nodes. In the inspector window
  they act on rows, with the keys of the panel of today: `j` `k` rows,
  `+` `-` the parameter, `c` types a value, `A` automates, `L` learns,
  `Enter` the curve, `f` finds a parameter, `V` selects parameters.
- `Enter` or `Tab` on a node goes to its inspector. `Ctrl-w p`, `Tab`
  or `Ctrl-w k` go back. The inspector follows the cursor of the graph.
- On a container, the inspector shows its macros, its modulators and its
  links. `gm{motion}` over parameters links a source to them, and `gM`
  makes a macro.
- `\p` pins the inspector to its node, as `\p` pins the panel to a track.
- At a height of less than 24 rows, the inspector closes, and `Enter`
  opens it as a float.

The inspector window removes the link mode of v1. To link a source to many parameters,
select them (`V` in the inspector, or `Ctrl-v` over nodes in the graph)
and press `gm`. `.` links the next one.

#### Other buffers

- The text form is a text buffer, with the modes of the text buffers of
  paw (`i` `a` `o` insert text). It is the same kind of buffer as
  `paw://track/2/devices`, so the design gives it that name too (see the
  questions).
- The picker, the command line and the keys to fill of a template are
  prompts. They close on `Esc`.

#### States that are not modes

The states below change what you hear and stay when the mode changes. Each
one shows as a chip in the header of the view, in the color of a
warning, so that you never forget one:

| State | Chip | On and off |
| --- | --- | --- |
| A branch solo | `SOLO Fizz` | `\s` |
| The solo follows the cursor | `SOLO follows` | `\S` |
| The whole chain bypassed | `BYPASS` | `\b` |
| Variant B plays | `B` | `\a` |
| A scope | `Gtr bus › Tame` in the path line | `zn`, `zW` |
| The inspector pinned | `pinned` | `\p` |

`Esc` does not change them. `Esc` cancels a count, an operator, a
selection, insert mode or a prompt, as the key rule says. A track solo
(`s`) shows where it shows in every view.

#### Sketches of the modes

Normal mode: the cursor fills the card of the rack "Level".

```text
 Devices · Vocal                          20 dev · 5 cont · 1.2 ms       ? keys
 Vocal
 in ━▶ EQ        ▅ ━▶ De-esser  ▅ ━▶ ▣ Level 2  ▆ ━▶ EQ        ▆ ━▶ ↩
       HP 100         6.5 kHz        two comps       +3 dB 3k
 NORMAL  Vocal  ▣ Level · rack · 2 devices
```

Insert mode after `i` on "Level" and then `c`: the new compressor is in
place, and the caret is after it, before "Level".

```text
 INSERT before ▣ Level · Vocal                                           ? keys
 Vocal
 in ━▶ EQ        ▅ ━▶ De-esser  ▅ ━▶ Comp      ▅ ━┃━▶ ▣ Level 2  ▆ ━▶ ↩
       HP 100         6.5 kHz        new
 INSERT  c comp  e EQ  s sat  g gate  l lim  R rack  L layer  B band  Tab more
```

Visual block over the compressors of three bands (`Ctrl-v` `2j`). The
selection is in brackets here; the view uses the color of a selection.

```text
 Devices · Bus · 3 x 1 block                                             ? keys
 Bus › Tame
 in ━▶ ┳━▶ 1 Low  [Comp      ▆]━━  0.0 ━┳ ━▶ out
       ┣━▶ 2 Mid  [Comp      ▅]━━  0.0 ━┫
       ┗━▶ 3 High [Comp      ▃]━━ -1.0 ━┛
 V-BLOCK  3 compressors · + - threshold of each · gm link · gM macro
```

The graph window and the inspector window. `Enter` on the de-esser went
to the inspector, and the status line of each window shows its mode:

```text
 Devices · Gtr bus                                16 dev · 4 cont · 5.3 ms
 Gtr bus › Tame › 3 Fizz
 ┗━▶ 3 Fizz De-esser   ▃ ━━ -1.0 ━┛
 ─ Devices · Gtr bus ───────────────────────────────────────────────────────────
 ▾ De-esser · Fizz band · on
   freq       ━━━━━━━━●─────────    7.0 kHz  A L
   range      ━━━━●─────────────    -2.0 dB  A L
 ─ Inspector · De-esser ─ NORMAL ───────────────────────────────────────────────
```

## 6. The display

### 6.1 Layouts

| Width of the window | Layout | Cards |
| --- | --- | --- |
| 100 columns or more | flow, inspector in two columns | two lines: the name and a meter; the main value |
| 72 to 99 | flow, inspector in one column | one line: the name and a meter |
| less than 72 | outline, as the panel of today, with rails | a row; the parameters open under it |

- A card is 14 columns at 120 and 11 at 80. A long name gets `…`.
- Wires: `━━▶` along the signal. `┳` and `┣` and `┗` split, `┫` and `┛`
  merge. The wire of the cursor's path is bright; others are faint.
- A branch head is a label at the start of the lane: number, name, and
  its zone or band (`Low  <120 Hz`). The gain of the branch is at the end
  of its lane, before the merge, so `+` there is where the eye is.
- A split is a header above its lanes: the kind, its values, and `mix`.
- The cursor is an inverse card (blue in the window).
- A card on bypass is faint with `off`. A missing plugin shows its state
  (`offline`, `stopped: gR`) as today.
- Badges on a card: `~` modulated, `↯` key, `⇉` further outputs, `⌛` a
  latency above 1 ms.
- Meters: the last cell of the card's first line is the peak of the
  node's output (`▁▂▃▄▅▆▇█`). While the song plays, only these cells
  change (live values, as the meters of the arrange view).
- When the graph is wider than the window, the first line is a mini map:
  one cell per node, the splits as `┳`, and the part that shows in
  brackets. The view scrolls to keep the cursor in view.
- The modulation lane is under the lanes of its split, faint until the
  cursor is in it.
- The inspector under the graph shows the node under the cursor: the
  rows of today (heading, picture, parameters with `A` and `L`), and for
  a modulated parameter a range on its slider (`━━━●▒▒▒──`) and a row for
  each link (`↳ ~ LFO 1  +20%`).
- At the end: the output of the track and its sends, as today.

### 6.2 A serial chain

At 120 columns:

```text
 Devices · Bass                          5 devices · latency 0.7 ms · cpu 1.9 %                          flow · ? keys
 in ━━▶ Synth        ▆ ━━▶ EQ           ▅ ━━▶ Compressor ↯  ▅ ━━▶ Saturation   ▆ ━━▶ Delay        ▃ ━━▶ out → Master
        saw · 4 kHz        3 bands            -4.2 dB GR            tape · 6 dB         1/8. · 30 %
 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 ▾ Compressor  Vocal glue ▾                key Kick ▾ · wet 100 % · out 0.0 dB · 0.1 ms                       on
   ▁▁▂▂▃▅▇▇▅▃▂▁  gain reduction -4.2 dB
   threshold  ━━━━━━━━●─────────  -18.0 dB A L   attack     ━━●────────────────   10 ms A L
   ratio      ━━━━━●────────────      4:1  A L   release    ━━━━━━●────────────  120 ms A L
   knee       ━━━●──────────────   6.0 dB  A L   makeup     ━━━━━━━━━●─────────   0.0 dB A L
 → Master ▾                                                                         ↗ Reverb  ━━━━━━━━●──  -9.0 dB  pre
```

At 80 columns:

```text
 Devices · Bass                        5 devices · 0.7 ms              flow
 in ━▶ Synth    ▆ ━▶ EQ       ▅ ━▶ Comp ↯   ▅ ━▶ Saturat… ▆ ━▶ Delay    ▃ ━▶ out
 ──────────────────────────────────────────────────────────────────────────────
 ▾ Compressor  Vocal glue ▾                 key Kick · wet 100 %          on
   threshold  ━━━━━━━━●─────────  -18.0 dB A L
   ratio      ━━━━━●────────────      4:1  A L
   attack     ━━●───────────────    10 ms  A L
   release    ━━━━━━●───────────   120 ms  A L
 → Master ▾                                ↗ Reverb  ━━━━━━━●──  -9.0 dB
```

### 6.3 A parallel split (parallel compression on a drum bus)

At 120 columns:

```text
 Devices · Drums                         3 devices · 1 split · latency 0.0 ms                             flow · ? keys
                         layer "Smash" · mix 100 %
 in ━━▶ EQ           ▅ ━━┳━▶ 1 Dry  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 0.0 dB ━┳━━▶ Limiter      ▆ ━━▶ out
        2 bands          ┃                                                                  ┃     -1.0 dB
                         ┗━▶ 2 Crush  Compressor   ▇ ━━▶ Saturation   ▆ ━━━━━━━━━━ -6.0 dB ━┛
                                      10:1 · -9 GR       tube · 9 dB
```

At 80 columns:

```text
 Devices · Drums                     3 devices · 1 split                 flow
               layer Smash · mix 100 %
 in ━▶ EQ   ▅ ━┳━▶ 1 Dry   ━━━━━━━━━━━━━━━━━━━━━━━━━━━ 0.0 ━┳━▶ Limiter ▆ ━▶ out
               ┗━▶ 2 Crush Comp  ▇ ━▶ Satur… ▆ ━━━━━━ -6.0 ━┛
```

### 6.4 A band split with three bands

At 120 columns:

```text
 Devices · Bass                          6 devices · 1 split · latency 0.6 ms                             flow · ? keys
                         band · 120 Hz · 2 kHz · mix 100 %
 in ━━▶ Synth        ▆ ━━┳━▶ 1 Low   <120 Hz   Utility      ▅ ━━▶ Compressor ↯ ▆ ━━━━━━━━━━ 0.0 dB ━┳━━▶ out → Master
        saw · 4 kHz      ┃                     mono               4:1 · -3 GR                       ┃
                         ┣━▶ 2 Mid   120-2k    Saturation   ▆ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -2.0 dB ━┫
                         ┃                     tape · 6 dB                                          ┃
                         ┗━▶ 3 High  >2 kHz    Chorus       ▃ ━━▶ Reverb       ▂ ━━━━━━━━━ -4.0 dB ━┛
                                               0.6 Hz             plate · 30 %
```

At 80 columns:

```text
 Devices · Bass                 6 devices · 1 split · 0.6 ms              flow
               band 120 Hz · 2 kHz
 in ━▶ Synth ▆ ┳━▶ Low  Utility  ▅ ━▶ Comp ↯   ▆ ━━━━━━━━━━━ 0.0 ━┳━▶ out
               ┣━▶ Mid  Saturat… ▆ ━━━━━━━━━━━━━━━━━━━━━━━━ -2.0 ━┫
               ┗━▶ High Chorus   ▃ ━▶ Reverb   ▂ ━━━━━━━━━━ -4.0 ━┛
```

### 6.5 A folded container

`za` on the split of 6.4 at 120 columns:

```text
 in ━━▶ Synth        ▆ ━━▶ ▸ band 120 Hz · 2 kHz   3 branches · 4 devices · 0.6 ms   ▆ ━━▶ out → Master
        saw · 4 kHz          Low 0.0 · Mid -2.0 · High -4.0 · ~ 1 link
```

At 80 columns:

```text
 in ━▶ Synth    ▆ ━▶ ▸ band 3 br · 4 dev  ▆ ━▶ out → Master
```

### 6.6 Modulation

The lane of the root split, under the lanes, at 120 columns. The cursor
is on `LFO 1`. The targets have the `~` badge.

```text
 in ━━▶ Synth        ▆ ━━┳━▶ 1 Dry  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 0.0 dB ━┳━━▶ Limiter      ▆ ━━▶ out
                         ┗━▶ 2 Crush  Saturation ~ ▆ ━━▶ Reverb ~     ▂ ━━━━ -6.0 dB ━┛
 ~ mods ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
   ≈ LFO 1      1/4 · sine  ▁▃▆█▆▃▁      ⟶ Reverb.mix +20 % · Saturation.drive +3 dB
   ◆ Crush      macro 35 %  ━━━●──────   ⟶ Saturation.drive +12 dB · Crush.gain +6 dB
   ⇡ Follower   key Kick    ▂▇▃▁▁▇▃▁     ⟶ Compressor.threshold -6 dB
 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 ▾ Saturation  ▾                                                     wet 100 % · out 0.0 dB                        on
   drive      ━━━━━━●▒▒▒▒▒▒▒▒──── 12.0 dB A L
     ↳ ≈ LFO 1      +3 dB
     ↳ ◆ Crush     +12 dB
   curve      ━━━━━━━━━●────────     tube A L
```

At 80 columns:

```text
 in ━▶ Synth ▆ ┳━▶ Dry   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 0.0 ━┳━▶ Limiter ▆ ━▶ out
               ┗━▶ Crush Saturat~ ▆ ━▶ Reverb ~ ▂ ━━━ -6.0 ━┛
 ~ mods ──────────────────────────────────────────────────────────────────────
   ≈ LFO 1    1/4 sine   ⟶ Reverb.mix +20 % · Saturation.drive +3 dB
   ◆ Crush    35 %       ⟶ Saturation.drive +12 dB · Crush.gain +6 dB
```

### 6.7 `K` on a split

`K` on the band split of 6.4:

```text
╭─ band split · Bass ─────────────────────────────────────────────────────╮
│ Split      band, 3 branches, Linkwitz-Riley 24 dB/oct                   │
│ Crossover  120 Hz, 2 kHz            ] [ on a band move its upper edge   │
│ Mix        100 %  gain 0.0 dB       + - change the mix                  │
│ Latency    0.6 ms (Compressor lookahead, in Low)                        │
│            Mid and High wait 0.6 ms so that the bands sum in phase      │
│ Branches   1 Low   <120 Hz    0.0 dB   Utility, Compressor (key Kick)   │
│            2 Mid   120-2k    -2.0 dB   Saturation                       │
│            3 High  >2 kHz    -4.0 dB   Chorus, Reverb                   │
│ Mods       LFO 1 moves the crossover 2 by +10 %                         │
│ CPU        1.1 % (splitter 0.1 %)                                       │
│ Keys       ds unwrap · cs change kind · o add a band · za fold · zn in  │
╰─────────────────────────────────────────────────────────────────────────╯
```

`K` on a device keeps today's text, and adds its place (`Bass › band ›
1 Low › Compressor`), its latency, its key, its outputs and its links.

### 6.8 The outline layout (a narrow window)

At 40 columns, as a side window beside the arrange view:

```text
 Devices · Bass            6 dev · 1 split
 ▸ Synth                   saw          ▆
 ▸ EQ                      3 bands      ▅
 ┳ band 120 Hz · 2 kHz                  ▆
 ┣┳ 1 Low  <120 Hz            0.0 dB
 ┃┣ ▸ Utility                           ▅
 ┃┗ ▸ Compressor ↯                      ▆
 ┣┳ 2 Mid  120-2k            -2.0 dB
 ┃┗ ▸ Saturation                        ▆
 ┗┳ 3 High >2 kHz            -4.0 dB
  ┣ ▸ Chorus                            ▃
  ┗ ▸ Reverb                            ▂
 ▸ Limiter                 -1.0 dB      ▆
 → Master ▾                       + send
```

### 6.9 What the window adds through the same scene

The window is paused (no work on `paw-gui` now). The view gives the
roles now, so the window can paint them later with no new view:

- `node` (a card: drag to move, `Ctrl` drag to copy, drop on a lane to add
  a branch), `wire` (from a port to a port: the window paints a curve),
  `lane` (a branch head with a fader and a pan knob), `split` (a header
  with crossover handles: drag a handle on a small spectrum),
  `modsource` (drag from it to a parameter to link, as Bitwig does),
  `meter` (as the arrange view).
- Hit regions use the same Lua functions as the keys.

## 7. Parity, and what is new

| Today | In the new view |
| --- | --- |
| `j k` rows, `w b e` devices | `j k` across branches (flow) or rows (outline), `w b e` devices. In the inspector, `j k` rows as today. |
| `+ -` parameter, wet on a device | The same, plus branch gain, split mix, link depth. |
| `c`, `x`, `A`, `Enter`, `gC`, `L`, `f`, `t` | The same, in the inspector. On a device, a preset is `cc`. |
| `a` at the end | `a` adds after the node. `i` starts insert mode before it, `o` in a new branch. |
| `dd yy p P`, `y` over parameters | The same, plus `gp gP` (as a branch), text objects. |
| `gcc` | The same, plus `gcab`, `gcas`. |
| `Alt-j Alt-k` | `<< >>`, `< >`. `Alt-j Alt-k` move to another branch. |
| `V` | `v V Ctrl-v`. |
| Presets, `[p ]p`, `<Space>dw` | The same, plus racks and templates. |
| `gS`, `O`, `:device.spread` | The same, plus taps and `outs` splits. |
| `ge`, `K`, `s`, `\p`, `devices://Bass` | The same, plus `\s` and `K` on splits. |
| Pictures, live values | In the inspector, plus a meter per node. |
| Output and sends rows | The same, at the end. |
| None | Splits, folds, scopes, modulation, macros, the text form, gain match. |

## 8. Speed

- A key stays well under 100 ms. The layout of the graph is computed one
  time per revision of the project and kept, as `rows_for` keeps rows
  today. A graph of 200 nodes is a list of 200 boxes: less than 1 ms.
- `+` on a value sends one `SetParam` and draws one frame. It does not
  compile a plan.
- A topology edit compiles a plan on the main thread: an allocation of
  some buffers and a list of ops. It is less than 1 ms for 64 nodes. A
  new plugin in the graph starts as today (out of process, without a
  wait).
- The audio thread runs `Op`s with fixed buffers. A test with the
  allocation counter of `rust-testing` makes sure that `process` and a
  plan swap do not allocate on the audio thread.
- Bench (not a test): `bench/graph.lua` measures the cost of a band split
  with 3 bands and of 16 layers against a serial chain.

## 9. Evaluation with three metal chains

The owner asked for a test of the design on real, complex chains of 10
or more devices. Here the design draws three chains from a modern metal mix
in the view, counts the keys of common jobs, and lists what broke and
the fix of each problem. The research behind the chains is in the
`mixing-mastering` skill, `references/metal.md`, with sources. Settings
there are starting points.

### 9.1 The three chains

**A. The rhythm guitar bus (quad-tracked).** Four DI tracks (L1 L2 R1
R2). Each has the same five devices: a boost, an amp sim, a cab IR, a
gate that listens to the clean DI (`key=@in`), and an EQ. The bus has 16
devices in four containers:

1. EQ: HP 90 Hz, LP 9 kHz.
2. Dynamic EQ at 131 Hz: palm-mute thump.
3. Band split "Tame" at 150 Hz and 2.5 kHz: Low has a compressor keyed
   from the Kick track; Mid has a dynamic EQ on mud at 400 Hz; Fizz has a
   de-esser at 4 to 8 kHz.
4. Layer "Crush": Dry, and Crush (compressor 20:1, EQ, saturation) at
   -12 dB.
5. Mid/side "Width": the side gets an EQ (HP 250 Hz) and saturation.
6. Rack "Glue": saturation, glue compressor, a dynamic EQ keyed from the
   Vocal track (room for the vocal), utility, meter.

With the DI tracks: 36 devices.

**B. The drum bus, with the snare and the room.** The snare has a gate
(detector HP 400 Hz), a layer "Reinforce" (an audio-to-MIDI trigger and
a sampler at -6 dB), EQ, compressor and saturation. The room has a crush
compressor, a gate keyed from the Snare track, and EQ. The bus has 12
devices in three splits: EQ, a transient split "Punch" (Attack: EQ and
saturation; Body: a slow compressor), a layer "Crush" (compressor 20:1,
EQ, saturation at -9 dB), a glue compressor, a band split "Limit" at
150 Hz with a limiter in each band, a tilt EQ and a meter. With the snare
and the room: 20 devices.

**C. The lead vocal.** 20 devices in five containers: EQ HP 100 Hz,
de-esser, rack "Level" (compressor 8:1 for peaks, compressor 3:1 for
level), EQ +3 dB at 3 kHz, layer "Scream" (clip, band-pass, compressor at
-14 dB), layer "Double" (an L/R split with pitch +8 and -8 cents and 12
and 18 ms delays, at -15 dB), a second de-esser, layer "Sends" (Throw: a
dotted-eighth delay with a compressor that listens to the dry vocal, its
branch gain automated from -inf; Verb: a plate and an EQ at -18 dB), a
limiter and a meter.

The owner's "ducking keyed from the guitars" is the other way round in
the sources: `Joey Sturgis` ducks the instruments from the vocal. So the
vocal's room is on the guitar bus (chain A, step 6), and the vocal ducks
only its own throw delay.

### 9.2 What the view shows

The sketches come from a prototype of the layout in the scratchpad
(`devices-graph/gen/graph.py`), so the columns are real, not drawn by
hand. Height is the number of rows of the graph, without the inspector.

| Chain | Folded, 120 | Folded, 80 | All open, 120 | All open, 80 |
| --- | --- | --- | --- | --- |
| A guitar bus | 2 rows | 4 rows | 19 rows | 15 rows, "Glue" folds itself |
| B drum bus | 4 rows | 4 rows | 14 rows | 16 rows |
| C vocal | 4 rows | 6 rows | 21 rows | 25 rows |

What broke in design v1:

- **Width.** v1 drew one long row and scrolled it. Chain A open is about
  330 columns wide: the cursor saw a third of the bus at 120 and a
  quarter at 80, and the mini map was the only overview. **Fix:** the top
  level wraps like text (`↩` at the end of a row, `↪` at the start of
  the next). A whole node stays on one row. A container that is off the
  cursor's path and does not fit folds itself.
- **Height.** Chain C open is 21 rows at 120 and 25 at 80. With the
  inspector it does not fit in a 40-row terminal, and at 80 x 24 the
  graph alone does not fit. **Fix:** containers start folded. The path
  to the cursor opens (as `zv` in Vim). `paw.opt.graph_foldlevel` (default
  0) sets how much opens. The inspector shows the main rows of the node
  (6 or fewer), and `\i` shows all its rows.
- **No container for order.** v1 had the `chain` kind but no face for it.
  Chain A's last five devices, and chain C's two compressors, are one
  idea each. **Fix:** a **rack**: a named group of devices in series that
  folds to one card. See 9.4.
- **The same chain on many tracks.** The four DI tracks and the vocal
  double need the same chain. v1 could only copy. **Fix:** templates and
  linked racks. See 9.5.

Chain A, folded, at 120 and at 80 columns:

```text
 Devices · Gtr bus                              16 dev · 4 cont · 5.3 ms · cpu 6 %                               ? keys
 Gtr bus
 in ━▶ EQ         ▅ ━▶ Dyn EQ     ▅ ━▶ ┳ Tame 3   ▆ ━▶ ┳ Crush 2  ▆ ━▶ ┳ Width 2  ▆ ━▶ ▣ Glue 5   ▆ ━▶ out
       cut 90-9k       131 Hz thump    fizz -2 dB      smash 40 %      side 130 %      glue 2 dB
```

```text
 Devices · Gtr bus          16 dev · 4 cont · 5.3 ms · cpu 6 %           ? keys
 Gtr bus
 in ━▶ EQ        ▅ ━▶ Dyn EQ    ▅ ━▶ ┳ Tame 3  ▆ ━▶ ┳ Crush 2 ▆ ━▶ ↩
       cut 90-9k      131 Hz thu…    fizz -2 dB     smash 40 %
  ↪ ┳ Width 2 ▆ ━▶ ▣ Glue 5  ▆ ━▶ out
    side 130 %     glue 2 dB
```

Chain A, all open at 120. The cursor is in the Fizz band. The rack
"Glue" draws as a frame, and the splits draw as forks:

```text
 Devices · Gtr bus                              16 dev · 4 cont · 5.3 ms · cpu 6 %                               ? keys
 Gtr bus › Tame › 3 Fizz
                                       band Tame · 150 Hz · 2.5 kHz
 in ━▶ EQ         ▅ ━▶ Dyn EQ     ▅ ━▶ ┳━▶ 1 Low  Comp ↯     ▆ ━━  0.0 ━┳ ━▶ ↩
       cut 90-9k       131 Hz thump    ┃          4:1 key Kick          ┃
                                       ┣━▶ 2 Mid  Dyn EQ     ▅ ━━  0.0 ━┫
                                       ┃          mud 400 Hz            ┃
                                       ┗━▶ 3 Fizz De-esser   ▃ ━━ -1.0 ━┛
                                                  fizz 7 kHz
    layer Crush · mix 100 %
  ↪ ┳━▶ 1 Dry    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   0.0 ━┳ ━▶ ↩
    ┗━▶ 2 Crush Comp       ▇ ━▶ EQ         ▆ ━▶ Saturat    ▆ ━━ -12.0 ━┛
                20:1 fast       200-5k          tube 9 dB
    ms Width
  ↪ ┳━▶ 1 Mid   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  0.0 ━┳ ━▶ ↩
    ┗━▶ 2 Side EQ         ▅ ━▶ Saturat    ▅ ━━ +1.5 ━┛
               HP 250          tape 3 dB
    ┌ ▣ Glue · glue 2 dB · space 3 dB ─────────────────────────────────────────────┐
  ↪ ━ Saturat    ▆ ━▶ Glue comp  ▅ ━▶ Space EQ ↯ ▅ ━▶ Utility    ▆ ━▶ Meter      ▆ ━ ━▶ out
    │ tape 2 dB       2:1 30 ms       key Vocal       -1.5 dB         -14 LUFS     │
    └──────────────────────────────────────────────────────────────────────────────┘
```

Chain B: the drum bus folded at 80, the bus open at 120 with the cursor
on the crush compressor, and the snare track at 80:

```text
 Devices · Drum bus              12 dev · 3 splits · 3.0 ms              ? keys
 Drum bus
 in ━▶ EQ        ▆ ━▶ ┳ Punch 2 ▆ ━▶ ┳ Crush 2 ▆ ━▶ Glue comp ▆ ━▶ ↩
       HP 30, -2 …    attack +1 …    smash 35 %     4:1 30 ms
  ↪ ┳ Limit 2 ▆ ━▶ EQ        ▆ ━▶ Meter     ▆ ━▶ out
    gr -1.5 dB     tilt +1        -10 LUFS
```

```text
 Devices · Drum bus                                  12 dev · 3 splits · 3.0 ms                                  ? keys
 Drum bus › Crush › 2 Crush
                       transient Punch · ext
 in ━▶ EQ         ▆ ━▶ ┳━▶ 1 Attack EQ         ▇ ━▶ Saturat    ▇ ━━ +1.0 ━┳ ━▶ ↩
       HP 30, -2 4…    ┃            +2 dB 4k        clip 4 dB             ┃
                       ┗━▶ 2 Body   Comp       ▅ ━━━━━━━━━━━━━━━━━━  0.0 ━┛
                                    3:1 slow
    layer Crush · mix 100 %
  ↪ ┳━▶ 1 Dry    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  0.0 ━┳ ━▶ Glue comp  ▆ ━▶ ↩
    ┗━▶ 2 Crush Comp       █ ━▶ EQ         ▇ ━▶ Saturat    ▇ ━━ -9.0 ━┛    4:1 30 ms
                20:1 all-in     smile           tape
    band Limit · 150 Hz
  ↪ ┳━▶ 1 Low  Limiter    ▆ ━━ 0.0 ━┳ ━▶ EQ         ▆ ━▶ Meter      ▆ ━▶ out
    ┃          -3 dB                ┃    tilt +1         -10 LUFS
    ┗━▶ 2 High Limiter    ▆ ━━ 0.0 ━┛
               -2 dB
```

```text
 Devices · Snare                6 dev · 1 split · 0.0 ms                 ? keys
 Snare
                      layer Reinforce
 in ━▶ Gate      ▆ ━▶ ┳━▶ 1 Dry     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━  0.0 ━┳ ━▶ ↩
       HP 400 -30     ┗━▶ 2 Sample Trigger   ▆ ━▶ Sampler   ▇ ━━ -6.0 ━┛
                                   audio→MIDI     snare 3
  ↪ EQ        ▆ ━▶ Comp      ▆ ━▶ Saturat   ▆ ━▶ out
    +3 200, 5k     4:1 10 ms      tape 3 dB
```

Chain C: the vocal folded at 80, and open at 120 with the cursor on the
throw delay:

```text
 Devices · Vocal                20 dev · 5 cont · 1.2 ms                 ? keys
 Vocal
 in ━▶ EQ        ▅ ━▶ De-esser  ▅ ━▶ ▣ Level 2 ▆ ━▶ EQ        ▆ ━▶ ↩
       HP 100         6.5 kHz        gr 7 dB        +3 dB 3k
  ↪ ┳ Scream… ▆ ━▶ ┳ Double… ▆ ━▶ De-esser  ▅ ━▶ ┳ Sends 3 ▆ ━▶ ↩
    dirt 40 %      shift -15 …    gentle         throw A · …
  ↪ Limiter   ▆ ━▶ Meter     ▆ ━▶ out
    -1 dB          -16 LUFS
```

```text
 Devices · Vocal                                    20 dev · 5 cont · 1.2 ms                                     ? keys
 Vocal › Sends › 2 Throw
                                       ┌ ▣ Level · two compressors ───┐
 in ━▶ EQ         ▅ ━▶ De-esser   ▅ ━▶ ━ Comp 1     ▆ ━▶ Comp 2     ▅ ━ ━▶ EQ         ▆ ━▶ ↩
       HP 100          6.5 kHz         │ 8:1 peaks       3:1 slow     │    +3 dB 3k
                                       └──────────────────────────────┘
    layer Scream · macro dirt
  ↪ ┳━▶ 1 Dry   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   0.0 ━┳ ━▶ ↩
    ┗━▶ 2 Dirt Saturat    █ ━▶ EQ         ▇ ━▶ Comp       ▇ ━━ -14.0 ━┛
               clip 18 dB      BP 500-4k       10:1
    layer Double
  ↪ ┳━▶ 1 Dry    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   0.0 ━┳ ━▶ De-esser   ▅ ━▶ ↩
    ┃           lr                                                     ┃    gentle
    ┗━▶ 2 Shift ┳━▶ L Pitch      ▅ ━▶ Delay      ▅ ━━ 0.0 ━┳ ━━ -15.0 ━┛
                ┃     +8 ct           12 ms                ┃
                ┗━▶ R Pitch      ▅ ━▶ Delay      ▅ ━━ 0.0 ━┛
                      -8 ct           18 ms
    layer Sends · in-chain sends
  ↪ ┳━▶ 1 Dry    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━    0.0 ━┳ ━▶ Limiter    ▆ ━▶ Meter      ▆ ━▶ out
    ┣━▶ 2 Throw Delay      ▂ ━▶ Ducker ↯   ▂ ━━ A -inf ━┫    -1 dB           -16 LUFS
    ┃           1/4. 30 %       key @in                 ┃
    ┗━▶ 3 Verb  Reverb     ▃ ━▶ EQ         ▃ ━━  -18.0 ━┛
                plate 1.8s      HP 400
```

### 9.3 Key counts

The devices view has the keyboard, on the right track, unless the job
says otherwise. `<CR>` is one key. "Switch track" is `Ctrl-w p`, `j`,
`Ctrl-w p`: 5 keys.

| Job | Today | Design v1 | Revised design |
| --- | --- | --- | --- |
| 1. Add a parallel crush to the snare only | Not in the chain. A send to a new crush track: about 45 keys and 3 commands. | 23: `G` `a` `comp<CR>` `gsinl` `O` `<Esc>` `a` `eq<CR>` `a` `sat<CR>` | 8: `G` `a` `crush<CR>` (a template "Parallel crush" from the picker) |
| 2. Change the amp sim on all four DI tracks | About 75: on each track `w` `w` `dd` `a` `5150<CR>`, then `Alt-k` to its place, and 3 track switches. Settings lost. | 46: `/amp<CR>` `cin` `5150<CR>` (13), then 3 times: switch track, `/amp<CR>`, `.` (11) | 14: `/amp<CR>` `cin` `5150<CR>` `<Esc>` on the linked rack "Rhythm amp": all four change, one undo step. Overrides stay. |
| 3. Solo the fizz band (from anywhere in the bus) | Not possible: a band-split plugin's own solo, with the mouse. | 6 to 9: `3l` (`zo` when folded) `l` `2j` `\s`. Depends on the folds and where the cursor is. | 8: `/fizz<CR>` `\s`. `/` opens the folds. `\S` then lets `j` `k` compare the bands. |
| 4. A/B the whole chain against no processing | 6: `ggVGgc`. It toggles each device, so a device that was off comes on. Not level-matched. | 4: `gcie`, with the same fault. | 2: `\b` bypasses the root and keeps the state of each node. With `paw.opt.ab_match` the bypass is level-matched. `\a` flips between two stored variants A and B. |
| 5. Copy the vocal chain to the double track | 11: `ggVGy`, switch track, `p`. No containers. | 12: `yie`, switch track, `vie` `p`. | 12, the same, plus `dab` on Sends (3) because a double needs no throws. Or 1 command: `:chain.copy Vocal Dbl`, or `:chain.link` to keep them the same. Taps are remapped; a key from another track stays. |

Moves of the cursor at scale: in chain C open, the throw delay is the
14th device. `w` needs `13w`, which nobody counts. `/throw<CR>` is 7
keys from anywhere. Folded, `w` treats a folded container as one node, so
`7w` gets to "Sends", then `zo` `j` (3 keys) into the Throw branch.

### 9.4 Racks: containers for order

A rack is a named group of devices in series. It folds to one card. In
the model it is a split of kind `chain` with one branch, so it has a
mix, a gain, macros and modulators, as every split does.

- **Draw.** Folded: one card, `▣ Glue 5`, with its macro face or a
  summary as the second line. Open: a frame around its devices (the
  sketches above). A split draws forks, and a rack draws a frame, so you
  see which is which.
- **Grammar.** `gs{obj}r` wraps in a rack (`gs3lr`, `V` then `gsr`), and
  asks for a name in the command line (Enter keeps "Rack 1"). `ds`
  takes the rack away: its devices go back in its place. `ir` and `ar` are the
  inside of the rack and the rack (`dar` cuts it). `za` folds it, `zn`
  enters it, `zW` goes out. `[(` and `])` go to its start and end.
- **Macros.** `gM` on a parameter makes it a macro of the nearest
  container around it, named after the parameter. `gM` on a second
  parameter in visual mode adds it to the same macro. A folded rack's
  inspector shows its macros as sliders first (the "macro face"), then
  the links, then its devices.
- **Breadcrumbs.** The second line of the view is the path of the
  cursor: `Gtr bus › Tame › 3 Fizz`. In a scope (`zn`), the path starts at
  the scope. Nesting has no limit, but the path shows the last four
  levels, with `…` before them.
- **K** on a rack: its devices, its template and link, overrides,
  macros, keys, latency and CPU, its path, and the keys that act on it.
- **Text form.** A rack is `rack #20 "Glue" macros: glue=2dB tape=30%`
  with its devices indented under it, with no `|` line.

The macro face of the rack "Glue":

```text
 ▾ ▣ Glue   rack · user:Glue bus · copy                   5 devices · 0.4 ms · cpu 1.2 %                            on
   glue       ━━━━━●──────────────   2.0 dB  A L      tape       ━━━━━━●─────────────     30 %  A L
   space      ━━━━━━━●────────────   3.0 dB  A L      trim       ━━━━━━━━━●──────────  -1.5 dB  A L
   ↳ glue: Glue comp.threshold, .makeup · space: Space EQ.depth · tape: Saturation.drive · trim: Utility.gain
   ▸ Saturation  ▸ Glue comp  ▸ Space EQ ↯ Vocal  ▸ Utility  ▸ Meter                  Enter or zo shows the devices
```

`K` on a linked rack:

```text
╭─ rack Rhythm amp · Gtr L1 ───────────────────────────────────────────╮
│ Rack       5 devices in series: Boost, Amp, Cab, Gate, EQ            │
│ Template   project:Rhythm amp, linked on L1 L2 R1 R2                 │
│ Overrides  2 here: Amp.gain 5.5, Cab.blend 40 %    :rack.reset       │
│ Macros     gain 5.5 · tight 60 % · bright 45 %                       │
│ Keys       Gate listens to @in (the DI of this track)                │
│ Latency    1.3 ms (the amp runs at 4x)      CPU 2.1 %                │
│ Path       Gtr L1 › Rhythm amp                                       │
│ Do         zn enter · za fold · ds ungroup · cc load a template      │
╰──────────────────────────────────────────────────────────────────────╯
```

### 9.5 Templates

A template is a saved rack, split or whole chain, with its macros, its
links and the keys that it needs.

- **Where.** User templates in `~/.local/share/paw/racks/`, project
  templates in the project folder (`racks/`), and bundled templates in
  the runtime. On a name clash the project wins, then the user, then the
  bundle. `:rack.save` asks where (user by default). `:rack.save!`
  overwrites.
- **Pick.** `a` and `i` show devices, presets and templates in one
  picker, with a preview on the right: the outline of the template, its
  macros, the keys to fill, its latency and CPU, and whether it is a copy
  or linked. `Tab` toggles the preview. `Ctrl-l` adds it linked.
- **Keys to fill.** A template names its keys (`Kick`, `Vocal`). On load
  paw guesses each from the track names. It shows a short form with the
  guesses: Enter keeps them, `Tab` goes to the next key, `Ctrl-n`
  `Ctrl-p` choose another track, `Esc` loads with no keys. A key that is
  not filled is a diagnostic (`]d`): "Space EQ listens to nothing: set
  the key Vocal (`gS`)".
- **Copy or linked.** A load is a **copy** by default: it belongs to the
  track, and a change of the template later does not reach it.
  `:rack.update` pulls the newer template into a copy, as one undo step,
  and says what changed. A **linked** rack (`Ctrl-l` in the picker,
  `:rack.link`) shares its devices, order and values with the other
  instances in the project, as linked clips do. A value changed on one
  instance is an **override**: it stays on that instance, `K` lists it,
  and `:rack.reset` removes it. A change of a device or of the order
  reaches all instances. `:rack.unlink` makes a copy.
- **Bundled templates** to start with: "Parallel crush", "Metal guitar
  bus", "Drum bus smash", "Scream vocal", "Bass split" (clean sub,
  driven middle band, amp). They come from `references/metal.md`.

The picker with a preview, and the keys to fill when a template loads:

```text
╭─ Add after Saturation · Snare ─────────────────────────────────────────────────────────────────────────────────────╮
│ > crush▏                                    │ ▣ Parallel crush               rack · user                           │
│ ▣ Parallel crush     rack  user     3 dev   │ layer Crush · mix 100 %                                              │
│ ▣ Drum bus smash     rack  project  6 dev   │ ┳━▶ 1 Dry   ━━━━━━━━━━━━━━━━━━━━━━━━━━━  0.0 ━┳                      │
│ ▣ Room crush         rack  bundled  3 dev   │ ┗━▶ 2 Crush Comp ▇ ━▶ EQ ▆ ━▶ Saturat ▆ -9.0 ━┛                      │
│   Compressor         built-in               │                                                                      │
│   Saturation: crush  preset built-in        │ Macros  smash 35 % · tone 50 % · blend -9 dB                         │
│                                             │ Keys    none to fill                                                 │
│                                             │ Adds    0.0 ms latency · cpu 0.4 %                                   │
│ Tab preview · Ctrl-l linked · Enter adds    │ Saved   2026-11-20 · copy (not linked)                               │
╰────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

```text
╭─ Metal guitar bus needs 2 keys ────────────────────────────────────────────╮
│ Kick    ▸ Kick                 a track named Kick                          │
│ Vocal   ▸ Lead vox             a track named *vox*                         │
│                                                                            │
│ Enter keeps both · Tab next · Ctrl-n Ctrl-p other tracks · Esc: no keys    │
╰────────────────────────────────────────────────────────────────────────────╯
```

### 9.6 Ease of use

- **A new user never sees 20 nodes at once.** Containers start folded,
  templates load folded with their macro face, and the top level wraps.
  Chain C folded is 10 cards in 4 to 6 rows.
- **Find.** `/` matches devices, racks, splits, branch names and kinds.
  It opens the folds on the way (`/fizz`, `/throw`). `n` `N` go on. `f`
  still finds a parameter of the node.
- **Overview.** The header line gives the number of devices and
  containers, the total latency, the CPU, and the keys of the chain
  (`keys Kick, Vocal`). Each folded card gives a summary. The mini map
  stays for a single node that is wider than the window, such as a split
  with long lanes.
- **The mixer strip** shows the top-level nodes of the chain (a folded
  container is one row), up to six, then `+n more`, and the latency and
  CPU of the chain.

```text
│ Gtr bus   │ Drum bus  │ Vocal     │
│ EQ        │ EQ        │ EQ        │
│ Dyn EQ    │ ┳ Punch   │ De-esser  │
│ ┳ Tame    │ ┳ Crush   │ ▣ Level   │
│ ┳ Crush   │ Glue comp │ EQ        │
│ ┳ Width   │ ┳ Limit   │ ┳ Scream  │
│ ▣ Glue    │ +2 more   │ +5 more   │
│ 5.3ms 6 % │ 3.0ms 4 % │ 1.2ms 5 % │
```

### 9.7 Other problems that the chains showed

- **Latency in a long branch.** In chain A the amp sims run at a higher rate (1.3
  ms on each DI track), and a look-ahead in one band delays the other
  bands. The header shows the total, a branch head shows its own latency
  with `⌛` when it is above 1 ms, and `K` names the device that causes it.
  Bundled templates use devices with no look-ahead.
- **Levels per branch.** To set a crush level you must see it. A branch
  head shows the peak of the branch where it enters the merge, beside its
  gain.
- **Many keys.** Chain A has two track keys and four taps; the room in
  chain B listens to the snare. `:keys` lists every key of the chain and
  where it comes from. `gS` on a device sets it. A key that a template
  could not fill is a diagnostic.
- **CPU per container.** The engine measures the time of each device in
  a block (two clock reads per device). A folded card and `K` show the
  sum.
- **Notes made in a branch.** The snare's trigger makes notes from audio
  in its branch, and the sampler plays them. The plan already gives each
  branch its own events. The trigger device goes in the `drums`
  extension.
- **Throws.** The throw is a branch gain lane: `A` on the branch head
  makes it. The lane is named `Vocal › Sends › Throw gain`.

### 9.8 Changes to the grammar

| Was (v1) | Now | Why |
| --- | --- | --- |
| `H` `L` move a node | `<` `>` as operators, `<<` `>>` for the node (`3>>`). `H` `L` stay free. | Under the key rule `<` `>` are time, and the order of the signal is its time. |
| `c` on a device chose a preset at once | `c` is an operator: it cuts, starts insert mode and opens the picker (`cin` replaces a device). `cc` chooses a preset, as the key rule says. On a parameter, `c` still types a value. | The same `c` as in the arrange view and the piano roll. |
| `gs{obj}c` (chain) | `gs{obj}r` wraps in a rack. `c` is no longer a kind letter. | A rack is the common case and has its own name. |
| None | `ir` `ar`: the inside of a rack, a rack. | Text objects for racks. |
| None | `gM`: make a parameter a macro of its container. | The macro face. |
| None | `\b`: bypass the chain, keep each node's state. `\a`: flip between variants A and B. | A/B at scale. |
| None | `\i`: the full inspector. | Height. |
| `o` on a node out of a split wraps it | The same, and `o` on `out` adds a layer with an empty Dry branch and the new device in branch 2. | A parallel effect at the end of the chain in one step. |
| `/` found nodes | `/` also finds branches and containers, and opens folds. | Find at scale. |

## 10. The chain language

The owner asked for a proper language for the text form: a language
that a person and an agent can both edit, with checks that always say
if a chain is correct, a linter and a formatter. The section below makes the
text form of "The text form" into that language. Its name is **chain**.

### 10.1 Decisions

1. **One language, four uses.** The same text is the file on disk, the
   buffer in paw, the template file, and what an agent reads and writes
   through the command line or the MCP server. Every use goes through
   one implementation, so the errors and the output are the same
   everywhere.
2. **The file on disk is chain text.** `tracks/<name>/devices.chain`
   replaces `devices.json`. The state of a plugin stays in its binary
   `.state` file, named by the id of the device. Templates are
   `racks/<name>.chain` (project) and `~/.local/share/paw/racks/<name>.chain`
   (user). paw keeps no backwards compatibility before a release, so
   `devices.json` goes. Question 2 changes with it.
   Reasons: `git diff` and merges work on the real file with no driver,
   an agent edits the file with any text tool, and a template is a file
   that you can share.
3. **The implementation is a Rust crate, `paw-chain`.** The kernel reads
   the project, so the parser cannot be Teal. The crate has no audio
   code: a lexer, a parser that recovers after an error, a printer, the
   checks, and the lints. The kernel, the command line, the language
   server, the MCP server and Lua (through `mlua`) use it. It uses a
   recommended parser crate (for example `chumsky`, which recovers from
   errors and keeps spans), as `paw-crates.md` asks.
4. **Every device kind has a schema.** A kind gives its parameters, with
   types, units, ranges and defaults, its outputs and its inputs. The
   built-in devices give it in Rust, Lua devices and split kinds in
   their definition, and CLAP plugins from their parameter info. Without
   a schema, the checks cannot know that `ratio=40kHz` is wrong.

### 10.2 The language

```text
chain 1                                   -- version of the language
track "Gtr bus"  rev=8f3a1c               -- rev: guard against a stale edit
eq #2  hp=90Hz  lp=9kHz
dyn-eq #3  "Thump"  b1.freq=131Hz  b1.range=-3dB  b1.attack=0.1ms
band #8  "Tame"  xover=150Hz,2.5kHz
  | Low
    compressor #5  ratio=4  threshold=-18dB  key=Kick
  | Mid
    dyn-eq #6  b1.freq=400Hz  b1.range=-2dB
  | Fizz  gain=-1dB
    de-esser #7  freq=7kHz  range=-3dB
layer #9  "Crush"
  | Dry
  | Crush  gain=-12dB
    compressor #10  ratio=20  attack=0.1ms
    clap:com.example.sat #11  "Drive"=9dB  "Mode"=tube
rack #20  "Glue"
  saturation #21  drive=2dB  curve=tape
  compressor #22  ratio=2  attack=30ms  key=@in
  use "Vocal space" #23  key.Vocal=Vocal   -- a linked template
mods
  macro #30  "glue"  2dB  -> #22.threshold -4dB, #22.makeup +2dB
  lfo #31  sync=1/4  shape=sine  -> #8.xover.2 +10%
checks
  latency <= 6ms
  gain pink -20dB = 0dB +- 1dB      -- with every device off
  peak <= -1dBTP
```

- One node is one line. Two spaces of indent go one level in. A line
  that starts with `|` is the head of a branch. `mods` holds the
  modulators of the container above it, and `checks` holds the checks of
  the file.
- A line is a kind, an optional `#id`, an optional quoted name, and
  fields `key=value`. A device kind is a built-in name (`compressor`), a
  plugin (`clap:<id>`) or a Lua device (`lua:<extension>/<name>`). A
  parameter name with spaces is quoted.
- A value has a unit when its parameter has one: `dB`, `Hz`, `kHz`,
  `ms`, `s`, `%`, a note value (`1/4`, `1/8.`), `on` and `off`, or a
  quoted choice.
- A line with no `#id` is a new device. paw gives it an id when it
  applies the text.
- `--` starts a comment, as in Lua. The formatter keeps comments.
- A parameter that a line does not name has its default. The printer
  writes only the parameters that differ from the default, so a diff
  shows only what you changed.
- `rev` in the header is a hash of the graph. An apply with an old
  `rev` is refused, so a person and an agent do not overwrite each
  other's changes. `apply --force` ignores it.
- The grammar is in a reference page,
  `docs/reference/chain-language.md`, with EBNF and an example of each
  rule.

### 10.3 Five levels of correctness

| Level | What it finds | When it runs | Result |
| --- | --- | --- | --- |
| Parse | A bad line, a bad indent, an unknown unit. The parser goes on and finds the next error too. | Each change in the buffer, each command, each load | Error, with line and column |
| Check | An unknown kind or parameter (with "did you mean"), a value out of range or with the wrong unit, two nodes with one id, a tap to a later node, a loop, a band split with crossovers out of order, the wrong number of branches for the kind, a key to a track that does not exist, a link to a parameter outside its container. | As for parse | Error. `:w`, `apply` and a load change nothing. A project with an error opens, and the track shows the error as a diagnostic. |
| Lint | Things that are allowed but are often a mistake: see 10.4. | As for parse | Warning or hint, with a code (`L012`), and often a fix. `-- allow L012` on a line or at the top turns one off. |
| Format | The one way to write a graph: indents, spaces, field order (the order of the schema), units (`4000Hz` is `4kHz`), no default values. | `=` in the buffer, `paw chain fmt`, on save of paw's own files | The text. The formatter never changes what the text means. |
| Render | The checks of the `checks` block: latency, the gain for a test signal, the peak, the gain when every device is off, no NaN and no endless values. paw renders a test signal through the graph offline, with no audio device. | `paw chain test`, the tests of the bundled templates, on request in paw (`:chain.test`) | Pass or fail for each check, with the measured value. |

The first four levels are pure functions of the text and the schemas,
so they are fast and the same in every place. The render level runs the
real devices.

### 10.4 The first lints

| Code | Lint | Fix |
| --- | --- | --- |
| L001 | A split with one branch: a rack says the same. | Make it a rack. |
| L002 | A container with nothing in it. | Remove it. |
| L003 | Equal branches of a layer with gain 0 dB: the sum is up to 6 dB louder. | Set each branch to -6 dB. |
| L004 | A parameter set to its default. | Remove the field (the formatter does it too). |
| L005 | A gate after a distortion with no key: the gate opens on the noise. | Set `key=@in`. |
| L006 | A limiter that is not the last device of the chain. | None, a hint. |
| L007 | A key to a track that is muted or has no sound. | None. |
| L008 | A template input that is not filled. | Choose a track. |
| L009 | A plugin that is not installed: the values stay as they are written. | None. |
| L010 | A device with look-ahead in one band of a band split: every band waits for it. | None, a hint with the latency. |

Extensions add lints with `paw.chain.lint.add(code, fn)`. A lint gets
the checked graph, not the text, so it does not parse the text again.

### 10.5 Humans and agents

| Who | How |
| --- | --- |
| A person in paw | `:e paw://track/2/devices` (or the short name `chain://Gtr bus`). Errors and lints show as you type, as diagnostics of the buffer (`]d`, `gK`, `<Space>la` for the fixes). Completion offers kinds, parameters, units, track names and template names. `=` formats. `:w` applies the text as one undo step, and says what changed: `added compressor #24, changed #5 ratio 4 to 6`. |
| A person in another editor | `paw chain lsp` is a language server on stdio: errors, lints, fixes, completion, formatting, hover with the schema of a parameter. A tree-sitter grammar gives the colors. |
| An agent with the command line | `paw chain print "Gtr bus"`, `paw chain check file.chain`, `paw chain fmt [--check]`, `paw chain lint`, `paw chain test`, and `paw chain apply "Gtr bus" file.chain --dry-run`. Each one takes `--json` and gives the diagnostics as data, with line, column, code and the fix. |
| An agent through MCP | `paw-mcp` gets `chain_read`, `chain_check` and `chain_apply`. `chain_apply` checks first, refuses a stale `rev`, makes one undo step, and returns what changed and the diagnostics. The agent sees in paw what it changed, and `u` undoes it. |

The agent loop is short and safe: read, edit the text, `check`, fix,
`apply --dry-run`, `apply`, `test`. An agent cannot make a broken graph,
because a text with an error never reaches the kernel.

### 10.6 Tests of the language

- Every example in the reference page parses, checks and formats to
  itself. A test reads the page.
- The round trip: for graphs made by property tests (`proptest`), print
  then parse gives the same graph, and format then format gives the same
  text.
- The formatter keeps the meaning: parse of the formatted text gives the
  same graph as parse of the text.
- A fuzz target for the parser in `paw-fuzz`: no panic, and the parser
  recovers.
- Golden files of diagnostics: a folder of bad chains, each with the
  errors that it must give (`tests/chain/bad/*.chain` and the expected
  output).
- Each lint has a test that fires and a test that does not.
- The bundled templates carry `checks`, and the suite runs
  `paw chain test` on them with the null audio device and the built-in
  devices only.

## 11. The plan

Sizes: S (a day), M (a few days), L (a week or more of agent work). Core
or extension in brackets. The evaluation with the metal chains changed
the plan: racks, templates, wrap and auto-fold come earlier, and macros
are a step of their own before the other modulators.

| Step | Work | Size | Depends on | Risks |
| --- | --- | --- | --- | --- |
| G0 | The owner approves this design and answers the questions at the end. | S | | |
| G1 | Kernel model [core]: `Graph`, `Split`, `Branch`, `Node`, racks (kind `chain` with a name and a face), macros on each container, linked rack definitions in the project with overrides per instance, `Graph::validate`, serde in `devices.json`, lanes on split and branch values, undo, the loop checks with taps. Lua API `paw.graph` (Teal). | L | G0 | Many places read `devices`. The flat list stays. Linked racks touch undo and save: one definition, many instances. |
| G2 | Engine [core]: `GraphPlan`, the compiler, `Msg::SetGraph`, the splitters and mergers, latency in branches, sleep of branches, a meter per node and per branch, CPU time per device, the 5 ms fade on a new topology. | L | G1 | Bit-exact null test for serial chains. LR4 bands sum flat. Freeze and render use the plan. Clock reads per device must stay cheap: measure in `bench/`. |
| G3 | View [core]: `views/devices.tl`, the graph window and the inspector window, the flow layout with wrap and auto-fold, cards with summaries, rack frames, breadcrumbs, the header (devices, latency, CPU, keys), the outline layout, the inspector with the macro face and `\i`, folds by default and `paw.opt.graph_foldlevel`, scenes. | L | G1 | Layout in cells at 80 and 120. Golden screens of the three metal chains, folded and open. |
| G4 | Modes and keys [core]: normal, insert (the caret, the insert keys, `paw.opt.graph_insertkeys`, `paw.insert.add` with `view`), visual, the inspector window, the header chips, motions, text objects (`ir ar` too), operators, `c` as an operator, `<< >>`, `gs ds cs`, `gM`, `/` over folds, visual block, `\s \S \b \i`, Ex commands, the key rule constitution. | M | G3 | `c` and `a` change meaning in this view: the key rule page and its tests change in the same commit. |
| G5 | Racks and templates [core]: `:rack.save` and `:rack.load` with user, project and bundled places, the picker with templates and a preview, keys to fill on load with guesses and diagnostics, copy or linked, overrides, `:rack.update`, `:rack.reset`, `:chain.copy`, `:chain.link`. Track templates keep the graph. | L | G1, G3 | The preview must stay fast in a large folder of templates. A linked rack across tracks with keys: each instance fills its own. |
| G6 | Macros [core]: macros in the plan, `gM`, macro lanes, the macro face, macros in the mixer strip. | M | G2, G3 | |
| G7 | The chain language, generic (owner 2026-11-23: usable outside paw, for example in REAPER; no chain-* crate depends on paw; host schemas as JSON data; the language server `chain-lsp` is standalone and paw plugs it in through an opt-in extension, as midilsp): the `paw-chain` crate (lexer, parser with recovery, printer and formatter, checks), the schema of each device kind, `devices.chain` and `racks/*.chain` on disk in place of `devices.json`, the `paw://track/<n>/devices` buffer with `:w`, the reference page with the grammar. | L | G1 | A parameter name of a plugin that changes between versions. A plugin that is not installed: keep the values as written. |
| G8 | Taps, the `outs` split and `:keys` [core]. | M | G2 | Order of the plan, loops. |
| G9 | Other modulators [core: lfo, follower, midi, random; extensions for more]: links, `CLAP_EVENT_PARAM_MOD`, the mods lane, `gm`, `:mod.bake`. | L | G6 | CPU per link. Plugins without non-destructive modulation. |
| G10 | A/B [core]: `\b` with the state of each node kept, `\a` variants, `=` gain match, `paw.opt.ab_match`. | S | G2 | A level match needs a short loudness window: no time in tests, wait for a state. |
| G11 | Extensions [extension]: the `transient` split and an audio-to-MIDI trigger device (in `extensions/drums`), the `gate` and `envelope` splits, an `xy` morph, `mseg` and `steps` modulators. | M | G2, G9 | Proves that the core is generic. The trigger makes events in a branch. |
| G12 | Bundled templates [core runtime]: "Parallel crush", "Metal guitar bus", "Drum bus smash", "Scream vocal", "Bass split", with the settings of `references/metal.md` on built-in devices. | S | G5 | Built-in devices must be good enough for these jobs. |
| G14 | Tools for the chain language (standalone `chain-lsp` and `chain` command; paw-only parts: render checks, `rev`, MCP, the `chainlsp` extension): lints and `paw.chain.lint.add`, `paw chain print check fmt lint test apply` with `--json`, the render checks, `rev`, lints and fixes as code actions of the language server, the tree-sitter grammar, the MCP tools `chain_read`, `chain_check`, `chain_apply`. | L | G7, G2 | A render check needs the devices: the bundled templates use built-in devices only. |
| G13 | Docs: the devices view reference, `about-device-graphs.md`, how-to guides (parallel compression, a band split, a keyboard split, racks and templates, and one guide for each metal chain, with tests), `key-rule.md`, `routing.md`, `devices.md`, `project-files.md`, a tutor lesson, the GIF. | M | G3 to G5 | Vale. The guides have tests (`tests/guides_howto.lua`). The docs of each step go with the step; G13 is the final pass. |

Order: G0, then G1, then G2, G3 and G7 in parallel (the file on disk
comes early, because every later step saves its work in it), then G4,
G5 and G14, then G6 and G8, then G9 and G10, then G11 and G12, then
G13. The milestone "Devices graph" in the Backlog holds these steps as
bundles.

Tests (each step has its tests; prune with `prune-tests`):

- Rust: a serial graph sounds the same to the bit as the chain of today
  (null test). A layer of N equal branches at -x dB. A band split sums
  flat. A mid/side split with nothing in it is the identity. Latency in
  one branch: the branches arrive together. A plan swap and `process` do
  not allocate. A tap that comes later is refused. A linked rack: a
  change of the definition reaches each instance, and an override stays.
- Lua with real keys: each operator (`gsinb`, `gs3lr`, `ds`, `csb`, `o`,
  `dab`, `gp`, `>>`, `>ib`, `cin`, `gM`, `Ctrl-v` then `+`), each makes
  one undo step and says what it did. `/fizz` opens the folds. `\b` puts
  back the state of each node. A template load fills its keys from the
  track names, and a key it cannot fill is a diagnostic. The text form
  round trip. `:w` of a bad line changes nothing. Folds are not undo
  steps. The key rule constitution passes.
- Golden screens at 40, 80 and 120 columns for each sketch of "The
  display" and for the three metal chains, folded and open.

## 12. Questions for the owner

Questions 1 to 11 are from the first version. Question 5 changed: `H L`
are no longer moves. Questions 12 to 27 are new. Questions 21 to 24 come from the design of the modes, and 25 to 27 from the chain language. Question 2 changed.

| # | Question | Recommendation |
| --- | --- | --- |
| 1 | A tree (series-parallel) or a free graph with cables? | A tree. It covers what the DAWs give, it has no crossed cables in a terminal, and Vim text objects fit it. A free graph (as The Grid) later, as an extension or a `Wasm` device. |
| 2 | Is the text form the file on disk, or a view of `devices.json`? | Changed: the chain language is the file on disk (`devices.chain`), with a Rust parser in `paw-chain`. `git diff`, merges, agents and templates all use the real file. The state of a plugin stays in its `.state` file. |
| 3 | Solo of a branch: `s` on a branch, or `\s`? | `\s`, so that `s` always solos the track as the key rule says. `\S` lets the solo follow the cursor for A/B. |
| 4 | `a` in the devices view: after the node, or at the end of the chain? | After the node, one device from the picker, in normal mode. `i` starts insert mode before the node, as in the arrange view. In the arrange view and the mixer, `a` stays at the end of the chain. The key rule page says so. |
| 5 | `<< >>` and `< >` move a node earlier and later in the signal. Is the order of the signal a meaning of time for the key rule? | Yes. The signal goes through the nodes in order, so this is a time of the signal. `H L` stay free. `Alt-j Alt-k` move between branches. |
| 6 | Modulators: in each container, or one rack for the track? | In each container, with targets inside it (as Bitwig). The root is a container, so a track rack exists too. |
| 7 | Band crossovers: minimum phase only, or also linear phase? | LR4 (minimum phase, no latency) first. Linear phase later, as a setting of the split, with its latency. |
| 8 | A topology edit while the song plays: a short dip, or a change with no gap? | A 5 ms fade out and in, as a bypass. A change with no gap needs two plans at the same time, with two copies of each device. |
| 9 | Branches on more threads? | Not in the first version. A track runs on one thread. Measure first (`bench/graph.lua`). |
| 10 | Replace the panel, or keep it as a second view? | Replace it. The outline layout at narrow widths looks like the panel of today, and there is no backwards compatibility before a release. |
| 11 | Does the mixer show the splits? | Changed: the strip shows the top-level nodes of the chain (a folded container is one row), up to six, then `+n more`, with the latency and CPU of the chain, and the macros of the root. `ge` opens the devices view. |
| 12 | A template load: a copy or a linked rack? | A copy by default, with `:rack.update` to pull a newer version. Linked on request (`Ctrl-l`, `:rack.link`), with overrides per instance. Linked is right for the four DI tracks; a copy is safer for most loads. |
| 13 | Where do templates live? | Three places: bundled, user (`~/.local/share/paw/racks/`) and project (`racks/`). On a name clash the project wins, then the user. `:rack.save` saves for the user by default. |
| 14 | Do track templates (the `templates` extension) keep the graph? | Yes, the whole graph with racks and macros. A linked rack in a track template becomes a copy, unless the project has its definition. |
| 15 | Wrap the top level, or scroll it sideways? | Wrap, with `↩ ↪`. A split never wraps inside; a split wider than the window is clipped with `▸` and the mini map shows it. |
| 16 | `c` becomes an operator that cuts and starts insert mode, and `cc` chooses a preset. | Yes. It is the `c` of the arrange view and of the piano roll, and `cc` keeps the key rule's "on a device, choose a preset". On a parameter, `c` still types a value at once. |
| 17 | Is a rack a split of kind `chain`, or a node type of its own? | A split of kind `chain` with one branch. It gets mix, gain, macros and modulators for free, and `cs` can turn it into a layer. Only the drawing differs. |
| 18 | Template keys: filled by guesses from the track names, or always asked? | Guess from the names, show the short form with the guesses, Enter keeps them. A key that stays empty is a diagnostic, not an error. |
| 19 | Where does the audio-to-MIDI trigger go? | In `extensions/drums`, as a device that makes notes in its branch. The core only gives each branch its own events. |
| 20 | CPU time per device: always on, or only when the view shows it? | Always on: two clock reads per device per block are cheap. Confirm with a bench before G2 ends. |
| 21 | The key rule gives `H` `L` "earlier and later" for a clip and a note. Should `H` `L` move a node, for the same meaning in the graph? | No, as the owner asked: `<<` `>>` move a node. Keep `H` `L` free in the graph, and the key rule page says so. |
| 22 | Is the inspector a window of its own, or a part of the graph window? | A window. Then the keys of the graph act on nodes and the keys of the inspector act on rows, with no guess. It is the device panel of today, narrowed to one node. |
| 23 | The text form: `chain://Bass`, or the name of the other text buffers, `paw://track/2/devices`? | `paw://track/2/devices`, with indents for the graph. A flat chain gives the same lines as today. `chain://Bass` stays as a short name. |
| 24 | Insert mode adds the devices at once, so that you hear them, or at `Esc`, as the piano roll writes its notes? | At once: a device must sound to be judged. It is one undo step all the same. |
| 25 | The name and the file: the language "chain", the file `devices.chain`? | Yes. Short, and it says what the file holds. |
| 26 | Render checks (`checks` block) in project files too, or only in templates? | In both. A project check runs only on `:chain.test` or `paw chain test`. A load runs none, so it stays fast. |
| 27 | Does the formatter run when paw saves the project? | Yes: paw always writes the canonical form. A hand-edited file keeps its comments, and the next save formats it. |
