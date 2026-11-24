# Teal and Lua toolset for paw (TASK-66, with TASK-67..71 built)

Date: 2026-11-22. Branch `worktree-agent-ae41aa43fc0af79f0` (commits listed at the end).
Every tool below was run on the repository, not only read about. Numbers are
wall time on the shared machine, **measured under external load** (load
average 4-21 during the runs), with user CPU time beside it where it matters.

Tree sizes: 94 `.tl` files (92 runtime/config, 2 extensions; 72k lines),
520 `.lua` files outside vendored/generated code (167k lines).

## Verdicts

| Tool | What it is | Version (nixpkgs / upstream) | Activity | Teal 0.24.8 / LuaJIT | Speed on paw | Verdict |
|---|---|---|---|---|---|---|
| **cyan** | Teal build tool; `cyan check` checks many files in one env | 0.4.1 / 0.4.1 (main ahead) | 60 commits in 6 months, last 2026-10 | uses tl 0.24.8, runs on LuaJIT | 94 files: **6.9-7.5 s** (5.8-6.4 s user) vs `tl check` per file **104-127 s** (90-109 s user) | **Adopt** (done, TASK-67). Patched: see fault below |
| **cerulean** (`ceru`) | Teal formatter, one style | not in nixpkgs / 1.9.2 | 80 commits in 6 months, last 2026-11-15; hobby project, heavily agent-written (its own docs say so) | its rock is Lua compiled for 5.4; built from the Teal source for LuaJIT here: works | check of 93 files: 7.1-7.4 s | **Package, do not reformat.** One fixed style, no knobs: breaks paw's one-line functions and aligned comments. Fails on 3 files |
| **tested** | Unit test runner for Lua and Teal | not in nixpkgs / 0.6.0 | 12 commits in 6 months, last 2026-11-19; pre-1.0 | builds for LuaJIT from source; ran a trial file in 0.02 s | n/a | **Do not adopt** (TASK-69). Not committed; recipe below |
| **StyLua** | Lua formatter (Rust) | 2.5.2 | very active, widely used | `syntax = "All"` parses LuaJIT and the 5.3 REAPER scripts | 515 files: 1.1 s | **Package, do not reformat.** Same problem as cerulean, less severe |
| **luacheck** | Lua linter | 1.2.0 | lunarmodules, slow but maintained | has `std = "luajit"` | 520 files: 7.5-8.2 s | **Adopt** (done, TASK-70): clean, flake check, found a real bug |
| **selene** | Lua linter (Rust) | 0.31.0 | active | **no LuaJIT std**; `lua51` std cannot parse `goto` or `ULL` literals (43 parse errors in 7 files); wrong signatures for `io.stdout:flush` | 0.4-0.5 s | **Reject** for paw |
| **teal-language-server** | LSP for Teal | **0.1.3** in nixpkgs / **0.3.0** | 24 commits in 6 months, last 2026-11-04 | 0.3.0 pins tl 0.24.8, luv 1.52.1, ltreesitter 0.3.0, all in nixpkgs | n/a | **Adopt 0.3.0** (done, TASK-71). 0.1.3 gives no hover, no completion, no diagnostics on paw's files |
| **lua-language-server** | LSP for Lua (LuaLS) | 3.18.1 | very active | `runtime.version = "LuaJIT"` | batch `--check` of the tree: 42 s, 9,859 diagnostics (5,013 undefined-field, 3,614 need-check-nil) | **Adopt for editing only** (done, TASK-71); not as a checker |

## Findings in detail

### cyan (TASK-67, built)

- `tools/tlcheck.sh` now runs one `cyan --quiet --color never --wdisable redeclaration -I extensions/*/lua check <all .tl>`.
  Each extension's `lua/` is on the path for every file (extension modules are named after the
  extension, so they cannot collide); `tl check` got `-I` per file.
- **Same errors.** Two files broken on purpose (`runtime/lua/paw/util.tl`: three type errors and an
  unused local; `extensions/rulerplus/init.tl`: two errors and an unused local). Old script: the
  five errors and two warnings, but util.tl's printed **94 times** (once per file that requires it),
  exit 1. New: the same five errors and two warnings, util.tl's printed twice (cyan checks it once
  by path and once as module `paw.util`), exit 1.
- **Fault in cyan 0.4.1 (also on its main branch):** `report_env_results` does
  `ok = ok and common.report_result(res, cfg)`, so after the first file with an error it reports
  nothing more; the exit status is still 1. With unpatched cyan the rulerplus errors were silently
  missing. `nix/lua-tools.nix` patches the line (`ok = report(...) and ok`). Worth an upstream issue
  (owner's call; I did not open one).
- **Redeclaration warning:** the documented `local paw = (_G as {string:Paw}).paw` makes Teal warn
  "variable shadows previous declaration of 'paw'" in 60 files (120 lines of output). The check
  turns that warning kind off; `paw.lang.check` in the suite still counts shadowing.
- The suite does not call `tlcheck.sh` (it runs the same check in-process with `paw.lang.check`,
  tests/teal.lua); the flake's `teal` check does, now with the patched cyan.

### Formatters (TASK-68: configs and a counting check; **no reformat**)

Tried on a copy of the tree, never on the worktree.

| | files changed | lines +/- | notes |
|---|---|---|---|
| StyLua, 120 col (committed config) | 468 / 515 | +38,285 / -15,466 of 166,725 | |
| StyLua, 140 col | 459 / 515 | +27,327 / -11,497 | |
| StyLua, 100 col | 475 / 515 | +66,748 / -27,870 | |
| cerulean, indent 2, 120 col, no require sort | 90 / 93 (+3 skipped) | +24,794 / -12,623 of 71,993 | "formatting skipped: output did not parse" on `limit.tl`, `pick.tl`, `ui.tl` |

What drives the diff (samples):

```diff
-M.NOTE_ON = 1      -- e.key, e.value (velocity, 0 to 1), e.channel (1 to 16), e.attr (see M.attr)
-M.NOTE_OFF = 2     -- e.key, e.channel
+M.NOTE_ON = 1 -- e.key, e.value (velocity, 0 to 1), e.channel (1 to 16), e.attr (see M.attr)
+M.NOTE_OFF = 2 -- e.key, e.channel
```
(StyLua and cerulean: 670 aligned trailing comments lose their alignment.)

```diff
-  if x < lo then return lo elseif x > hi then return hi end
+  if x < lo then
+    return lo
+  elseif x > hi then
+    return hi
+  end
```
(StyLua: `collapse_simple_statement` keeps one statement, not `if/elseif` or `for ... do x end`.)

```diff
-local function keymap(): Keymap return paw.keymap as Keymap end
+local function keymap(): Keymap
+  return paw.keymap as Keymap
+end
-  names: {string:string}
+  names: {string: string}
```
(cerulean: every one-line function expanded — 1,206 one-liners in the tree — and map types respaced;
long calls exploded one argument per line.)

The owner's condition was "if the config cannot match the style closely, stop before the
reformat": it cannot, for either tool. Committed: `stylua.toml`, `.styluaignore`,
`tools/fmtcheck.sh` (cerulean's settings are flags there, because cerulean reads them from a
`cerulean` key in `tlconfig.lua`, and cyan warns "Unknown key 'cerulean'"), and a flake check
`format` that prints `StyLua would change 471 Lua files, cerulean 93 Teal files` and never fails
(the same pattern as the rustfmt check).

### tested (TASK-69: decision, no change)

Trial (scratchpad, not committed): `extensions/utau/lua/utau/msgpack.lua` and `utau/kana.lua`, the
only kind of module that runs outside paw, under `tested -f plain`: 4 tests in 0.02 s, clear
given/should/expected/actual report, `-F` name filter, `-t` tag expressions, TAP and JSON output,
luacov coverage, Teal test files. Missing: parallelism (`-n` is a no-op since 0.5), and everything
paw's runner is for: the kernel, the terminal UI and real keys (`T.keys`), rendering, plugins,
scratch XDG folders, the guide tests that read the docs, the leftover-file check.

Only about 20 Lua modules (6,500 lines) do not touch `paw` at all, and they are already covered
through the behaviors that use them in the suite. A second runner would split conventions and CI
for little gain. **Decision: do not adopt.** Revisit if paw grows a body of pure Teal libraries
(e.g. a music-theory core) that wants fast unit tests; packaging is easy (the same build as
cerulean: `tl gen --gen-target=5.1` of `src/tested.tl` and `src/tested/**` plus `dkjson.lua`, run
`tested.main` with luajit + argparse, luafilesystem, luacov, compat53;
`fetchFromGitHub FourierTransformer/tested rev 0.6.0
sha256-lsF0RgmiKZqEXmOtjA4LSgrTNXHOQ/4FG2V5BjTlNfw=`). Ideas worth borrowing into paw's runner
instead: a TAP/JSON output for CI, and given/should wording in failure messages.

### Linters (TASK-70, built)

- luacheck with `.luacheckrc`: std luajit, global `paw`, per-file globals for the REAPER (Lua 5.3,
  `reaper`) and Ardour scripts and the utau image script; off: 212 (unused args: contracts), 213
  (unused loop vars), 4xx (shadowing), 542 (empty if with a comment), 581, 613; 311 off in tests.
- Before: 523 warnings. After the fixes: **0**, and a flake check `lua` runs it.
- **Real bug found:** `extensions/notation/lua/notation/musicxml.lua` called `rests_to(len)` after
  the loop whose body declared it: a MusicXML voice that stops before its barline without written
  rests (Finale and Dorico do this in a second voice) crashed the import with
  `attempt to call global 'rests_to'`. Fixed (function hoisted), test added
  (`musicxml: a second voice that stops before the end of its bar gets rests to the barline`),
  which fails without the fix.
- Also: `_` written as a global in `notation/engrave.lua`; the rest were 147 unused locals,
  6 unused functions, 2 write-only tables, ~10 values never read — removed (a call kept as a
  statement, a pure value dropped). One-line edits in `runtime/lua/paw/views/{files,arrange,
  mixer,curve}.lua` may touch TASK-65's files: trivial to resolve.
- selene rejected (see table).

### Language servers (TASK-71, built)

- teal-language-server 0.3.0 (override in `nix/lua-tools.nix`) on `runtime/lua/paw/ex.tl`:
  completion of `util.` gives the 11 members; on `extensions/rulerplus/init.tl`: `paw.` completes
  149 fields, hover shows types. Syntax errors are published. 0.1.3 (nixpkgs) gave nothing.
  Limitation: `tlconfig.lua` does not list the extensions' `lua/` dirs, so a Teal extension with
  several modules will not resolve its siblings in the editor (only 2 Teal extension files today,
  neither has siblings).
- LuaLS with `.luarc.json` (LuaJIT, `workspace.library = runtime/types`, global `paw`): hover on
  `paw.option` shows its fields from `runtime/types/paw.lua` after the workspace loads (~30-40 s on
  this machine).
- How-to: `docs/how-to/configure-an-editor-for-paws-code.md` (Neovim: `vim.lsp.enable({ "teal_ls",
  "lua_ls" })`), with a test of the facts it states.

## Plan for TASK-67..71 (status)

| Task | Status | What is left |
|---|---|---|
| 67 cyan check | built | upstream the cyan report fault; optionally make `paw.lang.check` and cyan share one list of include dirs |
| 68 formatter | configs + counting check; **reformat not done** | owner decision (questions 1-2) |
| 69 tested | decided: no | nothing |
| 70 linter | built, clean, flake check | owner may want 311 on in tests too (about 15 places) or 4xx shadowing on for Lua |
| 71 language servers | built | include extension `lua/` dirs for the Teal server if Teal extensions grow modules |

## Owner questions (with recommended answers)

1. **Reformat the tree with StyLua anyway?** It would end aligned trailing comments and
   multi-statement one-liners, a +38k/-15k line diff colliding with every branch in flight.
   *Recommended: no.* Keep the counting check; if wanted later, format only new files
   (a check on files changed since main) rather than the tree.
2. **Reformat the Teal with cerulean?** *Recommended: no.* One fixed style with no setting for
   one-line functions, 3 files it cannot format, a young hobby project. Re-evaluate in 6 months.
3. **Report the cyan fault upstream?** *Recommended: yes* (a one-line fix; then drop the patch).
4. **Keep luacheck's shadowing warnings (4xx) off for Lua?** *Recommended: yes for now*; the Lua
   being ported to Teal gets shadowing checked by `paw.lang.check`.
5. **Should `tested` come back for pure Teal libraries later?** *Recommended: only if such a
   library appears*; otherwise no second runner.

## Commits (branch `worktree-agent-ae41aa43fc0af79f0`)

- `56cf8ca6` Toolset 0 (TASK-66): tools in the dev shell, `nix/lua-tools.nix`
- `7af5c33f` Toolset 1 (TASK-67): `tools/tlcheck.sh` on cyan, flake `teal` check
- `e0ca4653` Toolset 5 (TASK-71): `.luarc.json`, how-to, about-teal section
- `cce50773` Toolset 4 (TASK-70): `.luacheckrc`, fixes, MusicXML bug, flake `lua` check
- `392a4a8c` Toolset 2 (TASK-68): `stylua.toml`, `tools/fmtcheck.sh`, flake `format` check
