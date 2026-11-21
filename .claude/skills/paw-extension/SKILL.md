---
name: paw-extension
description: Create, extend or debug an extension for paw (the personal audio workstation in this repository): a directory of Lua that adds commands, keys, views, buffer types, kinds of track, Lua devices, picker sources, query fields, status line components, hooks, health checks, and optionally native parts built by Nix. Use whenever a task adds a feature to paw that is not core (see docs/explanation/about-core-and-extensions.md), writes or changes anything under extensions/ or ~/.config/paw/extensions, or asks "how do I make paw do X" where the answer is Lua — even if it only says "add a command", "a new view", "a tracker", "a plugin for paw".
---

# Creating a paw extension

paw is built like Neovim: a small Rust kernel, and everything you touch is Lua
over one API, `paw`. An extension is ordinary Lua that calls that API — there
is no separate plugin interface. Read these before writing anything (they are
the source of truth; this page is the map):

- `docs/explanation/about-core-and-extensions.md` — what belongs in the core
  vs an extension, and why.
- `docs/reference/extensions.md` — layout, manifests and versions, what an
  extension owns and `:ext.unload`, views in the graphical window, health
  checks, what the core gives an extension (devices, track kinds, native
  engines, Nix packaging). `docs/reference/pictures.md` — strips,
  pictures of pixels (`paw.canvas.image`, `buf:image`) and `paw.plot`.
- `docs/reference/scripting.md` and the `lua-*.md` pages beside it — the API by area; `docs/reference/events.md` (every hook, one
  table) and buffer types / text buffer kinds.
- `docs/reference/api.md` (`:help paw.<name>`) — every public function, generated.
  `runtime/types/paw.lua` is the LuaLS meta file: point LuaLS's
  `workspace.library` at `runtime/types` to get completion while writing.
- `docs/reference/key-rule.md`, `docs/reference/grammar.md` and `docs/reference/keys.md` — the keys a user expects;
  `runtime/lua/paw/keyrule.lua` — the key rule your keys must follow.
- A bundled extension close to what you want, as a model (below).

The manual's contents are `docs/README.md`, by kind (tutorials, how-to,
reference, explanation): find a page through it.
`docs/reference/limits.md` says what paw does not do yet:
take out what your extension adds. An extension's README follows
`.claude/skills/diataxis-docs/SKILL.md` (sections by kind, in ASD-STE100).

## Rules that are not optional

1. **MIDI and the project are the truth.** An extension never owns clip data.
   Keep extension data in `meta` (note/clip/track/project) or files; the
   project must open, play and edit without the extension (notation and
   articulations are the models: notation is a *view* over MIDI).
2. **The key rule.** `h j k l w b e 0 ^ $ gg G` only move; `+ -` and
   `Ctrl-a`/`Ctrl-x` change the main value, `[ ]` the second; `< >` are time;
   `K` describes; `Esc` cancels and stays. A view's own keys go on
   `<localleader>` (backslash), **never** `<leader>` for one view's keys.
   Motions are declared `motion = true` so operators and visual mode work.
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
  the functions that register a view, a buffer type, a text kind, a track
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
  each `meta` entry of yours (`note.meta.lyric as Lyric`).
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
  manifest.lua      return { name, version, description, requires = { paw = "^1.0" } }
  init.tl           runs at load (or init.lua): require your modules, register things
  lua/<name>/…      your modules (on the require path), .tl or .lua
  devices/*.lua     Lua devices (JSFX-style DSP), optional
  README.md         the user's page: keys, commands, options — `:help` reads it
  tests.lua         tests, run by tests/tools/suite.sh
  images/           pictures for the README (scenes in images/make/)
  nix/default.nix   only if it ships native parts (an engine, a plugin)
```

A user's own extension lives in `~/.config/paw/extensions/<name>` the same
way; `paw.ext.load(path)` in `init.lua` or `:ext.load <name>` loads one.

## What you register (each is recorded as owned by your extension)

```lua
paw.command("euclid.fill", function(ctx) --[[ ctx.args, ctx.count, ctx.range ]] end,
  { desc = "Fill the clip with a Euclidean rhythm: `euclid.fill 5 8`", range = true })
paw.keymap.set("<localleader>e", "euclid.fill 3 8", { view = "pianoroll", desc = "Euclid 3 in 8" })
paw.keymap.set("]e", fn, { view = "pianoroll", motion = true, desc = "Next onset" })
paw.ui.view("euclid", { render = function(self, buf, ctx) end, on_key = …, title = "Euclid" })
paw.buftype("tally", { … })                    -- a buffer type with its own keys/motions/K/status
paw.textbuf.kind("clips", { … })               -- a listing edited as text, :w shows a plan
paw.track_kinds.define("euclid", { … })        -- a kind of track (create, editor, describe)
paw.on("edit.after", function(payload) end)    -- hooks: see docs/reference/events.md
paw.statusline.component("euclid", { fn = function(ctx) return { { "E", "StatusOn" } } end })
paw.query.field("note", "onset", function(note) end)  -- :select / :query fields
paw.grep.source("euclid", function(add) end)           -- :vimgrep text
paw.health.register("euclid", function(h) h.ok("ready") end, { desc = "Euclid" })
paw.option.define("euclid_density", 0.5, { min = 0, max = 1 })  -- typed, bounded
```

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
| a kind of track with its own editor | `extensions/drums`, `extensions/utau` |
| per-note data, roll layers, popovers | `extensions/articulations` |
| a native engine / CLAP plugin built by Nix | `extensions/sampler`, `extensions/utau` |
| a buffer type (e.g. a tracker, time top→down) | docs/reference/lua-views.md `paw.buftype` example ("tally") |

## Tests and checks (do these before calling it done)

`extensions/<name>/tests.lua` receives the suite's helpers:

```lua
local T = ...
T.test("euclid fills 3 in 8", function()
  T.fresh()                                   -- a clean project
  paw.ext.load("extensions/euclid")
  -- drive real keys where it is UX: T.keys("…") / paw.keymap.feed("…")
  T.eq(#clip:notes(), 3, "three onsets")
end)
```

Never wait a fixed time for a state: the machine may be loaded. Wait for it:
`T.until_(cond, what, ms)` polls `cond` (timers and events run meanwhile)
and fails with `what`; `T.next_block(n, device)` waits until the engine (or
one device) has run `n` whole blocks, so a parameter, note or change sent
before is in effect. Keep `paw.api.sleep` only where real time is the
point (a take of one second), with a comment that says so. The runner
loads every `extensions/*/tests*.lua` itself.

```sh
nix develop -c cargo build --release -j 8      # the runtime Lua is embedded: rebuild first
nix develop -c tests/tools/suite.sh            # all tests (output in target/test-scratch/suite.out)
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
