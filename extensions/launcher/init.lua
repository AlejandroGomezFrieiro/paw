-- The clip launcher: slots, scenes, the session view and its keys. See
-- README.md beside this file. The clips are the core's clips off the
-- timeline and the cues are the core's (`paw.api.cue`); the grid of slots
-- and the scenes are kept in `meta.launcher`.
paw.option.define("launch_rows", 8) -- the session view shows at least this many rows

local api = paw.api
local launcher = require("launcher")
local view = require("launcher.view")
local command, map, keymap, cursor = paw.command, paw.keymap.set, paw.keymap, paw.cursor

-- Commands ---------------------------------------------------------------------

local function track_or_warn()
  local id = cursor.track_id()
  if not id or id == 0 then paw.notify("no track selected", "warn") end
  return id ~= 0 and id or nil
end

--- A row from a command's argument (from 1), or the cursor's.
local function row_arg(arg)
  local n = tonumber(arg)
  return n and math.max(0, math.floor(n) - 1) or launcher.row
end

--- Call `fn`, and say its error as a message, not a stack trace.
local function try(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then paw.notify(tostring(err):gsub("^[^:]+:%d+: ", ""), "warn") end
  return ok
end

command("session", function() paw.ui.focus("session") end, { desc = "Show the session view and go to it" })
command("launch", function(ctx)
  local track = track_or_warn()
  if track then launcher.press(track, row_arg(ctx.args[1])) end
end, { desc = "Launch a slot of the selected track: `launch 2`, or the one under the cursor" })
command("launch.stop", function(ctx)
  if ctx.args[1] == "all" then return launcher.stop() end
  local track = track_or_warn()
  if track then launcher.stop(track) end
end, { desc = "Stop the selected track's clip on the next boundary: `launch.stop all` stops every one", complete = { "all" } })
command("launch.back", function(ctx)
  if ctx.args[1] == "all" then return launcher.back() end
  local track = track_or_warn()
  if track then launcher.back(track) end
end, { desc = "Have the selected track play its timeline again: `launch.back all` for every track", complete = { "all" } })
command("launch.quantize", function(ctx)
  local q = ctx.args[1]
  if not q then return paw.notify("launches land on: " .. launcher.quantize()) end
  if try(launcher.set_quantize, q) then paw.notify("launches land on: " .. q) end
end, { desc = "Where launches land: `launch.quantize 1/8` (off 1/16 1/8 1/4 beat bar 2bars 4bars)", complete = launcher.quantizes })
command("launch.capture", function() launcher.capture() end, {
  desc = "Write what is launched into the timeline when the song stops (again: stop capturing)",
})
command("scene", function(ctx)
  local row = row_arg(ctx.args[1])
  launcher.row = row
  launcher.scene(row)
end, { desc = "Launch a scene, every clip in a row: `scene 2`, or the cursor's row" })
command("scene.name", function(ctx)
  local name = table.concat(ctx.args, " ")
  if name ~= "" then return launcher.set_scene_name(launcher.row, name) end
  paw.ui.input({ prompt = "Scene name: ", text = launcher.scene_name(launcher.row) }, function(text)
    if text then launcher.set_scene_name(launcher.row, text) end
  end)
end, { desc = "Name the scene of the cursor's row: `scene.name Chorus`" })

--- The clip in the slot under the cursor, or a warning.
local function slot_clip()
  local track = track_or_warn()
  local clip = track and launcher.clip(track, launcher.row)
  if track and not clip then paw.notify("the slot is empty", "warn") end
  return clip
end

command("slot.new", function(ctx)
  local track = track_or_warn()
  if not track then return end
  if launcher.clip(track, launcher.row) then return paw.notify("the slot holds a clip already", "warn") end
  launcher.new_clip(track, launcher.row, tonumber(ctx.args[1]))
end, { desc = "A new MIDI clip in the slot under the cursor: `slot.new 2` for two bars" })
command("slot.record", function(ctx)
  if launcher.recording then return launcher.finish_recording() end
  local track = track_or_warn()
  if not track then return end
  if launcher.clip(track, launcher.row) then return paw.notify("the slot holds a clip already", "warn") end
  launcher.record(track, launcher.row, tonumber(ctx.args[1]) or ctx.count)
end, { desc = "Record into the empty slot under the cursor from the next boundary: `slot.record 2` for two bars (again: stop now)" })
command("slot.copy", function()
  local track = track_or_warn()
  local clip = track and cursor.clip()
  if not clip then return paw.notify("no clip under the arrange view's cursor", "warn") end
  launcher.copy(clip.id, track, launcher.row)
end, { desc = "Copy the clip under the arrange view's cursor into the slot under the session view's" })
command("slot.delete", function()
  local clip = slot_clip()
  if clip then api.clip_remove(clip.id) end
end, { desc = "Empty the slot under the cursor" })
command("slot.edit", function()
  local clip = slot_clip()
  if clip and clip.kind == "midi" then paw.ui.views.pianoroll:edit(paw.clip(clip.id)) end
end, { desc = "Open the notes of the clip in the slot under the cursor" })
command("slot.mode", function(ctx)
  local clip = slot_clip()
  if not clip then return end
  local mode = ctx.args[1]
  if not mode then
    -- Round the modes.
    for i, m in ipairs(launcher.modes) do
      if m == clip.mode then mode = launcher.modes[i % #launcher.modes + 1] end
    end
  end
  if not launcher.contains(launcher.modes, mode) then return paw.notify("a mode is trigger, gate or toggle", "warn") end
  launcher.set(clip.id, "mode", mode)
  paw.notify(clip.name .. ": " .. mode)
end, { desc = "How the slot's clip launches: `slot.mode gate` (trigger, gate, toggle; none goes round them)", complete = launcher.modes })
command("slot.legato", function()
  local clip = slot_clip()
  if not clip then return end
  launcher.set(clip.id, "legato", not clip.legato)
  paw.notify(clip.name .. ": legato " .. (clip.legato and "off" or "on"))
end, { desc = "Have the slot's clip take over where the clip before it had got to, or not" })
command("slot.quantize", function(ctx)
  local clip = slot_clip()
  if not clip then return end
  local q = ctx.args[1]
  if try(launcher.set, clip.id, "quantize", q or "project") then
    paw.notify(clip.name .. ": launches on " .. ((q and q ~= "project") and q or ("the project's " .. launcher.quantize())))
  end
end, {
  desc = "Where the slot's clip launches: `slot.quantize 1/16`, or `slot.quantize` for the project's",
  complete = function() return { "project", unpack(launcher.quantizes) } end,
})
command("slot.length", function(ctx)
  local clip = slot_clip()
  local bars = tonumber(ctx.args[1])
  if clip and bars and bars > 0 then api.clip_set(clip.id, "length", bars * paw.time.bar(0)) end
end, { desc = "How many bars the slot's clip loops over: `slot.length 2`" })

-- Keys -------------------------------------------------------------------------

map("<leader>l", "view.toggle session", { desc = "Show or hide the session view, clips to launch" })
local function smap(lhs, rhs, desc) map(lhs, rhs, { view = "session", desc = desc }) end
local function to_row(row)
  launcher.row = math.max(0, row)
  api.ui_redraw()
end
-- Tracks are the columns and slots the rows: `h` `l` go across, `j` `k` down.
local function smotion(lhs, rhs, desc) map(lhs, rhs, { view = "session", desc = desc, motion = true }) end
smotion("l", "cursor.down", "Next track")
smotion("h", "cursor.up", "Previous track")
smotion("<Right>", "cursor.down", "Next track")
smotion("<Left>", "cursor.up", "Previous track")
smotion("j", function(ctx) to_row(launcher.row + (ctx.count or 1)) end, "Next slot")
smotion("k", function(ctx) to_row(launcher.row - (ctx.count or 1)) end, "Previous slot")
smotion("<Down>", function(ctx) to_row(launcher.row + (ctx.count or 1)) end, "Next slot")
smotion("<Up>", function(ctx) to_row(launcher.row - (ctx.count or 1)) end, "Previous slot")
smotion("gg", function(ctx) to_row((ctx.count or 1) - 1) end, "First slot, or slot N")
smotion("G", function(ctx) to_row(ctx.count and ctx.count - 1 or launcher.rows() - 2) end, "Last slot with a clip, or slot N")
smotion("0", "cursor.first_track", "The first track")
smotion("^", "cursor.first_track", "The first track")
smotion("$", "cursor.last_track", "The last track")
smap("<CR>", "launch", "Launch the slot (an empty one stops the track)")
smap("L", "scene", "Launch the scene: the whole row")
-- `s` solos, `M` mutes and `r` arms, as on a track anywhere; stopping is the session's own.
smap("s", "track.solo", "Solo")
smap("M", "track.mute", "Mute the track")
smap("r", "track.armed", "Arm for recording")
smap("S", "launch.stop", "Stop the track's clip")
smap("gS", "launch.stop all", "Stop every clip")
smap("B", "launch.back", "Resume the track's timeline: stop its slot so the arranged clips play again")
smap("gB", "launch.back all", "Every track back to its timeline")
smap("n", "slot.new", "A new MIDI clip in the slot")
smap("i", "slot.edit", "Open the clip's notes, to enter some")
for lhs, rhs in pairs({ s = "launch.stop", S = "launch.stop all", b = "launch.back", B = "launch.back all", e = "slot.edit" }) do
  keymap.classic(lhs, rhs, { view = "session" })
end
smap("x", "slot.delete", "Empty the slot")
smap("dd", "slot.delete", "Empty the slot")
smap("gp", "slot.copy", "Copy the arrange view's clip into the slot")
smap("m", "slot.mode", "Next launch mode: trigger, gate, toggle")
smap("gl", "slot.legato", "Legato on or off")
smap("grn", "scene.name", "Name the scene")
smap("C", "launch.capture", "Capture what is launched into the timeline")
smap("R", "slot.record", "Record into the empty slot, a bar (or a count of bars) from the next boundary")
smap("yy", function(ctx)
  local track = cursor.track_id()
  local clip = track and launcher.clip(track, launcher.row)
  if clip then keymap.setreg({ kind = "slot", clip = paw.clip(clip.id):snapshot() }, ctx.register, true) end
end, "Yank the slot's clip")
smap("p", function(ctx)
  local track, value = cursor.track_id(), keymap.getreg(ctx.register)
  if not track or not value then return end
  -- A slot's clip, or the first clip yanked in the arrange view.
  local snap = value.kind == "slot" and value.clip
  if value.kind == "range" then
    for _, row in ipairs(value.rows) do snap = snap or row[1] end
  end
  if not snap then return paw.notify("the register holds no clip", "warn") end
  launcher.paste(snap, track, launcher.row)
end, "Paste a clip into the slot")

-- The line of keys under the view.
paw.ui.keybar.lines.session = {
  n = {
    { "<CR>", "launch" }, { "L", "scene" }, { "S", "stop" }, { "B", "resume timeline" }, { "n", "new clip" },
    { "i", "notes" }, { "m", "mode" }, { "<Space>", "play" }, { "?", "keys" },
  },
}

-- Controllers: a pad launches a slot, a scene, or stops -------------------------

paw.learn.trigger("launch", {
  press = function(b, down)
    if down then launcher.press(b.track, b.slot) else launcher.release(b.track, b.slot) end
  end,
  name = function(t) return api.track_get(t.track).name .. " › launch slot " .. (t.slot + 1) end,
  check = function(t)
    assert(t.track, "a launch names its track")
    assert(type(t.slot) == "number", "a launch names its `slot`, a row from 0")
  end,
  words = { "launch" },
  target_for = function(word, track)
    if word == "launch" then
      if not track then error("no track selected", 0) end
      return { track = track, target = "launch", slot = launcher.row }
    end
  end,
  -- In the session view, the slot under the cursor: a pad launches it.
  under_cursor = function(focused)
    local track = cursor.track_id()
    if focused == "session" and track then return { track = track, target = "launch", slot = launcher.row } end
  end,
})
paw.learn.trigger("scene", {
  press = function(b, down) if down then launcher.scene(b.slot) end end,
  name = function(t) return "launch " .. launcher.scene_name(t.slot) end,
  check = function(t) assert(type(t.slot) == "number", "a scene names its `slot`, a row from 0") end,
  words = { "scene" },
  target_for = function(word)
    if word == "scene" then return { target = "scene", slot = launcher.row } end
  end,
})
paw.learn.trigger("stop", {
  press = function(b, down) if down then launcher.stop(b.track) end end,
  name = function(t)
    if not t.track then return "stop every clip" end
    return api.track_get(t.track).name .. " › stop"
  end,
  words = { "stop", "stop all" },
  target_for = function(word, track)
    if word == "stop all" then return { target = "stop" } end
    if word == "stop" then
      if not track then error("no track selected", 0) end
      return { track = track, target = "stop" }
    end
  end,
})


return { launcher = launcher, view = view }
