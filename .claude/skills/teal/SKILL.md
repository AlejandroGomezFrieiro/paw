---
name: teal
description: 'Write, port or review Teal code in paw (Lua with types, compiled to Lua 5.1 for LuaJIT) and keep its conventions: no `any`, typed contracts, generated declarations, the any allow-list, the pitfalls the ports found. Use whenever a task creates or changes a `.tl` file, ports a Lua module of runtime/ or extensions/ to Teal, writes an extension in Teal, touches tools/apidoc.lua''s Teal output, runtime/lua/paw/types.tl or contracts.tl, runtime/types/, tlconfig.lua or any-allowed.txt, or meets a Teal type error — even if it only says "port this file", "add types", "why does tl check fail".'
---

# Teal in paw

paw's new code is Teal (rule 8 of the instructions for agents). The owner's
two rules come first. **Teal source is the truth**: a module gets types when
it moves to `.tl`, not from a declaration layer over Lua. **No `any` where a
value has a shape**. The owner calls `any` there an anti-pattern and wants
well-defined types.

Before you write, read
[About Teal in paw](../../../docs/explanation/about-teal.md): the why, the
migration plan and what each port found. Then read
[How to write an extension in Teal](../../../docs/how-to/write-an-extension-in-teal.md).
The list below is the checklist.

## Where things are

| What | Where | Edit it? |
|---|---|---|
| Runtime modules in Teal | `runtime/lua/paw/**/*.tl` | yes |
| Kernel records (what crosses `paw.api`) | `runtime/lua/paw/types.tl` | yes, from the Rust that builds each table. **No** between the marks of `paw.api.api_schema`: `tools/apidoc.lua` writes those records from the `schemars` schema of the Rust types (`crates/paw-core/src/api_schema.rs`) |
| Contracts extensions implement (`View`, `Buftype`, `PartKind`, Role, PickSource<T>, StatusComponent, QueryField, HealthCheck, Manifest…) | `runtime/lua/paw/contracts.tl` (`paw.contracts`) | yes |
| Kernel event descriptors | `runtime/lua/paw/events/kernel.tl` | **no**: generated |
| `paw` global, `paw.api`, Lua modules' records, options, role props | `runtime/types/paw.d.tl`, `paw/api.d.tl`, `paw/partial.d.tl`, `paw/opts.d.tl`, `paw/role_props.d.tl`, `paw/untyped.d.tl` | **no**: `tools/apidoc.lua` makes them |
| The generator of the files above | `tools/apidoc/` (Teal): `read/` fills `model.tl`, one module in `write/` for each file; `tools/apidoc.lua` is the entry | yes: a new file is one writer, a new source is one reader |
| The counted escapes | `runtime/types/any-allowed.txt` | only to remove entries, or add one by hand with a reason |
| Compiler settings | `tlconfig.lua` (`gen_target = "5.1"`, `gen_compat = "off"`) | rarely |
| The compiler, a copy in the tree | `runtime/lua/tl.lua` (Teal 0.24.8) | no |
| The Lua 5.3 library on LuaJIT | `runtime/lua/compat53/` (lua-compat-5.3 0.14.4, a copy), loaded by `runtime/lua/paw/compat.tl` | compat53: no; compat.tl: yes |

Kernel types come from Rust doc lines: `// @param`, `// @return`, `// @type`
over each function in `crates/paw-core/src/api/*.rs` and the `*_api.rs` files.
Serde structs (`#[derive(Serialize/Deserialize)]`) become records. A Lua
module still in Lua gets signatures through `--- @type function(...)` lines.
After a change of one of these, make the files again:

```sh
tests/tools/run.sh --clean --no-plugins -l tools/apidoc.lua
tests/tools/run.sh --clean --no-plugins -l tools/apidoc.lua check
nix develop -c tools/tlcheck.sh
```

The build type-checks every runtime `.tl` and stops on a type error. The
extension loader checks too: an extension with type errors still loads, warns
once, and lists the errors under `:checkhealth teal`.

## One set of rules for the check

The Teal files have one check: `tools/tlcheck.lua`, which runs
`paw.lang.check` (the compiler in the program, with `tlconfig.lua`) on every
`.tl` file of `runtime`, `config`, `extensions` and `tools`. Three places run
it, and they give the same result:

- `tools/tlcheck.sh` (with the paw of `tests/tools/run.sh`; a change of
  Teal needs no build, because the binary of the main checkout serves),
- the test suite (`tests/teal.lua`),
- `nix flake check` (the `teal` check, with the binary of the commit).

The rules:

- Each error fails, and each warning fails: an unused local, a shadowed
  local, an unused type alias. Do not put a warning on a list: fix it.
- `local paw = (_G as ...).paw` in a module that `paw.d.tl` names is not
  reported (the module is checked when the declarations load, before the
  global exists). In a module that `paw.d.tl` does not name, it is a shadowed
  `paw`: use the typed global there (see the pitfalls).
- The build (`crates/paw-core/build.rs`) stops on errors only, and `cyan gen`
  in `tools/dev-runtime.sh` makes the Lua only. Neither is the check.
- The files that cerulean cannot format are listed once, with the reason, in
  `tools/fmtcheck.sh`.

`nix flake check` also runs `tools/apidoc.lua check` (the `apidoc` check): a
declaration that is out of date with the source fails there, not only in
the suite.

## The head of a runtime module

```lua
-- What the module does (as before).
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")                   -- the kernel, typed
local type contracts = require("paw.contracts")  -- types only
local type partial = require("paw.partial")      -- typed records of Lua modules

local record Paw is partial.Paw                   -- only if you need more than partial gives
   cursor: CursorModule
end
local paw = (_G as {string:Paw}).paw
```

- A module cannot `require("paw")` for its types (paw.d.tl requires every
  module: a cycle). Take the global through `partial.Paw` as above. A module
  nothing requires may read the typed global `paw` directly.
- Prefer the real module types and contracts over hand-made stand-in records;
  a stand-in is acceptable only for a module not yet ported, and goes when it is.
- `local type X = require(...)` compiles to nothing (`tl gen` shows it):
  it names the types only, so it adds no load order. A module that needs
  the other module's values at run time requires it as a value.

## Types: what to write

- **Records** for tables with fields; **`enum` types** for string choices;
  **function types** for callbacks; **generics** where one type flows through
  (`PickSource<T>`, `option.define<T>` → `Option<T>`).
- **Unions** of primitive types are fine and narrowed with `is`
  (`number | string` for "an id or a name"). But prefer one type per
  parameter in a new API (two functions beat a union). Two table types in a
  union need records with a `where` discriminator; `string | MyEnum` is not
  allowed.
- **Interfaces** for specs that carry extra fields (view specs, providers), and
  `record X is Interface`; a table literal with unknown fields is rejected for
  a plain record.
- **Events:** in Teal, `paw.on` takes a descriptor, not a string:
  `paw.on(kernel.project_saved, function(p: kernel.Saved) … end)`. A module
  that emits its own events exports `paw.events.event<P>(name)` descriptors.
  Each event has one owner: the module that sends it exports the descriptor
  and the payload record (`options.changed`, `options.Changed`), and the
  other modules use them. Do not make a second descriptor or record of an
  event. Put `--- The event `name`: when it comes.` over the field of the
  descriptor: `tools/apidoc.lua` writes the rows of
  `docs/reference/events.md` from it. `paw.events.event` also declares the
  name. paw logs a `paw.on` by text with a name that no module declares
  (`:checkhealth events`).
- **Kernel setters** take a typed patch, one undo step:
  `api.part_set(id, { name = "Bass", volume = -6 })`. A patch cannot carry
  `nil`: to clear a field, keep the key form `api.part_set(id, "output", nil)`.
- **Options:** `paw.opt.x` is typed; an extension's own option:
  `local o = paw.option.define<number>(…)` then `o:get()`.
- **`Untyped`** (the escape for Lua not yet ported): cast once at the
  boundary (`x as types.Part`). Do not pass it on.

## No `any`

- Count `any` and `Untyped` entries in `any-allowed.txt` before and after;
  the count only goes down. Remove the entries your port makes unneeded.
- A loose doc comment is fixed at its source (Rust `// @return`, Lua `--- @type`),
  not papered over with `any` in a generator.
- The `any` that can stay: truly free data (JSON/TOML values, an
  extension's own `meta`), values whose type depends on a key in Lua-only
  forms. Each has a reason on the allow-list.

## Pitfalls the ports found

| Pitfall | Do |
|---|---|
| Teal's code calls the Lua 5.3 library (`math.type` for `is integer`, `bit32` for `&` `\|` `~` `<<` `>>`) | it is there: paw loads lua-compat-5.3 at boot (`runtime/lua/paw/compat.tl`), with `math.type`/`tointeger`, `table.unpack`/`pack`/`move`, `utf8`, `bit32`, `__pairs`. Not there: `string.pack` (use `ffi`), a zero byte in a pattern (write `%z`). `os.execute` gives `true`/`nil`, not `0` |
| `ipairs(proxy)` where `proxy` has the items in `__index` | `ipairs` is LuaJIT's own, so it sees only raw items: use a `for i = 1, n` loop |
| `ipairs(f())` where `f` returns two values | store the list first: `local list = f()` |
| A contract method must take every parameter of the contract | declare unused ones; contracts make context parameters optional |
| `paw.lang.check` reports unused locals as errors (`tl check` does not) | remove or use them |
| Shadowed locals are warnings the strict check counts | rename |
| Teal's library lacks LuaJIT's `unpack`, `table.maxn`, `loadstring`, `bit`, `ffi`, `jit` | prefer `table.unpack` and `load`; else cast `_G` once at the top of the file |
| `setmetatable` needs a typed metatable | a separate metatable record, not the class table |
| `integer` vs `number` inference in sums | annotate `: number` |
| `paw.Part` is a type in Teal, not a value | `getmetatable(x) == …` checks stay in Lua |
| A one-field kernel read (`part_get(id, "meta")`) is faster but has no type | keep it through one cast of the function when it is on a hot path |
| `commands.define` handlers must return `commands.Result` | annotate the handler's return |
| Two modules that require each other's types get two copies of a type that do not agree ("`Buf` is not a `Buf`") | one side requires the other; the other puts its functions on it (paw/roles.tl sets `Buf.mark`) |
| `f: function(x: A): R, y: B` in a parameter list reads `y` as a second result | a named function type (`local type Height = function(i: integer): number`) |
| `local a, b: A, B = ...` does not type `b`; `local x: T = nil` makes `x` nil until it is set | one `local` for each; `local x: T` with no value |
| An alias of a generic instance (`local type R = contracts.Role<P>`) is not that instance | write `contracts.Role<contracts.MarkProps>` |
| A record field with two function types (two forms) cannot be defined in Teal | one form with a union parameter |
| `pcall`/`xpcall` of a function with no results gives no second value | `pcall(f, x) as (boolean, string)` |
| A field of a module record with a local alias in its type is copied as it is into paw.d.tl when another module holds the value (`paw.ui.roles`) | qualify the types of exported fields and functions (`contracts.X`) |
| `paw.limit.named(name, fn, a, b)` with arguments of two types | a closure: `paw.limit.named(name, function(): boolean return fn(a, b) end)` |
| Two modules cannot name each other's types (`local type` requires in a cycle: "unknown type") | the lower module owns the shared records; the other declares only the part it calls (qf.tl and diagnostic.tl). `tools/layers.txt` gives which module is lower ([the layers](../paw-code/layers.md)) |
| A record does not fit a contract's interface without `is` (records are nominal) | cast where the value goes in: `data = clip as contracts.QueryData` |
| A field typed `{A \| B}` given a table literal that mixes a text and records (`items = { "-", { label = ... } }`) is not inferred | put the list in a local of that type first (`local items: {contracts.MenuEntry} = { ... }`) |
| A record with an array part that also implements an interface | the array goes in the `is` list: `record Node is {Node}, contracts.Window` |
| A module that requires another (as a value) loads it then, earlier than the Lua that read `paw.x` when it ran | read `paw.x` at run time, typed by `local type X = require(...)` (paw/ui.tl and `paw.draw`) |
| A module many others require (`paw.buf`, `paw.draw`, `paw.cursor`, `paw.commands`) and a module that names its types (`paw.ui`) | the lower one declares the small part of the higher it reads (`record Ui focused: string end`) |
| `{T} \| function(): {T}` tested with `x is Fn`: the `else` branch is not narrowed | test the table: `if x is {T} then ... elseif x then (x as Fn)() end` |
| A generic function type in a parameter list (`format?: function(item: T): string, mode?: M`) does not parse | a generic alias: `local type TextOf<T> = function(item: T): string` |
| `a or b` of two function types, or of a flag and a record | compare: `(spec.preview ~= nil or spec.audition ~= nil)` |
| A module that stores values of many item types (`paw.pick`'s open picker) | erase the type once where the value goes in (`spec as PickSource<Item>`), and give it back to the owner's own functions |
| JSON whose shape depends on the method (`params`, `result` of JSON-RPC) | an empty record (`rpc.Payload`) cast once by each handler to its method's record; user JSON values are `util.Data` |
| A cast to a function type in an argument list (`xpcall(f, g as function(string): string, key)`) reads `, key` as a second result | put the type in parentheses: `g as (function(string): string)` |
| Two aliases of the same tuple (`{string, string}`) in two modules do not agree | one module names it, the other uses that name (`DrawModule.KeyHint`) |
| `<` on two values of an `enum` type | cast each value to `string` first |
| A record of another module that adds fields with `is` (`record ProjectFile is KeymapModule.ProjectPlaces`) | the base must be an `interface`, not a record |
| A value that each caller fills with its own fields (a register) | an interface with the common field (`KeymapModule.Register`); each caller has `record X is KeymapModule.Register` and casts what it reads back |
| A part split out of a module needs a function of the module that requires it (`registers.replay`, `marks.on_jump`) | a function field of the part, which the module sets after it requires the part |
| Callers read and change a field of a module as a live table (`paw.keymap.registers`), and each seat has its own | keep one table; the `keep` of the seat copies the contents out and in |
| A module keeps its own copy of a contract record (`paw.edit` had its own `Region`) | use the contract: two copies give "Region is not a Region" |
| A view whose table is the module (`paw/views/arrange.tl`), and another module names its types | the view is the module record: `local record Arrange is contracts.ArrangeView ... end`, `local view = Arrange`, and `return Arrange`. `return view` gives a value, and `local type A = require(...)` then fails with "did not return a type" |
| Modules that the view uses also name the type of the view (`paw.scope`, `paw.vzoom`): a cycle | put the part that they use in `contracts.tl` as an interface (`ArrangeView`); the record of the view extends it and makes its fields narrower (`geometry: Geometry` for `ArrangeGeometry`) |
| A gesture adds fields to the handlers of `paw.mouse.grab` (`arrange`, `d`) | `paw.mouse.Handlers` is an interface: `record Grab is MouseModule.Handlers`, and a function that takes a `Grab`. A table literal for an interface parameter does not accept the added fields |
| A role of `roles/widgets.lua` or `roles/notes.lua` (Lua) that Teal marks | its record of props is in `contracts.tl` (`LabelMark`, `ButtonMark`, `SwitchMark`, `KnobMark`, `PlayheadMark`) |
| `local type X = require(m)` of a module that returns a value (a view): "'require' did not return a type" | the module returns a record with `type` fields and the value as a field (`paw.views.pianoroll` gives `PianoRoll`, `Layer`, `view`) |
| A module puts its own function in place of a method of another (the strip replaced `view:render`) | a function field of the other, which its method calls (`view.strip.draw`) |
| A module requires at its end a module that names its types (`pianoroll` loaded `roll_draw`): a loop | the module that loads both requires the higher one after the lower one (paw/init.lua) |
| `local paw = (_G as ...).paw` in a module that paw.d.tl does not name (`views/pianoroll_mouse`): the strict check counts a shadowed `paw` | use the typed global `paw` there |
| Ten modules kept their own record of one view, and the records did not agree (`clip` and `data` of a layer) | the view's module exports the records; each other module names them |

## What stays Lua

LuaJIT FFI code on the audio thread (`dsp.lua`, Lua devices), the copies of
`tl.lua` and `compat53/`, generated files, extension `manifest.lua` files (checked against
`contracts.Manifest`), and tests for now. Each needs a written reason.

## A port, step by step

1. Read the module and everything that requires it; list the shapes it takes and gives.
2. Write `name.tl` next to `name.lua`, delete the `.lua` (`git mv` keeps history).
3. Types from the real readers and writers; contracts and `types.tl` records first.
4. Build (type-checks the runtime), `tools/apidoc.lua`, `apidoc check`, `tools/tlcheck.sh` (the one check, above).
5. The tests that are there pass with no change; a test that changes means a real bug: say so.
6. Search the docs and READMEs for the old `.lua` path (the instructions for
   agents). Update the migration table and "What the checker found" in About
   Teal in paw.
7. Report: lines, `any`/`Untyped` counts before and after, what the checker found.
