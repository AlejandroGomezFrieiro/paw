# About Teal in paw

paw writes its new code in Teal, which is Lua with types. A checker finds
type errors before the code runs, and the compiler makes plain Lua. The
page explains why paw uses Teal and how Teal and Lua work together in paw.
It also gives the plan to move the Lua of paw to Teal.

## Why a language with types

The runtime of paw has about 60,000 lines of Lua, and the extensions have
about 60,000 more. In Lua, a wrong field name or a value of the wrong kind
shows only when that line runs, but a checker finds such errors in all of
the code at one time. An editor can also complete the names of fields and
functions, because it knows the type of each value.

## Why Teal

paw looked at the following languages:

| Language | What it is | Why paw does not use it, or uses it |
|---|---|---|
| Teal | Lua with types; its compiler is a Lua library | paw uses it. It makes Lua 5.1, which LuaJIT runs as it is: the JIT and the FFI stay. paw contains the compiler, so a `.tl` file loads with no build step. A file can have types or not, so code moves one file at a time. |
| TypeScriptToLua | TypeScript that compiles to Lua | It needs Node.js to compile. The Lua that it makes adds a library for the parts of TypeScript that Lua does not have. |
| Luau | The language with types of a game platform | It is a different virtual machine. LuaJIT cannot run Luau's own syntax, so each file needs a step that removes the types, and the checker is a separate program. |
| LuaLS annotations | Comments with types, read by the Lua language server | The types are comments. Nothing makes the code agree with them, and the program does not check them when it builds. |
| Fennel, YueScript | Other syntax that compiles to Lua | They give a different syntax, not types. |

paw can load each of these languages through the same registry of
languages (`paw.lang.add`), and Teal is only the first entry, which comes
with paw.

## How Teal and Lua work together

Teal code runs in three places in paw, which are the runtime, the
extensions and the configuration. The sections below explain how paw
compiles and checks each of them, and how Teal code gets the types of the
kernel and of the Lua modules.

### The runtime

A module of the runtime in Teal is a `.tl` file in `runtime/lua`. The build
compiles it to Lua and then to bytecode, as it does with each Lua module,
so paw does not compile it when it starts.

### Extensions and the configuration

paw compiles an `init.tl`, a one-file `name.tl` or a module in `.tl` when
it loads the file. paw keeps the Lua in `~/.cache/paw/lang`, by the
contents of the file, so a file compiles one time, and paw loads the
compiler only when a file is not in the cache.

### The build and the loader check the types

In some places, the Lua that Teal makes depends on the types. For example,
`value is Fn`, where `Fn` is a name of a function type, is a test for a
function. The build and the loader therefore compile as `tl gen` does,
after a check. The build stops at a type error in the runtime.

A file of an extension or of the configuration with type errors loads all
the same. paw
shows the errors one time, when it compiles the file, and
`:checkhealth teal` lists them.

### What a check reads

The program contains the declarations of `runtime/types` and the modules
of the runtime in Teal (`paw.api.runtime_file`). The first check in a run
reads the types of all of them, in about half a second, and that time is
not part of the time limit on Lua. The cache key of a file includes a hash
of the types, so a file compiles again when the types of paw change. A file
in the cache costs no check.

### The functions in Rust

`runtime/types/paw/api.d.tl` declares `paw.api`, which is the set of
functions of the kernel. `tools/apidoc.lua` makes the file from the
comments of the files of `crates/paw-core/src/api/` and of the other files
that add to `paw.api` (`fs_api.rs`, `tempo_api.rs`, `luadev_api.rs`,
`scene.rs` and `measure/mod.rs`). It reads the Rust type of each parameter,
a `// @param name T` line, and a `// @return T` line.

A function with more than one form instead has a `// @type function(...)`
line for each form, e.g., `part_set(id, patch)` and
`part_set(id, key, nil)`. A form whose type follows from the value of an
argument is not declared, so Lua can call `part_get(id, "name")`, and Teal
calls `part_get(id).name`. The records of the data that crosses `paw.api`
are in `runtime/lua/paw/types.tl`, and each record agrees with the Rust
code that makes or reads the table.

### The records that Rust makes

Some data has its shape in a Rust type, and `tools/apidoc.lua` makes the
Teal records from that type. `crates/paw-core/src/events.rs` gives each
event of the kernel and its payload, and the tool makes
`paw.events.kernel`, with a record for each payload and a descriptor for
each event (`paw.on(kernel.project_saved, function(p: kernel.Saved) ...
end)`).

`crates/paw-scene/src/props.rs` gives the props of each role that the
window paints, and the tool makes `runtime/types/paw/role_props.d.tl`
from it. The window reads the props with the same Rust types, so the
records agree with what the window reads.

### The global `paw`

`runtime/types/paw.d.tl` gives `paw.api`, and it gives each module of the
runtime that is in Teal with the types of its own code. A module that is
still in Lua gives types only for the functions and values that its doc
comments type. It uses a `--- @type function(...)` line over a function,
with one line for each form, and a `--- @type T` line over a value
(`M.views = {}`).

`runtime/types/paw/partial.d.tl` collects those types, with one record for
each module. All the other parts of a module in Lua have the type
`paw.Untyped`. A Teal file can call them, and it casts what it keeps, e.g.,
`paw.routes.reached(id) as {integer:boolean}`. When the module moves to
Teal, its types replace `paw.Untyped`.

### A module of the runtime and the global `paw`

The declaration of the global `paw` requires each module of the runtime
that is in Teal, so such a module cannot use the types of the global,
because the checker reads the module before the global exists. A module
gets the kernel's functions with `require("paw.api")`, and the modules in
Teal with `require`.

For the modules that are still in Lua, a module can take the global as
`Untyped`, the type in `runtime/types/paw/untyped.d.tl`, with `local paw =
(_G as {string:Untyped}).paw`. `paw.Untyped` is the same type. A better
choice is to take the global as `partial.Paw`, which holds the parts that
the modules in Lua type (`local type partial = require("paw.partial")`).
The module can then add the parts that it reads of the modules in Teal,
with `local record Paw is partial.Paw`, and `paw.hooks` and `paw.commands`
do so.

### Other names of a value

`paw.on` is `paw.events.on`, and `paw.opt` is `paw.option.opt`.
`tools/apidoc.lua` gives such a name the type of the value in its module,
which is the signature of the function in the source, or the type of the
field in the record of the module.

## The standard library

Teal's checker declares the Lua 5.3 standard library, but LuaJIT, which
runs paw, has the Lua 5.1 library and some parts of the Lua 5.2 library.
The code that Teal makes calls parts of the Lua 5.3 library. For example,
`value is integer` calls `math.type`, and the operators `&`, `|`, `~`,
`<<` and `>>` call `bit32`. The operator `//` calls `math.floor`, which
LuaJIT has.

paw therefore loads lua-compat-5.3 (release 0.14.4, MIT license,
`runtime/lua/compat53`) when the program starts, before the runtime and
before each extension. It changes the global functions, so the code in Teal
and the code in Lua use one library. `runtime/lua/paw/compat.tl` loads it
and adds the parts that it does not have in Lua:

- New functions and modules:
  - `math.type`, `math.tointeger`, `math.ult`, `math.maxinteger` and
    `math.mininteger`. An integer is a whole number from -2^53 to 2^53,
    and outside that range a number is a `"float"`, as compat-5.3 tells.
  - `table.unpack`, `table.pack` and `table.move`, `rawlen`, `utf8` and
    `bit32`. paw writes `utf8` and `bit32` in Teal, and they give the same
    results as Lua 5.3 and Lua 5.2, and LuaJIT compiles them. `bit32` uses
    LuaJIT's `bit`.
- Functions that behave as in Lua 5.3:
  - `pairs` uses `__pairs`.
  - In the main code, `coroutine.running` gives the main coroutine and
    `true`. In Lua 5.1, it gave `nil`.
  - `file:write` and `io.write` give the file, and `file:read`, `io.read`
    and `io.lines` accept `"l"`, `"n"` and `"a"` without `*`.
  - `os.execute` gives `true` or `nil`, then `"exit"` and the exit code.
    In Lua 5.1, it gave only the code.
- Functions that stay as they are. `load`, `loadstring`, `string.rep` and
  `string.format` stay LuaJIT's, because they already do what Lua 5.3
  does, and `bit`, `ffi` and `jit` stay.

Some parts of compat-5.3 are not in paw:

- The parts of compat-5.3 in C, and `string.pack`. A call of a C function
  stops the code that LuaJIT compiles, so use `ffi` to pack bytes.
- The forms of `string.find`, `string.match`, `string.gsub` and
  `string.gmatch` that accept a zero byte in a pattern. They made a search
  for plain text 250 times slower and a match 2 times slower, so write `%z`
  for a zero byte in a pattern.
- The `ipairs` that follows `__index`. It is a Lua function, and short loops
  over it run slowly. `ipairs` stays LuaJIT's own, so it reads only the
  items that a table holds itself. To walk a table that gets its items from
  `__index`, count with a `for` loop.

paw keeps `gen_compat = "off"` in `tlconfig.lua`, so a compiled file starts
with no extra lines. The devices written in Lua run in a Lua state of
their own on the audio thread, without compat-5.3.

## The contracts

An extension gives tables to paw, e.g., a view, a buffer type, a kind of
text buffer, a kind of part, a role or a picker. A status line component,
a query field, a source of grep and a health check are tables too.

The tables are the contracts between paw and the extensions.
`runtime/lua/paw/contracts.tl` gives a type to each one, with the fields
that the runtime reads. The module has only types, and it requires only
`paw.types` and the types of `paw.objects`, which requires no contract. The
modules in Lua can therefore name the contracts in their `@type` lines
before they move to Teal, and a module in Teal can require the contracts.

In an extension, the contracts are `paw.contracts.View`,
`paw.contracts.PickSource<T>` and the others. The functions that take a
contract take it with its type. They are `paw.ui.view`, `paw.buftype`,
`paw.textbuf.kind`, `paw.part_kinds.define`, `paw.clip_kinds.define`,
`paw.roles.define`, `paw.statusline.component`, `paw.query.field`,
`paw.grep.source`, `paw.health.register`, `paw.pick`, `paw.pick.sources`
and `paw.ui.menu`. The checker therefore finds a field with a wrong name,
e.g., `on_keys` for `on_key`. A picker is generic, so the type of its items
goes to `format`, `on_choose` and the other functions.

The options have types too. `runtime/types/paw/opts.d.tl` gives the type
of each option that the runtime defines, from its default and its rules,
so `paw.opt.zoom` is a number with no cast. `tools/apidoc.lua` makes the
file. `paw.option.define` gives a handle with the type of the default, so
after `local lanes = paw.option.define("lanes", 4)`, `lanes:get()` is a
number.

## The rule for `any`

Write no `any` where the value has a shape. Give an options table a
record, an event payload a record, and a callback a function type. The
data of an extension in `meta` belongs to the extension, so it has a
record of the extension.

`runtime/types/any-allowed.txt` lists each `any` and each `paw.Untyped` of
the declarations by name, with the reason. The `any` of the records in
`types.tl` are on the list too, as `types.Record.field`, because an `any`
that moves from a function into a record is still an `any`.

The records of `contracts.tl` count in the same way, as
`contracts.Record.field`, and `tools/apidoc.lua check` fails on one that
is not on the list. When the comments of `api/` give a type, or a module
moves to Teal, `tools/apidoc.lua` lowers the count. A person adds an entry
only by hand, with a stated reason, so the count only goes down.

## What stays in Lua

Some code stays in Lua, each part for its own reason:

- `runtime/lua/paw/dsp.lua` and the devices written in Lua. They are code
  for the audio thread that uses the FFI of LuaJIT and its JIT. Teal adds
  no cost to them, but casts at each FFI call make the code harder to read,
  so they stay in Lua until the FFI declarations have types.
- Copies of programs from outside paw:
  - `runtime/lua/tl.lua`, the compiler of Teal (version 0.24.8, MIT
    license, `runtime/lua/tl.LICENSE`).
  - `runtime/lua/compat53`, lua-compat-5.3 (release 0.14.4, MIT license,
    `runtime/lua/compat53/LICENSE`), with no change.
- Generated files, which are `runtime/types/paw.lua` (for LuaLS) and the
  files of `runtime/types`.
- The test files. The runner loads them with `loadfile`, and they can move
  later.
- `tools/apidoc.lua` and `tools/tlcheck.lua`, because `paw -l` runs a Lua
  file. Each one is short. The generator of the reference and the types is
  Teal, in `tools/apidoc/`.

## The tools for Teal and Lua

The dev shell of the flake has the tools below. Each one uses Teal 0.24.8,
which is the version in `runtime/lua/tl.lua`, and LuaJIT, as paw does.

`tools/tlcheck.sh` checks the types of all of the Teal files with
`paw.lang.check`, the compiler in the program. It runs paw on
`tools/tlcheck.lua`. The test suite and the `teal` check of the flake run
the same check, so the three agree: each error and each warning fails,
for example a local that is not used or a name declared again. For the
source tree, it takes 4 seconds.

Before, `tools/tlcheck.sh` ran `cyan check`, which took 13 seconds and let
a warning pass that the suite refused. `cyan` still makes the Lua of
`tools/dev-runtime.sh` (`cyan gen`). The program `tl check` checks one file at a time, and it checks again each
module that the file uses. `tl` also compiles one file, e.g., to look at
the Lua that Teal makes (`tl gen`).

`teal-language-server` and `lua-language-server` give completion, types
and errors in an editor. The first reads `tlconfig.lua`, and the second
reads `.luarc.json`. See [How to configure an editor for paw's
code](../how-to/configure-an-editor-for-paws-code.md).

`luacheck` finds names that are not used and global names that are not
declared in the Lua files. `.luacheckrc` declares the global `paw`, and
the `lua` check of the flake runs `luacheck`. It found a function that the
import of MusicXML called outside the loop that declared it.

StyLua formats Lua, and cerulean (`ceru`) formats Teal. All of paw's code
is formatted with them, with the settings in `stylua.toml` and
`tools/fmtcheck.sh`. `tools/fmtcheck.sh fix` formats the tree, and the
`format` check of the flake fails when a file is not formatted. cerulean
cannot format `limit.tl`, `pick.tl` and `ui.tl`, because its output for
them is not valid Teal, so the check leaves them out.
`.git-blame-ignore-revs` names the commit that formatted the tree, for
`git blame --ignore-revs-file`.

`nix/lua-tools.nix` pins the tools that nixpkgs does not have, or has in an
old version or with a fault.

## The plan

The order goes from the bottom up, so a module moves after the modules that
it uses, and its types are then actual types and not `paw.Untyped`. Each
area is the work of one agent, and the areas of one wave do not depend on
each other.

| Wave | Area | Files | Lines of Lua | Depends on |
|---|---|---|---|---|
| Done | Music data | `music`, `bytes`, `attr`, `regex`, `harmony/read`, `harmony/voice`, `types` | 1,100 | `paw.api` |
| Done | Core services | `util`, `events`, `options`, `limit`, `hooks`, `seats`, `commands`, `lang`: 15 fewer `paw.Untyped` entries | 1,700 | none |
| Done | File formats | `xml`, `zip`, `markdown`, `formats`, `midifile`: 2,356 lines of Teal, 5 fewer `paw.Untyped` entries | 1,800 | none |
| Done | Kernel types | the `// @return` of `api/` and the other files that add to `paw.api`, and records in `types.tl`: 343 `any` of `paw.api` down to 20, and 5 in the records, each with its reason | 270 functions | none |
| Done | Contracts, Rust side | the events of the kernel as a Rust type, with a descriptor and a record for each; the setters take a table of changes (`part_set(id, patch)`), and `device_find_all` is separate from `device_find`; the props of the roles that the window paints as Rust types: 13 fewer `any` entries | 45 events, 7 functions, 21 roles | none |
| Done | Contracts, Lua side | `contracts.tl`, the `@type` lines of the modules in Lua (`partial.d.tl`) and the types of the options (`opts.d.tl`): 880 lines of Teal, 12 fewer `paw.Untyped` entries | 10 functions that register | wave 1 |
| Done | The project | `objects`, `cursor`, `edit`, `address`, `tempo`, `tempolane`, `markers`, `locators`: 4,408 lines of Teal, 24 fewer entries of `any-allowed.txt`, and no `any` or `paw.Untyped` in these modules | 3,100 | wave 1 |
| Done | Music on the project | `harmony`, `structure`, `takes`, `groups`, `vca`, `lanes`, `curves`, `audition`: 3,859 lines of Teal, 42 fewer entries on the allow-list | 3,000 | wave 1 |
| Done | Queries and lists | `query`, `grep`, `qf`, `diagnostic`, `complete`, `snippet`: 5,601 lines of Teal, 6 fewer entries on the allow-list, and no `any` in these modules | 3,900 | wave 2 |
| Done | Drawing | `buf`, `draw`, `canvas`, `roles`, `scene`, `theme`, `plot`, `statusline`: 4,740 lines of Teal, 6 fewer entries on the allow-list, and no `any` or `paw.Untyped` in these modules | 3,700 | wave 2 |
| Done | Windows | `ui`, `layout`, `panes`, `mouse`, `menu`, `mouse_menus`, `window_menus`: 6,100 lines of Teal, 10 fewer entries on the allow-list (with the two `any` of `project_screen`), and no `any` or `paw.Untyped` in these modules | 4,500 | wave 3 |
| Done | Editors: Ex and text buffers | `ex`, `textbuf`: 4,817 lines of Teal, `paw.ex` and `paw.command` typed (the types of commands are contracts now), 3 fewer entries on the allow-list, and no `any` or `paw.Untyped` in these modules | 4,100 | wave 3 |
| Done | Editors: pickers, help and language servers | `pick` and `pick/`, `help`, `lsp/`: 8,039 lines of Teal, 3 fewer entries on the allow-list, and no `any` or `paw.Untyped` in these modules | 4,900 | wave 3 |
| Done | The frontend | `frontend`, `remote`, `render`, `media`: 5,290 lines of Teal, 9 fewer entries on the allow-list, and no `any` or `paw.Untyped` in these modules | 3,800 | wave 3 |
| Done | The pencil of the piano roll | `roll_draw` (moved when it changed) and the new `chords`: 1,400 lines of Teal, 1 fewer entry on the allow-list, and no `any` in these modules | 350 | wave 4 |
| Done | Scopes | `scope`, when scopes got time ranges and levels: 905 lines of Teal, 1 fewer entry on the allow-list, and no `any` or `paw.Untyped` in this module | 380 | wave 3 |
| Done | Keys | `keymap` (with `keymap/registers` and `keymap/marks`), `keyrule`, `keybar`: 3,021 lines of Teal, 2 fewer entries on the allow-list, the 14 records that other modules kept of `paw.keymap` and the 4 of `paw.ui.keybar` gone, and no `any` or `paw.Untyped` in these modules | 1,950 | wave 4 |
| Done | The piano roll | `views/pianoroll`, `views/pianoroll_mouse`, `views/pianoroll_strip`, `roll_clips`: 3,701 lines of Teal, 1 fewer entry on the allow-list, the 10 records that other modules kept of the piano roll gone, and no `any` or `paw.Untyped` in these modules | 2,430 | the keys |
| Done | The arrange view | `views/arrange`, `views/arrange_mouse`, `roles/arrange`, and `views/arrange_part`, which the port split from the view: 4,450 lines of Teal, the 6 records that other modules kept of the view gone, and no `any` in these modules | 3,230 | the keys |
| 5 | Views | the rest of `defaults/`, `views/` and `roles/` | 12,000 | the keys |
| Done | Extensions: `interop` | the readers and writers of REAPER and DAWproject files: 6,300 lines of Teal, no `any` or `paw.Untyped`, and no function over 100 lines (the longest had 196) | 4,300 | the modules of paw that it uses |
| Done | Extensions: `plugstate` | the adapters, the library, the snapshots, the readers of the state of each framework and the client of TONE3000: 9,550 lines of Teal, no `any` or `paw.Untyped`, and no function over 50 lines | 6,400 | the modules of paw that it uses |
| Done | Tools: the generator | `tools/apidoc.lua` as readers that fill one model and one writer for each file it makes, in `tools/apidoc/`: 2,330 lines of Teal, files the same to the byte, and `apidoc check` in `nix flake check` | 1,660 | none |
| 5 | Extensions | one agent for each: the others (under 3,200 each). `notation` and `utau` do not move to Teal, because they become native extensions in Rust | 56,000 | the modules of paw that each uses |

The spike moved 1,100 lines in a part of a day, with the checker. An area
of wave 1 or 2 is about one day of work for one agent, and an area of wave
4 or 5 is two to four days. After each area, `paw.Untyped` has fewer
entries.

## What the checker found in the spike

The checker found no error that changed what the code does, and the tests
of the modules pass with no change. It found the following smaller
problems.

`paw.harmony.voice.voice` gave `bass = false` to a field that is a pitch
class elsewhere, so the port gives the options without `bass`.

Teal tells integers apart from other numbers. A sum that starts at `0` is
an integer, so a sum of distances needed the type `number`.

`unpack` is not in Teal's list of the global functions of Lua 5.1, and
`math.tointeger` is not in LuaJIT. The port copies a list with a loop, and
it casts with `as integer`.

`paw.regex` kept the text of a number and the number in one variable, and
the port gives each one a name.

## What the checker found in the core services

The checker found no error that changed what the code does, and the tests
pass with no change. It found the following limits and problems.

Teal has no generic list of arguments of different types. The functions
that call another function with its arguments (`paw.limit.guard`,
`paw.seats.within`, `paw.seats.keep`) therefore take arguments of one type,
and code in Teal that has more gives a closure or a record.

A function type with no results is not the type of a function with
results. An event handler in Teal can return nothing, so `paw.on` takes
`function(P, string)`. The module keeps the handler as the type that can
refuse, with `false, reason`.

`unpack`, `table.maxn`, `loadstring` and `jit` are not in Teal's list of
the library of Lua 5.1, so a record of those names casts `_G` one time.

The build and the loader compiled without the checker, and without it,
`value is Fn`, where `Fn` is a name of a function type, became a test for
a table. The tests found two such tests, because completion by a function
and the time limit around a wait did not work. Now the build and the loader
check the types before they compile.

An error in a module in Teal names its `.tl` file. `paw.failure` moves the
place in a `.tl` file to the end of the message, as it does for a `.lua`
file.

The compiler of Teal in paw has no declarations of its own, so `paw.lang`
declares the parts that it calls.

## What the contracts of the kernel found

What the code does is the same after the contracts of the kernel. Two tests
changed, because they used the forms that Teal does not see now
(`part_get(id, key)`, `device_find` with `all = true`). The contracts
found the following problems.

The kernel sent the payload of `project.saved` in two shapes, with the
files written when it saves a folder, and with the path only for a file.
The record `kernel.Saved` has both shapes, and the files are optional.

The kernel sent a key of a piano (`labels` of the `keyboard` role) as
`{ pitch, name, style }`, and the window read only the first two fields.
The record says so. A curve's `values` holds `false` where there is no
value, not nil.

A setter that takes a table cannot clear a field, because a table has no
entry for nil. The key form stays for that purpose, and Teal sees it only
with `nil` as its value.

## What the checker found in the file formats

The checker found the following problems in the file formats.

`paw.midifile` gave the name of a project from a function that returned
two values, and the second value, a count, went to `paw.api.project_set`
as an extra argument. The function now returns one value.

A time signature that `paw.midifile` read had a denominator that was not
an integer (`2 ^ n`), and it is an integer now. `paw.midifile` also added
a field to each tempo and signature to sort them, and then removed it, so
the port keeps the order in a separate table.

`paw.markdown.render` had a variable that it did not use.

`paw.formats.register` copied each field of the table that it got, also the
fields that are not part of a format. It copies the fields of a format now,
and an extension in Teal gets an error for a field with a wrong name
(`paw.formats.Format`).

The kernel's element, `types.XmlElement`, has no methods, and its
attributes are text or numbers. An element of `paw.xml` has methods, and an
attribute can also be true or false, which `xml_encode` writes, so
`paw.xml` casts between the two types where it calls the kernel.

## What the checker found in the contracts

The checker found no error that changed what the code does, and the tests
pass with no change. It found the following limits.

Teal compares a method of a record with the method that the record
declares. A method of a view in Teal therefore has each parameter of
`paw.contracts.View`, also a parameter that it does not use. A function in
a table can have fewer parameters, so the contracts make such parameters
optional.

`paw.pick.sources` holds pickers of items of different types. The registry holds
`paw.contracts.PickInfo`, which has the fields that each picker has, and a
picker of an extension is a `PickSource` of its own items.

`paw.ext.current` and `paw.ui.float` are nil until something sets them, so
a module that reads the table does not find them. `tools/apidoc.lua` reads
the `@type` line over the line that sets each one.

## What the checker found in the project

The checker found the following problems and limits in the project
modules.

In Teal, `value is integer` becomes a call of `math.type`, which LuaJIT
does not have, so such a test stopped with an error when it ran. Now paw
loads compat-5.3, which gives `math.type`, as
[The standard library](#the-standard-library) explains. `paw.part` and
`Lane:state_index` take a number or a text, and they test for a number, as
the Lua did.

A method of an object has the name of a field of the kernel, e.g.,
`part:devices()`, `part:clips()`, `clip:part()` and `lane:states()`. The
method comes first, so the object does not give the field. The records
leave out those fields, and `get` gives them.

A setter takes a table of changes, and a table holds no nil, so an object
sets a field to nil (`part.output = nil`) with the key form, as the Lua
did.

`paw.address.resolve` gives a thing of the kind of its address, e.g., a
part, a note, a parameter or an item of an extension. Teal has no union of
several records, so the result is `paw.address.Thing`, and a caller casts
it by the kind of the address.

In Teal, `paw.Part` and the other objects are types and not values, so a
test such as `getmetatable(value) == paw.Part` is for Lua.

`paw.contracts.Selector` did not have `pitch` and `value`, which
`paw.address` names and the locator of the piano roll gives, and it has
them now. A view's locator is a contract too, `paw.contracts.Locator`.

`ipairs(clip:notes())` gave `ipairs` two values, and Teal wants only the
first, in parentheses. What the code does is the same.

## What the checker found in the music on the project

The checker found no error that changed what the code does, and the tests
pass with no change. It found the following problems and limits.

`value is integer` stopped with an error, as in the project (see above).
Now the kernel gives the Lua state a `math.type`, so the test works. The
ports test for the table all the same, so where a lane is
`integer | types.Lane`, the port tests `lane is types.Lane`.

A table of changes cannot hold nil. When `paw.groups` sends a part to the
master, the output is nil, so the port uses the key form
(`part_set(id, "output", nil)`) there.

`paw.groups.rows` gives the parts, or with `{ lanes = true }` also the
rows of the lanes, which is two types for one function. Teal sees only the
form without options, and it calls `paw.lanes.lines()` for the rows with
lanes. Lua keeps both forms.

`paw.api.clip_notes` gives two values, so `ipairs` of the call gets both,
and Teal finds the extra argument. The ports keep the list in a variable
first.

`part_get(id, "meta")` and `project_get("edits")` give one entry and are
quicker than the whole table, but Teal does not see those forms. The ports
keep them with a cast of the function, because `paw.groups.rows` and
`paw.harmony.fresh` run each time that paw draws.

The function that `paw.commands.define` gets must give a
`commands.Result`, so a command in Teal that gives nothing declares
`: commands.Result`. The function that `paw.command` gets
(`contracts.Command`) can give nothing.

`paw.harmony.read` gives its types now (`read.Note`, `read.Chord`), and
`read.Note` is an interface, so the notes of the song
(`paw.harmony.notes`, with their part and clip) go to `read.chords` with
no cast. `tools/apidoc.lua` declares `paw.harmony.read` and
`paw.harmony.voice` in the record of `paw.harmony`.

`paw.lanes.changed` and `paw.harmony.changed` are the descriptors of
`lanes.changed` and `harmony.changed`.

## What the checker found in the drawing

The checker found no error that changed what the code does, and the tests
pass with no change. A frame on the screen takes the same time as before,
because `bench/redraw.lua` with 16 parts gives the same median, in the
spread of six runs of each. The checker found the following problems in
the types.

The part of a strip that shows (`px.view` of `buf:strip`) had the type
`{number}` in the contracts. paw gives `{ x, y, w, h }`, and `paw.plot`
reads `view.x` and `view.w`, so the type is `types.Rect` now.

`shrink` of a status line component had the type `string`. The project
component gives `true`, and the line uses it as a flag, so the type is
`boolean` now.

Some fields that the code reads and writes were not in the contracts, and
the contracts have them now. They are the roles that a painted view marks
over its picture (`ctx.marks`, the playhead of notation), where in a plane
a press is (`e.at`), the label of a button of a hit list, and `hit` and
`cells` of a plane. `contracts.Axis` is `types.SceneAxis`, which the kernel
reads.

The glyphs (`paw.draw.g`) were a table of text or lists in the context of a
status line component. They are the record `contracts.Glyphs` now, and the
theme of the context has the groups of the sections.

`paw.buf` and `paw.roles` need the types of each other. When two modules
require each other's types, Teal makes two copies of a type, and the copies
do not agree. `paw.roles` therefore puts `mark`, `hit` and `plane` on the
buffer when it loads, and `paw.buf` needs nothing of it.

`paw.limit.named` takes arguments of one type, so the calls of the mouse
with a view and an event give a closure.

`tools/apidoc.lua` declared `paw.ui.Buf`, a module in Teal under a module
in Lua, as a record of `paw.ui`, which the declaration of the global could
not read. Such a module is left out until its parent is in Teal. The fields
of a module in Lua that are functions or tables of a module in Teal have
their type in `partial.d.tl` now (`paw.ui.roles`).

## What the checker found in Ex and the text buffers

The checker found the following problems in Ex and the text buffers,
including two bugs that a user could see.

`paw.command` was `paw.Untyped`. The types of a command (its context, range
and result) were in `paw/commands.tl`, and `partial.d.tl`, which types the
modules in Lua, cannot require that module, because the two require each
other. The types are contracts now (`paw.contracts.CommandContext`,
`CommandRange`, `CommandResult`, `CommandOptions` and the others), so
`paw.command` has the type `paw.contracts.Command`. The function that it
gets can give nothing.

The range of a command had five fields in the types, and `paw.ex` gives it
eleven more, e.g., the region of a selection, its pitches, the matches of
`:g` and the clips of a view. `paw.contracts.CommandRange` has all of them.
The items, the fields of patterns and the views of ranges are contracts
too (`ExItem`, `ExField`, `ExChange`, `ExView`), and `paw.query` uses them
in place of records of its own.

The piano roll told Ex its part with `clip.part`. On a `paw.Clip`,
`part` is a method, so the piano roll gave a function and not a part, and
`:mute` with no range in the piano roll failed. It gives the id now, and a
test types `:mute` there.

`paw.time.signature_at` gives two numbers, but Ex also read a table from
it, so the port reads the numbers only.

`:transpose` took any number, and a part of a semitone made a pitch that is
not a whole number. It takes whole numbers only now.

A place of a mark was `{string:number}` in `contracts.Grid`. The arrange
view keeps `{ part, beat }`, and a text buffer keeps its row, its column
and the name of the buffer, so `paw.contracts.GridMark` has them.

`ctx.kind` of the functions and keys of a kind of text buffer had the type
`string` in the contracts. paw gives the kind itself, and the files' kinds
read `ctx.kind.tree`, so its type is `paw.contracts.TextKindInfo` now. The
second argument of the `status` of a kind of text buffer had the type
`string`, but it is the context of the status line
(`paw.contracts.StatusContext`).

`paw.textbuf.changes` gives the lines that do not read, the row of each
line, and `moved`, which is true when the lines moved.
`contracts.TextChanges` and `contracts.TextLine` have those fields now. The
fields of a region of the keymap that a text buffer reads (`visual`,
`object`, `unstretched`) and the clips of a selection in the arrange view
are in `contracts.Region`.

The text module made its methods read-only by putting new methods in their
place when it loaded. Teal cannot type that, so each method that changes
the text asks first.

A kind's functions run in `pcall`, which gives no types, so the port calls
them in a closure that keeps their results.

`paw.textbuf.plan` gave the changes as a third value when it found a plan.
Nothing read the value, and Teal cannot give a value of two types in one
place, so the function gives the plan only.

## What the checker found in the queries and lists

The checker found no error that changed what the code does, and the tests
pass with no change. It found the following limits and problems.

A fix of a diagnostic can be a function (`apply`). `paw.diagnostic.apply`
gives the function the diagnostic, but `:cfix` gives it the entry of the
quickfix list. The two records are different, so the port casts the fix
where a diagnostic becomes an entry (`paw.qf.from_diagnostics`). The fixes
of paw and of its extensions do not read the value, so the port keeps the
behavior.

The function `paw.qf.fix` wrote a field `entry` into the changes of each
fix, to count the fixes that it made, but the changes are the tables of the
fix. The port keeps a separate table from each change to its entry.

The function `paw.qf.changed(source)` has the name of the event, so the
descriptor of the event `qf.changed` is `paw.qf.event`. The descriptors of
the other events are `paw.diagnostic.changed`, `paw.complete.changed`,
`paw.snippet.expanded` and `paw.snippet.finished`.

The quickfix list uses the types of `paw.diagnostic`, and
`paw.diagnostic` calls `paw.qf.diagnostics`. Two modules in Teal cannot
name the types of each other, so `paw.diagnostic` declares the part of
`paw.qf` that it calls.

The data of a node of a query is a record of its kind, e.g., a part, a
clip, a note, a marker or a point. Teal has no union of several records, so
a node holds `paw.contracts.QueryData`, and the port casts the data by the
kind of the node. The root of the tree has the kind `project`, which
`paw.contracts.QueryKind` did not have.

The query module kept the item that `paw.ex` reads in a field of the node,
which is not a field of `paw.contracts.QueryNode`, so the port keeps it in
a separate table.

A query in the table form and a query that `paw.query.parse` read are both
tables. Teal cannot tell two tables apart in a union, so one record
(`paw.query.QueryTable`) has the fields of both.

The functions `paw.limit.named` and `paw.seats.keep` take values of one
type. `paw.complete` therefore gives a source a closure, and
`paw.complete` and `paw.snippet` keep the state of each seat in one record.

The function `paw.snippet.pick` gives the picker that `paw.pick` opens, and
its type says so now. The module `paw.structure` declared its own records
for the nodes of a query, and it uses the types of `paw.query` now.

## What the checker found in the windows

The checker found no error that changed what the code does, and the tests
pass with no change. It found the following problems and limits.

The type of `on_drop` of `paw.contracts.View` had a list of paths and an
event. paw gives one event, which holds the clip that the window let go
over the view and the cell (`e.clip`, `e.x`, `e.y`), and the launcher reads
that event. The contract is `on_drop(self, e)` now, and `MouseEvent` has
`clip`.

`paw.contracts.PointerEvent` did not have `col` and `row`, the cell of the
screen under the pointer, which `paw.mouse` gives a view's `pointer`. It
also did not have `clip`, which a window gives with `drop`. `MouseEvent`
did not have `px` and `py`, the pixels that a terminal can give, and
`paw.contracts.LayoutBuffer` did not have `options`, which a buffer gets
from its type.

A window of the layout is also a node of the tree of its tab, so
`paw.contracts.Window` is an interface now, and `paw.layout.Node` is a
window or a split. `paw.layout` also gives the records of the tabs (`Tab`)
and of the arrangement of the screen (`Arrangement`, with its borders and
the areas for pixels).

The tabs and windows that a project keeps have records in `types.tl`
(`ProjectScreen`, `SavedLayout`, `SavedTab`, `SavedNode`), and the
comments of `project_screen` and `project_screen_set` name them, so their
two `any` go.

A menu at the pointer is a contract, which is `paw.contracts.MenuItem`, or
the text `"-"` for a line (`MenuEntry`). Teal cannot find the type of a list
of a text and records in a table, so the ports put such a list in a
variable of the type `{MenuEntry}` first.

The modules that draw and the views name the types of `paw.ui`,
`paw.layout` and `paw.mouse`, so those modules declare only the parts of
the modules above them that they call (`paw.roles`, `paw.canvas`,
`paw.statusline`, `paw.scene`). `paw.buf`, `paw.draw`, `paw.cursor` and
`paw.commands` are below `paw.ui`, and each declares the part of `paw.ui`
that it reads. `paw.roles` and `paw.statusline` use the actual types of
`paw.ui`, `paw.mouse` and `paw.panes` now, and `paw.complete` uses
`types.CellStyle` for a highlight group.

A module in Teal that requires another module loads it at that time.
`paw/ui.lua` used `paw.draw` when it drew, and `paw.draw` loads after
`paw.ui`, so `paw/ui.tl` names only the types of `paw.draw`, and it reads
`paw.draw` when it draws, as before.

The menus use the types of `paw.frontend`. Its `recent_menu` has the type
of a choice of a range (`name`, `label`), but `paw.recent` gives `label`
and `path`, so the File menu casts the list. `paw.frontend`, `paw.remote`,
`paw.render` and `paw.media` use the actual types of `paw.mouse`,
`paw.panes` and `paw.ui`. They do not yet use the views of `paw.ui`, which
`paw.frontend` reads as records of its own until wave 5.

`paw.seats.keep` takes values of one type, so `paw.ui` and `paw.panes` keep
the state of each seat in a record. `paw.layout.within` and
`paw.limit.named` take arguments of one type, so the ports give them
closures where a function takes more.

The `grid` of a buffer type is a function in the contract, but a type in
Lua can give a table, so the port keeps both, as the Lua did.

## What the checker found in the pickers, help and language servers

The checker found the following problems in the pickers, help and the
language servers, including one bug that a user could see.

A picker's items are of its own type, so the sources are generic
(`paw.contracts.PickSource<T>`). `paw.pick` keeps the items of the open
picker as `paw.pick.Item` and gives them back to the functions of the
picker. The sources of the runtime are pickers of records
(`paw.pick.sources.PartLine`, `paw.help.Tag`, `paw.query.Node`).

The picker of the Lua API walks the `paw` global, whose tables also have
number keys. The first port read each key as a name, and the search tests
found the error, so the port tests that a key is a name, as the Lua did.

`paw.pick.sources` held `_walk`, a function that is not a picker, for a
test. The function is `paw.pick.walk` now, and the test calls it there.

The place of the pointer is a number, and a row of the picker is an
integer, so the port rounds the place down to the row that it is in.

`paw.contracts.Selector` did not have `seconds`, which is the time range in
a render that a one-shot server gives. It also did not have `line` and
`col`, which help gives for its pages, and it has all of them now.

A one-shot server with a command of one word as text stopped with an
error, because paw read its command as a list. It is a list of one word
now, as for a server that runs as a process.

The `edit` of an item that a server suggests went to `paw.complete`, which
does not read it, so the port does not send it.

A message of JSON-RPC is a record (`paw.lsp.rpc.Message`). The parameters
and the result of a message are `paw.lsp.rpc.Payload`, which is a record
with no fields, and each handler casts it to the record of its method. The
settings of a server are JSON values (`paw.util.Data`).

The records that the adapters and paw share, e.g., a client, its config, a
document and an adapter, are in paw/lsp/standard.tl. paw/lsp/init.tl
requires that module, so the two modules do not need the types of each
other.

`lsp.status` and `lsp.analysis` have the descriptors
`paw.lsp.status_changed` and `paw.lsp.analysed`.

`paw.pick` needs the types of `paw.qf` and `paw.commands`, and those modules
call `paw.pick`. `paw.commands`, `paw.grep`, `paw.takes`, `paw.markers`,
`paw.diagnostic` and `paw.snippet` therefore declare the part of
`paw.pick` that they call.

## What the checker found in the frontend

The checker found one error that changed what the code does, and the other
tests pass with no change. The frontend is as fast as before. With 16
parts, the state that a window gets for each frame takes 16.4 µs before
and 16.6 µs after, in the spread of six runs of each, and it makes 2.1 KB
of garbage before and after. A key with its frame, `bench/redraw.lua` and
the state after an edit give the same median, in the spread of the runs.

The error was in the gesture `act.glue_clips`, which kept the error of a
glue of audio clips and the result of the glue in one variable. When the
glue failed, the message said "false" and not the error. The port keeps the
error in a variable of its own, so the message gives it, and a test makes
sure of it.

The checker also found the following problems and limits.

`paw.frontend.state` is what the window reads, and it has records now,
which are `paw.frontend.State`, with `Modal`, `ProjectState`,
`PartState`, `ClipState`, `DeviceState` and `Routing`. `paw.remote` sends
the parts of the state by those records.

The prompt of the modal state holds the candidates that show, but
`paw.views.cmdline` gives a list of all the candidates, so the port gives
the prompt of the state a record of its own, over the same table.

The window sends some flags as `true` or `1`, and the mode of a choice as a
number or a word. The gestures take those forms
(`free?: boolean | integer`, `mode: integer | string`).

`act.set_velocity` gave the place of the note for one note, and nothing for
several notes. Its type says so now, an integer or nil.

`paw.render` was a function, and the module of the render was out of the
way. Now `paw.render` is the module, and a call of it renders, so
`paw.render(path, opts)` is `paw.render.render(path, opts)`. The other
names (`paw.render_status`, `paw.render_tags` and the others) are the
functions of the module, so they have its types. `paw.render_ranges` is the
table of the ranges itself, not a table that passes each key on.

The options of `paw.render` are the kernel's options, and also the options
that only Lua knows, which are `range`, `rate`, `channels` as a word,
`background` and `format`. They are a record of their own,
`paw.render.Options`. `render.before` and `render.finished` have
descriptors (`paw.render.before`, `paw.render.finished`).

`paw.media.glue` takes a list of clips, or one clip without a list. Teal
cannot give two table types to one parameter, so its type is the list, and
Lua can give one clip as before.

`paw.mouse.hint_text` and `paw.takes.count` were called two times for one
value, and the port calls each one time.

`paw.lanes`, `paw.curves` and `paw.query` call `paw.frontend`, and
`paw.frontend` names their types, so those modules declare the part of
`paw.frontend` that they call.

## What the checker found in the keys

The checker found no error that changed what a key does, and the tests pass
with no change. Most of what it found was in the records that 14 other
modules kept of `paw.keymap`, and in the contracts that a view gives the
keymap.

The keymap was one file of 1,597 lines. The port moves the registers and
the macros to `paw/keymap/registers.tl`, and the marks, the jump list and
the change list to `paw/keymap/marks.tl`. `paw.keymap` still gives all of
their functions, so a configuration and an extension call them as before.

The keymap found a key by a walk of every mapping of each scope, for each
key that you type. It now keeps, for each mode and scope, the prefixes of
the mappings, so a key needs one look in a table for each scope. A prefix
ends at the end of a key, so `<` is no longer a prefix of `<C-a>`. No key
that the keyboard sends is `<` alone, because the keyboard sends `<lt>`.

`mode.changed` was made as a descriptor in five modules, each with its own
record of the payload. `paw.keymap.mode_changed` is now the one descriptor,
and `paw.keymap.ModeChanged` is the one record.

Eleven modules had their own record of the payload of `option.changed`,
and two had their own of `render.before`. Now the module that sends an
event gives its descriptor and its record: `paw.option.changed`,
`paw.render.before`, `paw.events.startup` and `paw.events.exit`. A
descriptor also declares the name of its event, so a handler that waits
for a name that nothing declares is in the log, and `:checkhealth events`
lists it. The first run found `theme.changed`, an event that nothing
sends, in the articulations extension. `tools/apidoc.lua` writes the rows
of these descriptors on the page on events.

The contracts of a view missed some fields that the keymap reads:

- `view:subscope()` can give a list of scopes, as the piano roll does.
- `view.insert_hints` says that insert mode is a choice of keys that the key
  line lists.
- A place on the jump list keeps the scope of the window (`scoped` and
  `scope` in `paw.contracts.GridMark`).
- `ctx.op_count` is the count of an operator made with `count = "operator"`.

A register holds a table that the code that yanked it makes, so its type is
an interface, `paw.keymap.Register`, with only `kind`. A module that yanks
gives its own record of a register that is a `Register`, and it casts what
`paw.keymap.getreg` gives back to its record.

`paw.edit` kept its own record of a region, and that record did not agree
with `paw.contracts.Region`, so the frontend could not give a selection of
the keymap to it. `paw.edit` uses the contract now.

## What the checker found in the arrange view

The checker found no error that changed what the arrange view draws or what
the pointer does in it, and the tests pass with no change. Most of what it
found was in the records that other modules kept of the view, and in the
gestures of the pointer.

Six modules kept their own record of the arrange view, with the few fields
that each one used. The contracts now give the view as
`paw.contracts.ArrangeView`, with what a layer of an extension gets
(`paw.contracts.ArrangeLayer`) and where the view drew its parts
(`paw.contracts.ArrangeGeometry`). The view is a record that has these
fields, and it adds its own state for each window.

A gesture of the pointer adds its own fields to what it gives
`paw.mouse.grab`, for example the function that draws a dragged clip over
the view. `paw.mouse.Handlers` was a closed record, so it is an interface
now, and each gesture of the arrange view is a record that extends it. One
gesture kept a number in the field where the others keep the last event of
the drag, and it has a field of its own for that number now.

The header of a part set the columns of its buttons on the view while it
drew them. The header now gives the columns back, and the view keeps them,
so the drawing of a header changes nothing else. The drawing of a frame was
one function of 352 lines and the header one of 208 lines. Each is now a
short function that calls one function for each part, for example the
ruler, the rows, the selection and the playhead. The clips of one part are
in `paw/views/arrange_part.tl`, and a head of `paw/heads.tl` draws the
header.

The widget roles (`label`, `button`, `switch`, `knob` and `playhead`) are
still defined in Lua, and their props had no record. The contracts give one
record for each of them, so a view in Teal marks them with typed props.

## What the checker found in the piano roll

The checker found no error that changed what the piano roll does, and the
tests pass with no change. Most of what it found was in how the piano roll
and the modules around it named each other.

Ten modules kept their own record of the piano roll, and some kept records
of its layers, its clips and its marks too. The records did not agree:
one gave a layer the clip as `clip`, and another as `data`. Each module
now names the types of the piano roll. The module
`paw.views.pianoroll` gives the record of the view, `PianoRoll`, and the
records of a layer, a tool, a band, a note mark and a hit region. The
view itself is still `paw.ui.views:get("pianoroll")`, and a module
casts it to `PianoRoll`.

`paw.roll_clips` gives the record of a clip that the piano roll edits as an
interface, `paw.roll_clips.Portion`. The frontend keeps more fields of a portion,
so it has a record of its own that is a `Portion`.

The piano roll loaded `paw.roll_draw` at its end, and `paw.roll_draw`
names the types of the piano roll. In Teal that is a loop, so
`paw/init.lua` now loads `paw.roll_draw` after the views.

The velocity strip changed what the piano roll draws by putting its own
function in place of `view:render`. The view now has a field `strip`,
which `view:render` calls after it draws the roll. `view:render` was one
function of about 300 lines, and it is now a short function that calls
one function for each part: the title, the ruler, the rows, the
playhead, the velocities, the cursor and the scroll bar.

`view:window_target` gives the clip of the window as a number, and the
contract of a view said text. The contract now says text or a number.
A change to text would change the files that save the layout.

The picker of `:roll.parts` read a third argument in its action for
Enter, to change the text of the line. The picker never gives that
argument, so the line kept its old text after Enter. The port removed
the code that could not run. Now an action of a picker can say
`refresh = true`, and the picker makes the line of the item again after
the action. `:roll.parts` uses it, and a test checks the line.

`pianoroll.opened` and `roll_clips.changed` had a descriptor in the
module that sends them and a second one in `paw.lsp`. `paw.lsp` now uses
the descriptors of the modules that send them.

## What the checker found in interop

The checker found no error that changed what an import or an export does,
and the tests of the extension pass with no change. It found the following
smaller problems.

`interop.register` copied each field of the table that it got to the format,
also `module`, and it gave `import = false` to `paw.formats` as it was. It
gives the fields of a format now (`paw.formats.Format`).

`interop.device_types()` kept `false` for a kind of device that is not
installed, so a caller got a device type or `false`. It gives nil now, and it
keeps the kinds that are not installed in a set of its own, so each kind is
still looked up once.

A document of `interop.rpp.format` found its `project` with a function on its
metatable, so the field had no type. The document now keeps `project` as a
field, and it sets the field again when its children change.

A token of a line can be a number that a script set. The data lines of a block
and the name of a node took each token as text, so a number there stopped the
code. They turn a number into text first, as REAPER writes it.

`interop.db` used `paw.dsp`, which is Lua for the audio thread and has no
types. It now does the same arithmetic itself, so it gives the same numbers.

A merge kept the master of the file as `false` in the table of the parts by
their id. It is in a set of its own now, and the table holds part ids only.

The strict check of the test suite did not find the other modules of an
extension, because only `tools/tlcheck.sh` put the `lua/` folder of each
extension on the path. The test gives these folders to `paw.lang.check` now.

## What the checker found in plugstate

The checker found one error that lost data. A preset that inserts a node
with nodes in it (`.jucepreset`, written by `:plugstate.preset_write`) kept
each child node in a tag, and the reader of presets did not take the tag
off. So the inserted node came back without its children. A preset now
keeps the children as they are, and the reader still takes the old form.
The tests of the extension pass with no change. The checker also found the
following smaller problems.

`juce.value` read a 32-bit or 64-bit number past the end of a value that was
too short, and gave a number from the bytes after it. It gives nil now.

The edits of a preset, the arguments of `jucestate.convert` and the result of
`doc:diff` each took two forms, a table with names or a list in order, and a
tree or a document. Each takes one form now: an edit has names
(`{ path, value, kind }`), `convert` takes `{ plugin, desc, uri }`, and
`doc:diff` takes a document. No caller used the other forms.

`plugstate.frameworks` kept `false` in its cache for a binary with no marker
strings, so a caller got a name or `false`. The cache keeps nil now.

A sign-in to TONE3000 is nil before paw reads it, `false` when there is none,
or the tokens. The type says so (`Session | boolean`), and each reader of it
checks which one it is.

The options of the client of TONE3000 were read through `paw.opt`, which
gives a value of any type. The client keeps the handles that
`paw.option.define` gives, and the other modules ask the client.

## What the checker found in the generator

The port of `tools/apidoc.lua` to Teal changed no file that it makes. Its
files are the same to the byte as before. The generator ran before and
after the port with the same binary on the same tree, and the outputs
matched.

The model gives each type of the kernel's functions and records as the
Rust source spells it: an `Option`, a list, a tuple or a named type. Each
writer writes the type in its own notation, so `LuaString` is `string` in
Teal and `any` for LuaLS, as before. A reader of a description that Rust
makes can fill the same model later.

Two checks of the Teal files had different rules. `tools/tlcheck.sh` ran
`cyan check` and let a warning pass, such as a local that is not used. The
check of the suite failed on it. Now the two run the same check.
