# Window instances of a view (TASK-130, spike of L6 / P8)

Status: spike done 2026-11-23. Branch `worktree-agent-a45f8a1b8868242eb`,
commits 578b7a60 (the spike), 23d854ce (merge of main 6c3286a3: TASK-124
window stamps, `paw.roll_context`) and 0ae575b3 (the stamp, the frames
test).
Source: `architecture-review-lua.md`, finding L6, proposal P8.

## 1. The question

A view is one table. With `window_state`, `layout.bind` copies the fields
of the window before out of the table, and copies the fields of the next
window into the table, before each draw, key, pointer event and command.
A reader outside the view (a timer, an event handler, another module)
reads the state of the window that was bound last.

The spike answers two questions:

1. Can the piano roll keep its state in one table for each window (an
   instance, with `__index` to the view), with no change for its readers?
2. Must the contract `View` change for all views and for extensions?

## 2. What the branch does

The piano roll sets `window_instances = true` (a new optional field of
`contracts.View`). Then:

- `paw/layout.tl` (`M.instances`) gives each window an instance: a table
  with the fields of `window_state`. Its metatable takes the other fields
  and the methods from the view's table (`__index = base`). A write of a
  field that is not in `window_state` goes to the view's table
  (`__newindex`), as before.
- `layout.bind` sets a pointer (`bound[name] = win`) and copies no field.
  A new window copies the state of the bound window (a split: the fresh
  fields are dropped, lists are copied), or all of the state of a bound
  window that went, or the home state. These are the rules of the swap,
  kept one for one (`instance_of`, `bind`, `drop_instances`).
- The view's table never holds a field of `window_state`. The home state
  (the state when no window shows the view) is a separate table. Each
  seat keeps its own home state (`seats.keep("layout.instances.<name>")`),
  so the `seats.fields("pianoroll", ...)` call is gone.
- `paw.ui.views.pianoroll` is a proxy. It reads and writes the fields of
  `window_state` in the instance of the bound window, else in the home
  state. The 81 references to `paw.ui.views.pianoroll` in 45 files (15
  files in 6 extensions) do not change.
- The draw of a window and its window stamp (TASK-124) call `render` and
  `stamp` with the instance as `self` (`ui.tl`: `draw`, `window_stamp`).
  Keys, the pointer and commands still call the view through the proxy,
  after `bind`.
- `paw.ui.instance(name)` gives the instance of the window with the
  keyboard (else the window that had it last, else any window; with no
  window, the proxy). `paw.ui.instance_of(win)` gives the instance of one
  window. Neither binds a window.
- `paw/roll_clips.lua` kept two module locals for each window through
  `window_keep` (the clips edited with the active clip, the toggles of
  the context tracks). An instanced view never swaps keepers, so these
  locals are now fields of the roll's instance (`edited`,
  `context_shown`). A new test guards it: two rolls of one clip, and `gE`
  in one adds a clip in that window only. The test fails with the
  `roll_clips.lua` of main on the branch.
- `M.per_window(name)` is true for a view on the swap and for a view with
  instances. `one_window`, `within`, `hand_over`, `settle`, the close of
  a window and `canvas.tl` use it in place of `M.keepers[name]`.
- `copy_tabs` (a new seat) leaves out `instances`, as it leaves out
  `kept`.

The other views with a state for each window (arrange, mixer, devices,
launcher, notation) stay on the swap. Both mechanisms work side by side.

## 3. Measurements

Lines (`git diff main --numstat`):

| File | Added | Removed |
| --- | --- | --- |
| `layout.tl` | 198 | 5 |
| `ui.tl` | 36 | 3 |
| `roll_clips.lua` | 42 | 33 |
| `pianoroll.lua` | 21 | 9 |
| `canvas.tl`, `contracts.tl` | 5 | 7 |
| tests (`window_state.lua`, `frames.lua`) | 23 | 1 |

The spike adds about 290 lines, because the swap stays for the other
views. When all views move, `window_keep`, `window_fields`, `Keeper`,
`kept`, `M.keepers` and the swap in `bind` go: about 130 lines of
`layout.tl`.

Time: the shared dev binary of main 6c3286a3, with its own runtime
("main") and with the branch runtime. A track with two clips of 64
notes; 300 frames of `ui_snapshot(160, 48)` after one warm frame; three
runs of each, alternated. Measured under external load (load average 6.6
to 8.9). Medians in ms, with the spread of the three runs:

| Case | main p50 | branch p50 |
| --- | --- | --- |
| one roll | 1.09 to 1.17 | 0.82 to 1.15 |
| two rolls side by side | 0.54 to 0.83 | 0.55 to 0.84 |
| `bind` of the other window (100 000 times, ns each) | 1 296 to 2 705 | 722 to 1 278 |
| read of `paw.ui.views.pianoroll.pitch` (ns) | 1.1 to 1.8 | 28 to 57 |

Load-independent counts (10 frames with two rolls): `render` runs 1.1
times for each frame on main and on the branch (the TASK-124 stamps keep
the window without the keyboard), and `bind` runs the same number of
times. The frame time is the same within the spread. A `bind` costs
about half: it still finds the window before in the tree (`M.get`), and
it copies no field. A read through the proxy costs a call of `__index`
(a function) in place of a field of a table, about 30 times more, but
no hot loop of the roll reads through the proxy (the draw has the
instance as `self`).

## 4. Findings

1. **The instance works with no change for readers.** The roll's tests,
   the window tests, the seat tests, the stamp and frame tests, the scene
   tests, and the extensions that read the roll (notation,
   articulations, musicops, snippets, launcher) pass. Failures that are
   also on main: "the vocal editor draws and erases expression curves
   under the notes", "narrowing to a group shows its tracks alone in
   this window" (under the `window` filter), "tutor: lesson 4" (under the
   `roll` filter).
2. **The proxy keeps the "bound window" rule.** A reader through
   `paw.ui.views.pianoroll` still reads the window that drew or acted
   last. Only a reader that changes to `paw.ui.instance_of(win)` gets the
   state of a named window. The gain of L6 ("a reader gets the state of a
   named window") comes only when the readers move, one by one.
3. **Module locals for each window are a hidden link.** `roll_clips.lua`
   kept window state in locals through `window_keep`. The tests did not
   see that the spike's first version lost it (no test had two rolls with
   different sets of edited clips): the new test closes that gap. The
   notation keeps locals the same way (`notation/init.lua`,
   `window_keep`).
4. **`rawget` on a view does not see the proxy.** `tests/frames.lua` read
   `rawget(view, "render")` and put it back after the test: on the proxy
   it read nil, put back `render = nil`, and every later roll test failed
   (14 to 29 tests, depending on the filter). The test now reads
   `view.render`. No runtime or extension code uses `rawget`, `pairs`
   or `next` on a view table, but an extension can: the contract must say
   so.
5. **Code that reads both `self` and the module's `view`.**
   `pianoroll.lua` has 126 `self` and 87 `view` references. While `bind`
   and the instance agree (the draw binds the window, then calls
   `render` with its instance), both give one state. To draw without
   `bind`, each `view.x` in the view's code must become `self.x`, and
   each helper module (`roll_clips`, `roll_draw`, `pianoroll_mouse`,
   `pianoroll_strip`) must take the instance as an argument.
6. **TASK-6.2 state (folds, scope, vzoom) is already on the window node**
   (`win.folds`, `win.scope`, `win.vzoom`), not in the view table. It
   needs no move.

## 5. Recommendation

- **Merge the branch.** It is safe (the tests pass; the change is opt-in
  by one flag, on the piano roll only), it gives the two functions that
  readers need (`paw.ui.instance`, `paw.ui.instance_of`), and it halves
  the cost of `bind` for the roll. It adds a second mechanism next to the
  swap until all views move. If the owner wants one mechanism only, merge
  only the finding and keep the branch for the next step.
- **The contract `View`:** keep `window_instances` opt-in now. Make it
  the default for each view with `window_state` when the last runtime
  view moves. Keep `window_state`: it stays the list of fields that a
  split copies. Write in the contract that a view with instances is a
  proxy (no `rawget`, `pairs` or `next` on it).
- **The order to move:** mixer and launcher (3 fields each, no keepers),
  then devices and arrange (with the `L.bound` checks in
  `device_rows.lua` and `devices.lua`), then the notation, whose
  `window_keep` locals must become instance fields first. Each move is
  one flag and a check for module locals and `rawget`.
- **Readers:** move the modules that read the roll outside a turn
  (timers, event handlers, gestures; the 15 of the L6 evidence) to
  `paw.ui.instance(name)` or `paw.ui.instance_of(win)`. Then make the
  view's code use `self` only. After that, the proxy and the `bind` of
  the draw can go, and `M.keepers` with them.
- **Seats:** with instances, a seat keeps only the home state of each
  view; the windows of a seat hold the rest.

## 6. Extension views that change

When `window_instances` becomes the default:

| Extension | What | Change |
| --- | --- | --- |
| launcher | `launcher` view (`window_state = scroll, top, geometry`) | none in its code; reads through the proxy stay correct |
| notation | `notation` view (`window_state` of 15 fields and a `window_keep`) | move the `window_keep` locals into fields of the instance |
| articulations, musicops, tutor, notation (`roll.lua`) | read `paw.ui.views.pianoroll` | none while the proxy stays; move to `paw.ui.instance` to read a named window |

The other extension views (doctor, mixdiag, drums, tutor panel, sections,
undotree, projdiff, vinput, the utau editor) show in one window at a time
and do not change.
