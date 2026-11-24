# Architecture review of paw: the Lua and Teal side

Review only. No code and no tracked file changed. Audited at
`998ab9079dbf646303431f748e94969bc00c839a` (`998ab907`, 2026-11-22).
Internal text, in Simplified Technical English.

The scope: the runtime in `runtime/lua/paw/` (Teal and the Lua that
stays), the declarations in `runtime/types/`, `contracts.tl`, `types.tl`,
`tlconfig.lua` and `any-allowed.txt`; the bundled extensions in
`extensions/`; the Lua test suite in `tests/` and its scripts; the tools
in `tools/` and the checks of `flake.nix` that run them; and `web/` (small,
see the notes).

The present review is the second part of
[architecture-review.md](architecture-review.md) (the Rust side, F1 to
F12 and E1 to E6). It does not repeat those findings. It refers to them
where they touch the Lua side: F2 (one typed source for the shapes), E2
(F10, one `Registry<T>`), E3 (F11, `needs` in the manifest) and E5 (F12,
the API lock).

## 0. Method

The method and the word list are the same as in the Rust review: the
skills `improve-codebase-architecture` and `codebase-design` from
`mattpocock/skills` (read again on 2026-11-22). In short:

- **Module**: anything with an interface and an implementation (a
  function, a Teal record, a file, an extension).
- **Interface**: all that a caller must know: types, rules, order of
  calls, errors, costs.
- **Deep module**: much behavior behind a small interface. **Shallow
  module**: an interface that is almost as large as its implementation.
- **Seam**: the place where the interface of a module is. **Adapter**: a
  thing that fills a seam.
- **Gain for callers** and **locality** (a change is in one
  place).
- **The deletion test**: if you delete the module, does complexity go
  away, or come back in many callers?
- **One adapter is a seam on paper, two adapters are a real seam.**

Changes from the process of the skill, for this task:

- The skill writes an HTML report and then asks which finding to explore.
  The owner asked for this Markdown file. The last parts of this file
  hold the proposed tickets and the questions for the owner.
- The skill starts a sub-agent to walk the code. This review walked the
  code itself, with scripts that count lines, functions, casts and the
  references between modules (the counts below).
- The domain words come from `AGENTS.md`, the explanation pages of the
  manual and the designs in `backlog/docs/designs`. The decisions not to
  open again come from the owner decisions at the end of the Rust review
  (no `Factory` in paw's own names; never load Rust libraries into the
  kernel) and from the notes on tickets.
- Teal advice follows the local skill `teal` (no `any` where a value has
  a shape; Teal source is the truth). Extension advice follows the local
  skill `paw-extension` (MIDI is the truth, the key rule, one view for two
  frontends).
- The current focus is m-2 (views and subprojects), m-3 (fast and lean)
  and m-4 (modal editing). m-10 (architecture) comes after them. Each
  finding says if it helps m-2, m-3 or m-4 now.

Hot spots: `git log --since=2026-11-10` over `runtime/lua`, `extensions`,
`tests` and `tools` (paths as they are now) names these files most often:
`paw/init.lua` (46 commits), `views/arrange.lua` (36), `tests/suite.lua`
(31), `keymap.lua` (30), `defaults/keys.lua` (30), the notation extension
(`keys.lua` 34, `init.lua` 31, `tui.lua` and `gui.lua` 26 each),
`contracts.tl` (28), `tools/apidoc.lua` (24), `types.tl` (23),
`views/pianoroll.lua` (20) and `ext.lua` (20). Most of the hot runtime
files are still Lua. The review gives these files more weight.

## 1. Measurements

### Size

| Part | Files | Lines |
| --- | ---: | ---: |
| Runtime, Teal (`runtime/lua/paw/**/*.tl`) | 94 | 78 745 |
| Runtime, Lua (`runtime/lua/paw/**/*.lua`) | 69 | 27 387 |
| Declarations (`runtime/types/*.d.tl`, `paw/*.d.tl`, generated) | 7 | 1 042 |
| LuaLS meta file (`runtime/types/paw.lua`, generated) | 1 | about 400 kB |
| Extensions, Lua without tests | | 71 319 |
| Extensions, Teal | | 764 |
| Extension tests (`extensions/*/tests*.lua`) | | 22 396 |
| `tests/*.lua` (the suite and its files) | 134 | 41 504 |
| `tests/e2e` | | 1 928 |
| `tools/` (Lua and shell) | 13 | 2 521 |
| `web/browserpod` (JavaScript, shell, Nix) | 12 | 947 |

The runtime is three quarters Teal. The extensions are 99 % Lua.

### Extensions

| Extension | Lua | Teal | Tests | Raw `paw.api` calls | Native |
| --- | ---: | ---: | ---: | ---: | --- |
| `notation` | 24 376 | 157 | 6 600 | 253 | |
| `utau` | 9 508 | 209 | 2 167 | 239 | Nix |
| `plugstate` | 6 437 | 0 | 3 133 | 145 | |
| `interop` | 4 591 | 0 | 1 822 | 164 | |
| `articulations` | 3 915 | 0 | 806 | 69 | |
| `tutor` | 3 470 | 0 | 537 | 22 | |
| `doctor` | 2 217 | 0 | 526 | 110 | |
| `projdiff` | 2 199 | 0 | 594 | 40 | |
| `drums` | 2 172 | 0 | 805 | 48 | |
| `vinput` | 1 812 | 0 | 411 | 42 | |
| `mixdiag` | 1 787 | 0 | 708 | 44 | |
| `pattern` | 1 527 | 0 | 500 | 21 | |
| `launcher` | 1 259 | 0 | 703 | 105 | |
| `musicops` | 1 245 | 0 | 623 | 12 | |
| `sections` | 1 166 | 0 | 370 | 40 | |
| `undotree` | 909 | 0 | 418 | 95 | |
| `midilsp` | 816 | 0 | 374 | 17 | |
| the other 8 | under 600 each | `columnplus` 254, `rulerplus` 144 | | | `ara`, `sampler` |

All extensions together make about 1 470 calls to the raw kernel
(`paw.api.*`), with no type check, because the files are Lua.

### Largest files

| File | Lines | Language | Note |
| --- | ---: | --- | --- |
| `frontend.tl` | 4 791 | Teal | the state for the window, and 123 gesture functions (`paw.frontend.act`) |
| `layout.tl` | 3 520 | Teal | windows, buffers, tabs, per-window state, and the commands of windows (`M.setup`, 625 lines) |
| `textbuf.tl` | 3 356 | Teal | lists edited as text |
| `ex.tl` | 2 911 | Teal | Ex ranges and commands |
| `roll_draw.tl` | 2 348 | Teal | the pencil of the piano roll |
| `objects.tl` | 1 971 | Teal | track, clip, device and lane objects |
| `types.tl` | 1 922 | Teal | kernel records, written by hand (F2) |
| `help.tl` | 1 898 | Teal | |
| `lsp/init.tl` | 1 864 | Teal | |
| `contracts.tl` | 1 829 | Teal | 115 records and interfaces |
| `scope.tl` | 1 768 | Teal | |
| `ui.tl` | 1 746 | Teal | |
| `views/arrange.lua` | 1 734 | Lua | hot spot |
| `pick.tl` | 1 695 | Teal | |
| `keymap.lua` | 1 597 | Lua | hot spot; the core of modal editing |
| `views/curve.lua` | 1 438 | Lua | |
| `defaults/keys.lua` | 1 381 | Lua | about 300 mappings, 226 inline functions |
| `views/pianoroll.lua` | 1 059 | Lua | hot spot |
| `views/arrange_mouse.lua` | 999 | Lua | |
| `fx.lua` | 927 | Lua | |
| `ext.lua` | 854 | Lua | about 35 registries (E2) |
| `tools/apidoc.lua` | 1 527 | Lua | 8 generated outputs |

### Longest functions (not tests)

A script found each `function` and its `end` at the same indent. One-line
functions are not counted.

| Lines | Function | Kind of length |
| ---: | --- | --- |
| 786 | `notation/tui.lua:266 view:render` | the whole staff in cells, one procedure |
| 716 | `paw/pick/sources.tl:582 make` | a table of about 30 picker sources, one closure each |
| 666 | `notation/score.lua:315 M.transcribe` | one procedure |
| 625 | `paw/layout.tl:2894 M.setup` | a list of `command(...)` and `map(...)` entries |
| 597 | `notation/musicxml.lua:1370 part_xml` | one procedure |
| 425 | `utau/gui.lua:130 view:paint` | one procedure |
| 352 | `paw/views/arrange.lua:1301 view:render` | the arrange view, all rows and parts |
| 298 | `paw/views/pianoroll.lua:480 view:render` | the piano roll, all parts |
| 265 | `paw/frontend.tl:1659 M.state` | the state for the window, many parts |
| 261 | `tools/apidoc.lua:870 M.teal` | the writer of `paw.d.tl` |
| 257 | `paw/ext.lua:176` (the table `M.registries`) | a list of registries (E2) |
| 249 | `paw/theme.tl:121 build` | a table of highlight groups |
| 243 | `paw/fx.lua:675 M.setup` | commands and keys |
| 217 | `paw/views/mixer.lua:68 strip` | one procedure |
| 208 | `paw/views/arrange.lua:365 header` | one procedure |
| 184 | `paw/keymap.lua:1162 handle` | the dispatch of one key |

The runtime has 42 functions of 100 lines or more, and 10 of 200 lines or
more. The extensions have 43 and 12. The deletion test says that a list
of entries (`make`, `M.setup`, `M.registries`, `build`) is long but not
deep or shallow: a split moves the length and does not remove it. The
long procedures (the `render` functions, `transcribe`, `part_xml`,
`handle`) are the real candidates.

### Types

- `any` in the code of the Teal runtime: 7 places (`shada.tl:137`,
  `roll_draw.tl:1272`, `ui.tl:1654`, `types.tl:34` `Meta`, and 3 more in
  comments or `KindValue`). The rule "no `any` where a value has a shape"
  holds in the Teal runtime.
- `any-allowed.txt`: 49 entries. 37 of them say "written in Lua: typed
  when its module is ported to Teal". 11 are truly free data (JSON, TOML,
  state, `meta`).
- `paw.d.tl`: the global `paw` has 150 top-level names. 32 of them are
  `Untyped` (the modules that are still Lua).
- Casts: 1 384 `as` casts in the code lines of the Teal runtime (comments
  and strings removed). The most common: 65 `(_G as {string: Paw}).paw`,
  148 `as integer`, 101 `as (boolean, ...)` after `pcall`, 53 `as Value`.
- Stand-in records: Teal modules declare their own small record for a
  module that is still Lua or that they cannot name: `local record Keymap`
  in 14 files, `Roll` or `PianoRoll` in 10, `Ui` in 12, `Arrange` in 5.
  Each one is a copy of a part of an interface, and no check makes sure
  that the copy agrees with the module.
- 13 `(require as function(string))("paw.x")` calls hide a `require` from
  the checker, to break a cycle of load order.

### References between modules

`require` shows only a part of the graph, because modules also reach each
other at run time through the global table `paw`.

| Module | `require` fan-in | Distinct `paw.*` names it reads | Note |
| --- | ---: | ---: | --- |
| `paw.api` | 78 | | the kernel |
| `paw.types`, `paw.partial`, `paw.contracts` | 59, 53, 53 | | types only |
| `paw.events` | 41 | | |
| `paw.objects`, `paw.options` | 39, 39 | | |
| `paw.frontend` | | 59 | and 28 `require` |
| `paw.defaults.project`, `defaults.keys`, `paw.ext` | | 37, 36, 35 | |
| `paw.views.arrange`, `paw.roll_draw`, `paw.ex`, `paw.lsp` | | 26 to 28 | |

`paw.ui.views.<name>` is read 181 times from outside the view. The piano
roll alone is read from 15 modules (`paw.ui.views.pianoroll`, 37 times
and more through local names).

References in both directions between the central modules (row reads
column, `paw.x` uses and `require`):

| | `ui` | `layout` | `keymap` | `draw` | `cursor` | `scope` | `canvas` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `ui` | | 2 | 1 | 12 | | | 9 |
| `layout` | 14 | | 2 | | 2 | | 4 |
| `keymap` | 45 | | | | 4 | | |
| `draw` | 2 | | | | | | |
| `cursor` | 2 | | 2 | | | | |
| `scope` | 8 | 3 | 1 | | 10 | | |
| `canvas` | 40 | 11 | 3 | | | | |

So `ui` and `keymap`, `ui` and `layout`, `ui` and `canvas`, `ui` and
`draw`, and `cursor` and `keymap` each read the other.

### Events

- The kernel events have one owner: `events/kernel.tl`, generated from
  Rust, one descriptor and one payload record each.
- The runtime events have no owner. The descriptor of `option.changed`
  is made again in 10 modules, with 8 local `OptionChanged` records.
  `mode.changed` is made in 5 modules, `startup` in 4, `exit`,
  `render.before` and `render.finished` in 3 each.
- Teal code subscribes with descriptors (43 places). Lua code and
  extensions subscribe with text (90 places), so a misspelled name is
  silent.

### State that a seat or a window swaps

- 39 calls of `seats.keep` or `seats.fields`: when another seat (another
  terminal or window) has its turn, paw stores these module locals and
  puts back the values of that seat.
- 6 views name `window_state`, and 3 modules call `window_keep`: before a
  view draws in a window, or a key acts in it, `layout.bind` puts the
  state of that window into the fields of the one view table.

### Tests

- About 1 870 tests in 134 files of `tests/` and the `tests*.lua` files of
  25 extensions. `tests/suite.lua` loads all of them into one paw process
  and runs them in order. No test runs in a process of its own.
- `T.fresh()` makes a new project and puts back the layout and focus. It
  does not put back options, the mode, registers, scopes, hooks, timers
  or the registrations of an extension.
- 383 writes of `paw.opt.x = ...` in 91 test files. Each file must put
  each value back itself (194 uses of `T.after` or `after`).
- Local helpers that many files repeat: `start` in 55 files, `screen` in
  33 (a call of `api.ui_snapshot(w, h)`), `load` in 32, `song` in 23.
- TASK-121 lists tests that fail only under `suite.sh only <words>`.

### The cost of a key (from `bench/RESULTS.md`, 2026-11-21 and 2026-11-22)

On the large bench project (64 tracks, 2 000 clips, 50 000 notes), with
external load: moves in the arrange view 7 to 12 ms of kernel time; `j`
in the piano roll 77 ms (TASK-113); `dd` and `u` 192 ms a round, of which
full frames are 58 ms; Enter on a clip, "drawing the screen" 370 to 540
ms under heavy load. `ui.render_screen` (`ui.tl:1153`) draws every
window of the tab on every frame. Only the arrange view keeps cells
between frames (its row cache, `buf:keep`, `views/arrange.lua:965`).

## 2. Summary: the findings, by value and risk

Value: the gain for callers or the locality, and what the change
unblocks. Risk: the chance to break behavior. Size: S is less than 1 day,
M is 1 to 3 days, L is 3 to 7 days. "Now" says which milestone in
progress the finding helps.

| # | Finding | Value | Risk | Size | Order | Now | Tickets |
| --- | --- | --- | --- | --- | --- | --- | --- |
| L1 | A reset seam and a leak check for the test suite; shared helpers; shards | high | low | M | 1 | m-3 (TASK-121) | refines TASK-121; touches TASK-69 |
| L2 | Keep the cells of a window when what it shows did not change | high | medium | M | 2 | m-3 | TASK-113, TASK-77.2, TASK-77.4 |
| L3 | Port the hot Lua first: `keymap`, then the piano roll, then the arrange view | high | low | L, in parts | 3 | m-4, m-2 | splits TASK-22 |
| L4 | `frontend.tl` in two modules, and gestures that use the same edit operations as keys | high | medium | L | 4 | m-4, m-3 | TASK-77.4, TASK-17 |
| L5 | One owner for each runtime event | medium | low | S | with L3 | m-4 | none |
| L6 | A state for each window as an object, not fields swapped into one view table | medium | medium | L | 5 (spike first) | m-2 | TASK-6.2 |
| L7 | A written order of layers, and a check of new upward references | medium | low | S, then M | 6 | none | TASK-26 |
| L8 | The public surface of `paw`: mark what is internal before the API lock | medium | low | S to M | 7 | none | before TASK-105 |
| L9 | `tools/apidoc.lua` in Teal, as readers and writers, and its check in `nix flake check` | medium | low | M | 8 | none | with TASK-96 |
| L10 | The extensions with the most raw API calls move to Teal before F2 changes the shapes | medium | low | L | 9 | none | TASK-22, before TASK-96 |

The order in short: L1 first (it is cheap, and it makes each later
change safer to merge), then L2 (the largest gain for m-3, and the seam
is already there), then L3 with the m-4 work on keys, then L4. L6 needs a
spike after the piano roll is Teal. L7 to L10 go to m-10 with the Rust
findings.

## 3. The findings

### L1. A reset seam and a leak check for the test suite

**Evidence.**

- One paw process runs all about 1 870 tests (`tests/suite.lua`, lines
  315 to 378). The order is the order of the file names, then the
  extensions.
- `T.fresh()` (`tests/suite.lua:128`) resets the project, the loop, the
  layout and the focus. It does not reset options, the mode, registers,
  marks, scopes, open floats, hooks, timers, or what an extension
  registered.
- 91 test files write 383 options. Each file puts them back with
  `T.after`, or in its last test (TASK-121 names `tests/tuimouse.lua`).
  A filter (`only <words>`) that skips the last test leaves the options
  changed for the next file.
- 55 files define their own `start()` (most do `fresh()`, two Escapes and
  close the floats), 33 their own `screen()`.
- The runner has no way to say which test left state behind, and the
  suite is serial: one core for the whole run.

**Proposed change.**

1. `paw.options.snapshot()` and `paw.options.restore(s)`, from
   `options.definitions()`. `T.fresh()` restores the options of the start
   of the run, sets the mode to normal, clears the pending keys and the
   floats, and widens the scope of each window.
2. After each test file, the runner compares a small fingerprint with the
   one of the start: the option values, the number of hooks, timers and
   keymaps, and the loaded extensions. A difference fails a test named
   "`<file>` leaves no state behind", with the names that changed. With
   E2 (`Registry<T>`), the fingerprint is "the entries whose owner is not
   the runtime or a loaded extension".
3. `T.start()` and `T.screen(w, h)` in `tests/suite.lua`. Delete the
   local copies when a file changes next (no sweep of all files).
4. Shards: `suite.sh -j N` starts N paw processes, each with its own
   scratch folders, and gives each a share of the files. The default
   stays one process. The owner limits builds and agents to `-j 4`, so N
   is 4 at most.

**Gain.** Locality: the reset is one function, not 55. A test that
leaks state fails in the file that leaks, not in a later file. Any
filter gives the same result as the full suite (the acceptance criteria
of TASK-121). Shards make a full run shorter, and they show order
dependence because the order changes.

**Risk.** Low. The fingerprint check can show many leaks at the start:
add it with an allow-list that only goes down, as `any-allowed.txt` does.

**Size and order.** M. First.

### L2. Keep the cells of a window when what it shows did not change

**Evidence.**

- `ui.render_screen` (`ui.tl`, lines 1153 to 1268) fills the screen and
  calls the `render` of each window of the tab on each frame. A view is
  drawn in immediate mode: all its rows, each frame.
- The kernel can keep cells: `buf:keep(key, x, y, w, h)` and the
  matching restore (`buf.tl:107`, `api.grid_keep`). One adapter uses it:
  the row cache of the arrange view (`views/arrange.lua:965`, TASK-88).
- The cost: `j` in the piano roll costs 77 ms of kernel time, against 7
  ms in the arrange view (TASK-113). A key in one window draws all the
  others again too. In the `dd` and `u` round, full frames are 58 ms of
  192 ms.
- `paw.derived` (`derived.tl`) gives a value and a stamp for what the
  project derives, and TASK-77.4 plans a node for the state of each track.

**Proposed change.**

- A view can give `stamp(self, ctx): string`: a cheap key of all that its
  drawing reads (the size of the window, the cursor, the scroll, the
  revision of the project or the stamps of the derived nodes it reads,
  the focus, the mode). `render_screen` keeps the cells of each window
  rect under the stamp (`buf:keep`). When the stamp is the same, it puts
  the cells back and does not call `render`.
- A view without `stamp` draws as now. A highlight change forgets all
  kept cells (`buf.tl:106` does so already).
- Live parts (the clock, meters) stay as they are: `M.live` draws them
  over the kept cells.
- First adapters: the arrange view (its row key becomes the window
  stamp), the piano roll, the mixer and the track list. Two adapters make
  the seam real; the arrange row cache is the first.

**Gain.** m-3: a key in one window costs the drawing of that window, not
of the tab. The seam already exists in the kernel. The stamps of
`paw.derived` (TASK-77) give each view a correct key with no own cache.

**Risk.** Medium. A stamp that misses an input shows an old picture.
Guard it with a debug option that draws each window and compares it with
the kept cells (`paw.opt.check_stamps`), run in the suite on the view
tests.

**Size and order.** M. Second, with TASK-113.

### L3. Port the hot Lua first: `keymap`, then the piano roll, then the arrange view

**Evidence.**

- The Lua that stays in the runtime is 27 387 lines in 69 files. The
  migration table of `docs/explanation/about-teal.md` (lines 298 to 317)
  plans it as wave 5, "Keys and views": `keymap`, `keyrule`, `keybar`,
  `defaults/`, `views/`, `roles/`, 15 000 lines, in TASK-22 (m-6, low).
- These files are the hot spots of the last two weeks: `views/arrange.lua`
  36 commits, `keymap.lua` 30, `defaults/keys.lua` 30, `views/pianoroll.lua`
  20, `ext.lua` 20.
- Because they are Lua, the Teal modules copy parts of their interfaces:
  14 local `Keymap` records, 10 `Roll` or `PianoRoll`, 5 `Arrange`. 37 of
  the 49 entries of `any-allowed.txt` and 32 `Untyped` names of
  `paw.d.tl` are modules in Lua.
- `keymap.lua` (1 597 lines) holds mappings, modes, the visual selection,
  registers, the jump list, the change list, marks, search, macros, the
  ShaDa parts and the dispatch (`handle`, 184 lines). `lookup`
  (`keymap.lua:1065`) walks all mappings of each scope for each key and
  compares prefixes (859 mappings in the runtime and extensions). It was
  not measured as a cost; a prefix table makes it independent of the
  number of mappings.
- `mode.changed` is made as a descriptor in 5 Teal modules, because
  `keymap` cannot export one (L5).

**Proposed change.** Split TASK-22 into ordered parts, each one port with
no change of behavior (the teal skill, "A port, step by step"):

1. `keymap` (with `keyrule`, `keybar`). In the port, move the parts that
   the deletion test keeps apart: registers and macros
   (`keymap/registers.tl`), marks and jumps (`keymap/marks.tl`, next to
   `address.tl` and `locators.tl`, which already own the forms of a
   place), and the mapping table with dispatch (`keymap.tl`). Export
   `mode_changed` as a descriptor. Use a table of prefixes for `lookup`.
   Delete the 14 stand-in `Keymap` records.
2. The piano roll: `views/pianoroll.lua`, `roll_clips.lua`,
   `views/pianoroll_mouse.lua`, `views/pianoroll_strip.lua`. Give the
   view one exported record `PianoRoll` and delete the 10 stand-ins.
3. The arrange view: `views/arrange.lua`, `views/arrange_mouse.lua`,
   `roles/arrange.lua`. Split `view:render` (352 lines) by part (header,
   rows, lanes, ruler) in the port.
4. `ext.lua` with E2 (TASK-103): the registries become typed in the same
   change.
5. `defaults/` and the other views.

**Gain.** For callers: one typed interface in place of 29 copies. m-4
(modal editing) works in `keymap`: TASK-17 and the pencil work get the
checker there. m-2 (views) works in the piano roll and the arrange view.
The allow-list loses about 10 entries for each part.

**Risk.** Low: a port changes no behavior, and the tests guard it. Do
part 1 when no other branch changes `keymap.lua` (it is a hot spot).

**Size and order.** L in all, M for each part. Third, part 1 with the
next m-4 work on keys.

### L4. `frontend.tl` in two modules, and gestures that use the same edit operations as keys

**Evidence.**

- `frontend.tl` (4 791 lines) holds two modules in one file: the state
  that a graphical frontend polls (`M.state`, 265 lines, and its helpers,
  lines 847 to 2175), and `paw.frontend.act` (`A`, lines 2176 to 4791):
  123 gesture functions for clips, notes, lanes, tempo, takes, routing
  and devices. The window calls `act` by name
  (`paw-gui/src/app.rs:294`), and so do the mouse modules of the
  terminal (`views/arrange_mouse.lua:16`) and `mouse_menus.tl`. This
  part follows rule 2: one code path for both frontends.
- It reads 59 distinct `paw.*` names and 28 modules: the widest module of
  the runtime.
- The gestures edit the model themselves: in the `A` part, 17 calls of
  `api.clip_set`, 11 of `api.track_set`, 8 of `:edit_notes`, and 7 of
  `commands.exec`. The keys go through `paw.edit` operators
  (`edit.tl`) and commands. So one action has two implementations.
- Example: quantize exists three times. `edit.tl:464 A.quantize` (the
  operator: clips to `opt.grid`, notes to `opt.note_grid`),
  `frontend.tl:4520 A.quantize_notes` (the chosen notes, with a
  strength), and `extensions/musicops/lua/musicops/init.lua:165
  M.quantize` (notes in, notes out, with strength, swing and lengths).
  The menu of the curve view has a fourth for points
  (`curves.tl:627`).

**Proposed change.**

1. Split the file: `frontend/state.tl` (the poll, with TASK-77.4's node
   for each track) and `frontend/act/` with one file for each area
   (`clips.tl`, `notes.tl`, `lanes.tl`, `tempo.tl`, `routing.tl`,
   `devices.tl`). `paw.frontend.act` stays the one table that the window
   calls, so `paw-gui` does not change.
2. A core module of pure note transforms, `paw.notes` (Teal): a list of
   notes and options in, a list of notes out (quantize with strength,
   swing and lengths; legato; and the others of `musicops` that the core
   needs). The key operator, the gesture and `musicops` call it. This
   follows rule 5: the core change is generic, and the extension gets
   smaller.
3. A gesture that has a key equivalent calls the same operation (a
   `paw.edit` operator over a region, or a command), so the undo name
   and the message are the same (rule 6).

**Gain.** Locality: one implementation of each edit, one place to fix.
For m-4: the mouse and the keys stay the same in behavior (the pencil,
TASK-17). For m-3: a small state module is the place for TASK-77.4.

**Risk.** Medium. The window tests (`cargo test -p paw-gui`),
`tests/frontend.lua` and `tests/tuimouse.lua` guard it. The quantize of
the operator and of the gesture differ today (the gesture keeps the
length inside the clip). Keep each behavior through options of the
shared transform, and do not change what the user sees in the same
branch.

**Size and order.** L: the split is M, the shared transforms are M.
Fourth.

### L5. One owner for each runtime event

**Evidence.** See "Events" in part 1. The kernel events have a generated
owner (`events/kernel.tl`); the runtime events (`option.changed`,
`mode.changed`, `view.focused`, `startup`, `exit`, `render.*`,
`win.enter`, `tab.enter`, `cursor.changed`, `lanes.changed`) do not. 8
copies of the record `OptionChanged` can disagree, and a Lua handler
with a wrong name gets no call and no error.
`docs/reference/events.md` lists the events by hand.

**Proposed change.**

- The module that emits an event exports its descriptor:
  `options.changed`, `keymap.mode_changed` (after L3 part 1),
  `ui.view_focused`, `shada.exit`. The other modules use that one.
- `paw.on("name", fn)` with text warns once in the log when no module
  declared the name (a typo), and `:checkhealth events` lists such names.
- `tools/apidoc.lua` writes the rows of `docs/reference/events.md` from
  the descriptors and their payload records, as it does for the kernel
  events.

**Gain.** One record for each payload. A typo shows. The events page is
always true (the documentation rule: each fact is true).

**Risk.** Low. Size S. With L3 part 1.

### L6. A state for each window as an object, not fields swapped into one view table

**Evidence.**

- A view is one table. `window_state` (6 views) and `window_keep` (3
  modules) make a view work in many windows: `layout.bind`
  (`layout.tl:667`) stores the fields of the window before and puts the
  fields of the next window into the view table, before each draw, key,
  pointer event and command (`layout.tl`, lines 570 to 640).
- Seats do the same for module locals (39 keepers, `seats.tl`).
- 15 modules read `paw.ui.views.pianoroll` at any time (a timer, an
  event handler, a gesture). Each reads the state of the window that was
  bound last. That is correct only when the caller runs inside a bound
  turn.
- TASK-6.2 (m-2) moves folds into the state of each window, so the
  amount of swapped state grows. Subprojects (TASK-7) and scopes
  (`scope.tl`) already keep state for each window.

**Proposed change (a spike first).** The layout makes one instance for
each window of a view: `setmetatable({ win = id }, { __index = view })`.
`render(self, buf, ctx)` and the other methods get the instance as
`self`, so the fields of `window_state` are fields of the instance and
need no swap. A module outside the view asks for an instance:
`paw.ui.instance("pianoroll")` (the window with the focus, else the last
one) or `paw.ui.instance_of(win)`. `window_state` stays as the list of
what a split copies. Seats keep the map of windows, not each field.

**Gain.** Locality: the state of a window is in one table. A reader gets
the state of a named window, not of the last bound one. No swap on each
draw. Two piano rolls on one screen are two objects.

**Risk.** Medium. It changes the contract `View` for extensions (6
views of the runtime, and the views of extensions that keep state).
Do the spike on the piano roll after L3 part 2, and decide then.

**Size and order.** L. Fifth, after a spike of S size.

### L7. A written order of layers, and a check of new upward references

**Evidence.** See "References between modules" in part 1. The global
`paw` works as a service locator: a module reads `paw.x` at run time and
the `require` graph does not show it. The table shows pairs that read
each other (`ui` and `keymap`, `ui` and `canvas`, `ui` and `layout`,
`cursor` and `keymap`). 13 `require as function` calls and 12 stand-in
`Ui` records exist only to break such cycles for the checker or for the
load order. The teal skill lists five pitfalls that come from these
cycles (two copies of one type that do not agree, "unknown type", the lower module declares
the part of the higher one).

**Proposed change.**

- Write the layers down in the explanation of the runtime (internal
  text, next to `about-teal.md`), from low to high: data (`util`,
  `music`, `types`, `bytes`); the project (`objects`, `cursor`, `edit`,
  `address`, `markers`, `tempo`); the screen (`buf`, `draw`, `canvas`,
  `layout`, `ui`); input (`keymap`, `commands`, `ex`); views
  (`views/*`, `roll_draw`, `textbuf`, `pick`); frontends (`frontend`,
  `remote`). A lower module gets what it needs of a higher one through
  an event or a callback that the higher module gives it at setup.
- A small script in `tools/` (Lua, run by the suite) reads the `require`
  and the `paw.x` references of each module and fails on an upward
  reference that is not on its allow-list. The list only goes down, as
  `any-allowed.txt` does.
- Then remove the upward references one by one, where a module changes
  for other reasons.

**Gain.** The graph that the check prints is the map that TASK-26 (a
scanner of Lua and Teal for the architecture map) wants. Fewer cycles mean fewer stand-in
records and fewer casts. TASK-3 (lazy extensions) and TASK-29 (the
runtime without LuaJIT) need a known load order.

**Risk.** Low (a check). Size S for the check, M for the first removals.

### L8. The public surface of `paw`: mark what is internal before the API lock

**Evidence.**

- `paw.d.tl` gives 150 top-level names. Public modules (`paw.track`,
  `paw.cursor`, `paw.ui`) are beside internal ones (`paw.seats`,
  `paw.remote`, `paw.mixer_rows`, `paw.device_rows`, `paw.roll_clips`,
  `paw.render_ranges`, `paw.timers`). `paw.derived` says in its header
  that it is internal, but nothing marks it.
- The same thing has two forms: `paw.render` (a module) and the
  top-level `paw.render_cancel`, `paw.render_status`, `paw.render_tags`,
  `paw.render_stems`, `paw.render_ranges`.
- Extensions require internal modules: `paw.views.cmdline` (13 places,
  for `remember`, the history of the command line), `paw.dsp`,
  `paw.canvas`, `paw.theme`, `paw.menu`, `paw.mouse_menus`,
  `paw.lsp.rpc`, `paw.layout`.
- Extensions replace global slots with no owner:
  `notation/popover.lua:48` sets `paw.notify` for a time,
  `utau/editor.lua:337` sets `paw.ui.grabber`.
- E5 (TASK-105) locks "each function of `paw.api` and `paw.*`" before the
  first release. Without a public list, the lock also freezes internal
  names.

**Proposed change.**

- A doc tag `--- @internal` on a module or a function. `tools/apidoc.lua`
  leaves tagged items out of `docs/reference/api.md` and of the lock,
  and keeps them in `paw.d.tl` for the runtime.
- Give the parts that extensions use a public form: the history of the
  command line (`paw.cmdline.history`), a stack for the key grabber and
  for a message sink (`push` with an owner, `pop`), which an unload pops.
- Fold the `render_*` names into `paw.render`. No compatibility is
  needed before a tagged release.
- Decide if `paw.api` (the raw kernel) is public for extensions. Today
  extensions make about 1 470 such calls. Neovim makes `vim.api` public.

**Gain.** Extension authors know what is stable. The lock of E5 covers
only that. A key grabber or a message sink that an extension takes goes
back when it unloads.

**Risk.** Low. Size S for the tag, M for the public forms.

### L9. `tools/apidoc.lua` in Teal, as readers and writers, with its check in `nix flake check`

**Evidence.**

- `tools/apidoc.lua` (1 527 lines, Lua) reads Rust doc lines and serde
  structs with patterns, the doc comments of the Lua modules, and the
  Teal modules. It writes 8 outputs: `docs/reference/api.md`,
  `runtime/types/paw.lua`, `paw.d.tl`, `paw/api.d.tl`, `partial.d.tl`,
  `opts.d.tl`, `role_props.d.tl` and `events/kernel.tl`. `M.teal` (the
  writer of `paw.d.tl`) is 261 lines.
- The check that the outputs are current runs in the suite
  (`tests/apidoc.lua`, which starts a second paw). `nix flake check`
  runs Vale, `cyan`, `luacheck`, the format check, the website and clippy,
  but not `apidoc check`.
- Two Teal checks have different rules: `tools/tlcheck.sh` (`cyan`, used
  by the flake) turns off the warning for a name declared again because 60 files
  cast `_G`; `paw.lang.check` in the suite counts unused locals and
  shadowed names as errors. `tools/fmtcheck.sh` leaves out `limit.tl`,
  `pick.tl` and `ui.tl`, because cerulean writes Teal that does not compile for them.

**Proposed change.**

- Port `apidoc` to Teal, as readers (Rust comments, serde structs, Lua
  doc comments, Teal modules) that fill one model, and writers (one for
  each output) that read the model. With F2 (TASK-96) the Rust readers
  get smaller: the shapes come from typed structs.
- Add `apidoc check` to `nix flake check`. The flake builds `paw`
  already, and the check needs no display or audio.
- One set of Teal rules: run `paw.lang.check`'s strict rules in the flake
  too, or make `tlcheck.sh` give the same result. Keep the cerulean list
  of skipped files in one place with the reason (it is there now).

**Gain.** Locality for the generator: a new output is one writer. A
stale declaration fails in CI, not only in a full suite run.

**Risk.** Low. Size M. With TASK-96.

### L10. The extensions with the most raw API calls move to Teal before F2 changes the shapes

**Evidence.**

- The extensions are 71 319 lines of Lua and 764 of Teal. They make about
  1 470 raw `paw.api` calls (`notation` 253, `utau` 239, `interop` 164,
  `plugstate` 145, `doctor` 110, `launcher` 105, `undotree` 95). No
  checker reads these calls.
- F2 (TASK-96) changes the views and patches of the kernel area by area.
  For each change, only the tests find the Lua callers.
- The longest functions of the code base are in extensions:
  `notation/tui.lua:266 view:render` (786 lines),
  `notation/score.lua:315 M.transcribe` (666),
  `notation/musicxml.lua:1370 part_xml` (597), `utau/gui.lua:130
  view:paint` (425).
- Rule 8 of the agent instructions: "A Lua file that changes much moves to Teal." The
  notation files are hot spots (`keys.lua` 34 commits, `init.lua` 31).

**Proposed change.** Port the extension files with the most raw API
calls and the most commits first: the notation files that F2's first
areas (tracks, clips) touch, then `utau`, `interop`, `plugstate`. In the
port, split each procedure over 200 lines by its steps. One extension is
one agent (the migration table already says so).

**Gain.** When F2 changes a shape, `cyan` names each caller. The long
procedures get names for their steps.

**Risk.** Low. Size L. Before the first area of TASK-96.

### Findings with a note only (no ticket)

- **The contract `View` is wide.** It has 43 optional fields
  (`contracts.tl:429`). It is a real seam (the runtime views and the
  extension views are many adapters), and each field has a use. When L6
  changes the contract, group the fields into records of capabilities
  (`grid`, `paint`, `window`, `time_axis`), so that an author reads one
  group at a time.
- **Lists of entries** (`pick/sources.tl make`, `layout.tl M.setup`,
  `theme.tl build`, `fx.lua M.setup`) are long and flat. Do not split
  them alone (the deletion test). `layout.tl M.setup` holds the commands
  of windows inside the module of windows: move it to
  `defaults/windows` when `defaults/` is ported (L3 part 5).
- **Eager boot.** `paw/init.lua` requires every module at start. The
  first frame without a project takes 35 ms, so this is not a cost now.
  TASK-3 (lazy extensions) and L7 give the load order that a lazy boot
  needs later.
- **Small copies of helpers** (`round` in 6 files, a file read in 35
  extension files) are below the level of this review. `paw.util` has
  `round` and `clamp`.
- **`web/`** has 947 lines of JavaScript, shell and Nix for the
  BrowserPod demo. They are small and have one job. No finding.
- **Teal is fine where it is.** The modules that waves 1 to 4 ported have
  no `any` and no `Untyped`. `contracts.tl` and `events/kernel.tl` are
  good seams. `paw.derived` is a deep module: a small interface (`node`,
  `get`, `changed`) over the graph, the slices and the cutoffs.

## 4. The extension system, the Lua side

The Rust review gave E1 to E6. The table below adds what the Lua side shows.

| From | What it shows | What to do |
| --- | --- | --- |
| `ext.lua` | About 35 registries; an unload compares copies of tables made before and after the load. Per-window and per-seat keepers, timers (`paw.timers`) and global slots (`paw.ui.grabber`) are not in the list. | E2 (TASK-103). Add the keepers, the timers and the slots of L8 as registries with an owner, so an unload removes them too. |
| Requires of runtime internals | `paw.views.cmdline`, `paw.canvas`, `paw.theme`, `paw.dsp`, `paw.menu`, `paw.layout` | L8: public forms, and `@internal` on the rest. |
| Raw kernel calls | about 1 470, with no type check | L10, and the decision of L8 on `paw.api`. |
| Core and extension | `musicops` has the best quantize; the core has two others. `xml.tl` and `zip.tl` in the core serve `interop`, `notation`, `plugstate` and `articulations`: a correct generic core (rule 5). `lsp/` serves `midilsp`, `mixdiag` and `notation`: also generic. | L4 part 2: pure note transforms in the core, `musicops` uses them. |
| Teal extensions | only `columnplus` and `rulerplus` are Teal at their root; `notation` and `utau` have a few `.tl` files | L10. The skill `paw-extension` already says "write it in Teal". |
| Two pictures of one view | `notation` and `utau` draw in cells (`tui.lua`, `editor.lua`) and paint in pixels (`gui.lua`), from one model. This follows rule 2 ("cells as the fallback"). | No change. |
| Events by text | extensions subscribe with text | L5: a warning for a name that no module declares. |

E3 (`needs` in the manifest) gets one more input from this review: the
extensions that use `ffi` or `io.popen` are the same ones that require
`paw.dsp` or start helpers (`luafx`, `utau`, `sampler`, `plugstate`).

## 5. The findings and the existing tickets

| Ticket | What this review adds |
| --- | --- |
| TASK-121 (order-dependent tests, m-3) | L1: the reset in `T.fresh`, the leak check after each file, shared helpers; shards show order dependence. |
| TASK-69 (tested as the test runner, m-8) | L1 gives the runner the reset and the shards first; compare `tested` after that. |
| TASK-113 (piano roll `j` costs 77 ms, m-3) | L2: a window that did not change is not drawn again; the stamp of the piano roll. |
| TASK-77.2, TASK-77.4 (derived nodes, m-3) | L2 uses the stamps of the nodes as window stamps; L4 makes the state of the window a small module for D4. |
| TASK-22 (Teal wave 5, m-6) | L3: split into ordered parts, `keymap` first, with the m-4 work. L10 for the extensions. |
| TASK-17 (pencil and insert, m-4) | L3 part 1 types `keymap` under it; L4 part 3 keeps the gestures and the keys of the pencil the same. |
| TASK-6.2 (folds are view state, m-2) | L6: more state for each window; a spike of window instances before or with it. |
| TASK-103 (E2 `Registry<T>`) | The extension part above: keepers, timers and global slots as registries with an owner. |
| TASK-104 (E3 `needs`) | The extension part above: the list of extensions with `ffi` or processes. |
| TASK-105 (E5 API lock) | L8 first: `@internal`, so that the lock covers the public surface only. |
| TASK-96 (F2 typed shapes) | L9: `apidoc` readers get smaller; L10: port the callers before the shapes change. |
| TASK-26 (a scanner of Lua and Teal for the architecture map, m-7) | L7: the check prints the graph that the scanner needs. |
| TASK-3 (lazy extensions), TASK-29 (no LuaJIT) | L7: a known order of layers and load. |

## 6. What a reader of each part meets first

- **The Teal runtime** is in good shape where waves 1 to 4 went: no
  `any`, typed contracts, generated declarations. Its cost is the casts
  and the stand-in records at the edges with the Lua that stays (L3) and
  with cycles (L7).
- **The Lua runtime** is the part that changes most: keys and views. It
  is the part that m-2 and m-4 work in (L3).
- **`frontend.tl`** is the widest module: two jobs in one file (L4).
- **The screen** draws all of it on each frame (L2).
- **The extensions** are many and capable, with a clear model (one API,
  registries with owners). They are Lua, and they call the raw kernel
  (L10, L8).
- **The tests** are thorough and real (real keys, a whole kernel). They
  share one process with no reset seam (L1).

## 7. Proposed tickets

Another agent cleans the backlog now. The present review makes no tickets. The
proposals below are ready to copy. The overlaps were checked with
`backlog search --plain` and `backlog task view --plain`.

### P1 (L1). Tests: a reset seam, a leak check after each file, and shards

- **Milestone:** m-3 (with TASK-121).
- **Description:** `T.fresh()` resets only the project and the layout,
  and one paw process runs about 1 870 tests in order. Add
  `paw.options.snapshot()` and `restore()`; make `T.fresh()` restore
  options, the mode, pending keys, floats and scopes. After each test
  file, compare a fingerprint (options, hooks, timers, keymaps, loaded
  extensions) with the start, and fail "`<file>` leaves no state behind"
  on a difference (with an allow-list that only goes down). Add
  `T.start()` and `T.screen(w, h)`. Add `suite.sh -j N` (N at most 4)
  with one process and scratch folders for each shard.
- **Acceptance criteria:** (1) the tests that TASK-121 names pass under
  any `only` filter; (2) the leak check runs after each file, and its
  allow-list exists with a count; (3) `suite.sh -j 2` gives the same
  result as `suite.sh`; (4) the how-to page on the tests says how to use
  `-j` and what the leak check says.
- **Dependencies:** none. E2 (TASK-103) makes the fingerprint smaller
  later.
- **Overlaps:** TASK-121 (this ticket can replace it, or be its plan);
  TASK-69.

### P2 (L2). Screen: keep the cells of a window whose stamp did not change

- **Milestone:** m-3.
- **Description:** `ui.render_screen` draws every window on each frame.
  Add an optional `stamp(self, ctx)` to the contract `View`; keep the
  cells of each window rect with `buf:keep` under its stamp, and put
  them back when the stamp is the same. Adapters: the arrange view (its
  row cache), the piano roll, the mixer, the track list. Add
  `paw.opt.check_stamps` that draws anyway and fails on a difference.
- **Acceptance criteria:** (1) a move key in the piano roll does not
  call the `render` of the other windows (a test counts calls); (2) the
  kernel time of `j` in the piano roll on the bench project falls,
  measured with the spread against main; (3) the view tests pass with
  `check_stamps` on; (4) the reference page on views documents `stamp`.
- **Dependencies:** none. Better with TASK-77.2 and TASK-77.4 (the stamps
  of the nodes).
- **Overlaps:** TASK-113 (do them together), TASK-77.2, TASK-77.4.

### P3 (L3). Teal wave 5, part 1: `keymap`, `keyrule`, `keybar`

- **Milestone:** m-4.
- **Description:** Port `keymap.lua` (1 597 lines), `keyrule.lua` and
  `keybar.lua` to Teal. Split registers and macros, and marks and jumps,
  into their own files under `keymap/`. Export `mode_changed` as a
  descriptor. Make `lookup` use a table of prefixes. Delete the 14
  stand-in `Keymap` records and the entries of `any-allowed.txt` that go.
- **Acceptance criteria:** (1) no `any` and no `Untyped` in the new
  modules; (2) the 14 stand-ins are gone; (3) the suite passes with no
  test changed; (4) the migration table of the Teal explanation and the teal skill
  say what the port found.
- **Dependencies:** none. Do it when no branch changes `keymap.lua`.
- **Overlaps:** TASK-22 (split it), TASK-17.

### P4 (L3). Teal wave 5, part 2: the piano roll

- **Milestone:** m-2.
- **Description:** Port `views/pianoroll.lua`, `roll_clips.lua`,
  `views/pianoroll_mouse.lua` and `views/pianoroll_strip.lua`. Export one
  record `PianoRoll`. Delete the 10 stand-in `Roll` and `PianoRoll`
  records. Split `view:render` (298 lines) by part.
- **Acceptance criteria:** as P3, for these files.
- **Dependencies:** P3 is better first (the view reads `keymap`).
- **Overlaps:** TASK-22, TASK-113 (do not port while TASK-113 changes the
  file).

### P5 (L3). Teal wave 5, part 3: the arrange view

- **Milestone:** m-2.
- **Description:** Port `views/arrange.lua`, `views/arrange_mouse.lua` and
  `roles/arrange.lua`. Split `view:render` (352 lines) and `header` (208
  lines) by part. Delete the 5 stand-in `Arrange` records.
- **Acceptance criteria:** as P3, for these files.
- **Dependencies:** P3.
- **Overlaps:** TASK-22.

### P6 (L4). Frontend: state and gestures in separate modules; shared note transforms

- **Milestone:** m-4 (the gestures), m-3 (the state for TASK-77.4).
- **Description:** Split `frontend.tl` into `frontend/state.tl` and
  `frontend/act/<area>.tl`; `paw.frontend.act` stays one table. Add a
  core Teal module `paw.notes` with pure transforms (quantize with
  strength, swing and lengths; legato; more as needed). The operator
  `edit.tl A.quantize`, the gesture `A.quantize_notes` and
  `musicops.quantize` call it. A gesture with a key equivalent calls the
  same operation as the key.
- **Acceptance criteria:** (1) no file of `frontend/` has more than 1 500
  lines; (2) one implementation of quantize for notes; (3) the window
  tests, `tests/frontend.lua` and `tests/tuimouse.lua` pass with no
  change of behavior; (4) the `musicops` README stays true.
- **Dependencies:** none for the split; the transforms are better after
  P4.
- **Overlaps:** TASK-77.4, TASK-17.

### P7 (L5). Events: one owner for each event of the runtime

- **Milestone:** m-4 (the mode event), else m-10.
- **Description:** The emitting module exports the descriptor of each
  runtime event; other modules import it. A text subscription to a name
  that no module declares warns once and shows in
  `:checkhealth events`. `tools/apidoc.lua` writes the runtime rows of
  the reference page on events from the descriptors.
- **Acceptance criteria:** (1) one descriptor and one payload record for
  `option.changed`, `mode.changed`, `startup`, `exit`, `render.*`; (2) a
  test of the warning; (3) the page on events is generated for these rows.
- **Dependencies:** P3 for `mode.changed`.
- **Overlaps:** none.

### P8 (L6). Views: a spike of one instance for each window

- **Milestone:** m-2.
- **Description:** On the piano roll, make the layout give each window
  its own instance of the view (`__index` to the view table), in place
  of the swap of `window_state` fields by `layout.bind`. Add
  `paw.ui.instance(name)` and `paw.ui.instance_of(win)` for readers
  outside the view. Measure the change in lines and in the time of a
  frame, and write a short design with a recommendation for all views
  and for the contract `View`.
- **Acceptance criteria:** (1) a branch with the piano roll on instances
  and its tests passing; (2) a design note with the recommendation and
  the list of extension views that change.
- **Dependencies:** P4.
- **Overlaps:** TASK-6.2 (more window state comes; decide before or with
  it).

### P9 (L7). Runtime: the order of layers, and a check of upward references

- **Milestone:** m-10.
- **Description:** Write the layers of the runtime in an internal page.
  Add a Lua script in `tools/` that reads `require` and `paw.x`
  references of each module, prints the graph, and fails on an upward
  reference that is not on its allow-list. Run it in the suite.
- **Acceptance criteria:** (1) the page and the script exist; (2) the
  allow-list has a count, and the check fails on a new upward reference;
  (3) the graph output can feed TASK-26.
- **Dependencies:** none.
- **Overlaps:** TASK-26.

### P10 (L8). API: `@internal`, public forms for what extensions use, and `render_*` into `paw.render`

- **Milestone:** m-10 (before TASK-105).
- **Description:** Add the doc tag `@internal`, honored by
  `tools/apidoc.lua`. Tag the internal modules. Give public forms to the
  command-line history and to the key grabber and message sink (a stack
  with an owner). Fold the top-level `render_*` names into `paw.render`.
  Write down whether `paw.api` is public for extensions.
- **Acceptance criteria:** (1) api.md lists no internal module; (2) no
  bundled extension requires a module that is internal; (3) an unload
  gives back a grabber or a sink that the extension took.
- **Dependencies:** none; before TASK-105.
- **Overlaps:** TASK-105, TASK-103.

### P11 (L9). Tools: `apidoc` in Teal as readers and writers; its check in the flake

- **Milestone:** m-8.
- **Description:** Port `tools/apidoc.lua` to Teal with readers that fill
  one model and one writer for each of the 8 outputs. Add `apidoc check`
  to `nix flake check`. Make `tools/tlcheck.sh` and `paw.lang.check` use
  the same rules.
- **Acceptance criteria:** (1) the outputs are the same bytes as before
  the port; (2) `nix flake check` fails on a stale declaration; (3) one
  set of Teal rules, written in the teal skill.
- **Dependencies:** none; easier after the first area of TASK-96.
- **Overlaps:** TASK-96, TASK-67 (done), TASK-22.

### P12 (L10). Extensions: port the files with the most raw API calls before F2

- **Milestone:** m-10 (with TASK-96).
- **Description:** Port to Teal the extension files that call the kernel
  areas of F2's first branches (tracks, clips): `notation` first, then
  `utau`, `interop`, `plugstate`. Split each procedure over 200 lines by
  its steps.
- **Acceptance criteria:** (1) the ported files type-check with no `any`
  where a value has a shape; (2) the extension tests pass unchanged;
  (3) no function over 300 lines in a ported file.
- **Dependencies:** P3 to P5 make the types of the runtime that these
  files use.
- **Overlaps:** TASK-22, TASK-96, TASK-77.6.

## 8. Questions for the owner

1. **Window instances (L6, P8): may the contract `View` change for
   extensions?** The swap of fields works, but a reader outside a turn
   sees the last window, and TASK-6.2 adds more window state.
   Recommended: yes to the spike on the piano roll; decide for all views
   after it.
2. **Shards for the suite (L1): may the suite run in up to 4 paw
   processes at once?** Recommended: yes, with one process as the
   default, and `-j` at most 4 (the rule for builds and agents).
3. **Internal names (L8): tag them only, or move them out of the global
   `paw`?** Recommended: tag them with `@internal` now, and move them
   before the first tagged release, when the API lock (TASK-105) starts.
4. **Is `paw.api` public for extensions (L8)?** Extensions make about
   1 470 raw calls. Recommended: yes, as `vim.api` is in Neovim, with
   the typed shapes of F2 as its contract.
5. **Pure note transforms in the core (L4), so that `musicops` uses
   them?** Recommended: yes. It follows rule 5 (the core change is
   generic), and it removes two copies of quantize.
6. **Port the extensions with the most raw calls before TASK-96 (L10)?**
   Recommended: yes for `notation` and `utau`, because F2 changes the
   shapes that they read, and only a checker finds all callers.

## Owner decisions (2026-11-22)

The recommendations of questions 1 to 5 are accepted: a spike on the piano roll before the `View` contract changes (L6); the suite may run up to 4 paw processes, one is the default (L1); internal names are tagged now and moved out before the first tagged release (L8); `paw.api` is public for extensions, with the typed shapes of F2 as its contract (L8); the core gets pure note transforms that `musicops` uses (L4).

Question 6: no. `notation` and `utau` do not move to Teal. They move to Rust as native extensions later, under the rule that paw loads no Rust library into the kernel. A design ticket covers how. L10 ports `interop` and `plugstate` only.

Tickets: P1 is in TASK-121; P2 to P12 are TASK-124 to TASK-134; the design of native extensions is TASK-135.
