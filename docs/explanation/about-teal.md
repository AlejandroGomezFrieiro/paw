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
- **The build and the loader check the types.** In some places, the Lua
  that Teal makes depends on the types: `value is Fn`, where `Fn` is a
  name of a function type, is a test for a function. So the build and
  the loader compile as `tl gen` does, after a check. The build stops at
  a type error in the runtime. A file of an extension or of the
  configuration with type errors loads all the same, as the compiler of
  TypeScript gives its output on an error. paw shows the errors one time,
  when it compiles the file, and `:checkhealth teal` lists them.
- **What a check reads.** The program contains the declarations of
  `runtime/types` and the modules of the runtime in Teal
  (`paw.api.runtime_file`). The first check in a run reads the types of
  all of these, in about half a second. This time is not part of the
  time limit on Lua. The cache key of a file includes a hash of these
  types, so a file compiles again when the types of paw change. A file in
  the cache costs no check.
- **The functions in Rust.** `runtime/types/paw/api.d.tl` declares
  `paw.api`, the functions of the kernel. `tools/apidoc.lua` makes it from
  the comments of `crates/paw-core/src/api.rs` and of the other files that
  add to `paw.api` (`fs_api.rs`, `tempo_api.rs`, `luadev_api.rs`,
  `scene.rs` and `measure/mod.rs`): the Rust type of each parameter, a
  `// @param name T` line, and a `// @return T` line. A function with
  more than one form has a `// @type function(...)` line for each form
  instead (`track_set(id, patch)` and `track_set(id, key, nil)`). A form
  whose type follows from the value of an argument is not declared: Lua
  can call `track_get(id, "name")`, and Teal calls `track_get(id).name`.
  The records of the data that crosses `paw.api` are in
  `runtime/lua/paw/types.tl`. Each record agrees with the Rust code that
  makes or reads the table.
- **The records that Rust makes.** Some data has its shape in a Rust
  type, and `tools/apidoc.lua` makes the Teal records from that type.
  `crates/paw-core/src/events.rs` gives each event of the kernel and its
  payload: the tool makes `paw.events.kernel`, with a record for each
  payload and a descriptor for each event
  (`paw.on(kernel.project_saved, function(p: kernel.Saved) ... end)`).
  `crates/paw-scene/src/props.rs` gives the props of each role that the
  window paints: the tool makes `runtime/types/paw/role_props.d.tl`. The
  window reads the props with the same Rust types, so the records agree
  with what the window reads.
- **The global `paw`.** `runtime/types/paw.d.tl` gives `paw.api`, and each
  module of the runtime that is in Teal with the types of its own code. A
  module that is still in Lua is not described: it has the type
  `paw.Untyped`. A Teal file can call it, and casts what it keeps:
  `paw.cursor.track_id() as integer`. When the module moves to Teal, its
  types replace `paw.Untyped`.
- **A module of the runtime and the global `paw`.** The declaration of
  the global `paw` requires each module of the runtime that is in Teal.
  So such a module cannot use the types of the global: the checker
  reads the module before the global exists. A module gets the kernel's
  functions with `require("paw.api")`, and the modules in Teal with
  `require`. For the modules that are still in Lua, it takes the global
  as `Untyped`, the type in `runtime/types/paw/untyped.d.tl`:
  `local paw = (_G as {string:Untyped}).paw`. `paw.Untyped` is the same
  type. Better, it declares a record of the parts of `paw` that it reads
  and takes the global as that record:
  `local paw = (_G as {string:Paw}).paw`. The modules of the core services
  do this.
- **Other names of a value.** `paw.on` is `paw.events.on`, and `paw.opt`
  is `paw.option.opt`. `tools/apidoc.lua` gives such a name the type of the
  value in its module: the signature of the function in the source, or the
  type of the field in the record of the module.

## The rule for `any`

Write no `any` where the value has a shape. Give an options table a
record, an event payload a record, and a callback a function type. The
data of an extension in `meta` is the extension's own: it has a record of
the extension.

`runtime/types/any-allowed.txt` lists each `any` and each `paw.Untyped`
of the declarations, by name, with the reason. The `any` of the records in
`types.tl` are on the list too, as `types.Record.field`: an `any` that moves
from a function into a record is still one. `tools/apidoc.lua check`
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
| Done | Core services | `util`, `events`, `options`, `limit`, `hooks`, `seats`, `commands`, `lang`: 15 fewer `paw.Untyped` entries | 1,700 | none |
| Done | File formats | `xml`, `zip`, `markdown`, `formats`, `midifile`: 2,356 lines of Teal, 5 fewer `paw.Untyped` entries | 1,800 | none |
| Done | Kernel types | the `// @return` of `api.rs` and the other files that add to `paw.api`, and records in `types.tl`: 343 `any` of `paw.api` down to 20, and 5 in the records, each with its reason | 270 functions | none |
| Done | Contracts of the kernel | the events of the kernel as a Rust type, with a descriptor and a record for each; the setters take a table of changes (`track_set(id, patch)`), and `device_find_all` is separate from `device_find`; the props of the roles that the window paints as Rust types: 13 fewer `any` entries | 45 events, 7 functions, 21 roles | none |
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

## What the checker found in the core services

- Teal has no generic list of arguments of different types. The functions
  that call another function with its arguments (`paw.limit.guard`,
  `paw.seats.within`, `paw.seats.keep`) take arguments of one type. Code
  in Teal that has more gives a closure or a record.
- A function type with no results is not the type of a function with
  results. An event handler in Teal can return nothing, so `paw.on` takes
  `function(P, string)`. The module keeps the handler as the type that
  can refuse, with `false, reason`.
- `unpack`, `table.maxn`, `loadstring` and `jit` are not in Teal's list
  of the library of Lua 5.1. A record of these names casts `_G` one time.
- The build and the loader compiled without the checker. Without it,
  `value is Fn`, where `Fn` is a name of a function type, became a test
  for a table. The tests found two such tests: completion by a function
  and the time limit around a wait did not work. Now the build and the
  loader check the types before they compile.
- An error in a module in Teal names its `.tl` file. `paw.failure` moves
  the place in a `.tl` file to the end of the message, as it does for a
  `.lua` file.
- The compiler of Teal in paw has no declarations of its own, so
  `paw.lang` declares the parts that it calls.
- The checker found no error that changed what the code does: the tests
  pass with no change.

## What the contracts of the kernel found

- The kernel sent the payload of `project.saved` in two shapes: with the
  files written when it saves a folder, and with the path only for a
  file. The record `kernel.Saved` has both, and the files are optional.
- The kernel sent a key of a piano (`labels` of the `keyboard` role) as
  `{ pitch, name, style }`, and the window read only the first two. The
  record says so. A curve's `values` holds `false` where there is no
  value, not nil.
- A setter that takes a table cannot clear a field, because a table has
  no entry for nil. The key form stays for that, and Teal sees it only
  with `nil` as its value.
- What the code does is the same. Two tests changed: they used the forms
  that Teal does not see now (`track_get(id, key)`, `device_find` with
  `all = true`).

## What the checker found in the file formats

- `paw.midifile` gave the name of a project from a function that returned
  two values. The second value, a count, went to `paw.api.project_set` as
  an extra argument. The function now returns one value.
- A time signature that `paw.midifile` read had a denominator that was
  not an integer (`2 ^ n`). It is an integer now.
- `paw.midifile` added a field to each tempo and signature to sort them,
  and then removed it. The port keeps the order in a separate table.
- `paw.markdown.render` had a variable that it did not use.
- `paw.formats.register` copied each field of the table that it got,
  also the fields that are not part of a format. It copies the fields of
  a format now. An extension in Teal gets an error for a field with a
  wrong name (`paw.formats.Format`).
- The kernel's element, `types.XmlElement`, has no methods, and its
  attributes are text or numbers. An element of `paw.xml` has methods,
  and an attribute can also be true or false, which `xml_encode` writes.
  `paw.xml` casts between the two types where it calls the kernel.
