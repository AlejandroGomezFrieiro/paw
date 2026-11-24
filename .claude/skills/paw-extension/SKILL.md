---
name: paw-extension
description: 'Create, extend or debug an extension for paw (the personal audio workstation in this repository): a directory of Lua that adds commands, keys, views, buffer types, kinds of part, Lua devices, picker sources, query fields, status line components, hooks, health checks, and optionally native parts built by Nix. Use whenever a task adds a feature to paw that is not core (see docs/explanation/about-core-and-extensions.md), writes or changes anything under extensions/ or ~/.config/paw/extensions, or asks "how do I make paw do X" where the answer is Lua — even if it only says "add a command", "a new view", "a tracker", "a plugin for paw".'
---

# Creating a paw extension

paw is built like Neovim: a small Rust kernel, and everything you touch is Lua
over one API, `paw`. An extension is ordinary Lua that calls that API — there
is no separate plugin interface. Read these before writing anything (they are
the source of truth; this page is the map):

- `docs/explanation/about-core-and-extensions.md` — what belongs in the core
  vs an extension, and why.
- The skill `architecture` — the target design (kinds, templates,
  modifiers). Use it before an extension needs a new part of the core.
- `docs/reference/extensions.md` — layout, manifests and versions, what an
  extension owns and `:ext.unload`, views in the graphical window, health
  checks, what the core gives an extension (devices, part kinds, native
  engines, Nix packaging). `docs/reference/pictures.md` — strips,
  pictures of pixels (`paw.canvas.image`, `buf:image`) and `paw.plot`.
- `docs/reference/scripting.md` and the `lua-*.md` pages beside it — the API by area; `docs/reference/events.md` (every hook, one
  table) and buffer types / text buffer kinds.
- `docs/reference/api.md` (`:help paw.<name>`) — every public function, generated.
  `runtime/types/paw.lua` is the LuaLS meta file: point LuaLS's
  `workspace.library` at `runtime/types` to get completion while writing.
- `docs/reference/key-rule.md`, `docs/reference/grammar.md` and `docs/reference/keys.md` — the keys a user expects;
  `runtime/lua/paw/keyrule.tl` — the key rule your keys must follow.
- A bundled extension close to what you want, as a model (below).

The manual's contents are `docs/README.md`, by kind (tutorials, how-to,
reference, explanation): find a page through it.
`docs/reference/limits.md` says what paw does not do yet:
take out what your extension adds. An extension's README follows
`.claude/skills/diataxis-docs/SKILL.md` (sections by kind). A README is an external page: write it with
`.claude/skills/plain-writing`.

## Rules that are not optional

1. **Lanes are the truth.** Source lanes hold the data. A derived lane is a
   recipe plus its kept result. A project opens and plays without the
   extension or program that made a derived lane. An extension never owns
   the data of a source lane (today: the notes and clips of a part).
   Keep extension data in `meta` (note/clip/part/project), under keys that
   you declare with `paw.meta.define`, or in files; the
   project must open, play and edit without the extension (notation and
   articulations are the models: notation is a *view* over MIDI). A kind
   of clip saves what it compiles, so its clips play without it. Lanes of
   each kind do not exist yet: the target design is in the skill
   `architecture`, where the container is a *part*. The API still says
   *part*; use the API names.
2. **The key rule.** `h j k l w b e 0 ^ $ gg G` only move; `+ -` and
   `Ctrl-a`/`Ctrl-x` change the main value, `[ ]` the second; `< >` are time;
   `K` describes; `Esc` cancels and stays. A view's own keys go on
   `<localleader>` (backslash), **never** `<leader>` for one view's keys.
   A key on `<leader>` that works from every view goes in a domain:
   `<leader>` + noun + verb (`<leader>ma` measures the mix, `<leader>pu` the
   undo tree). Use the domain of what the key does (docs/reference/keys.md,
   "The leader keys"); a new domain names its group with `paw.keymap.group`.
   `tests/fixtures/keys_walk.lua` fails on a leader key outside a domain.
   Motions are declared `motion = true` so operators and visual mode work.
   A musical object of the piano roll is a text object
   (`paw.keymap.textobject`), not a new selection key: return the region of
   its notes, with `notes` (note ids by clip id) when other notes lie
   between them, as `require("paw.note_objects").region(notes)` makes it.
   The core objects are in docs/reference/grammar.md ("Objects of the
   piano roll"); do not map their letters again.
   `tests/keys_constitution.lua` and `paw.keyrule.broken()` check it.
3. **Terminal first, both frontends from one code path.** Draw views in
   cells with `buf:text`/`buf:fill`; the window renders the same scene (see
   docs/reference/extensions.md "Views in the graphical window"). For pixels, use
   strips (`buf:strip`, `paw.plot.*`) under the cells, with the cell drawing
   as the fallback; for a picture of pixels, `buf:image` (half blocks where
   there are no pictures). Never write a second window-only UI.
4. **Everything undoable, everything said.** Edits go through the API so they
   are undo steps (one per user action); every action gives feedback
   (`paw.notify`) and every failure a clear message, never a stack trace.
5. **Fast keys.** A key handler stays well under 100 ms on large projects;
   Lua that runs away is stopped after 2 s (`paw.opt.lua_limit`).

## Write it in Teal

New extensions are written in Teal (AGENTS.md, rule 8): Lua with types,
which paw compiles as it loads `init.tl`, `name.tl` or `lua/<name>/*.tl`,
with the Lua cached in `~/.cache/paw/lang`. No build step. Read
`docs/how-to/write-an-extension-in-teal.md` and
`docs/explanation/about-teal.md` first.

- The `paw` global for Teal is `runtime/types/paw.d.tl` (`tlconfig.lua`
  names it): `paw.api` (from `crates/paw-core/src/api/`), and the
  runtime's modules already in Teal (`paw.music`, `paw.attr`, `paw.regex`, `paw.harmony.read`, ...) with
  their real types. The modules still in Lua type what their doc comments
  give (`--- @type ...`, collected in `runtime/types/paw/partial.d.tl`):
  the functions that register a view, a buffer type, a text kind, a part
  kind, a role, a picker, a status component, a query field, a grep source
  and a health check. The rest of paw is `paw.Untyped`: callable and
  indexable, and you cast what you keep (`x as integer`).
- The tables you give paw have types in `paw.contracts`
  (runtime/lua/paw/contracts.tl): `local record V is paw.contracts.View`,
  `paw.contracts.PickSource<Item>`, `paw.contracts.Buftype`, ... A method
  of such a record takes every parameter of the contract. `paw.opt.X` has
  its type, and `paw.option.define(name, default)` gives a typed handle
  (`h:get()`, `h:set(v)`).
- No `any` where a value has a shape: a record for each options table, each
  event payload (`paw.on("project.saved", function(p: Saved) ... end)`) and
  each `meta` entry of yours (`note.meta.fingering as Fingering`).
- Check: `nix develop -c tools/tlcheck.sh`, or `paw.lang.check(files)` in
  paw; the suite runs the check over every `.tl` file (tests/teal.lua).
  The loader checks too, as it compiles (the Lua of `x is F` depends on the
  types): a file with type errors still loads, with a warning, and
  `:checkhealth teal` lists the errors.
- `manifest.lua` stays Lua. Devices in `devices/*.lua` stay Lua (FFI, the
  audio thread).
- Another language: `paw.lang.add("fnl", { command = "fennel --compile %s" })`.

## Layout

```
extensions/<name>/
  manifest.lua      return { name, version, description, requires = { paw = "^1.0" }, needs = {} }
  init.tl           runs at load (or init.lua): require your modules, register things
  lua/<name>/…      your modules (on the require path), .tl or .lua
  devices/*.lua     Lua devices (JSFX-style DSP), optional
  README.md         the user's page: keys, commands, options — `:help` reads it
  tests.lua         tests, run by tests/tools/suite.sh
  images/           pictures for the README (scenes in images/make/)
  nix/default.nix   only if it ships native parts (an engine, a plugin)
```

A user's own extension lives in `~/.config/paw/extensions/<name>` the same
way. `paw.ext.use(path)` in `init.lua` or `:ext.load <name>` loads one.

## The manifest: dependencies and the first use

- `requires = { name = "^1.0" }`: paw loads these extensions first. If
  one is not there, the extension does not load, and the message says
  where to put it.
- `optional = { name = "*" }`: the extension uses these extensions when
  they are there. paw loads them first when they load in the same batch
  (one folder, or the packaged set). The extension must work without
  them, and must work when they load later or unload.
- Do not read `package.loaded` or `paw.ext.loaded` to find another
  extension. Meet it through a registry of the core or an event. For
  example, notation and articulations meet in `paw.query.marks` (the
  marks of a note) and the event `notation.marked`. Each extension works
  without the other.
- The modules of an extension have the name of the extension
  (`require("sampler")`). Do not put an entry under `paw.` in
  `package.loaded`: that name is for the runtime.
- With triggers, the extension waits for its first use: `cmd`, `keys`,
  `event`, `kind` (a key of any registry: `{ registry = "pickers", key =
  "x" }`), `view`, and `lazy = false`. paw puts a stub for each command,
  key and view. The first use loads the extension and runs the command
  or the key again as one undo step. Give each stub a `desc`.
- Do not give triggers to an extension that must run before its first
  use: an extension that sends MIDI while the song plays, an extension
  of devices that a project needs when it opens, or an extension that
  watches each save.
- The page "Extensions" of the reference (sections "Load on first use"
  and "Manifests and versions") gives the full reference.

## What you register (each is recorded as owned by your extension)

```lua
paw.command("euclid.fill", function(ctx) --[[ ctx.args, ctx.count, ctx.range ]] end,
  { desc = "Fill the clip with a Euclidean rhythm: `euclid.fill 5 8`", range = true })
paw.keymap.set("<localleader>e", "euclid.fill 3 8", { view = "pianoroll", desc = "Euclid 3 in 8" })
paw.keymap.set("]e", fn, { view = "pianoroll", motion = true, desc = "Next onset" })
paw.ui.view("euclid", { render = function(self, buf, ctx) end, on_key = …, title = "Euclid" })
paw.buftype("tally", { … })                    -- a buffer type with its own keys/motions/K/status
paw.textbuf.kind("clips", { … })               -- a listing edited as text, :w shows a plan
paw.kinds.define("part", "euclid", { head = "euclid", … })  -- a kind of part (create, editor, describe, head)
paw.heads.define("euclid", { rows = …, render = function(ctx) end, keys = { … } })  -- the header of its parts (docs/reference/extensions.md)
paw.kinds.define("clip", "cues", { gives = "midi", schema = { … }, … })  -- a kind of clip: own data, compiled to sound/signals (docs/reference/extensions.md)
paw.kinds.define("stream", "euclid.hits", { time = "beats", props = { … } })  -- a kind of stream that lanes and clips carry
paw.meta.define("euclid", { title = "The rhythm of a part", version = 1 })  -- declare each key of meta that you keep; K names you as its owner
paw.nest.define_kind("drums.pattern", { … })   -- a kind of subproject: create(region), enter(nest), describe(nest)
paw.chain.define_kind("drums.transient", { min = 2, max = 2, first = 2 })  -- a kind of split in a chain; edit a chain with paw.chain.of({ part = id })
paw.on("edit.after", function(payload) end)    -- hooks: see docs/reference/events.md
paw.statusline.component("euclid", { fn = function(ctx) return { { "E", "StatusOn" } } end })
paw.partcolumn.add("euclid", { order = 25, width = 1, render = function(part, ctx) end })  -- a component of the part column
paw.partcolumn.sign("euclid", { priority = 10, render = function(part, ctx) end })      -- a sign in its `signs` component
paw.partcolumn.set("fold", { order = 5, glyphs = { open = "-" }, styles = { fold = "Dim" } })  -- change a built-in component
paw.ruler.add("euclid", { order = 20, render = function(bar, ctx) end })            -- a part of each bar's label
paw.insert.add("E", { kind = "midi", desc = "A Euclid clip", length = "2 bars", open = function(ctx, item) end })  -- a key of the arrange view's insert mode (docs/reference/insert-mode.md); `insert = "e"` on a clip kind does it too
paw.query.field("note", "onset", function(note) end)  -- :select / :query fields
paw.grep.source("euclid", function(add) end)           -- :vimgrep text
paw.health.register("euclid", function(h) h.ok("ready") end, { desc = "Euclid" })
paw.option.define("euclid_density", 0.5, { min = 0, max = 1 })  -- typed, bounded
paw.pick.sources:put("euclid", { desc = "Rhythms", items = … })  -- a picker: a registry (below)
```

### Registries

A module that takes entries from extensions keeps them in a registry
(`paw.registry`, runtime/lua/paw/registry.tl). The page "Extensions" of
the reference lists the registries of paw. Commands, views, buffer types
and kinds of part are registries, for example. Read an entry with `get`:
`paw.ui.views:get("pianoroll")`. Each kind above is a registry: keys
(`paw.keymap.mappings`), hooks (`paw.events.hooks`), timers
(`paw.timers.waiting`) and options (`paw.option.defined`) too.

- To add a registry to a module, make it once with
  `registry.new(kind, title, options)`. In Teal, give the type of the
  entries: `local styles: registry.Registry<Style> = registry.new("styles", "note styles")`.
  `options.label` gives the words for `:extensions`, and
  `options.changed` runs after an entry changes (for example, to redraw).
- Use `reg:put(key, value)`, `reg:get(key)`, `reg:remove(key)` and
  `reg:entries()`. Do not keep a second table of the same entries.
- `put` records the owner from the code that calls it (`paw.ext.caller`).
  `paw.ext.unload` removes the entries of the owner, and the entry below
  each one returns. A registry made with `made = true` takes the owner
  from the files that made the value (`paw.registry.maker`), as the
  timers do.
- Add a row for the new registry to the table `registries` in
  `tests/extensions_api.lua`.
- The page "Extensions" of the reference (section "Registries") gives the full reference.

Check exact signatures in docs/reference/lua-*.md / `:help` before using one; the
lines above are a map, not the contract. For devices see
docs/reference/lua-devices.md (`dsp.device{…}`; `dev.call` receives
`paw.api.device_call`; large data via `dsp.map`). For an extension that ships
an engine or a plugin, follow `extensions/utau` and `extensions/sampler`
(`nix/default.nix`, `paw.plugins.add_dir`, `paw.withExtensions`). For a
native library that takes plugins and reaches their own extensions (ARA),
follow `extensions/ara` (`paw.plugins.attach`, docs/reference/attachments.md).

## Models to copy

| You want | Read |
| --- | --- |
| commands + keys + text objects on the timeline | `extensions/sections` |
| a view in its own window, cells + pixels | `extensions/undotree`, `extensions/mixdiag` |
| a whole editor over MIDI with its own grammar | `extensions/notation` |
| a kind of part with its own editor | `extensions/drums`, `extensions/utau` |
| per-note data, roll layers, popovers | `extensions/articulations` |
| a native engine / CLAP plugin built by Nix | `extensions/sampler`, `extensions/utau` |
| components and signs of the part column, bar labels, in Teal | `extensions/columnplus`, `extensions/rulerplus` |
| an extension in Teal with many modules (`lua/<name>/*.tl`), formats of other programs | `extensions/interop` |
| a buffer type (e.g. a tracker, time top→down) | docs/reference/lua-views.md `paw.buftype` example ("tally") |

## Tests and checks (do these before calling it done)

`extensions/<name>/tests.lua` receives the suite's helpers:

```lua
local T = ...
T.test("euclid fills 3 in 8", function()
  T.start()                                   -- a clean project, normal mode, no float
  paw.ext.load("extensions/euclid")
  -- drive real keys where it is UX: T.keys("…") / paw.keymap.feed("…")
  T.eq(#clip:notes(), 3, "three onsets")
end)
```

Never wait a fixed time for a state: the machine may be loaded. Wait for it.
The suite runs on the manual clock (`paw --clock manual`).

`T.until_(cond, what)` settles the kernel and checks `cond`. It fails at
once with `what` when nothing is left to do. `T.advance(ms)` moves the
clock, so each timer and delay fires in its order, and
`T.advance_until(cond, what, ms)` moves it to the timer that makes `cond`.
`T.next_block(n, device)` waits until the engine (or one device) has run
`n` whole blocks, so a parameter, note or change sent before is in effect.
The suite plays on the stepped audio backend: `T.next_block(n)` runs
exactly `n` blocks, and `T.meter(thing)` reads a meter after them.

A test that needs real time (a take of one second) is live:
`T.test(name, fn, { live = "why" })`. The runner loads every
`extensions/*/tests*.lua` itself.

In the code of an extension, a delay, a throttle or a time out for the
user reads `api.now()`. A budget of work, or a limit that stops a process
that does not end, reads `api.real_ms()`. The manual clock does not move
while the code runs. A limit on it never stops the process. Add such a
file to `M.real_time` in `tools/testlint.lua`.

The runner gives back the options of the start of the run after each test.
`T.fresh()` gives a new project, the default layout, normal mode and no
float. `T.start()` also types `<Esc><Esc>` and focuses the arrange view.
`T.screen(w, h)` gives the text of the screen. After the test files of an
extension, the runner unloads the extensions that the tests loaded, and
removes the event handlers, timers and key mappings that test code made. A
handler, timer or key mapping that is still there fails
"`extensions/<name>/` leaves no state behind".

The check also compares the audio engine, the MIDI ports and the step
input controls. The MIDI ports are the test ports and the ports of the
program. A change of one of them fails the check. The message names the
test that made the change.

Remove what a test adds with `T.after(fn)`. Do not add lines to
`tests/leaks-allowed.txt`.

```sh
nix develop -c cargo build --release -j 8      # the runtime Lua is embedded: rebuild first
nix develop -c tests/tools/suite.sh            # all tests (output in target/test-scratch/suite.out and parts/)
nix develop -c tests/tools/suite.sh only euclid  # only the tests whose name holds "euclid"
nix develop -c target/release/paw --clean --no-plugins -l tools/apidoc.lua check  # API docs current
```

Also, inside paw: `:checkhealth`, `:extensions`, `:ext.unload <name>` then
`:ext.load <name>` (must work cleanly), `:help <your command>` and
`:help <your key>` (must land in your README), and `paw.keyrule.broken()`
empty. Test with `--audio null` and a scratch `XDG_CONFIG_HOME`; never touch
the user's real config, devices or display from tests.

## Documentation

Your README is the user's page and `:help` reads it: a short intro, a keys
table, commands, options, and what is not done. Mention every command and key
you register (a test walks them). When the reference grows long, move it to
`doc/reference.md` (also a page of `:help`) and link it from the README. Add pictures with a scene script under
`images/make/` (see docs/images/make for the rig) so they can be made again.
