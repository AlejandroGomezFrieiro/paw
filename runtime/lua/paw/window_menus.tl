-- The window's menus, built here so that the window only shows them: the
-- context menus are the terminal's (`paw.mouse_menus`), entry for entry,
-- and the menus only the window has (the File menu, "+ Track", More, the
-- audio devices, a track's input, a device's presets and routing) are here.
--
--   paw.frontend.menu("clip", { id, beat })      -- entries to show
--   paw.frontend.act.menu_choose("clip", { id, beat }, { 9, 2 })  -- the 2nd of the 9th's submenu
--
-- An entry is `{ label, keys, enabled, checked, items }`, or
-- `{ separator = true }`. An entry the window does itself names it in
-- `window` (a dialog of its own, leaving the project): "new", "open",
-- "open:<path>", "saveas", "import", "render", "quit", "listen".
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local mouse_menus = require("paw.mouse_menus")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type CommandsModule = require("paw.commands")
local type CanvasModule = require("paw.canvas")
local type CursorModule = require("paw.cursor")
local type MenuModule = require("paw.menu")
local type FrontendModule = require("paw.frontend")

local type Entry = contracts.MenuEntry
local type Item = contracts.MenuItem
local type Choice = mouse_menus.Choice
local type MenuArg = mouse_menus.MenuArg
local type Described = mouse_menus.Described

--- A function that builds a menu from the window's arguments.
local type Builder = function(...: MenuArg): {Entry}

local record Paw is partial.Paw
  commands: CommandsModule
  canvas: CanvasModule
  cursor: CursorModule
  frontend: FrontendModule
end
-- The global `paw` of the declarations does not hold this module, so its
-- local has a name of its own.
local runtime = (_G as {string:Paw}).paw

-- Lua 5.1's function that Teal's library leaves out.
local record Lua51
  unpack: function({MenuArg}): MenuArg...
end
local unpack = (_G as Lua51).unpack

local record M
  shown: function(): {Entry}
  items: function(kind: string, args?: {MenuArg}): {Entry}
  describe: function(kind: string, args?: {MenuArg}): {Described}
  choose: function(kind: string, args: {MenuArg}, path: {integer})
end

local function frontend(): FrontendModule return runtime.frontend end
local function act(): FrontendModule.Act return frontend().act end
local function added_acts(): mouse_menus.MoreActs return frontend().act as mouse_menus.MoreActs end
local function run(line: string): function() return function() runtime.commands.exec(line) end end
local function menu(): MenuModule return require("paw.menu") end

-- A menu of choices as the frontend lists them (`{ label, checked }`),
-- each passed to `choose` with its place from 1.
local function choices(list: {Choice}, choose: function(i: integer)): {Entry}
  local out: {Entry} = {}
  for i, c in ipairs(list or {}) do
    out[i] = { label = c.label, checked = c.checked, run = function() choose(i) end }
  end
  return out
end

local function heading(label: string): Item return { label = label, enabled = false } end

local function append(list: {Entry}, more: {Entry}): {Entry}
  for _, item in ipairs(more) do list[#list + 1] = item end
  return list
end

--- The File menu, from the project's name.
function M.file(): {Entry}
  local recent: {Entry} = {}
  for i, entry in ipairs(frontend().recent_menu() as {mouse_menus.Recent}) do
    recent[i] = { label = entry.label, window = "open:" .. entry.path }
  end
  recent[#recent + 1] = "-"
  recent[#recent + 1] = { label = "Clear the list", run = run("recent.clear") }
  return {
    { label = "New project", window = "new" },
    { label = "Open…", window = "open" },
    { label = "Open recent", items = recent },
    { label = "Recover unsaved work…", run = run("recover") },
    "-",
    { label = "Save", run = run("write") },
    { label = "Save as…", window = "saveas" },
    "-",
    { label = "Import…", window = "import" },
    { label = "Render…", window = "render" },
    { label = "Sound files", items = {
      { label = "Find missing files…", run = run("media.relink") },
      { label = "Copy into the project's folder", run = run("media.collect") },
    } },
    "-",
    { label = "Markers and regions…", run = run("marker.list") },
    { label = "MIDI controllers…", run = run("learn.list") },
    "-",
    { label = "Quit", window = "quit" },
  }
end

--- "+ Track": an empty one, one from a sound file, and the kinds of track
--- extensions add (the timeline's entries, for the selected track).
function M.add_track(): {Entry}
  local items: {Entry} = {
    { label = "Empty track", run = run("track.add") },
    { label = "From a sound file…", window = "import" },
  }
  for index, entry in ipairs(frontend().menus.timeline) do
    items[#items + 1] = { label = entry.label, run = function() act().menu("timeline", index, runtime.cursor.track_id(), -1) end }
  end
  return items
end

--- More: every view to open in a pane, the extensions' among them.
function M.views(): {Entry}
  local items: {Entry} = {}
  for i, v in ipairs(runtime.canvas.openable()) do
    items[i] = { label = v.title, run = run("view.open " .. v.name) }
  end
  if #items == 0 then items[1] = heading("No other views") end
  return items
end

--- The audio devices, from the engine indicator. `opts`: whether the
--- window is attached to a kernel elsewhere (`remote`) and plays its sound
--- (`listening`).
function M.engine(opts?: mouse_menus.MenuTable): {Entry}
  opts = opts or {}
  local engine = frontend().engine_menu()
  local items: {Entry} = {}
  for _, line in ipairs(engine.info) do items[#items + 1] = heading(line.label) end
  items[#items + 1] = "-"
  items[#items + 1] = { label = "Hear it on this machine", checked = opts.listening or false, enabled = opts.remote or false, window = "listen" }
  local function group(name: string): function(i: integer) return function(i: integer) act().choose_engine(name, i) end end
  append(items, { "-", heading("Output") })
  append(items, choices(engine.output as {Choice}, group("output")))
  append(items, { "-", heading("Input") })
  append(items, choices(engine.input as {Choice}, group("input")))
  append(items, {
    "-",
    { label = "Block size", items = choices(engine.block as {Choice}, group("block")) },
    { label = "Sample rate", items = choices(engine.rate as {Choice}, group("rate")) },
    { label = "Sound system", items = choices(engine.backend as {Choice}, group("backend")) },
  })
  return items
end

--- A track's input button: its audio inputs, MIDI ports and channels,
--- monitoring, and where it sends MIDI.
function M.input(track: integer): {Entry}
  local input = frontend().input_menu(track)
  local function group(name: string): function(i: integer) return function(i: integer) act().choose_input(track, name, i) end end
  local items: {Entry} = { heading("Audio") }
  append(items, choices(input.audio as {Choice}, group("audio")))
  append(items, { "-", heading("MIDI") })
  append(items, choices(input.midi as {Choice}, group("midi")))
  append(items, {
    { label = "MIDI channel", items = choices(input.channel as {Choice}, group("channel")) },
    "-",
    { label = "Monitor: hear the input without arming", checked = input.monitor or false, run = function() act().toggle(track, "monitor") end },
    "-",
    { label = "MIDI out: send what it plays to", items = choices(input.midi_out as {Choice}, group("midi_out")) },
    { label = "MIDI out channel", items = choices(input.midi_out_channel as {Choice}, group("midi_out_channel")) },
    { label = "MIDI out form, where the port takes no MIDI 2.0", items = choices(input.midi_out_form as {Choice}, group("midi_out_form")) },
  })
  return items
end

--- Where a track plays into: the master or another track.
function M.output(track: integer): {Entry}
  local routing = frontend().routing(track)
  local items: {Entry} = {}
  for i, t in ipairs(routing.targets) do
    items[i] = { label = t.name, checked = t.id == routing.output_id, run = function() act().set_output(track, t.id) end }
  end
  return items
end

--- A track to send a track's sound to as well.
function M.send(track: integer): {Entry}
  local items: {Entry} = {}
  for i, t in ipairs(frontend().routing(track).targets) do
    items[i] = { label = t.name, enabled = t.id ~= 0, run = function() act().add_send(track, t.id) end }
  end
  return items
end

--- A device's presets, and saving one.
function M.preset(device: integer): {Entry}
  local items: {Entry} = {}
  for i, name in ipairs(added_acts().preset_menu(device)) do
    items[i] = { label = name, run = function() added_acts().preset_choose(device, i) end }
  end
  append(items, {
    { label = "Save as a preset…", run = function() added_acts().device_command(device, "preset.save") end },
    { label = "New ones start from this preset", run = function() added_acts().device_command(device, "preset.default") end },
  })
  return items
end

--- What a device listens to on its side-chain.
function M.sidechain(device: integer): {Entry}
  return choices(frontend().sidechain_menu(device) as {Choice}, function(i: integer) act().choose_sidechain(device, i) end)
end

--- Where a device's further output pairs play.
function M.outputs(device: integer): {Entry}
  local items: {Entry} = {}
  for p, pair in ipairs(frontend().outputs_menu(device)) do
    items[p] = { label = pair.label, items = choices(pair.choices as {Choice}, function(i: integer) act().route_pair(device, p + 1, i) end) }
  end
  append(items, { "-", { label = "Spread the outputs over new tracks", run = function() added_acts().device_command(device, "device.spread") end } })
  return items
end

--- The entries of menu `kind` for `args` (a list), as the terminal's
--- menu takes them.
function M.items(kind: string, args?: {MenuArg}): {Entry}
  args = args or {}
  local own = M as {string:Builder}
  local build = own[kind] ~= nil and kind ~= "items" and kind ~= "describe" and kind ~= "choose" and own[kind]
    or (mouse_menus as {string:Builder})[kind]
  if not build then error("no menu " .. tostring(kind)) end
  return build(unpack(args)) or {}
end

local function describe(items: {Entry}): {Described}
  local out: {Described} = {}
  for i, entry in ipairs(items) do
    if entry == "-" or (entry as Item).separator then
      out[i] = { separator = true }
    else
      local item = entry as Item
      out[i] = {
        label = item.label, keys = item.keys or "", enabled = item.enabled ~= false, checked = item.checked or false,
        window = item.window, items = item.items and describe(item.items) or nil,
      }
    end
  end
  return out
end

--- Menu `kind` for `args`, as plain data for a window to show.
function M.describe(kind: string, args?: {MenuArg}): {Described}
  return describe(M.items(kind, args))
end

--- The menu the kernel has open (`paw.ui.menu`: a right click in a pane
--- the window shows from its scene), which the window shows as its own.
function M.shown(): {Entry}
  return (menu().shown()) or {}
end

--- Do the entry at `path` (its place from 1 in each menu down to it) of
--- menu `kind` for `args`, as built again now.
function M.choose(kind: string, args: {MenuArg}, path: {integer})
  local items = M.items(kind, args)
  -- The kernel's menu the window showed is let go before its entry is done.
  if kind == "shown" then menu().close(0) end
  local item: Item
  for _, at in ipairs(path) do
    local entry = items and items[at]
    if not entry is Item then return end
    item = entry
    items = item.items
  end
  if item and item.enabled ~= false and item.run then item.run() end
end

(frontend() as mouse_menus.MoreFrontend).menu = M.describe
added_acts().menu_choose = M.choose
--- The window let go of the kernel's menu it showed (`shown`) without
--- choosing: so does the kernel.
added_acts().menu_dismiss = function() menu().close(0) end

return M
