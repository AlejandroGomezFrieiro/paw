# About Teal in paw

paw writes its new code in Teal. Teal is Lua with types: a checker finds
errors of type before the code runs, and the compiler makes plain Lua. This
page tells why paw uses Teal and how Teal and Lua work together in paw. It
also gives the plan to move the Lua of paw to Teal.

## Why a language with types

The runtime of paw has about 60,000 lines of Lua, and the extensions have
about 60,000 more. In Lua, a wrong field name or a value of the wrong kind
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
  module that is still in Lua gives types only for the functions and
  values that its doc comments type: a `--- @type function(...)` line
  over a function, one line for each form, and a `--- @type T` line over
  a value (`M.views = {}`). `runtime/types/paw/partial.d.tl` collects
  these types, one record for each module. All the other parts of a
  module in Lua have the type `paw.Untyped`. A Teal file can call them,
  and casts what it keeps: `paw.scope.current() as integer`. When the
  module moves to Teal, its types replace `paw.Untyped`.
- **A module of the runtime and the global `paw`.** The declaration of
  the global `paw` requires each module of the runtime that is in Teal.
  So such a module cannot use the types of the global: the checker
  reads the module before the global exists. A module gets the kernel's
  functions with `require("paw.api")`, and the modules in Teal with
  `require`. For the modules that are still in Lua, it takes the global
  as `Untyped`, the type in `runtime/types/paw/untyped.d.tl`:
  `local paw = (_G as {string:Untyped}).paw`. `paw.Untyped` is the same
  type. Better, it takes the global as `partial.Paw`, the parts that the
  modules in Lua type (`local type partial = require("paw.partial")`).
  It can add the parts that it reads of the modules in Teal:
  `local record Paw is partial.Paw`. `paw.hooks` and `paw.commands` do
  this.
- **Other names of a value.** `paw.on` is `paw.events.on`, and `paw.opt`
  is `paw.option.opt`. `tools/apidoc.lua` gives such a name the type of the
  value in its module: the signature of the function in the source, or the
  type of the field in the record of the module.

## The standard library

Teal's checker declares the Lua 5.3 standard library. LuaJIT, which runs
paw, has the Lua 5.1 library and some parts of the Lua 5.2 library. The
code that Teal makes calls parts of the Lua 5.3 library.
`value is integer` calls `math.type`. The operators `&`, `|`, `~`, `<<`
and `>>` call `bit32`. The operator `//` calls `math.floor`, which LuaJIT
has.

So paw loads lua-compat-5.3 (release 0.14.4, MIT license,
`runtime/lua/compat53`) when the program starts, before the runtime and
before each extension. It changes the global functions, so the code in
Teal and the code in Lua use one library. `runtime/lua/paw/compat.tl`
loads it and adds the parts that it does not have in Lua:

- `math.type`, `math.tointeger`, `math.ult`, `math.maxinteger` and
  `math.mininteger`. An integer is a whole number from -2^53 to 2^53.
  Out of this range, a number is a `"float"`, as compat-5.3 tells.
- `table.unpack`, `table.pack` and `table.move`, `rawlen`, `utf8` and
  `bit32`. paw writes `utf8` and `bit32` in Teal. They give the same
  results as Lua 5.3 and Lua 5.2, and LuaJIT compiles them. `bit32`
  uses LuaJIT's `bit`.
- `pairs` uses `__pairs`, and `ipairs` uses `__index`, as in Lua 5.3.
- In the main code, `coroutine.running` gives the main coroutine and
  `true`. In Lua 5.1, it gave `nil`.
- `file:write` and `io.write` give the file. `file:read`, `io.read` and
  `io.lines` accept `"l"`, `"n"` and `"a"` without `*`.
- `os.execute` gives `true` or `nil`, then `"exit"` and the exit code, as
  in Lua 5.3. In Lua 5.1, it gave only the code.
- `load`, `loadstring`, `string.rep` and `string.format` stay LuaJIT's,
  which already do what Lua 5.3 does. `bit`, `ffi` and `jit` stay.

Some parts of compat-5.3 are not in paw:

- The parts of compat-5.3 in C, and `string.pack`. A call of a C
  function stops the code that LuaJIT compiles. Use `ffi` to pack bytes.
- The forms of `string.find`, `string.match`, `string.gsub` and
  `string.gmatch` that accept a zero byte in a pattern. They made a
  search for a plain text 250 times slower and a match 2 times slower.
  Write `%z` for a zero byte in a pattern.

paw keeps `gen_compat = "off"` in `tlconfig.lua`, so a compiled file
starts with no extra lines. The devices written in Lua run in a Lua
state of their own on the audio thread, without compat-5.3.

## The contracts

An extension gives tables to paw. Examples are a view, a buffer type, a
kind of text buffer, a kind of track, a role and a picker. A status line
component, a query field, a source of grep and a health check are tables
too.

These tables are the
contracts between paw and the extensions. `runtime/lua/paw/contracts.tl`
gives a type to each one, with the fields that the runtime reads. The
module has only types. It requires only `paw.types` and the types of
`paw.objects`, which requires no contract. So the modules in Lua name the
contracts in their `@type` lines before they move to Teal, and a module in
Teal can require it.

In an extension, the contracts are `paw.contracts.View`,
`paw.contracts.PickSource<T>` and the others. The functions that take a
contract (`paw.ui.view`, `paw.buftype`, `paw.textbuf.kind`,
`paw.track_kinds.define`, `paw.roles.define`, `paw.statusline.component`,
`paw.query.field`, `paw.grep.source`, `paw.health.register`, `paw.pick`,
`paw.pick.sources` and `paw.ui.menu`) take it with its type. So the checker finds a
field with a wrong name, for example `on_keys` for `on_key`. A picker is
generic: the type of its items goes to `format`, `on_choose` and the other
functions.

The options have types too. `runtime/types/paw/opts.d.tl` gives the type
of each option that the runtime defines, from its default and its rules:
`paw.opt.zoom` is a number with no cast. `tools/apidoc.lua` makes the file.
`paw.option.define` gives a handle with the type of the default:
`local lanes = paw.option.define("lanes", 4)`, then `lanes:get()` is a
number.

## The rule for `any`

Write no `any` where the value has a shape. Give an options table a
record, an event payload a record, and a callback a function type. The
data of an extension in `meta` is the extension's own: it has a record of
the extension.

`runtime/types/any-allowed.txt` lists each `any` and each `paw.Untyped`
of the declarations, by name, with the reason. The `any` of the records in
`types.tl` are on the list too, as `types.Record.field`: an `any` that moves
from a function into a record is still one.

The records of `contracts.tl` count in the same way, as
`contracts.Record.field`. `tools/apidoc.lua check`
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
- `runtime/lua/compat53`, lua-compat-5.3 (release 0.14.4, MIT license,
  `runtime/lua/compat53/LICENSE`). It is a copy of a program from outside
  paw, with no change.
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
| Done | Contracts, Rust side | the events of the kernel as a Rust type, with a descriptor and a record for each; the setters take a table of changes (`track_set(id, patch)`), and `device_find_all` is separate from `device_find`; the props of the roles that the window paints as Rust types: 13 fewer `any` entries | 45 events, 7 functions, 21 roles | none |
| Done | Contracts, Lua side | `contracts.tl`, the `@type` lines of the modules in Lua (`partial.d.tl`) and the types of the options (`opts.d.tl`): 880 lines of Teal, 12 fewer `paw.Untyped` entries | 10 functions that register | wave 1 |
| Done | The project | `objects`, `cursor`, `edit`, `address`, `tempo`, `tempolane`, `markers`, `locators`: 4,408 lines of Teal, 24 fewer entries of `any-allowed.txt`, and no `any` or `paw.Untyped` in these modules | 3,100 | wave 1 |
| Done | Music on the project | `harmony`, `structure`, `takes`, `groups`, `vca`, `lanes`, `curves`, `audition`: 3,859 lines of Teal, 42 fewer entries on the allow-list | 3,000 | wave 1 |
| Done | Queries and lists | `query`, `grep`, `qf`, `diagnostic`, `complete`, `snippet`: 5,601 lines of Teal, 6 fewer entries on the allow-list, and no `any` in these modules | 3,900 | wave 2 |
| Done | Drawing | `buf`, `draw`, `canvas`, `roles`, `scene`, `theme`, `plot`, `statusline`: 4,740 lines of Teal, 6 fewer entries on the allow-list, and no `any` or `paw.Untyped` in these modules | 3,700 | wave 2 |
| Done | Windows | `ui`, `layout`, `panes`, `mouse`, `menu`, `mouse_menus`, `window_menus`: 6,100 lines of Teal, 10 fewer entries on the allow-list (with the two `any` of `project_screen`), and no `any` or `paw.Untyped` in these modules | 4,500 | wave 3 |
| Done | Editors: Ex and text buffers | `ex`, `textbuf`: 4,817 lines of Teal, `paw.ex` and `paw.command` typed (the types of commands are contracts now), 3 fewer entries on the allow-list, and no `any` or `paw.Untyped` in these modules | 4,100 | wave 3 |
| Done | Editors: pickers, help and language servers | `pick` and `pick/`, `help`, `lsp/`: 8,039 lines of Teal, 3 fewer entries on the allow-list, and no `any` or `paw.Untyped` in these modules | 4,900 | wave 3 |
| Done | The frontend | `frontend`, `remote`, `render`, `media`: 5,290 lines of Teal, 9 fewer entries on the allow-list, and no `any` or `paw.Untyped` in these modules | 3,800 | wave 3 |
| 5 | Keys and views | `keymap`, `keyrule`, `keybar`, `defaults/`, `views/`, `roles/` | 15,000 | wave 4, and the work on the keys that runs now |
| 5 | Extensions | one agent for each: `notation` (20,000), `utau` (8,000), `plugstate` (5,700), `interop` (4,000), the others (under 3,200 each) | 60,000 | the modules of paw that each uses |

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

## What the checker found in the contracts

- Teal compares a method of a record with the method that the record
  declares. So a method of a view in Teal has each parameter of
  `paw.contracts.View`, also a parameter that it does not use. A function
  in a table can have fewer: the contracts make such parameters optional.
- `paw.pick.sources` holds pickers of items of different types. The map
  holds `paw.contracts.PickInfo`, the fields that each picker has, and a
  picker of an extension is a `PickSource` of its own items.
- `paw.ext.current` and `paw.ui.float` are nil until something sets them,
  so a module that reads the table does not find them. `tools/apidoc.lua`
  reads the `@type` line over the line that sets each one.
- The checker found no error that changed what the code does: the tests
  pass with no change.

## What the checker found in the project

- In Teal, `value is integer` becomes a call of `math.type`, which LuaJIT
  does not have. So such a test stopped with an error when it ran. Now
  paw loads compat-5.3, which gives `math.type`: see
  [The standard library](#the-standard-library).
  `paw.track` and `Lane:state_index` take a number or a text, and test
  for a number, as the Lua did.
- A method of an object has the name of a field of the kernel:
  `track:devices()`, `track:clips()`, `clip:track()` and
  `lane:states()`. The method comes first, so the object does not give
  the field. The records leave out these fields, and `get` gives them.
- A setter takes a table of changes, and a table holds no nil. An
  object sets a field to nil (`track.output = nil`) with the key form, as
  the Lua did.
- `paw.address.resolve` gives a thing of the kind of its address: a
  track, a note, a parameter, an item of an extension. Teal has no union
  of several records, so the result is `paw.address.Thing`, and a caller
  casts it by the kind of the address.
- In Teal, `paw.Track` and the other objects are types, not values. A
  test such as `getmetatable(value) == paw.Track` is for Lua.
- `paw.contracts.Selector` did not have `pitch` and `value`, which
  `paw.address` names and the locator of the piano roll gives. It has
  them now. A view's locator is a contract too: `paw.contracts.Locator`.
- `ipairs(clip:notes())` gave `ipairs` two values. Teal wants the first
  only, in parentheses. What the code does is the same.

## What the checker found in the music on the project

- `value is integer` stopped with an error, as in the project (see
  above). Now the kernel gives the Lua state a `math.type`, so the test
  works. These ports test for the table all the same: a lane is
  `integer | types.Lane`, and the port tests `lane is types.Lane`.
- A table of changes cannot hold nil. When `paw.groups` sends a track to
  the master, the output is nil, so the port uses the key form
  (`track_set(id, "output", nil)`) there.
- `paw.groups.rows` gives the tracks, or with `{ lanes = true }` the rows
  of the lanes too: two types for one function. Teal sees only the form
  without options, and calls `paw.lanes.lines()` for the rows with lanes.
  Lua keeps both forms.
- `paw.api.clip_notes` gives two values. `ipairs` of the call gets both,
  and Teal finds the extra argument. The ports keep the list in a variable
  first.
- `track_get(id, "meta")` and `project_get("edits")` give one entry and are
  quicker than the whole table. Teal does not see these forms. The ports
  keep them, with a cast of the function, because `paw.groups.rows` and
  `paw.harmony.fresh` run each time that paw draws.
- The function that `paw.commands.define` gets must give a
  `commands.Result`. A command in Teal that gives nothing declares
  `: commands.Result`. The function that `paw.command` gets
  (`contracts.Command`) can give nothing.
- `paw.harmony.read` gives its types now (`read.Note`, `read.Chord`), and
  `read.Note` is an interface, so the notes of the song (`paw.harmony.notes`,
  with their track and clip) go to `read.chords` with no cast.
  `tools/apidoc.lua` declares `paw.harmony.read` and `paw.harmony.voice` in
  the record of `paw.harmony`.
- `paw.lanes.changed` and `paw.harmony.changed` are the descriptors of
  `lanes.changed` and `harmony.changed`.
- The checker found no error that changed what the code does: the tests
  pass with no change.

## What the checker found in the drawing

- The part of a strip that shows (`px.view` of `buf:strip`) had the type
  `{number}` in the contracts. paw gives `{ x, y, w, h }`, and
  `paw.plot` reads `view.x` and `view.w`. The type is `types.Rect` now.
- `shrink` of a status line component had the type `string`. The project
  component gives `true`, and the line uses it as a flag. The type is
  `boolean` now.
- Some fields that the code reads and writes were not in the contracts:
  the roles that a painted view marks over its picture (`ctx.marks`, the
  playhead of notation), where in a plane a press is (`e.at`), the label of
  a button of a hit list, and `hit` and `cells` of a plane. The contracts
  have them now. `contracts.Axis` is `types.SceneAxis`, which the kernel
  reads.
- The glyphs (`paw.draw.g`) were a table of text or lists in the context
  of a status line component. They are the record `contracts.Glyphs` now,
  and the theme of the context has the groups of the sections.
- `paw.buf` and `paw.roles` need the types of each other. When two modules
  require each other's types, Teal makes two copies of a type, and the
  copies do not agree. So `paw.roles` puts `mark`, `hit` and `plane` on
  the buffer when it loads, and `paw.buf` needs nothing of it.
- `paw.limit.named` takes arguments of one type. The calls of the mouse
  with a view and an event give a closure.
- `tools/apidoc.lua` declared `paw.ui.Buf`, a module in Teal under a
  module in Lua, as a record of `paw.ui`, which the declaration of the
  global could not read. Such a module is left out until its parent is in
  Teal. The fields of a module in Lua that are functions or tables of a
  module in Teal have their type in `partial.d.tl` now (`paw.ui.roles`).
- The checker found no error that changed what the code does: the tests
  pass with no change. A frame on the screen takes the same time as
  before: `bench/redraw.lua` with 16 tracks gives the same median, in the
  spread of six runs of each.

## What the checker found in Ex and the text buffers

- `paw.command` was `paw.Untyped`. The types of a command (its context,
  range and result) were in `paw/commands.tl`, and `partial.d.tl`, which
  types the modules in Lua, cannot require that module: the two require
  each other. These types are contracts now (`paw.contracts.CommandContext`,
  `CommandRange`, `CommandResult`, `CommandOptions` and the others), so
  `paw.command` has the type `paw.contracts.Command`. The function that it
  gets can give nothing.
- The range of a command had five fields in the types. `paw.ex` gives it
  eleven more (the region of a selection, its pitches, the matches of
  `:g`, the clips of a view). `paw.contracts.CommandRange` has all of
  them. The items, the fields of patterns and the views of ranges are
  contracts too (`ExItem`, `ExField`, `ExChange`, `ExView`), and
  `paw.query` uses them in place of records of its own.
- The piano roll told Ex its track with `clip.track`. On a `paw.Clip`,
  `track` is a method, so the piano roll gave a function, not a track.
  `:mute` with no range in the piano roll failed. It gives the id now,
  and a test types `:mute` there.
- `paw.time.signature_at` gives two numbers, but Ex also read a table
  from it. The port reads the numbers only.
- `:transpose` took any number. A part of a semitone made a pitch that is
  not a whole number. It takes whole numbers only now.
- A place of a mark was `{string:number}` in `contracts.Grid`. The arrange
  view keeps `{ track, beat }`, and a text buffer keeps its row, its
  column and the name of the buffer. `paw.contracts.GridMark` has them.
- `ctx.kind` of the functions and keys of a kind of text buffer had the
  type `string` in the contracts. paw gives the kind itself, and the
  files' kinds read `ctx.kind.tree`. Its type is
  `paw.contracts.TextKindInfo` now.
- The second argument of the `status` of a kind of text buffer had the
  type `string`. It is the context of the status line
  (`paw.contracts.StatusContext`).
- `paw.textbuf.changes` gives the lines that do not read, the row
  of each line, and `moved`, true when the lines moved. `contracts.TextChanges` and
  `contracts.TextLine` have these fields now. The fields of a region of
  the keymap that a text buffer reads (`visual`, `object`, `unstretched`)
  and the clips of a selection in the arrange view are in
  `contracts.Region`.
- The text made its methods read-only: it put new methods in their place when it loaded.
  Teal cannot type that, so each method that changes the text asks first.
- A kind's functions run in `pcall`, which gives no types. The port calls
  them in a closure that keeps their results.
- `paw.textbuf.plan` gave the changes as a third value when it found a
  plan. Nothing read it, and Teal cannot give a value of two types in one
  place, so it gives the plan only.

## What the checker found in the queries and lists

- A fix of a diagnostic can be a function (`apply`). `paw.diagnostic.apply`
  gives it the diagnostic, but `:cfix` gives it the entry of the quickfix
  list. The two records are different, so the port casts the fix where a
  diagnostic becomes an entry (`paw.qf.from_diagnostics`). The fixes of
  paw and of its extensions do not read the value, so the port keeps
  this behavior.
- The function `paw.qf.fix` wrote a field `entry` into the changes of each fix, to
  count the fixes that it made. These changes are the tables of the fix.
  The port keeps a separate table from each change to its entry.
- The function `paw.qf.changed(source)` has the name of the event, so the descriptor of the event
  `qf.changed` is `paw.qf.event`. The descriptors of the other events are
  `paw.diagnostic.changed`, `paw.complete.changed`,
  `paw.snippet.expanded` and `paw.snippet.finished`.
- The quickfix list uses the types of `paw.diagnostic`, and `paw.diagnostic` calls
  `paw.qf.diagnostics`. Two modules in Teal cannot name the types of each
  other, so `paw.diagnostic` declares the part of `paw.qf` that it calls.
- The data of a node of a query is a record of its kind: a track, a clip,
  a note, a marker, a point. Teal has no union of several records, so a
  node holds `paw.contracts.QueryData`, and the port casts the data by the
  kind of the node. The root of the tree has the kind `project`, which
  `paw.contracts.QueryKind` did not have.
- The query module kept the item that `paw.ex` reads in a field of the node,
  which is not a field of `paw.contracts.QueryNode`. The port keeps it in
  a separate table.
- A query in the table form and a query that `paw.query.parse` read are
  both tables. Teal cannot tell two tables apart in a union, so one record
  (`paw.query.QueryTable`) has the fields of both.
- The functions `paw.limit.named` and `paw.seats.keep` take values of one type.
  `paw.complete` gives a source a closure, and `paw.complete` and
  `paw.snippet` keep the state of each seat in one record.
- The function `paw.snippet.pick` gives the picker that `paw.pick` opens. Its type says
  so now.
- The module `paw.structure` declared its own records for the nodes of a query. It
  uses the types of `paw.query` now.
- The checker found no error that changed what the code does: the tests
  pass with no change.

## What the checker found in the windows

- The type of `on_drop` of `paw.contracts.View` had a list of paths and an
  event. paw gives one event: the clip that the window let go over the
  view, and the cell (`e.clip`, `e.x`, `e.y`). The launcher reads that
  event. The contract is `on_drop(self, e)` now, and `MouseEvent` has
  `clip`.
- `paw.contracts.PointerEvent` did not have `col` and `row`, the cell of
  the screen under the pointer, which `paw.mouse` gives a view's `pointer`,
  or `clip`, which a window gives with `drop`. `MouseEvent` did not have
  `px` and `py`, the pixels that a terminal can give.
  `paw.contracts.LayoutBuffer` did not have `options`, which a buffer gets
  from its type.
- A window of the layout is also a node of the tree of its tab. So
  `paw.contracts.Window` is an interface now, and `paw.layout.Node` is a
  window or a split. `paw.layout` also gives the records of the tabs
  (`Tab`) and of the arrangement of the screen (`Arrangement`, with its
  borders and the areas for pixels).
- The tabs and windows that a project keeps have records in `types.tl`
  (`ProjectScreen`, `SavedLayout`, `SavedTab`, `SavedNode`), and the
  comments of `project_screen` and `project_screen_set` name them. Their
  two `any` go.
- A menu at the pointer is a contract: `paw.contracts.MenuItem`, or the
  text `"-"` for a line (`MenuEntry`). Teal cannot find the type of a list
  of a text and records in a table, so the ports put such a list in a
  variable of the type `{MenuEntry}` first.
- The modules that draw and the views name the types of `paw.ui`,
  `paw.layout` and `paw.mouse`. So these modules declare only the parts
  of the modules above them that they call (`paw.roles`, `paw.canvas`,
  `paw.statusline`, `paw.scene`). `paw.buf`, `paw.draw`, `paw.cursor` and
  `paw.commands` are below `paw.ui`: each declares the part of `paw.ui`
  that it reads. `paw.roles` and `paw.statusline` use the real types of
  `paw.ui`, `paw.mouse` and `paw.panes` now, and `paw.complete` uses
  `types.CellStyle` for a highlight group.
- A module in Teal that requires another module loads it at that time.
  `paw/ui.lua` used `paw.draw` when it drew, and `paw.draw` loads after
  `paw.ui`. So `paw/ui.tl` names only the types of `paw.draw`, and reads
  `paw.draw` when it draws, as before.
- The menus use the types of `paw.frontend`. Its `recent_menu` has the
  type of a choice of a range (`name`, `label`), but `paw.recent` gives
  `label` and `path`: the File menu casts the list. `paw.frontend`,
  `paw.remote`, `paw.render` and `paw.media` use the real types of
  `paw.mouse`, `paw.panes` and `paw.ui` (not yet the views of `paw.ui`,
  which `paw.frontend` reads as records of its own until wave 5).
- `paw.seats.keep` takes values of one type, so `paw.ui` and `paw.panes`
  keep the state of each seat in a record.
- `paw.layout.within` and `paw.limit.named` take arguments of one type, so
  the ports give them closures where a function takes more.
- The `grid` of a buffer type is a function in the contract, but a type
  in Lua can give a table. The port keeps both, as the Lua did.
- The checker found no error that changed what the code does: the tests
  pass with no change.

## What the checker found in the pickers, help and language servers

- A picker's items are of its own type, so the sources are generic:
  `paw.contracts.PickSource<T>`. `paw.pick` keeps the items of the open
  picker as `paw.pick.Item` and gives them back to the functions of the
  picker. The sources of the runtime are pickers of records
  (`paw.pick.sources.TrackLine`, `paw.help.Tag`, `paw.query.Node`).
- The picker of the Lua API walks the `paw` global, whose tables also
  have number keys. The first port read each key as a name, and the
  search tests found the error. The port tests that a key is a name, as
  the Lua did.
- `paw.pick.sources` held `_walk`, a function that is no picker, for a
  test. The function is `paw.pick.walk` now, and the test calls it there.
- The place of the pointer is a number, and a row of the picker is an
  integer. The port rounds the place down to the row that it is in.
- `paw.contracts.Selector` did not have `seconds`, the time range in a
  render that a one-shot server gives, or `line` and `col`, which help
  gives for its pages. It has them now.
- A one-shot server with a command of one word as text stopped with an
  error, because its command was read as a list. It is a list of one word
  now, as for a server that runs as a process.
- The `edit` of an item that a server suggests went to `paw.complete`,
  which does not read it. The port does not send it.
- A message of JSON-RPC is a record (`paw.lsp.rpc.Message`). The
  parameters and the result of a message are `paw.lsp.rpc.Payload`, a
  record with no fields: each handler casts it to the record of its
  method. The settings of a server are JSON values (`paw.util.Data`).
- The records that the adapters and paw share (a client, its config, a
  document, an adapter) are in paw/lsp/standard.tl. paw/lsp/init.tl
  requires that module, so the two modules do not need the types of each
  other.
- `lsp.status` and `lsp.analysis` have the descriptors
  `paw.lsp.status_changed` and `paw.lsp.analysed`.
- `paw.pick` needs the types of `paw.qf` and `paw.commands`, and these
  modules call `paw.pick`. So `paw.commands`, `paw.grep`, `paw.takes`,
  `paw.markers`, `paw.diagnostic` and `paw.snippet` declare the part of
  `paw.pick` that they call.

## What the checker found in the frontend

- The gesture `act.glue_clips` kept the error of a glue of audio clips and
  the result of the glue in one variable. When the glue failed, the message
  said "false" and not the error. The port keeps the error in a variable of
  its own, so the message gives it. A test makes sure of this.
- `paw.frontend.state` is what the window reads. It has records now:
  `paw.frontend.State`, with `Modal`, `ProjectState`, `TrackState`,
  `ClipState`, `DeviceState` and `Routing`. `paw.remote` sends the parts
  of the state by these records.
- The prompt of the modal state holds the candidates that show, but
  `paw.views.cmdline` gives a list of all the candidates. The port gives the
  prompt of the state a record of its own, over the same table.
- The window sends some flags as `true` or `1`, and the mode of a choice as
  a number or a word. The gestures take these forms
  (`free?: boolean | integer`, `mode: integer | string`).
- `act.set_velocity` gave the place of the note for one note, and nothing
  for several notes. Its type says so now: an integer, or nil.
- `paw.render` was a function, with the module of the render out of
  reach. Now `paw.render` is the module, and a call of it renders:
  `paw.render(path, opts)` is `paw.render.render(path, opts)`. The other
  names (`paw.render_stems`, `paw.render_status` and the others) are the
  functions of the module, so they have its types. `paw.render_ranges` is
  the table of the ranges itself, not a table that passes each key on.
- The options of `paw.render` are the kernel's options, and also the
  options that only Lua knows: `range`, `rate`, `channels` as a word,
  `background` and `format`. They are a record of their own,
  `paw.render.Options`. `render.before` and `render.finished` have
  descriptors (`paw.render.before`, `paw.render.finished`).
- `paw.media.glue` takes a list of clips, or one clip without a list. Teal
  cannot give two table types to one parameter, so its type is the list.
  Lua can give one clip as before.
- `paw.mouse.hint_text` and `paw.takes.count` were called two times for one
  value. The port calls each one time.
- `paw.lanes`, `paw.curves` and `paw.query` call `paw.frontend`, and
  `paw.frontend` names their types. So these modules declare the part of
  `paw.frontend` that they call.
- The checker found no other error that changed what the code does: the
  other tests pass with no change.
- The frontend is as fast as before. With 16 tracks, the state that a
  window gets for each frame takes 16.4 µs before and 16.6 µs after, in
  the spread of six runs of each. It makes 2.1 KB of garbage before and
  after. A key with its frame,
  `bench/redraw.lua` and the state after an edit give the same median, in
  the spread of the runs.
