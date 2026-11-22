-- The terminal's context menus: what a right click opens, entry for entry
-- the window's, each doing what the window's does (a command run with the
-- cursor put where the click was, or a `paw.frontend.act`).
--
--   paw.ui.menu(paw.mouse_menus.clip(id, beat), { x = x, y = y })
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local options = require("paw.options")
local type contracts = require("paw.contracts")
local type types = require("paw.types")
local type partial = require("paw.partial")
local type DiagnosticModule = require("paw.diagnostic")
local type CommandsModule = require("paw.commands")
local type TakesModule = require("paw.takes")
local type GroupsModule = require("paw.groups")
local type VcaModule = require("paw.vca")
local type AddressModule = require("paw.address")
local type TempolaneModule = require("paw.tempolane")
local type FrontendModule = require("paw.frontend")
local type LspModule = require("paw.lsp")

local type Entry = contracts.MenuEntry
local opt = options.opt

--- A choice of a menu of the frontend (`{ label, checked }`).
local record Choice
  label: string
  checked: boolean
end

--- A recent project of the File menu (`paw.frontend.recent_menu`, from
--- paw/recent.lua).
local record Recent
  label: string
  path: string
end

--- The gestures that other modules add to `paw.frontend.act`
--- (paw/views/curve.lua, paw/fx.lua, paw/diagnostic.tl and paw/window_menus.tl).
local record MoreActs
  open_curve: function(uri: string)
  automate_param: function(device: integer, key: string)
  note_action: function(clip: integer, place: integer, n: integer)
  preset_menu: function(device: integer): {string}
  preset_choose: function(device: integer, index: integer)
  device_command: function(device: integer, line: string)
  menu_choose: function(kind: string, args: {MenuArg}, path: {integer})
  menu_dismiss: function()
end

--- What the window's menus take as a table: the window's state for the
--- engine's menu, a marker, a location.
local record MenuTable
  remote: boolean
  listening: boolean
  id: integer
  length: number
  uri: string
end

--- An argument of a menu, as the window gives it (`paw.frontend.menu`).
local type MenuArg = number | string | boolean | MenuTable

--- An entry of a menu as plain data, for a window to show.
local record Described
  label: string
  keys: string
  enabled: boolean
  checked: boolean
  window: string
  items: {Described}
  separator: boolean
end

--- What paw/window_menus.tl adds to `paw.frontend`: the menus as plain data.
local record MoreFrontend
  menu: function(kind: string, args: {MenuArg}): {Described}
end

local record Paw is partial.Paw
  lsp: LspModule
  diagnostic: DiagnosticModule
  commands: CommandsModule
  takes: TakesModule
  groups: GroupsModule
  vca: VcaModule
  address: AddressModule
  tempolane: TempolaneModule
  frontend: FrontendModule
end
-- The global `paw` of the declarations does not hold this module, so its
-- local has a name of its own.
local runtime = (_G as {string: Paw}).paw

local record M
  type Choice = Choice
  type Recent = Recent
  type MoreActs = MoreActs
  type MoreFrontend = MoreFrontend
  type MenuArg = MenuArg
  type MenuTable = MenuTable
  type Described = Described
end

local function frontend(): FrontendModule
  return runtime.frontend
end
local function act(): FrontendModule.Act
  return frontend().act
end
local function added_acts(): MoreActs
  return frontend().act as MoreActs
end

--- The entries extensions add (`paw.frontend.menus[kind]`), for `target`
--- (a clip or a track) clicked at `beat`.
local function added(kind: string, target: integer, beat: number, midi: boolean): {Entry}
  local out: {Entry} = {}
  for index, entry in ipairs(frontend().menus[kind] or {}) do
    local fits = not entry.only or entry.only == "" or (entry.only == "midi") == midi
    out[#out + 1] = {label = entry.label, enabled = fits, run = function() act().menu(kind, index, target, beat) end}
  end
  return out
end

local function append(list: {Entry}, more: {Entry}): {Entry}
  for _, item in ipairs(more) do
    list[#list + 1] = item
  end
  return list
end

--- What the diagnostics and language servers have for a location
--- (paw/address.tl): its fixes and the servers' actions, and what they say
--- about it. Empty when nothing is said of it and no server is running.
function M.lens(location: contracts.Location): {Entry}
  if not (runtime.lsp and runtime.diagnostic) then
    return {}
  end
  local said = #runtime.diagnostic.get(location.uri) > 0
  if not said and #runtime.lsp.clients() == 0 then
    return {}
  end
  return {
    {label = "Fixes and actions…", run = function() runtime.lsp.code_actions(location) end},
    {label = "What the language servers say about it", run = function() runtime.lsp.show_hover(location) end},
  }
end

--- A clip, clicked at `beat`.
function M.clip(id: integer, beat: number): {Entry}
  local c = api.clip_get(id)
  local midi = c.kind == "midi"
  local count, take = runtime.takes.count(id)
  local many = count > 1
  local function run(line: string): function()
    return function() act().clip_command(id, beat, line) end
  end
  local function on_audio(item: contracts.MenuItem): contracts.MenuItem
    item.enabled = not midi and item.enabled ~= false
    return item
  end
  local take_items: {Entry} = {
    {label = "Next take", keys = "]t", enabled = many, run = run("take next")},
    {label = "Take before", keys = "[t", enabled = many, run = run("take prev")},
    {label = "Choose from a list…", enabled = many, run = run("take.list")},
    {label = "Show or hide the take lanes, to comp by swiping", keys = "zt", run = run("take.lanes")},
    "-",
    {label = "New take: keep this, carry on in a copy", run = run("take.new")},
    {label = "Throw this take away", enabled = many, run = run("take.remove")},
    {label = "Keep only this take", enabled = many, run = run("take.keep")},
    {label = "Put the other takes on tracks of their own", enabled = many, run = run("take.explode")},
  }
  local stretch_items: {Entry} = {
    on_audio({label = "Stretch to the selection", run = function() act().stretch_clip(id, "selection") end}),
    on_audio({label = "Stretch to the loop", run = function() act().stretch_clip(id, "loop") end}),
    on_audio({label = "Stretch by…", keys = "Alt+Shift drag the end", run = run("clip.stretch")}),
    on_audio({label = "Reset stretch", run = function() act().stretch_clip(id, "reset") end}),
    on_audio({label = "Shift pitch…", run = run("clip.pitch")}),
    on_audio({label = "Follow the tempo", run = run("clip.tempo")}),
    on_audio({label = "Keep formants when shifted", run = run("clip.formants")}),
    "-",
    on_audio({label = "Warp marker at the pointer", run = function() act().warp_add(id, beat) end}),
    on_audio({label = "Warp markers onto the grid", enabled = #(c.warp or {}) > 0, run = run("clip.warp snap")}),
    on_audio({label = "Remove the warp markers", enabled = #(c.warp or {}) > 0, run = run("clip.warp clear")}),
    "-",
    {label = c.loop and "Stop looping" or "Loop: repeat when made longer", run = run("clip.loop")},
  }
  local items: {Entry} = {
    {label = midi and "Edit notes" or "Select", run = function() act().open_clip(id) end},
    {label = "Rename", run = run("clip.rename")},
    "-",
    {label = "Split at the pointer", run = run("clip.split")},
    {label = "Split at the edit cursor", keys = "S", run = function() act().menu_split(id) end},
    {label = "Glue the chosen clips", keys = "J", run = function() act().menu_glue(id) end},
    {label = "Repeat after itself", run = run("clip.duplicate")},
    {label = c.muted and "Unmute" or "Mute", run = run("clip.mute")},
    {label = many and string.format("Takes (%d of %d)", take, count) or "Takes", items = take_items},
    {label = "Stretch and loop", items = stretch_items},
  }
  append(items, added("clip", id, beat, midi))
  items[#items + 1] = "-"
  items[#items + 1] = {label = "Delete", run = run("clip.remove")}
  return items
end

local colours = {"Coral", "Gold", "Lime", "Teal", "Sky", "Violet", "Pink", "Sand"}

--- paw/window_menus.tl, as far as this module calls it: it names this
--- module's types, so this one cannot name its.
local record WindowMenus
  input: function(track: integer): {Entry}
end

--- A track's header (or its mixer strip).
function M.track(id: integer): {Entry}
  local t = api.track_get(id)
  if t.master then
    return {}
  end
  local groups, vca = runtime.groups, runtime.vca
  local is_group, depth = groups.is_group(id), groups.depth(id)
  local function run(line: string): function()
    return function() act().track_command(id, line) end
  end
  local colour: {Entry} = {}
  for i, name in ipairs(colours) do
    colour[i] = {label = name, run = run("track.color " .. name:lower())}
  end
  colour[#colour + 1] = "-"
  colour[#colour + 1] = {label = "The theme's", run = run("track.color none")}
  local mode = t.automation or "read"
  local function auto(word: string, label: string): Entry
    return {label = label, checked = mode as string == word, run = run("automation " .. word)}
  end
  local auto_items: {Entry} = {
    auto("read", "Read: the lanes play"),
    auto("touch", "Touch: write while a control is held"),
    auto("latch", "Latch: write from the first move until stop"),
    auto("write", "Write: write everything while playing"),
    auto("off", "Off: the lanes do not play"),
    "-",
    {label = "Show or hide the lanes as rows", run = run("lane.rows")},
  }
  local midi_items: {Entry} = {
    {label = "Learn for the fader…", run = run("learn volume")},
    {label = "Learn for the pan…", run = run("learn pan")},
    {label = "What is bound…", run = function() runtime.commands.exec("learn.list") end},
  }
  local items: {Entry} = {
    {label = "Rename", run = run("track.rename")},
    {label = "Colour", items = colour},
    {label = "Input", items = (require as function(string): WindowMenus)("paw.window_menus").input(id)},
    "-",
    {label = "Duplicate", run = run("track.duplicate")},
    "-",
    {label = "New group with this track…", run = run("track.group")},
    {label = "Move into a group…", run = run("track.into")},
    {
      label = is_group and "Dissolve the group" or "Take out of its group",
      enabled = is_group or depth > 0,
      run = run("track.ungroup"),
    },
    {label = "Link the faders of the group", enabled = is_group or depth > 0, run = run("group.link")},
    {
      label = groups.folded(id) and "Open the group" or "Fold the group away",
      enabled = is_group or depth > 0,
      run = run("fold.toggle"),
    },
    {label = "New VCA with this track…", enabled = not vca.is_vca(id), run = run("vca.make")},
    {label = "Put under a VCA…", enabled = not vca.is_vca(id), run = run("vca.assign")},
    {
      label = vca.is_vca(id) and "Dissolve the VCA" or "Take out of its VCAs",
      enabled = vca.is_vca(id) or #vca.of(id) > 0,
      run = run(vca.is_vca(id) and "vca.dissolve" or "vca.release"),
    },
    "-",
    {label = "Automation", items = auto_items},
    {label = "Show or hide the take lanes", run = run("take.lanes")},
    {label = "MIDI controller", items = midi_items},
    "-",
    {label = "Bounce to audio", run = run("track.bounce")},
    {label = "New track below", run = run("track.add")},
  }
  append(items, added("track", id, 0, false))
  local lens = M.lens({uri = runtime.address.track(id)})
  if #lens > 0 then
    items[#items + 1] = "-"
    append(items, lens)
  end
  items[#items + 1] = "-"
  items[#items + 1] = {label = "Delete", run = run("track.remove")}
  return items
end

--- An empty stretch of the timeline, on `track` at `beat`: the cursor is
--- put there first, as the window does.
function M.timeline(track: integer, beat: number): {Entry}
  local t = api.transport_get()
  local function run(line: string): function()
    return function() runtime.commands.exec(line) end
  end
  local items: {Entry} = {
    {label = "New clip here", run = run("clip.add")},
    {label = "Import a sound file…", run = run("import")},
    {label = "Paste", run = function() act().keys("P") end},
    "-",
    {label = "Marker here", run = run("marker at=" .. math.max(0, beat))},
    {label = "Region over the selection or the loop", run = run("region")},
    "-",
    {label = "Punch in and out over the selection or the loop", run = run("punch selection")},
    {
      label = t.punch_enabled and "Punch recording off" or "Punch recording on",
      enabled = t.punch_enabled or t.punch_end > t.punch_start,
      run = run("punch"),
    },
    {
      label = (t.count_in or 0) > 0 and "No count-in before a take" or "Count a bar in before a take",
      run = run((t.count_in or 0) > 0 and "countin off" or "countin 1"),
    },
    {
      label = ((opt.pre_roll or 0) > 0 or (opt.pre_roll_seconds or 0) > 0) and "No pre-roll before a punch"
        or "Pre-roll two bars before a punch",
      run = run("preroll"),
    },
    {label = runtime.tempolane.shown() and "Hide the tempo lane" or "Show the tempo lane", run = run("tempo.lane")},
    {label = "Show or hide the track's take lanes", run = run("take.lanes")},
    "-",
    {label = "New track", run = run("track.add")},
  }
  return append(items, added("timeline", track, beat, false))
end

--- A stretch of time selected on the timeline.
function M.selection(): {Entry}
  local function keys(k: string): function()
    return function() act().keys(k) end
  end
  return {
    {label = "Delete", keys = "d", run = keys("d")},
    {label = "Copy", keys = "y", run = keys("y")},
    {label = "Loop this stretch", keys = "gl", run = keys("gl")},
    {label = "Mute or unmute", keys = "~", run = keys("~")},
    "-",
    {label = "Let go", keys = "Esc", run = keys("<Esc>")},
  }
end

--- A track's take lanes.
function M.takes(track: integer): {Entry}
  return {
    {label = "Hide the take lanes", keys = "zt", run = function() act().track_command(track, "take.lanes off") end}
  }
end

--- An automation lane shown as a row.
function M.lane(lane: integer): {Entry}
  local l = api.lane_get(lane)
  return {
    {label = "Edit the curve…", run = function() added_acts().open_curve(runtime.address.lane(lane)) end},
    {label = "Clear this lane", run = function() act().clear_lane(lane) end},
    {label = l.enabled and "Turn this lane off" or "Turn this lane on", run = function() act().toggle_lane(lane) end},
    "-",
    {label = "Hide the track's lane rows", run = function() act().hide_lane_rows(lane) end},
  }
end

--- A tempo (`kind` "tempo") or signature change flagged on the ruler.
function M.tempo_mark(kind: string, beat: number): {Entry}
  local tempo = kind == "tempo"
  return {
    {
      label = tempo and "Change tempo…" or "Change signature…",
      run = function() act().tempo_mark("edit", kind, beat) end,
    },
    {
      label = tempo and "Remove tempo change" or "Remove signature change",
      run = function() act().tempo_mark("remove", kind, beat) end,
    },
  }
end

--- The tempo lane under the ruler.
function M.tempo_lane(): {Entry}
  return {
    {label = "Edit the tempo as a curve…", run = function() added_acts().open_curve(runtime.address.tempo()) end},
    {label = "Hide the tempo lane", run = function() act().tempo_lane(false) end},
  }
end

--- A device's parameter: automating it, and its curve.
function M.param(device: integer, key: string): {Entry}
  return {
    {label = "Automate this parameter", run = function() added_acts().automate_param(device, key) end},
    {label = "Edit its curve…", run = function() added_acts().open_curve(runtime.address.param(device, key)) end},
  }
end

--- A marker or region in the band under the ruler.
function M.marker(m: MenuTable): {Entry}
  local function run(line: string): function()
    return function() runtime.commands.exec(line .. " id=" .. m.id) end
  end
  return {
    {label = "Rename…", run = run("marker.rename")},
    {label = "Loop this region", enabled = m.length ~= nil, run = run("region.loop")},
    "-",
    {label = "Remove", run = run(m.length and "region.remove" or "marker.remove")},
  }
end

--- A warp marker of an audio clip, the `index`th.
function M.warp(id: integer, index: integer): {Entry}
  return {{label = "Remove warp marker", run = function() act().warp_remove(id, index) end}}
end

--- Empty grid in the piano roll, for `clip`.
function M.roll(clip: integer): {Entry}
  return {
    {label = "Choose every note", run = function() act().select_all_notes(clip) end},
    {label = "Let go of the chosen notes", run = function() act().clear_note_selection() end},
    {label = "Delete the chosen notes", run = function() act().remove_chosen_notes(clip) end},
    {label = "Quantize the chosen notes (or all) to the grid", run = function() act().quantize_notes(clip) end},
    "-",
    {label = "Snap to the grid", checked = opt.note_snap, run = function() act().toggle_note_snap() end},
  }
end

--- A note with something to fix, by its place: the fixes the diagnostics
--- offer (each a workspace edit, one undo step), what the servers say and
--- can do about the note, and taking the note away.
function M.note(clip: integer, place: integer): {Entry}
  local items: {Entry} = {}
  for n, action in ipairs(runtime.diagnostic and runtime.diagnostic.actions(clip, place) or {}) do
    items[#items + 1] = {label = action.title, run = function() added_acts().note_action(clip, place, n) end}
  end
  local notes = api.clip_notes(clip)
  local note = notes[place]
  if note and note.id and runtime.address then
    append(items, M.lens({uri = runtime.address.note(clip, note.id)}))
  end
  if #items > 0 then
    items[#items + 1] = "-"
  end
  items[#items + 1] = {label = "Remove the note", run = function() act().remove_note(clip, place) end}
  return items
end

--- The controller strip under the piano roll, showing `kind` (and `number`).
function M.strip(clip: integer, kind: string, number: integer): {Entry}
  return {
    {
      label = "Choose every move of this controller", run = function() act().select_all_controls(clip, kind, number) end
    },
    {label = "Let go of the chosen moves", run = function() act().clear_control_selection(clip) end},
    {label = "Delete the chosen moves", run = function() act().remove_chosen_controls(clip) end},
    {
      label = "Clear this controller",
      run = function() act().clear_controls(clip, kind as types.ControlType, number) end,
    },
  }
end

return M
