# LAZY: lazy-loaded extensions, as lazy.nvim does

Read AGENTS.md, then TASK.md in this folder (`git reset --hard main` first; never end your turn to
wait; no `cargo fmt`; co-author line; no push, no merge; docs follow; never run tests/tools/e2e.sh
or loaded.sh; never wait with `pgrep -f` in a loop). Use .claude/skills/teal, paw-extension,
diataxis-docs. Read runtime/lua/paw/ext.lua (load, unload, the registries it tracks), the
manifests in extensions/*/manifest.lua, docs/reference/extensions.md, and the profile's startup
numbers in bench/profile.md and the scratchpad profile/REPORT.md if present.

## The owner's request
"It would be great to lazy-load extensions, so that heavy things like notation don't act until
called upon, similar to current Neovim." The owner uses lazy.nvim daily (`cmd`, `keys`, `event`,
`ft`, `lazy = true`, a stub that loads the plugin on first use). Match its words where they fit.

## Build
1. **Triggers in the manifest** (and in the user's config, which wins): `cmd` (Ex commands),
   `keys` (with mode and scope), `event` (paw events, e.g. `project_loaded`), `kind` (a clip kind or
   buffer type or track kind the project uses: a project with a notation clip loads notation when
   that clip is shown/opened, the analog of `ft`), `view`, and `lazy = false` to load at start.
   Decide the default (lazy where the manifest gives triggers) and say why.
2. **Stubs**: before load, the triggers exist as light stubs: the command shows in `:command`,
   completion and the `:` picker with its description; the key shows in which-key and `<leader>fk`;
   the first use loads the extension and then runs the real command/key with the same arguments,
   count and register, as one user action (one undo step). `K` and `:help ext` work without load.
3. **MIDI is the truth / a project opens and plays without the extension**: a project with clips
   of a lazy kind opens, plays and saves byte for byte the same before the extension loads; the
   kind loads when its data is first read/shown or edited. Health (`:checkhealth`) and
   `:extensions` show loaded / not loaded and why it loaded (which trigger), like `:Lazy`.
4. **Measure**: start-up time to the first frame and memory after open, before and after, for the
   default bundled set and for a project with notation clips (processor time, `perf stat`, spread,
   "measured under external load"; flock as RUST-COMMON). Name which extensions are worth lazy and
   make them lazy in their manifests (notation, utau, mixdiag, ... by the numbers).
5. Unload after a lazy load restores exactly (the registries); a lazy extension that fails to load
   gives one clear message, and the stub stays.
6. Docs: extensions.md (the triggers, the default), the paw-extension skill, a how-to section
   ("make an extension load on demand"), each changed manifest's README if it names start-up.
7. Tests (real keys): `:notation...` on a fresh start loads and runs; a key stub with a count; a
   project with a notation clip loads it when the clip is opened, plays unchanged before; `:extensions`
   status; unload/restore. Apply prune-tests.
Checks: build, tlcheck, apidoc check, full `suite.sh plugins`, Vale 0 errors, key-rule check empty.
Report: the design, the triggers per bundled extension, before/after numbers, the checks. Opus.
90–150 minutes.
