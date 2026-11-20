-- The terminal's context menus: what a right click opens, entry for entry
-- the window's, each doing what the window's does (a command run with the
-- cursor put where the click was, or a `paw.frontend.act`).
--
--   paw.ui.menu(paw.mouse_menus.clip(id, beat), { x = x, y = y })
local api = paw.api
local M = {}

local function act() return paw.frontend.act end

--- The entries extensions add (`paw.frontend.menus[kind]`), for `target`
--- (a clip or a track) clicked at `beat`.
local function added(kind, target, beat, midi)
  local out = {}
  for index, entry in ipairs(paw.frontend.menus[kind] or {}) do
    local fits = not entry.only or entry.only == "" or (entry.only == "midi") == midi
    out[#out + 1] = { label = entry.label, enabled = fits, run = function() act().menu(kind, index, target, beat) end }
  end
  return out
end

local function append(list, more)
  for _, item in ipairs(more) do list[#list + 1] = item end
  return list
end

--- What the diagnostics and language servers have for a location
--- (paw/address.tl): its fixes and the servers' actions, and what they say
--- about it. Empty when nothing is said of it and no server is running.
function M.lens(location)
  if not (paw.lsp and paw.diagnostic) then return {} end
  local said = #paw.diagnostic.get(location.uri) > 0
  if not said and #paw.lsp.clients() == 0 then return {} end
  return {
    { label = "Fixes and actions…", run = function() paw.lsp.code_actions(location) end },
    { label = "What the language servers say about it", run = function() paw.lsp.show_hover(location) end },
  }
end

--- A clip, clicked at `beat`.
function M.clip(id, beat)
  local c = api.clip_get(id)
  local midi = c.kind == "midi"
  local takes, take = paw.takes.count(id)
  local many = takes > 1
  local function run(line) return function() act().clip_command(id, beat, line) end end
  local function on_audio(item)
    item.enabled = not midi and item.enabled ~= false
    return item
  end
  local items = {
    { label = midi and "Edit notes" or "Select", run = function() act().open_clip(id) end },
    { label = "Rename", run = run("clip.rename") },
    "-",
    { label = "Split at the pointer", run = run("clip.split") },
    { label = "Split at the edit cursor", keys = "S", run = function() act().menu_split(id) end },
    { label = "Glue the chosen clips", keys = "J", run = function() act().menu_glue(id) end },
    { label = "Repeat after itself", run = run("clip.duplicate") },
    { label = c.muted and "Unmute" or "Mute", run = run("clip.mute") },
    { label = many and string.format("Takes (%d of %d)", take, takes) or "Takes", items = {
      { label = "Next take", keys = "]t", enabled = many, run = run("take next") },
      { label = "Take before", keys = "[t", enabled = many, run = run("take prev") },
      { label = "Choose from a list…", enabled = many, run = run("take.list") },
      { label = "Show or hide the take lanes, to comp by swiping", keys = "zt", run = run("take.lanes") },
      "-",
      { label = "New take: keep this, carry on in a copy", run = run("take.new") },
      { label = "Throw this take away", enabled = many, run = run("take.remove") },
      { label = "Keep only this take", enabled = many, run = run("take.keep") },
      { label = "Put the other takes on tracks of their own", enabled = many, run = run("take.explode") },
    } },
    { label = "Stretch and loop", items = {
      on_audio({ label = "Stretch to the selection", run = function() act().stretch_clip(id, "selection") end }),
      on_audio({ label = "Stretch to the loop", run = function() act().stretch_clip(id, "loop") end }),
      on_audio({ label = "Stretch by…", keys = "Alt+Shift drag the end", run = run("clip.stretch") }),
      on_audio({ label = "Reset stretch", run = function() act().stretch_clip(id, "reset") end }),
      on_audio({ label = "Shift pitch…", run = run("clip.pitch") }),
      on_audio({ label = "Follow the tempo", run = run("clip.tempo") }),
      on_audio({ label = "Keep formants when shifted", run = run("clip.formants") }),
      "-",
      on_audio({ label = "Warp marker at the pointer", run = function() act().warp_add(id, beat) end }),
      on_audio({ label = "Warp markers onto the grid", enabled = #(c.warp or {}) > 0, run = run("clip.warp snap") }),
      on_audio({ label = "Remove the warp markers", enabled = #(c.warp or {}) > 0, run = run("clip.warp clear") }),
      "-",
      { label = c.loop and "Stop looping" or "Loop: repeat when made longer", run = run("clip.loop") },
    } },
  }
  append(items, added("clip", id, beat, midi))
  items[#items + 1] = "-"
  items[#items + 1] = { label = "Delete", run = run("clip.remove") }
  return items
end

local colours = { "Coral", "Gold", "Lime", "Teal", "Sky", "Violet", "Pink", "Sand" }

--- A track's header (or its mixer strip).
function M.track(id)
  local t = api.track_get(id)
  if t.master then return {} end
  local groups = paw.groups
  local is_group, depth = groups.is_group(id), groups.depth(id)
  local function run(line) return function() act().track_command(id, line) end end
  local colour = {}
  for i, name in ipairs(colours) do colour[i] = { label = name, run = run("track.color " .. name:lower()) } end
  colour[#colour + 1] = "-"
  colour[#colour + 1] = { label = "The theme's", run = run("track.color none") }
  local mode = t.automation or "read"
  local function auto(word, label) return { label = label, checked = mode == word, run = run("automation " .. word) } end
  local items = {
    { label = "Rename", run = run("track.rename") },
    { label = "Colour", items = colour },
    { label = "Input", items = require("paw.window_menus").input(id) },
    "-",
    { label = "Duplicate", run = run("track.duplicate") },
    "-",
    { label = "New group with this track…", run = run("track.group") },
    { label = "Move into a group…", run = run("track.into") },
    { label = is_group and "Dissolve the group" or "Take out of its group", enabled = is_group or depth > 0, run = run("track.ungroup") },
    { label = "Link the faders of the group", enabled = is_group or depth > 0, run = run("group.link") },
    { label = groups.folded(id) and "Open the group" or "Fold the group away", enabled = is_group or depth > 0, run = run("track.fold") },
    { label = "New VCA with this track…", enabled = not paw.vca.is_vca(id), run = run("vca.make") },
    { label = "Put under a VCA…", enabled = not paw.vca.is_vca(id), run = run("vca.assign") },
    { label = paw.vca.is_vca(id) and "Dissolve the VCA" or "Take out of its VCAs",
      enabled = paw.vca.is_vca(id) or #paw.vca.of(id) > 0, run = run(paw.vca.is_vca(id) and "vca.dissolve" or "vca.release") },
    "-",
    { label = "Automation", items = {
      auto("read", "Read: the lanes play"),
      auto("touch", "Touch: write while a control is held"),
      auto("latch", "Latch: write from the first move until stop"),
      auto("write", "Write: write everything while playing"),
      auto("off", "Off: the lanes do not play"),
      "-",
      { label = "Show or hide the lanes as rows", run = run("lane.rows") },
    } },
    { label = "Show or hide the take lanes", run = run("take.lanes") },
    { label = "MIDI controller", items = {
      { label = "Learn for the fader…", run = run("learn volume") },
      { label = "Learn for the pan…", run = run("learn pan") },
      { label = "What is bound…", run = function() paw.commands.exec("learn.list") end },
    } },
    "-",
    { label = "Bounce to audio", run = run("track.bounce") },
    { label = "New track below", run = run("track.add") },
  }
  append(items, added("track", id, 0, false))
  local lens = M.lens({ uri = paw.address.track(id) })
  if #lens > 0 then
    items[#items + 1] = "-"
    append(items, lens)
  end
  items[#items + 1] = "-"
  items[#items + 1] = { label = "Delete", run = run("track.remove") }
  return items
end

--- An empty stretch of the timeline, on `track` at `beat`: the cursor is
--- put there first, as the window does.
function M.timeline(track, beat)
  local t = api.transport_get()
  local function run(line) return function() paw.commands.exec(line) end end
  local items = {
    { label = "New clip here", run = run("clip.add") },
    { label = "Import a sound file…", run = run("import") },
    { label = "Paste", run = function() act().keys("P") end },
    "-",
    { label = "Marker here", run = run("marker at=" .. math.max(0, beat)) },
    { label = "Region over the selection or the loop", run = run("region") },
    "-",
    { label = "Punch in and out over the selection or the loop", run = run("punch selection") },
    { label = t.punch_enabled and "Punch recording off" or "Punch recording on",
      enabled = t.punch_enabled or t.punch_end > t.punch_start, run = run("punch") },
    { label = (t.count_in or 0) > 0 and "No count-in before a take" or "Count a bar in before a take",
      run = run((t.count_in or 0) > 0 and "countin off" or "countin 1") },
    { label = ((paw.opt.pre_roll or 0) > 0 or (paw.opt.pre_roll_seconds or 0) > 0) and "No pre-roll before a punch"
      or "Pre-roll two bars before a punch", run = run("preroll") },
    { label = paw.tempolane.shown() and "Hide the tempo lane" or "Show the tempo lane", run = run("tempo.lane") },
    { label = "Show or hide the track's take lanes", run = run("take.lanes") },
    "-",
    { label = "New track", run = run("track.add") },
  }
  return append(items, added("timeline", track, beat, false))
end

--- A stretch of time selected on the timeline.
function M.selection()
  local function keys(k) return function() act().keys(k) end end
  return {
    { label = "Delete", keys = "d", run = keys("d") },
    { label = "Copy", keys = "y", run = keys("y") },
    { label = "Loop this stretch", keys = "gl", run = keys("gl") },
    { label = "Mute or unmute", keys = "~", run = keys("~") },
    "-",
    { label = "Let go", keys = "Esc", run = keys("<Esc>") },
  }
end

--- A track's take lanes.
function M.takes(track)
  return { { label = "Hide the take lanes", keys = "zt", run = function() act().track_command(track, "take.lanes off") end } }
end

--- An automation lane shown as a row.
function M.lane(lane)
  local l = api.lane_get(lane)
  return {
    { label = "Edit the curve…", run = function() act().open_curve(paw.address.lane(lane)) end },
    { label = "Clear this lane", run = function() act().clear_lane(lane) end },
    { label = l.enabled and "Turn this lane off" or "Turn this lane on", run = function() act().toggle_lane(lane) end },
    "-",
    { label = "Hide the track's lane rows", run = function() act().hide_lane_rows(lane) end },
  }
end

--- A tempo (`kind` "tempo") or signature change flagged on the ruler.
function M.tempo_mark(kind, beat)
  local tempo = kind == "tempo"
  return {
    { label = tempo and "Change tempo…" or "Change signature…", run = function() act().tempo_mark("edit", kind, beat) end },
    { label = tempo and "Remove tempo change" or "Remove signature change", run = function() act().tempo_mark("remove", kind, beat) end },
  }
end

--- The tempo lane under the ruler.
function M.tempo_lane()
  return {
    { label = "Edit the tempo as a curve…", run = function() act().open_curve(paw.address.tempo()) end },
    { label = "Hide the tempo lane", run = function() act().tempo_lane(false) end },
  }
end

--- A device's parameter: automating it, and its curve.
function M.param(device, key)
  return {
    { label = "Automate this parameter", run = function() act().automate_param(device, key) end },
    { label = "Edit its curve…", run = function() act().open_curve(paw.address.param(device, key)) end },
  }
end

--- A marker or region in the band under the ruler.
function M.marker(m)
  local function run(line) return function() paw.commands.exec(line .. " id=" .. m.id) end end
  return {
    { label = "Rename…", run = run("marker.rename") },
    { label = "Loop this region", enabled = m.length ~= nil, run = run("region.loop") },
    "-",
    { label = "Remove", run = run("marker.remove") },
  }
end

--- A warp marker of an audio clip, the `index`th.
function M.warp(id, index)
  return { { label = "Remove warp marker", run = function() act().warp_remove(id, index) end } }
end

--- Empty grid in the piano roll, for `clip`.
function M.roll(clip)
  return {
    { label = "Choose every note", run = function() act().select_all_notes(clip) end },
    { label = "Let go of the chosen notes", run = function() act().clear_note_selection() end },
    { label = "Delete the chosen notes", run = function() act().remove_chosen_notes(clip) end },
    { label = "Quantize the chosen notes (or all) to the grid", run = function() act().quantize_notes(clip) end },
    "-",
    { label = "Snap to the grid", checked = paw.opt.note_snap, run = function() act().toggle_note_snap() end },
  }
end

--- A note with something to fix, by its place: the fixes the diagnostics
--- offer (each a workspace edit, one undo step), what the servers say and
--- can do about the note, and taking the note away.
function M.note(clip, place)
  local items = {}
  for n, action in ipairs(paw.diagnostic and paw.diagnostic.actions(clip, place) or {}) do
    items[#items + 1] = { label = action.title, run = function() act().note_action(clip, place, n) end }
  end
  local note = api.clip_notes(clip)[place]
  if note and note.id and paw.address then append(items, M.lens({ uri = paw.address.note(clip, note.id) })) end
  if #items > 0 then items[#items + 1] = "-" end
  items[#items + 1] = { label = "Remove the note", run = function() act().remove_note(clip, place) end }
  return items
end

--- The controller strip under the piano roll, showing `kind` (and `number`).
function M.strip(clip, kind, number)
  return {
    { label = "Choose every move of this controller", run = function() act().select_all_controls(clip, kind, number) end },
    { label = "Let go of the chosen moves", run = function() act().clear_control_selection(clip) end },
    { label = "Delete the chosen moves", run = function() act().remove_chosen_controls(clip) end },
    { label = "Clear this controller", run = function() act().clear_controls(clip, kind, number) end },
  }
end

return M
