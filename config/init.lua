-- A configuration to start from: the bundled extensions loaded, the
-- settings worth knowing about, each with what it does, and a command, a key
-- and an event of your own. It runs at startup and again on `:reload`.
--
-- `extensions/` beside this file holds two small extensions of your own,
-- loaded at startup as every folder in the configuration's `extensions` is:
-- `euclid` (a command and a key) and `clock.lua` (a view, `,C`).
--
-- To make it yours, link this directory as the configuration directory:
--
--   ln -s /path/to/paw/config ~/.config/paw
--
-- or try it for one run with `paw --config /path/to/paw/config`
-- (`paw-gui` takes the same option).

-- Where the bundled plugins are: the `extensions` directory beside this one,
-- or wherever $PAW_HOME says the source tree is.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local home = os.getenv("PAW_HOME") or (here .. "/..")
local plugins = home .. "/extensions"

-- The plugins. Take a line out, or put `--` before it, to leave one out;
-- each has a README in its directory saying what it adds and which keys.
for _, name in ipairs({
  "drums",      -- drum tracks in one step, a grid of the kit's pieces (`\kn`; `:drums.track`)
  "notation",   -- a MIDI clip as staff notation, to read and edit (`\n` on a clip)
  "utau",       -- singing synthesis and the vocal editor (`\Vt` adds a vocal track)
  "vinput",     -- virtual inputs: a guitar heard as MIDI through gdi2m (`\i`)
  "templates",  -- tracks, groups and device chains saved under a name (`\Tl` makes one, `\Ts` saves)
  "pattern",    -- clips written as a line of pattern text (`\tt`)
  "sections",   -- named sections of the song, and arranging by section (`\S…`)
  "musicops",   -- humanize, strum, arpeggiate, scales and the project's key
  "mixdiag",    -- the mix measured: loudness, true peak, phase (`,x…`)
  "undotree",   -- the undo tree, named checkpoints, A/B listening (`,u…`)
  "interop",    -- opening and writing the projects of REAPER and of DAWproject programs (`:e song.rpp`, `:import`, `:export`)
  "tutor",      -- the course: `:tutor` starts it
  "doctor",     -- a guided check of the hardware, with a written report (`:doctor`, `paw doctor`)
  "luafx",      -- devices written in Lua: gain and pan, drive, chords, sine (and how to write your own)
  "plugstate",  -- amp models, impulse responses, instrument files of plugins; snapshots (`]m`, `\s` in the device panel)
}) do
  paw.ext.load(plugins .. "/" .. name)
end

-- Plugins that `:doctor` loads on a track of its own and plays a few notes
-- on, to say whether sound comes out: name fragments, as `:device.add` takes.
-- paw.opt.doctor_plugins = { "MT-PowerDrumKit", "Ugritone" }

-- Audio. The devices are chosen once from the engine menu (`:audio`) and
-- remembered for this machine; name them here instead to pin them.
-- paw.audio.use({ output = "UR22mkII Stereo", input = "UR22mkII", buffer = 128 })

-- How things look and behave. These are the values the program starts with;
-- change one and take the `--` away.
-- paw.opt.zoom = 4              -- columns per beat in the terminal's arrange view
-- paw.opt.track_height = "auto" -- rows per track in the terminal; a number to fix it
-- paw.opt.header_width = "auto" -- columns for the terminal's track headers
-- paw.opt.termcolors = "auto"   -- "true" for 24-bit colour, "256", or "auto" to ask the terminal
-- paw.opt.ascii = false         -- draw the terminal with plain ASCII characters only
-- paw.opt.curve_glyphs = "sextant" -- curves in cells: "sextant" (connected), "braille" (dots) or "line"
-- paw.opt.braille = true        -- false draws curves as lines, whatever curve_glyphs says
-- paw.opt.graphics = true       -- pictures (kitty graphics protocol) where the terminal shows them; false: cells only
-- paw.opt.grid = 1              -- beats the cursor and clips snap to
-- paw.opt.note_grid = 0.25      -- beats notes snap to (a sixteenth)
-- paw.opt.autosave = 60         -- seconds between safety copies; 0 for none
-- paw.opt.reopen_last = false   -- start with the project that was open last, when none is named
-- paw.opt.threads = 0          -- audio threads; 0 leaves it to the machine
-- paw.opt.keybar = true         -- the line of keys at the bottom of the terminal
-- paw.opt.native_dialogs = true -- the window opens, saves and imports with the desktop's file dialog; false for the kernel's list
-- paw.opt.editor_on_add = true  -- a plugin added by hand (picker, `:device.add`, the window) opens its own window

-- A colour of your own for anything on screen:
-- paw.ui.hl("Playhead", { bg = "#ff5555" })

-- A command of your own. `ctx.args` holds what was typed after the name:
-- `:track.synth Lead cutoff=900`.
paw.command("track.synth", function(ctx)
  local track = paw.add_track({ name = ctx.args[1] or "Synth" })
  track:add_device("synth", { wave = 1, cutoff = tonumber(ctx.args.cutoff) or 1800 })
  track:add_device("delay", { mix = 0.2 })
  paw.cursor.set_track(track)
end, { desc = "Add a track with a synth and a delay: `track.synth Lead cutoff=900`" })

-- A key of your own: `,y` runs that command. The right-hand side is a
-- command line or a function.
paw.keymap.set("<leader>y", "track.synth", { desc = "Add a synth track" })

-- An event: react to what happens in the project.
-- paw.on("project.saved", function(event) paw.notify("saved to " .. event.path) end)
