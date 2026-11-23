# The layers of the runtime

The runtime (`runtime/lua/paw`) has an order of layers, from low to
high. A module reads the modules of its own layer and of the layers
below it. `tools/layers.lua` checks this order, and the suite runs the
check (`tests/layers.lua`). The item L7 of the review of the Lua and
Teal code gave the order.

## Why the order exists

The global `paw` is a service locator. A module reads `paw.x` at run
time, and its `require` calls do not show this reference. So two modules
can read each other with no cycle in the `require` graph. For example,
`ui` and `keymap`, `ui` and `canvas`, and `cursor` and `keymap` read each
other.

These cycles have a cost:

- Teal needs stand-in records (a local `record Ui` in a lower module)
  and `require as function` casts to load the modules in an order.
- The teal skill lists five pitfalls that come from these cycles.
- Lazy extensions and a runtime without LuaJIT need
  a known order of load.

## The layers

`tools/layers.txt` gives each module its layer. The order is this:

| Layer | What it holds | Examples |
| --- | --- | --- |
| `kernel` | The Rust side, the declarations of `runtime/types/paw`, and the modules that the kernel loads first. | `paw.api`, `paw.compat`, `paw.partial` |
| `data` | Values and helpers that know nothing of a project or a screen. | `paw.util`, `paw.types`, `paw.music`, `paw.events`, `paw.options` |
| `project` | The project and the things that the user edits in it. | `paw.objects`, `paw.cursor`, `paw.edit`, `paw.markers`, `paw.tempo` |
| `screen` | Cells, windows, tabs, the mouse and the roles of a scene. | `paw.buf`, `paw.draw`, `paw.canvas`, `paw.layout`, `paw.ui` |
| `input` | Keys, commands, the command line, completion, help, the language server and the extensions. | `paw.keymap`, `paw.commands`, `paw.ex`, `paw.ext` |
| `views` | The things that the windows show. | `paw.views.*`, `paw.roll_draw`, `paw.textbuf`, `paw.pick` |
| `frontends` | The terminal and the clients of the control socket. | `paw.frontend`, `paw.remote`, `paw.scene` |
| `boot` | `paw/init.lua`, which makes the global `paw`, and the defaults. | `paw`, `paw.defaults.*` |

## How a lower module gets what it needs

A lower module must not read a higher module. Use one of these methods:

- An event. The lower module emits an event (`paw.emit`), and the higher
  module listens for it (`paw.on`).
- A callback. The higher module gives a function to the lower module at
  setup, and the lower module calls it.
- A move. If the code that the lower module needs is about data, move
  that code down to a module of the lower layer.

## What the check counts

`tools/layers.lua` reads the text of each module. It does not run the
code.

- A `require("paw.x")` is one reference. A `local type X =
  require("paw.x")` and a `(require as function(string): X)("paw.x")` are
  references too.
- A `paw.x.y` in the code is a reference to the module that owns
  `paw.x.y`. The owner is the longest prefix that is a module, or the
  module that sets the name in `paw` (`paw.notify = messages.notify`
  belongs to `paw.messages`). A Teal cast, `(paw.x as T).y`, reads `paw.x.y`.
- `paw.ui.views:get("<name>")` is a reference to the module
  `paw.views.<name>`.
- Comments and strings do not count.
- The count of a pair of modules is the number of distinct names that
  one reads of the other. The name is the prefix of the owner and one more
  part, for example `paw.ui.focused`. So one more read of `paw.ui.focused`
  does not change the count.
- The name of the module itself (from a `require`) counts only when it is
  the only name. So a type import that replaces a stand-in record does not
  change the count.

## What to do when the check fails

Each message names the file and the line to change.

- **A module has no layer.** Add a line for the module in
  `tools/layers.txt`, under its layer.
- **A module of the list does not exist.** Remove its line from
  `tools/layers.txt`.
- **A module splits or moves.** Change the lines of `tools/layers.txt`,
  and move the counts of the allow-list to the new module names.
- **A count goes up.** The module reads a new name of a higher layer.
  Give the module what it needs through an event or a callback. If the
  module belongs in a higher layer, move its line in `tools/layers.txt`.
  If a record that a lower module needs is in a higher module, move the
  record down, or give its module a lower layer. For example,
  `paw.keymap.registers` is in the `project` layer because `paw.edit`
  makes registers.
- **A registry of a higher module.** Make it with
  `paw.registry.new` in its own module. `paw.ext` reads
  `paw.registry.all()`, so it takes away what an extension added, in any
  layer, with no reference to the module.
- **A count goes down.** Make the line of `tools/layers-allowed.txt`
  smaller, as the message says. The list only gets shorter.

Run the check:

```sh
luajit tools/layers.lua          # the check
luajit tools/layers.lua counts   # the lines of the allow-list of today
luajit tools/layers.lua graph    # the graph
```

Do not write `counts` into the allow-list to make a new upward reference
pass. Use `counts` only when a module splits or moves, and read the
difference before the commit.

## The graph

`luajit tools/layers.lua graph` writes one edge on each line, sorted:

```text
<from> <to> <count> <kinds> <from layer> <to layer> <up|down|same> <file>:<line>
```

`<kinds>` gives the references of each kind, for example
`paw=3,require=1`. The kinds are `require`, `type` and `paw`. `<file>:<line>`
is the first reference of `<from>` to `<to>`. The architecture map of
the architecture map can read this text in place of its own scan of `require` calls.

## The upward references of today

On 2026-11-23, the allow-list held 186 names on 142 lines. These modules
get the most upward references:

| Module | Names | What the lower modules read |
| --- | ---: | --- |
| `paw.frontend` | 48 | `paw.frontend.act`, `paw.frontend.format_value`, the chosen clips and notes |
| `paw.keymap` | 21 | the mode, the selection |
| `paw.ui` | 16 | `paw.ui.focused`, the views |
| `paw.pick` | 16 | the picker sources, `paw.pick.open` |
| `paw` (`paw/init.lua`) | 12 | `paw.state`, `paw.json` |

The timers (`paw.timers`), the message sink (`paw.messages`, which
`paw.ui` shows) and the command registry (`paw.command`) are in the `data`
layer. A lower module requires them, and does not read `paw.defer`,
`paw.notify` or `paw.commands`. The parts of `paw.frontend` are in the
`frontends` layer, and the reads of them can move to events or
callbacks. `paw.ui` and `paw.help` import the types of `paw.keybar`
(`views` layer). Remove the others one at a time, when a module changes
for other reasons.
