-- Commands and keys of the drums extension.
local api = paw.api
local util = paw.util
local drums = require("drums")
local E = require("drums.edit")
local grid = require("drums.grid")
local keymap = paw.keymap
local command, map = paw.command, keymap.set

--- Open a clip in the drum grid, which a graphical frontend shows in a
--- pane as the terminal shows it.
local function open(clip) grid:edit(clip) end
drums.open = open

-- Commands --------------------------------------------------------------------

command("drums.track", function(ctx)
  local index = paw.cursor.index()
  local track = drums.make_track({
    name = ctx.args.name or ctx.args[1] and tostring(ctx.args[1]) or nil,
    map = ctx.args.map,
    kit = ctx.args.kit,
    index = index and index + 1 or nil,
  })
  local bar = paw.time.bar()
  local start = math.floor(paw.cursor.beat / bar + 1e-9) * bar
  local clip = track:add_clip({ start = start, length = bar * (tonumber(ctx.args.bars) or 1), name = "beat" })
  paw.cursor.set_track(track)
  paw.cursor.set_beat(start)
  if ctx.args.open ~= false then open(clip) end
  paw.notify("drum track " .. track.name .. ": program the beat in the grid (Enter on a cell), Ctrl-w p goes back")
end, {
  desc = "Add a drum track with the built-in kit and a clip to program: `drums.track`, `drums.track Beat map=gm-full kit=~/samples/808`",
})

local function map_items()
  local items = {}
  for _, name in ipairs(drums.map_names()) do
    local def = drums.maps[name]
    items[#items + 1] = { name = name, text = string.format("%-10s %s (%d rows)", name, def.label or "", #def.rows) }
  end
  items[#items + 1] = { name = "off", text = "off        an ordinary track again: its clips open in the piano roll" }
  return items
end

local function apply_map(track, name)
  if name == "off" or name == "none" then
    drums.clear_map(track)
    return paw.notify(track.name .. " is an ordinary track again")
  end
  local info = drums.set_map(track, name)
  paw.notify(string.format("%s is a drum track: map %s, %d rows", track.name, info.map, #info.rows))
end

command("drums.map", function(ctx)
  local track = paw.cursor.track()
  if not track then return paw.notify("no track under the cursor", "warn") end
  local name = ctx.args[1] and tostring(ctx.args[1])
  if name then return apply_map(track, name) end
  paw.pick({
    title = "Drum map for " .. track.name,
    items = map_items(),
    format = function(item) return item.text end,
    on_choose = function(item) apply_map(track, item.name) end,
    preview = function(item)
      local def = drums.maps[item.name]
      if not def then return { "The track's clips open in the piano roll again." } end
      local lines = { { text = def.label or item.name, style = "Title" } }
      for _, row in ipairs(def.rows) do
        lines[#lines + 1] = string.format("%3d  %s", row.note, row.name)
      end
      return lines
    end,
  })
end, {
  desc = "Make the track a drum track, whatever plays it, with a drum map: `drums.map gm`, `drums.map gm-full`, `drums.map off`",
  complete = function()
    local out = drums.map_names()
    out[#out + 1] = "off"
    return out
  end,
})

command("drums.edit", function()
  local clip = paw.cursor.clip()
  if not clip then return paw.notify("no clip under the cursor", "warn") end
  if not drums.is_drum(clip:get().track) then
    return paw.notify("not a drum track: `:drums.map` makes it one", "warn")
  end
  open(clip)
end, { desc = "Open the clip under the cursor in the drum grid" })

command("drums.rename", function(ctx)
  local view = grid
  local track_id = view:track_id() or (paw.cursor.track() and paw.cursor.track().id)
  local info = track_id and drums.info(track_id)
  if not info then return paw.notify("not on a drum track", "warn") end
  local piece = view:piece()
  local name = table.concat(ctx.args, " ")
  if not piece or piece.extra or name == "" then
    return paw.notify("put the cursor on a row of the map, then `drums.rename Name`", "warn")
  end
  local rows = info.rows
  for _, row in ipairs(rows) do
    if row.note == piece.note then row.name = name end
  end
  drums.set_map(track_id, rows, info.map)
end, { desc = "Rename the drum grid's row under the cursor: `drums.rename Ghost snare`" })

command("drums.kit", function(ctx)
  local kit = require("drums.kit")
  local dir = ctx.args[1] and tostring(ctx.args[1])
  if not dir then return paw.notify("drums.kit takes a folder of sound files: `drums.kit ~/samples/808`", "warn") end
  local track = paw.cursor.track()
  if track and drums.is_drum(track) then
    kit.build(track, dir)
  else
    local index = paw.cursor.index()
    track = drums.make_track({ kit = dir, index = index and index + 1 or nil })
    paw.cursor.set_track(track)
  end
  local pads = kit.pads(kit.device(track))
  paw.notify(string.format("%s plays %d samples from %s", track.name, #pads, dir))
  if grid:clip() and grid:track_id() == track.id then api.ui_redraw() end
end, { desc = "Play the drum track from a folder of samples, named by what they are: `drums.kit ~/samples/808`" })

command("drums.pad", function(ctx)
  local kit = require("drums.kit")
  local track_id = grid:track_id() or (paw.cursor.track() and paw.cursor.track().id)
  local device = track_id and kit.device(track_id)
  if not device then return paw.notify("the track has no kit of samples: `drums.kit <folder>` gives it one", "warn") end
  local piece = grid:clip() and grid:piece()
  local note = tonumber(ctx.args.note) or (piece and piece.note)
  if not note then return paw.notify("open the grid on the row to change, or give `note=`", "warn") end
  local fields = {}
  for _, key in ipairs({ "level", "pan", "tune", "group" }) do
    fields[key] = tonumber(ctx.args[key])
  end
  if ctx.args.file then fields.file = tostring(ctx.args.file) end
  local pad = kit.set_pad(device, note, fields)
  paw.notify(
    string.format(
      "%s: level %g dB, pan %g, tune %g, group %d",
      drums.piece(track_id, note),
      pad.level,
      pad.pan,
      pad.tune,
      pad.group
    )
  )
end, {
  desc = "Change the sample of the grid's row: `drums.pad level=-3 pan=0.3 tune=-2 group=1`, `drums.pad file=snare2.wav`",
})

command("drums.beat", function(ctx)
  local beats = require("drums.beats")
  local clip = grid:clip() and paw.ui.focused == "drums" and grid:clip() or paw.cursor.clip()
  if not clip then return paw.notify("put the cursor on a clip, or open one in the drum grid", "warn") end
  local function said(name, n, hidden)
    if hidden > 0 then
      return paw.notify(
        string.format(
          "%s: %d hits; %d note%s outside the drum map went with the old beat (u brings them back)",
          name,
          n,
          hidden,
          hidden == 1 and "" or "s"
        ),
        "warn"
      )
    end
    paw.notify(string.format("%s: %d hits", name, n))
  end
  local function apply(name) said(name, beats.apply(clip, name)) end
  if ctx.args[1] then return apply(tostring(ctx.args[1])) end
  local items = {}
  for _, name in ipairs(beats.names()) do
    items[#items + 1] = { name = name, text = string.format("%-9s %s", name, beats.list[name].label) }
  end
  paw.pick({
    title = "A beat to start from",
    items = items,
    format = function(item) return item.text end,
    on_choose = function(item) apply(item.name) end,
    -- Written into the clip as a trial, and its first bar played over and
    -- over through the track; Escape gives the clip its notes back.
    audition_key = "drums.beat",
    audition = function(item)
      local n, hidden = paw.audition.try(function() return beats.apply(clip, item.name) end)
      local c = clip:get()
      local bar = math.min(paw.time.bar(c.start), c.length)
      local notes = {}
      for _, note in ipairs(clip:notes()) do
        if note.start < bar then
          notes[#notes + 1] = { pitch = note.pitch, start = note.start, length = note.length, velocity = note.velocity }
        end
      end
      paw.audition.phrase(c.track, notes, { length = bar, at = c.start })
      return {
        label = item.name .. " · its first bar",
        keep = function() said(item.name, n, hidden or 0) end,
      }
    end,
    preview = function(item)
      local lines = { { text = beats.list[item.name].label, style = "Title" } }
      local notes = {}
      for note in pairs(beats.list[item.name].rows) do
        notes[#notes + 1] = note
      end
      table.sort(notes, function(a, b) return a > b end)
      for _, note in ipairs(notes) do
        lines[#lines + 1] =
          string.format("%-11s %s", drums.maps.gm_names[note] or note, beats.list[item.name].rows[note])
      end
      return lines
    end,
  })
end, {
  desc = "Fill the clip with a beat to start from, in place of its notes: `drums.beat rock`, or choose one",
  complete = function() return require("drums.beats").names() end,
})

-- The arrange view --------------------------------------------------------------

keymap.group("<localleader>k", "drums", { view = "arrange" })
map("<localleader>kn", "drums.track", { view = "arrange", desc = "Add a drum track" })
map("<localleader>km", "drums.map", { view = "arrange", desc = "Choose the track's drum map" })

-- A drum track is a kind of track (`paw.track_kinds`): `:track.add drums`,
-- `:track.new` and the window's menus that make a track offer it, the
-- header shows its `D`, and Enter (`clip.edit`) and a double click open its
-- clips in the drum grid; other clips go to the piano roll as before.
paw.track_kinds.define("drums", {
  title = "Drum track",
  letter = "D",
  desc = "a kit, and a grid of its pieces by name",
  create = function(track, args) drums.dress(track, args) end,
  editor = function(clip)
    if clip:get().kind ~= "midi" then return false end
    open(clip)
    return true
  end,
  describe = function(id)
    local info = drums.info(id)
    return info and (info.map .. " map") or nil
  end,
  -- Drum tracks made before there were kinds of track keep their map.
  is = function(id) return drums.is_drum(id) end,
})
table.insert(paw.frontend.menus.clip, { label = "Open in the drum grid", command = "drums.edit", only = "midi" })
table.insert(paw.frontend.menus.clip, { label = "Drum beat to start from…", command = "drums.beat", only = "midi" })
table.insert(paw.frontend.menus.track, { label = "Drum map…", command = "drums.map" })

-- The grid's keys -----------------------------------------------------------------

local motion, linewise = { motion = true }, { motion = true, linewise = true }
local far_lines = { motion = true, linewise = true, jump = true }
local function gmap(lhs, rhs, desc, opts) map(lhs, rhs, util.merge({ view = "drums", desc = desc }, opts)) end
local function move(dsteps, drows)
  return function(ctx)
    local n = ctx.count or 1
    grid:move(dsteps * n, drows * n)
  end
end
gmap("h", move(-1, 0), "Left one step", motion)
gmap("l", move(1, 0), "Right one step", motion)
gmap("j", move(0, 1), "Down a row", linewise)
gmap("k", move(0, -1), "Up a row", linewise)
gmap("<Left>", move(-1, 0), "Left one step", motion)
gmap("<Right>", move(1, 0), "Right one step", motion)
gmap("<Down>", move(0, 1), "Down a row", linewise)
gmap("<Up>", move(0, -1), "Up a row", linewise)
gmap("w", function(ctx) grid:to_hit(1, ctx.count) end, "Next hit on the row", motion)
gmap("b", function(ctx) grid:to_hit(-1, ctx.count) end, "Previous hit on the row", motion)
gmap("W", function(ctx) grid:to_bar(ctx.count or 1) end, "Next bar", motion)
gmap("B", function(ctx) grid:to_bar(-(ctx.count or 1)) end, "Previous bar", motion)
gmap("0", function() grid:set(nil, 0) end, "Start of the clip", motion)
gmap("$", function()
  local clip = grid:clip()
  if clip then grid:set(nil, clip.length) end
end, "End of the clip", motion)
gmap("^", function()
  grid:set(nil, 0)
  local piece, clip = grid:piece(), grid:clip()
  if piece and clip and not E.hit(clip, piece.note, 0, grid:step_size()) then grid:to_hit(1) end
end, "First hit on the row", motion)
gmap("gg", function() grid:set(1, nil) end, "The first row", far_lines)
gmap("G", function(ctx) grid:set(ctx.count or #grid:rows(), nil) end, "The last row, or row N", far_lines)
gmap("gp", "transport.to_cursor", "Playhead to the cursor")

-- Text objects.
local function object(lhs, fn, desc) keymap.textobject(lhs, fn, { view = "drums", desc = desc }) end
local function cursor_cell()
  local step = grid:step_size()
  local c0 = E.cell(grid.beat, step) * step
  return c0, c0 + step
end
for _, lhs in ipairs({ "ih", "ah" }) do
  object(lhs, function()
    local c0, c1 = cursor_cell()
    return { view = "drums", kind = "block", r0 = grid.row, r1 = grid.row, c0 = c0, c1 = c1 }
  end, "The cell under the cursor")
end
for _, lhs in ipairs({ "ib", "ab" }) do
  object(lhs, function(ctx)
    local clip = grid:clip()
    if not clip then return end
    local bar = paw.time.bar()
    local c0 = math.floor((clip.start + grid.beat) / bar + 1e-9) * bar - clip.start
    return { view = "drums", kind = "char", r0 = grid.row, r1 = grid.row, c0 = c0, c1 = c0 + bar * (ctx.count or 1) }
  end, "This bar on every row, or N bars")
end
for _, lhs in ipairs({ "ir", "ar" }) do
  object(lhs, function()
    local clip = grid:clip()
    if clip then return { view = "drums", kind = "block", r0 = grid.row, r1 = grid.row, c0 = 0, c1 = clip.length } end
  end, "The row, all along the clip")
end
for _, lhs in ipairs({ "ic", "ac", "ie", "ae" }) do
  object(lhs, function()
    local clip = grid:clip()
    if clip then return { view = "drums", kind = "char", r0 = grid.row, r1 = grid.row, c0 = 0, c1 = clip.length } end
  end, "Every hit of the clip")
end

-- Operators.
local function op(lhs, fn, desc)
  keymap.operator(lhs, function(region, ctx)
    local clip = grid:clip()
    if clip then return fn(clip, grid:rows(), region, ctx) end
  end, { view = "drums", desc = desc })
end
op("d", function(clip, rows, region, ctx) keymap.setreg(E.delete(clip, rows, region), ctx.register) end, "Delete hits")
op("y", function(clip, rows, region, ctx)
  local value = E.yank(clip, rows, region)
  keymap.setreg(value, ctx.register, true)
  paw.notify(#value.notes == 1 and "yanked 1 hit" or "yanked " .. #value.notes .. " hits")
end, "Yank hits")
local function shift(clip, rows, region, steps)
  local step = grid:step_size()
  local by = math.max(steps * step, region.kind == "line" and -math.huge or -region.c0)
  E.shift(clip, rows, region, by)
  if region.kind ~= "line" then grid:set(nil, grid.beat + by) end
end
op(
  ">",
  function(clip, rows, region, ctx) shift(clip, rows, region, region.visual and ctx.count or 1) end,
  "Move hits a step later"
)
op(
  "<lt>",
  function(clip, rows, region, ctx) shift(clip, rows, region, -(region.visual and ctx.count or 1)) end,
  "Move hits a step earlier"
)
op("gs", function(clip, rows, region, ctx)
  local amount = ctx.count and ctx.count / 100 or paw.opt.drums_swing
  local moved = E.swing(clip, rows, region, amount, grid:step_size())
  paw.notify(string.format("swung %d hits by %d%% of a step", moved, math.floor(amount * 100 + 0.5)))
end, "Swing: every other step later (a count is the percent of a step)")

-- Single keys.
gmap("<CR>", function() grid:toggle() end, "Add or remove a hit")
gmap("x", function() keymap.normal("dih") end, "Remove the hit")
gmap("D", function() keymap.normal("d$") end, "Delete to the end of the clip")
gmap("Y", function() keymap.normal("y$") end, "Yank to the end of the clip")
local function paste(before)
  return function(ctx)
    local clip = grid:clip()
    if not clip then return end
    local step = grid:step_size()
    local at = E.cell(grid.beat, step) * step
    if not before then at = at + step end
    local value = keymap.getreg(ctx.register)
    for _ = 1, ctx.count or 1 do
      local finish = E.paste(clip, grid:rows(), value, grid.row, at, step)
      if not finish then return end
      at = finish
    end
  end
end
gmap("p", paste(false), "Paste after the cursor")
gmap("P", paste(true), "Paste at the cursor")
-- How hard. A hit has no pitch to change, so its velocity is its main value
-- (`+` `-`, `Ctrl-a` `Ctrl-x`) and, as in the piano roll, its second (`]`
-- `[`, which wait a moment for `]g` and `[g`).
local roles =
  { ["+"] = "main+", ["<C-a>"] = "main+", ["]"] = "second+", ["-"] = "main-", ["<C-x>"] = "main-", ["["] = "second-" }
for lhs, role in pairs(roles) do
  local sign = role:sub(-1) == "+" and 1 or -1
  gmap(
    lhs,
    function(ctx) grid:velocity(sign * 16 * (ctx.count or 1)) end,
    sign > 0 and "Harder" or "Softer",
    { role = role }
  )
end
-- The step: finer and coarser, as `[g` and `]g` make the arrange view's grid.
gmap("[g", function() grid:set_step(E.next_step(grid:step_size(), 1)) end, "Finer steps", { mode = { "n", "x" } })
gmap("]g", function() grid:set_step(E.next_step(grid:step_size(), -1)) end, "Coarser steps", { mode = { "n", "x" } })
-- Triplets are `<localleader>3` here and in the score (its tuplet popover).
gmap(
  "<localleader>3",
  function() grid:set_step(E.toggle_triplet(grid:step_size())) end,
  "Triplet steps, or straight again"
)
gmap("&", function(ctx)
  local clip = grid:clip()
  if not clip then return end
  local n = E.repeat_bar(clip, grid.beat, ctx.count)
  paw.notify(n == 1 and "the bar is repeated once" or "the bar is repeated " .. n .. " times")
end, "Repeat this bar to the end of the clip (N: N times)")
gmap("gh", function() grid:hear() end, "Hear the piece")
gmap("gb", "drums.beat", "Fill the clip with a beat to start from")
-- Escape stays, as in every view; `<C-w>p` goes back to the window before.
gmap("<Esc>", function() keymap.escape_hint() end, "Stay in the grid (Ctrl-w p leaves)", { repeatable = false })
keymap.classic("<Esc>", function() paw.layout.back() end, { view = "drums", desc = "Back to the window before" })

-- On a selection.
local function vx(lhs, fn, desc)
  map(lhs, nil, {
    view = "drums",
    mode = "x",
    desc = desc,
    operator = function(region, ctx)
      local clip = grid:clip()
      if clip then fn(clip, grid:rows(), region, ctx) end
    end,
  })
end
vx("x", function(clip, rows, region, ctx) keymap.setreg(E.delete(clip, rows, region), ctx.register) end, "Delete hits")
for lhs, sign in pairs({ ["+"] = 1, ["]"] = 1, ["<C-a>"] = 1, ["-"] = -1, ["["] = -1, ["<C-x>"] = -1 }) do
  vx(lhs, function(clip, rows, region, ctx)
    local by = sign * 16 * (ctx.count or 1)
    E.each(clip, rows, region, function(n) n.velocity = drums.clamp_velocity(n.velocity + by) end)
  end, sign > 0 and "Harder" or "Softer")
end
vx("p", function(clip, rows, region, ctx)
  local value = keymap.getreg(ctx.register)
  if not value then return end
  local replaced = E.delete(clip, rows, region)
  E.paste(clip, rows, value, region.r0, region.c0, grid:step_size())
  keymap.setreg(replaced)
end, "Replace with the register")

if paw.ui.keybar then
  paw.ui.keybar.set("drums", "n", {
    { "<CR>", "hit" },
    { "+", "harder" },
    { "-", "softer" },
    { "[g", "finer" },
    { "]g", "coarser" },
    { "<localleader>3", "triplets" },
    { "&", "repeat bar" },
    { "d", "clear row", "dd" },
    { "gh", "hear" },
    { "<C-w>p", "back" },
  })
  paw.ui.keybar.set("drums", "x", {
    { "x", "delete" },
    { "+", "harder" },
    { "-", "softer" },
    { "gs", "swing" },
    { "y", "yank" },
    { "<Esc>", "done" },
  })
end
