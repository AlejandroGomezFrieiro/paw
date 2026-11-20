---
name: teal
description: Write, port or review Teal code in paw (Lua with types, compiled to Lua 5.1 for LuaJIT) and keep its conventions: no `any`, typed contracts, generated declarations, the any allow-list, the pitfalls the ports found. Use whenever a task creates or changes a `.tl` file, ports a Lua module of runtime/ or extensions/ to Teal, writes an extension in Teal, touches tools/apidoc.lua's Teal output, runtime/lua/paw/types.tl or contracts.tl, runtime/types/, tlconfig.lua or any-allowed.txt, or meets a Teal type error — even if it only says "port this file", "add types", "why does tl check fail".
---

# Teal in paw

paw's new code is Teal (AGENTS.md rule 8). The owner's two rules come first:
**Teal source is the truth** (a module becomes typed by being ported to `.tl`,
never by a declaration layer over Lua) and **no `any` where a value has a
shape** ("an anti-pattern; we want well-defined typing"). Read
[about-teal.md](../../../docs/explanation/about-teal.md) (the why, the
migration plan and what each port found) and
[write-an-extension-in-teal.md](../../../docs/how-to/write-an-extension-in-teal.md)
before writing; this page is the checklist.

## Where things are

| What | Where | Edit it? |
|---|---|---|
| Runtime modules in Teal | `runtime/lua/paw/**/*.tl` | yes |
| Kernel records (what crosses `paw.api`) | `runtime/lua/paw/types.tl` | yes, from the Rust that builds each table |
| Contracts extensions implement (View, Buftype, TrackKind, Role, PickSource<T>, StatusComponent, QueryField, HealthCheck, Manifest…) | `runtime/lua/paw/contracts.tl` (`paw.contracts`) | yes |
| Kernel event descriptors | `runtime/lua/paw/events/kernel.tl` | **no**: generated |
| `paw` global, `paw.api`, Lua modules' records, options, role props | `runtime/types/paw.d.tl`, `paw/api.d.tl`, `paw/partial.d.tl`, `paw/opts.d.tl`, `paw/role_props.d.tl`, `paw/untyped.d.tl` | **no**: `tools/apidoc.lua` makes them |
| The counted escapes | `runtime/types/any-allowed.txt` | only to remove entries, or add one by hand with a reason |
| Compiler settings | `tlconfig.lua` (`gen_target = "5.1"`, `gen_compat = "off"`) | rarely |
| The vendored compiler | `runtime/lua/tl.lua` (Teal 0.24.8) | no |

Kernel types come from Rust doc lines: `// @param`, `// @return`, `// @type`
over each function in `crates/paw-core/src/api.rs` and the `*_api.rs` files;
serde structs (`#[derive(Serialize/Deserialize)]`) become records. A Lua
module still in Lua gets signatures through `--- @type function(...)` lines.
After changing any of these, regenerate:

```sh
nix develop -c cargo build --release -j 8
nix develop -c target/release/paw --clean --no-plugins -l tools/apidoc.lua
nix develop -c target/release/paw --clean --no-plugins -l tools/apidoc.lua check
nix develop -c tools/tlcheck.sh
```

The build type-checks every runtime `.tl` and stops on a type error. The
extension loader checks too: an extension with type errors still loads, warns
once, and lists the errors under `:checkhealth teal`.

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
- `local type X = require(...)` still runs `require` at run time.

## Types: what to write

- **Records** for tables with fields; **enums** for string choices;
  **function types** for callbacks; **generics** where one type flows through
  (`PickSource<T>`, `option.define<T>` → `Option<T>`).
- **Unions** of primitive types are fine and narrowed with `is`
  (`number | string` for "an id or a name"). But prefer one type per
  parameter in new APIs (two functions beat a union). Two table types in a
  union need records with a `where` discriminator; `string | MyEnum` is not
  allowed.
- **Interfaces** for specs that carry extra fields (view specs, providers), and
  `record X is Interface`; a table literal with unknown fields is rejected for
  a plain record.
- **Events:** in Teal, `paw.on` takes a descriptor, not a string:
  `paw.on(kernel.project_saved, function(p: kernel.Saved) … end)`. A module
  that emits its own events exports `paw.events.event<P>(name)` descriptors.
- **Kernel setters** take a typed patch, one undo step:
  `api.track_set(id, { name = "Bass", volume = -6 })`. A patch cannot carry
  `nil`: to clear a field, keep the key form `api.track_set(id, "output", nil)`.
- **Options:** `paw.opt.x` is typed; an extension's own option:
  `local o = paw.option.define<number>(…)` then `o:get()`.
- **`Untyped`** (the escape for Lua not yet ported): cast once at the
  boundary (`x as types.Track`), never pass it on.

## No `any`

- Count `any` and `Untyped` entries in `any-allowed.txt` before and after;
  the count only goes down. Remove the entries your port makes unneeded.
- A loose doc comment is fixed at its source (Rust `// @return`, Lua `--- @type`),
  not papered over with `any` in a generator.
- Legitimate remaining `any`: truly free data (JSON/TOML values, an
  extension's own `meta`), values whose type depends on a key in Lua-only
  forms. Each has a reason on the allow-list.

## Pitfalls the ports found

| Pitfall | Do |
|---|---|
| `x is integer` compiles to `math.type(x)`; LuaJIT has no `math.type` | paw provides it at boot (being replaced by the full lua-compat-5.3, which also gives `math.tointeger`, `table.unpack`, `utf8`, `bit32` for `&` `\|` `<<`). Until compat-5.3 lands, avoid those library calls and bitwise operators |
| `ipairs(f())` where `f` returns two values | store the list first: `local list = f()` |
| A contract method must take every parameter of the contract | declare unused ones; contracts make context parameters optional |
| `paw.lang.check` reports unused locals as errors (`tl check` does not) | remove or use them |
| Shadowed locals are warnings the strict check counts | rename |
| Teal's 5.1 library lacks `unpack`, `table.maxn`, `loadstring`, `jit` | cast `_G` once at the top of the file |
| `setmetatable` needs a typed metatable | a separate metatable record, not the class table |
| `integer` vs `number` inference in sums | annotate `: number` |
| `paw.Track` is a type in Teal, not a value | `getmetatable(x) == …` checks stay in Lua |
| A one-field kernel read (`track_get(id, "meta")`) is faster but untyped | keep it through one cast of the function when it is on a hot path |
| `commands.define` handlers must return `commands.Result` | annotate the handler's return |
| Two modules cannot name each other's types (`local type` requires in a cycle: "unknown type") | the lower module owns the shared records; the other declares only the part it calls (qf.tl and diagnostic.tl) |
| `local ok, err = pcall(f)` where `f` returns nothing: "did not produce an initial value for `err`" | wrap it: `pcall(function(): string f() end)` |
| A record does not fit a contract's interface without `is` (records are nominal) | cast where the value goes in: `data = clip as contracts.QueryData` |

## What stays Lua

LuaJIT FFI code on the audio thread (`dsp.lua`, Lua devices), the vendored
`tl.lua`, generated files, extension `manifest.lua` files (checked against
`contracts.Manifest`), and tests for now. Each needs a written reason.

## A port, step by step

1. Read the module and everything that requires it; list the shapes it takes and gives.
2. Write `name.tl` next to `name.lua`, delete the `.lua` (`git mv` keeps history).
3. Types from the real readers and writers; contracts and `types.tl` records first.
4. Build (type-checks the runtime), `tools/apidoc.lua`, `apidoc check`, `tools/tlcheck.sh`.
5. The existing tests pass unchanged; a test that changes means a real bug: say so.
6. Search the docs and READMEs for the old `.lua` path (AGENTS.md); update the
   migration table and "What the checker found" in about-teal.md.
7. Report: lines, `any`/`Untyped` counts before and after, what the checker found.
