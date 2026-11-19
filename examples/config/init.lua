-- An example configuration. Copy it to ~/.config/paw/init.lua, or try it with
--   paw --config examples/config
-- Everything here goes through the same `paw` module the built-in commands,
-- keys and views are written with (see runtime/lua/paw/defaults/).

-- Options.
paw.opt.zoom = 4            -- columns per beat in the arrange view
paw.opt.grid = 0.5          -- cursor step in beats
paw.opt.leader = ","

-- Colours: override any highlight group.
paw.ui.hl("ClipMidi", { fg = "#1a1b26", bg = "#bb9af7" })
paw.ui.hl("Playhead", { bg = "#f7768e" })

-- A command of your own. `ctx.args` holds what was typed after the name,
-- `ctx.count` the number typed before a key mapping.
paw.command("track.synth", function(ctx)
  local track = paw.add_track({ name = ctx.args[1] or "Synth" })
  track:add_device("synth", { wave = 1, cutoff = tonumber(ctx.args.cutoff) or 1800 })
  track:add_device("delay", { mix = 0.2 })
  paw.cursor.set_track(track)
end, { desc = "Add a track with a synth and a delay: `track.synth Lead cutoff=900`" })

-- Keys. The right-hand side is a command line or a function.
paw.keymap.set("<leader>s", "track.synth", { desc = "Add a synth track" })
paw.keymap.set("<leader>w", "write", { desc = "Save" })
paw.keymap.set("<leader>8", function()
  -- Loop the eight bars starting where the cursor is.
  local bar = paw.time.bar()
  local from = math.floor(paw.cursor.beat / bar) * bar
  paw.transport.loop_start, paw.transport.loop_end = from, from + 8 * bar
  paw.transport.loop_enabled = true
end, { desc = "Loop eight bars from the cursor" })

-- Events: react to what happens in the project.
paw.on("track.added", function(event)
  local track = paw.track(event.id)
  -- Give every new track a colour tag that other extensions could use.
  track.meta = { created = os.date("%Y-%m-%d") }
end)

paw.on("project.saved", function(event)
  paw.notify("saved to " .. event.path)
end)
