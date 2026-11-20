# About Teal in paw

paw writes its new code in Teal. Teal is Lua with types: a checker finds
errors of type before the code runs, and the compiler makes plain Lua. This
page tells why paw uses Teal and how Teal and Lua work together in paw. It
also gives the plan to move the Lua of paw to Teal.

## Why a language with types

The runtime of paw has about 60,000 lines of Lua, and the extensions have
about 30,000 more. In Lua, a wrong field name or a value of the wrong kind
shows only when that line runs. A checker finds these errors in all of the
code, at one time. An editor also completes the names of fields and
functions, because it knows the type of each value.

## Why Teal

These are the possible languages:

| Language | What it is | Why paw does not use it, or uses it |
|---|---|---|
| Teal | Lua with types; its compiler is a Lua library | paw uses it. It makes Lua 5.1, which LuaJIT runs as it is: the JIT and the FFI stay. paw contains the compiler, so a `.tl` file loads with no build step. A file can have types or not, so code moves one file at a time. |
| TypeScriptToLua | TypeScript that compiles to Lua | It needs Node.js to compile. The Lua that it makes adds a library for the parts of TypeScript that Lua does not have. |
| Luau | The language with types of a game platform | It is a different virtual machine. LuaJIT cannot run Luau's own syntax, so each file needs a step that removes the types, and the checker is a separate program. |
| LuaLS annotations | Comments with types, read by the Lua language server | The types are comments. Nothing makes the code agree with them, and the program does not check them when it builds. |
| Fennel, YueScript | Other syntax that compiles to Lua | They give a different syntax, not types. |

paw can load each of these through the same registry of languages
(`paw.lang.add`). Teal is only the first entry, which comes with paw.

## How Teal and Lua work together

- **The runtime.** A module of the runtime in Teal is a `.tl` file in
  `runtime/lua`. The build compiles it to Lua and then to bytecode, as it
  does with each Lua module. paw does not compile it when it starts.
- **Extensions and the configuration.** paw compiles an `init.tl`, a
  one-file `name.tl` or a module in `.tl` when it loads it. paw keeps the
  Lua in `~/.cache/paw/lang`, by the contents of the file, so a file
  compiles one time. paw loads the compiler only when a file is not in the
  cache.
- **The loader does not check types.** It only compiles, as a
  compiler of TypeScript that removes the types does. `tl check`, `paw.lang.check` and the test suite
  check the types.
- **The functions in Rust.** `runtime/types/paw/api.d.tl` declares
  `paw.api`, the functions of the kernel. `tools/apidoc.lua` makes it from
  the comments of `crates/paw-core/src/api.rs`: the Rust type of each
  parameter, a `// @param name T` line, and a `// @return T` line. The
  records of the data that crosses `paw.api` are in
  `runtime/lua/paw/types.tl`.
- **The global `paw`.** `runtime/types/paw.d.tl` gives `paw.api`, and each
  module of the runtime that is in Teal with the types of its own code. A
  module that is still in Lua is not described: it has the type
  `paw.Untyped`. A Teal file can call it, and casts what it keeps:
  `paw.cursor.track_id() as integer`. When the module moves to Teal, its
  types replace `paw.Untyped`.

## The rule for `any`

Write no `any` where the value has a shape. Give an options table a
record, an event payload a record, and a callback a function type. The
data of an extension in `meta` is the extension's own: it has a record of
the extension.

`runtime/types/any-allowed.txt` lists each `any` and each `paw.Untyped`
of the declarations, by name, with the reason. `tools/apidoc.lua check`
fails on one that is not on the list. When the comments of `api.rs` give a
type, or a module moves to Teal, `tools/apidoc.lua` lowers the count. A
person adds an entry only by hand, with a real reason. So the count only
goes down.

## What stays in Lua

- `runtime/lua/paw/dsp.lua` and the devices written in Lua. They are code
  for the audio thread that uses the FFI of LuaJIT and its JIT. Teal adds
  no cost to them, but casts at each FFI call make the code harder to read.
  They stay in Lua until the FFI declarations have types.
- `runtime/lua/tl.lua`, the compiler of Teal (version 0.24.8, MIT
  license, `runtime/lua/tl.LICENSE`). It is a copy of a program from
  outside paw.
- Generated files: `runtime/types/paw.lua` (for LuaLS) and the files of
  `runtime/types`.
- The test files. The runner loads them with `loadfile`. They can move
  later.

## The plan

The order is from the bottom: a module moves after the modules that it
uses, so that its types are real and not `paw.Untyped`. Each area is the
work of one agent. The areas of one wave do not depend on each other.

| Wave | Area | Files | Lines of Lua | Depends on |
|---|---|---|---|---|
| Done | Music data | `music`, `bytes`, `attr`, `regex`, `harmony/read`, `harmony/voice`, `types` | 1,100 | `paw.api` |
| 1 | Core services | `util`, `events`, `options`, `limit`, `hooks`, `seats`, `commands`, `lang` | 1,600 | none |
| 1 | File formats | `xml`, `zip`, `markdown`, `formats`, `midifile` | 1,800 | none |
| 1 | Kernel types | the `// @return` of `api.rs`, and records in `types.tl` | 270 functions | none |
| 2 | The project | `objects`, `cursor`, `edit`, `address`, `tempo`, `tempolane`, `markers`, `locators` | 3,400 | wave 1 |
| 2 | Music on the project | `harmony`, `structure`, `takes`, `groups`, `vca`, `lanes`, `curves`, `audition` | 3,100 | wave 1 |
| 3 | Queries and lists | `query`, `grep`, `qf`, `diagnostic`, `complete`, `snippet` | 3,900 | wave 2 |
| 3 | Drawing | `buf`, `draw`, `canvas`, `roles`, `scene`, `theme`, `plot`, `statusline` | 4,100 | wave 2 |
| 4 | Windows | `ui`, `layout`, `panes`, `mouse`, the menus | 4,500 | wave 3 |
| 4 | Editors | `ex`, `textbuf`, `pick` and `pick/`, `help`, `lsp/` | 9,000 | wave 3 |
| 4 | The frontend | `frontend`, `remote`, `render`, `media` | 3,800 | wave 3 |
| 5 | Keys and views | `keymap`, `keyrule`, `keybar`, `defaults/`, `views/`, `roles/` | 15,000 | wave 4, and the work on the keys that runs now |
| 5 | Extensions | one agent for each: `notation` (20,000), `utau` (8,000), `plugstate` (5,700), `interop` (4,000), the others (under 3,200 each) | 30,000 | the modules of paw that each uses |

The spike moved 1,100 lines in a part of a day, with the checker. An area
of wave 1 or 2 is about one day of work for one agent. An area of wave 4
or 5 is two to four days. After each area, `paw.Untyped` has fewer
entries.

## What the checker found in the spike

- `paw.harmony.voice.voice` gave `bass = false` to a field that is a
  pitch class elsewhere. The port gives the options without `bass`.
- Teal knows integers from other numbers. A sum that starts at `0` is an
  integer, so a sum of distances needed the type `number`.
- `unpack` is not in Teal's list of the global functions of Lua 5.1, and
  `math.tointeger` is not in LuaJIT. The port copies a list with a loop,
  and casts with `as integer`.
- `paw.regex` kept the text of a number and the number in one variable.
  The port gives each one a name.
- The checker found no error that changed what the code does: the tests
  of these modules pass with no change.
