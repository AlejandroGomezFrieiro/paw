-- The default commands and keys: pickers. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local api = paw.api
local command, map = paw.command, paw.keymap.set
local common = require("paw.defaults.common")
local need_track = common.need_track

--
-- `paw.pick` chooses from a list by typing a few letters of what is wanted.
-- Every source in `paw.pick.sources` has a command, `:pick <name>`, and the
-- built-in ones a command of their own and a key under `<leader>f`.

command("pick", function(ctx)
  local name = ctx.args[1] and tostring(ctx.args[1]) or "pickers"
  if name == "resume" then return paw.pick.resume() end
  if not paw.pick.sources[name] then return paw.notify("no picker `" .. name .. "`; `:pick` lists them", "warn") end
  paw.pick(name, { query = ctx.args.query and tostring(ctx.args.query) or nil })
end, { desc = "Choose from a list: `pick tracks`, `pick devices query=reverb`; with no name, every picker", complete = { "pickers" } })
command("pick.resume", function() paw.pick.resume() end, { desc = "Open the last picker again, with what was typed" })

-- The letter after `f` is the one the same thing has elsewhere on the
-- leader where it has one: `fc` clips (`<leader>c`), `fd` the track's devices
-- (`<leader>d`), `fr` regions (`<leader>r`), `ft` tracks (`<leader>t`).
local pick_keys = {
  { "files", "f", "Open a project or import audio from here" },
  { "grep", "g", "Find any text in the project" },
  { "keys", "k", "Find a key mapping for this view" },
  { "clips", "c", "Go to a clip" },
  { "regions", "r", "Go to a region" },
  { "markers", "m", "Go to a marker" },
  { "marks", "'", "Go to a mark" },
  { "tracks", "t", "Go to a track" },
  { "track_devices", "d", "Show a device of the track" },
  { "notes", "n", "Find a note by pitch, lyric or articulation" },
  { "help", "h", "Go to a help tag" },
  { "options", "o", "Set an option" },
  { "extensions", "e", "Extensions, loaded or not" },
  { "symbols", "s", "Find a function of the Lua API" },
  { "presets", "P", "Load a preset into the device" },
  { "quickfix", "q", "The entries of the quickfix list" },
  { "media", "a", "Sound files the project uses" },
  { "undo", "u", "Go to a state of the undo history" },
  { "registers", '"', "Paste a register or play a macro" },
  { "commands", ":", "Run a command" },
  { "messages", "l", "Earlier messages: the log" },
  { "pickers", "p", "Every picker" },
  { "devices", nil, "Add a device or plugin to the track" },
}
for _, entry in ipairs(pick_keys) do
  local name, key, desc = entry[1], entry[2], entry[3]
  command("pick." .. name, function(ctx)
    paw.pick(name, { query = ctx.args[1] and table.concat(ctx.args, " ") or nil })
  end, { desc = desc .. ", in a picker" })
  if key then map("<leader>f" .. key, "pick." .. name, { desc = desc }) end
end
map("<leader>f.", "pick.resume", { desc = "The last picker again" })
-- Adding a device is the devices' (`<leader>d`); opening a recent project the project's (`<leader>p`).
map("<leader>da", "pick.devices", { desc = "Add a device or plugin to the track" })
map("<leader>pr", "recent", { desc = "Open a recent project" })

-- With no argument, `device.add` chooses from every device in a picker.
do
  local add_by_name = paw.commands.get("device.add")
  command("device.add", function(ctx)
    if ctx.args[1] then return add_by_name.run(ctx) end
    if need_track() then paw.pick("devices") end
  end, { desc = add_by_name.desc .. "; with no name, choose in a picker", complete = add_by_name.complete })
end


-- A plugin runs in a process of its own; when that stops, the session goes
-- on without it and says so.
paw.on("device.stopped", function(event)
  local track = pcall(api.track_get, event.track) and api.track_get(event.track, "name") or "a track"
  if event.loading then
    return paw.notify(string.format("%s on %s could not be loaded: %s. It is passed over and keeps its saved state; `:device.restart` tries again.",
      event.name, track, event.reason), "error")
  end
  paw.notify(string.format("%s on %s stopped working: %s. The track plays on without it; `:device.restart` starts it again.",
    event.name, track, event.reason), "error")
end)
command("plugins.rescan", function(ctx)
  local name = ctx.args[1] and tostring(ctx.args[1]) or nil
  local notes = api.plugins_rescan(name)
  if not notes then return paw.notify("plugins are not loaded in this session", "warn") end
  for _, note in ipairs(notes) do paw.api.log("plugin scan: " .. note) end
  paw.emit("plugins.scanned", { notes = notes, name = name })
  paw.notify(string.format("looked into %s again%s", name and ("plugin files matching “" .. name .. "”") or "every plugin file",
    #notes > 0 and (": " .. #notes .. " could not be used (see the log)") or ""))
end, { desc = "Look into plugin files again, including ones skipped because they failed: `plugins.rescan`, `plugins.rescan surge`" })
-- A device whose output holds NaN or infinity is silenced where it is, once said.
paw.on("device.invalid", function(event)
  local track = pcall(api.track_get, event.track) and api.track_get(event.track, "name") or "a track"
  paw.notify(string.format("%s on %s put out invalid numbers (NaN or infinity); its output is replaced by silence",
    event.name, track), "error")
end)
