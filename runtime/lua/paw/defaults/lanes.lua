-- The default commands and keys: automation lanes as rows (see paw.lanes). Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local api = paw.api
local util = paw.util
local command, map = paw.command, paw.keymap.set
local cursor = paw.cursor
local keymap = paw.keymap
local common = require("paw.defaults.common")
local motion, need_track, read_pan, param_reader, amap =
  common.motion, common.need_track, common.read_pan, common.param_reader, common.amap

--- What a new lane's first point starts from: the target's value now.
local function value_now(lane) return paw.lanes.value_at(lane:get(), cursor.beat) end

local function clamp_to(l, v) return util.clamp(v, l.min, l.max) end

--- The lane the cursor's row is, or a warning.
local function cursor_lane()
  local id = cursor.lane_id()
  if not id then
    paw.notify(
      "the cursor is not on an automation lane: `" .. paw.keymap.human("<leader>aa") .. "` shows the track's lanes",
      "warn"
    )
  end
  return id and paw.lane(id)
end

--- How near the cursor a point must be to be the one under it.
local function reach() return paw.opt.grid / 2 - 1e-9 end

command("lane.pick", function()
  local track = need_track()
  if not track then return end
  local have = {}
  for _, l in ipairs(api.lane_list(track.id)) do
    have[(l.target == "param" and l.device .. ":" .. l.param) or l.target] = true
  end
  local items = { { target = "volume", name = "Volume" }, { target = "pan", name = "Pan" } }
  for _, device in ipairs(track:devices()) do
    local d = device:get()
    items[#items + 1] = { target = "state", device = d.id, name = d.name .. " › state (presets, models, snapshots)" }
    for _, p in ipairs(d.param_info) do
      items[#items + 1] = { target = "param", device = d.id, param = p.key, name = d.name .. " › " .. p.name }
    end
  end
  local function key_of(item)
    if item.target == "param" then return item.device .. ":" .. item.param end
    if item.target == "state" then return item.device .. ":state" end
    return item.target
  end
  for _, l in ipairs(api.lane_list(track.id)) do
    if l.target == "state" then have[l.device .. ":state"] = true end
  end
  paw.pick({
    title = "Automate on " .. track.name,
    items = items,
    format = function(item) return (have[key_of(item)] and "● " or "  ") .. item.name end,
    on_choose = function(item)
      if item.target == "state" then
        local lane = paw.device(item.device):automate_state()
        paw.lanes.open(track)
        cursor.set_track(track.id, lane.id)
        paw.ui.focus("arrange")
        paw.notify(
          paw.lanes.name(lane.id)
            .. " lane: `\\s` keeps the device's state at the cursor, `+` `-` `c` choose a state, `x` removes it"
        )
        return
      end
      local lane = item.target == "param" and paw.device(item.device):automate(item.param)
        or track:automate(item.target)
      paw.lanes.open(track)
      cursor.set_track(track.id, lane.id)
      paw.ui.focus("arrange")
      paw.notify(paw.lanes.name(lane.id) .. " lane: `A` adds a point, `+` `-` `c` change it, `x` removes it")
    end,
  })
end, { desc = "Choose what to automate on the track (volume, pan, a device's parameter) and show its lane" })
command(
  "lane.show",
  function(ctx)
    local which = ctx.args[1]
    if which == "all" or which == "none" then
      for _, id in ipairs(api.track_list()) do
        if which == "none" or #api.lane_list(id) > 0 then paw.lanes.open(id, which == "all") end
      end
      if which == "none" and cursor.lane_id() == nil then cursor.set_track(cursor.track_id()) end
      return
    end
    local track = need_track()
    if not track then return end
    if #api.lane_list(track.id) == 0 then
      return paw.notify(
        track.name .. " has no automation yet: `" .. paw.keymap.human("<leader>al") .. "` chooses what to automate",
        "warn"
      )
    end
    local now = paw.lanes.toggle(track)
    cursor.set_track(track.id)
    paw.notify(track.name .. (now and ": lanes shown" or ": lanes hidden"))
  end,
  {
    desc = "Show the track's automation lanes as rows under it, or hide them: `lane.show`, `lane.show all`, `lane.show none`",
    complete = function() return { "all", "none" } end,
  }
)
command(
  "lane.rows",
  function()
    local track = need_track()
    if not track then return end
    local now = paw.frontend.act.lane_rows(track.id)
    paw.notify(track.name .. (now and ": lanes shown as rows" or ": lanes hidden"))
  end,
  { desc = "Show the track's automation lanes as rows under it, making one for its fader if it has none; or hide them" }
)
command("lane.point.add", function()
  local lane = cursor_lane()
  if not lane then return end
  local l = lane:get()
  local v = value_now(lane)
  lane:add(cursor.beat, v)
  paw.notify(
    string.format("%s: a point at %s, %s", paw.lanes.name(l), paw.time.format(cursor.beat), paw.lanes.format(l, v))
  )
end, { desc = "Add an automation point at the cursor, at the curve's value there", label = "Add a point" })
command(
  "lane.point.nudge",
  function(ctx)
    local lane = cursor_lane()
    if not lane then return end
    local l = lane:get()
    local at = paw.lanes.point_at(l.id, cursor.beat, reach())
    if not at then return paw.notify("no point under the cursor: `A` adds one", "warn") end
    local by = (tonumber(ctx.args.by) or 1) * (ctx.count or 1) * paw.lanes.step(l)
    local v
    paw.lanes.edit(l.id, function(points)
      points[at][2] = clamp_to(l, points[at][2] + by)
      v = points[at][2]
    end)
    paw.notify(paw.lanes.name(l) .. " " .. paw.lanes.format(l, v))
  end,
  { desc = "Raise or lower the automation point under the cursor: `lane.point.nudge by=-1`", label = "Change a point" }
)
command("lane.point.set", function()
  local lane = cursor_lane()
  if not lane then return end
  local l = lane:get()
  local at, point = paw.lanes.point_at(l.id, cursor.beat, reach())
  local beat = point and point[1] or cursor.beat
  local now = point and point[2] or value_now(lane)
  if l.target == "state" then
    if #l.states == 0 then
      return paw.notify("the lane has no states yet: `\\s` keeps the device's state at the cursor", "warn")
    end
    local items = {}
    for i, name in ipairs(l.states) do
      items[i] = { index = i - 1, name = name }
    end
    return paw.pick({
      title = paw.lanes.name(l) .. " at " .. paw.time.format(beat),
      items = items,
      format = function(item) return item.name end,
      on_choose = function(item)
        paw.lanes.edit(l.id, function(points)
          if at then
            points[at][2] = item.index
          else
            points[#points + 1] = { beat, item.index }
          end
        end)
        paw.notify(string.format("%s: %s from %s", paw.lanes.name(l), item.name, paw.time.format(beat)))
      end,
    })
  end
  local opts = { label = paw.lanes.name(l), now = now, min = l.min, max = l.max }
  local scale = 1
  if l.target == "volume" then
    opts.unit = "dB"
  elseif l.target == "pan" then
    scale = 100
    opts.now, opts.min, opts.max = util.round(now * 100, 1), -100, 100
    opts.parse = read_pan
    opts.show = function(v) return paw.draw.pan_text(v / 100) end
  else
    local p = paw.lanes.param_of(l)
    if p then
      opts.parse = param_reader(p)
      opts.show = function(v) return paw.frontend.format_value(p, v) end
    end
  end
  paw.ui.ask_value(opts, function(v)
    v = v / scale
    paw.lanes.edit(l.id, function(points)
      if at then
        points[at][2] = v
      else
        points[#points + 1] = { beat, v }
      end
    end)
  end)
end, { desc = "Type the value of the automation point under the cursor, or of a new one there", label = "Set a point" })
command("lane.point.remove", function()
  local lane = cursor_lane()
  if not lane then return end
  local at = paw.lanes.point_at(lane.id, cursor.beat, reach())
  if not at then return paw.notify("no point under the cursor", "warn") end
  paw.lanes.edit(lane.id, function(points) table.remove(points, at) end)
end, { desc = "Remove the automation point under the cursor", label = "Remove a point" })

--- The points of the cursor's lane within a selection, by index: from one
--- end to the other, both included, since a point is an instant.
local function points_in(lane_id, region)
  local c0, c1 = region.c0, region.c1
  -- A selection not yet stretched is the cursor's own beat.
  if region.unstretched then c1 = c0 end
  local out = {}
  for i, p in ipairs(api.lane_points(lane_id)) do
    if p[1] >= c0 - 1e-9 and p[1] <= c1 + 1e-9 then out[#out + 1] = i end
  end
  return out
end

--- Next (`dir` 1) or previous point of the cursor's lane.
local function to_point(dir, n)
  local id = cursor.lane_id()
  if not id then return end
  for _ = 1, n or 1 do
    local to
    for _, p in ipairs(api.lane_points(id)) do
      if dir > 0 and p[1] > cursor.beat + 1e-9 and not to then to = p[1] end
      if dir < 0 and p[1] < cursor.beat - 1e-9 then to = p[1] end
    end
    if not to then return end
    cursor.set_beat(to)
  end
end

command(
  "lane.state",
  function(ctx)
    local lane = cursor_lane()
    if not lane then return end
    local l = lane:get()
    if l.target ~= "state" then
      return paw.notify(
        "the cursor is not on a state lane: `" .. paw.keymap.human("<leader>al") .. "` makes one for a device",
        "warn"
      )
    end
    local device = paw.device(l.device)
    local name = table.concat(ctx.args, " ")
    if name == "" then
      local d = device:get()
      name = (d.meta or {}).preset
      local taken = {}
      for _, n in ipairs(l.states) do
        taken[n] = true
      end
      if not name or taken[name] then
        for c in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):gmatch(".") do
          if not taken[c] then
            name = c
            break
          end
        end
      end
    end
    local ok, state = pcall(device.capture, device, name)
    if not ok then return paw.notify((tostring(state):gsub("^.-:%d+: ", "")), "error") end
    local index = lane:add_state(state)
    lane:add(cursor.beat, index)
    paw.notify(string.format("%s: %s from %s", paw.lanes.name(l), state.name, paw.time.format(cursor.beat)))
  end,
  {
    desc = "Keep the device's state now as a state of its state lane, given from the cursor on: `lane.state crunch`",
    label = "Keep the state here",
  }
)

local function lmap(lhs, rhs, desc, opts) map(lhs, rhs, util.merge({ view = "arrange.lane", desc = desc }, opts)) end
lmap("<localleader>s", "lane.state", "Keep the device's state now as a state of the lane, from the cursor on")
lmap("A", "lane.point.add", "Add a point at the cursor, at the curve's value")
lmap("+", "lane.point.nudge by=1", "Raise the point under the cursor", { role = "main+" })
lmap("-", "lane.point.nudge by=-1", "Lower the point under the cursor", { role = "main-" })
lmap("c", "lane.point.set", "Type the value of the point under the cursor")
lmap("x", "lane.point.remove", "Remove the point under the cursor")
lmap("w", function(ctx) to_point(1, ctx.count) end, "Next point", motion)
lmap("b", function(ctx) to_point(-1, ctx.count) end, "Previous point", motion)
local function lx(lhs, fn, desc)
  map(lhs, nil, {
    view = "arrange.lane",
    mode = "x",
    desc = desc,
    operator = function(region, ctx)
      local id = cursor.lane_id()
      if id then fn(id, region, ctx) end
    end,
  })
end
local function remove_points(id, region)
  local gone = {}
  for _, i in ipairs(points_in(id, region)) do
    gone[i] = true
  end
  paw.lanes.edit(id, function(points)
    for i = #points, 1, -1 do
      if gone[i] then table.remove(points, i) end
    end
  end)
end
lx("x", remove_points, "Remove the points selected")
lx("d", remove_points, "Remove the points selected")
local function move_points(steps)
  return function(id, region, ctx)
    local by = steps * (ctx.count or 1) * paw.opt.grid
    local chosen = {}
    for _, i in ipairs(points_in(id, region)) do
      chosen[i] = true
    end
    paw.lanes.edit(id, function(points)
      local landed = {}
      for i, p in ipairs(points) do
        if chosen[i] then
          p[1] = math.max(0, p[1] + by)
          landed[#landed + 1] = p[1]
        end
      end
      -- A point moved onto another's beat takes its place.
      for i = #points, 1, -1 do
        if not chosen[i] then
          for _, beat in ipairs(landed) do
            if math.abs(points[i][1] - beat) < 1e-9 then
              table.remove(points, i)
              break
            end
          end
        end
      end
    end)
  end
end
lx("L", move_points(1), "Move the points selected later")
lx("H", move_points(-1), "Move the points selected earlier")
local function nudge_points(sign)
  return function(id, region, ctx)
    local l = api.lane_get(id)
    local by = sign * (ctx.count or 1) * paw.lanes.step(l)
    local chosen = {}
    for _, i in ipairs(points_in(id, region)) do
      chosen[i] = true
    end
    paw.lanes.edit(id, function(points)
      for i, p in ipairs(points) do
        if chosen[i] then p[2] = clamp_to(l, p[2] + by) end
      end
    end)
  end
end
lx("+", nudge_points(1), "Raise the points selected")
lx("-", nudge_points(-1), "Lower the points selected")
lx("<C-a>", nudge_points(1), "Raise the points selected by the count")
lx("<C-x>", nudge_points(-1), "Lower the points selected by the count")
-- On a lane row the time operators move points, not clips.
for lhs, steps in pairs({ [">"] = 1, ["<lt>"] = -1 }) do
  keymap.operator(lhs, function(region, ctx)
    local id = cursor.lane_id()
    if id then move_points(steps)(id, region, ctx) end
  end, { view = "arrange.lane", desc = steps > 0 and "Move points later" or "Move points earlier" })
end
lmap("<C-a>", "lane.point.nudge by=1", "Raise the point under the cursor by the count", { role = "main+" })
lmap("<C-x>", "lane.point.nudge by=-1", "Lower the point under the cursor by the count", { role = "main-" })
lmap("gc", "lane.toggle", "Turn the lane's automation off or on", { role = "mute" })
keymap.classic("gc", "curve.open", { view = "arrange.lane", desc = "Edit this lane's curve" })
amap("<leader>cf", "clip.fade", "Fade the clip in and out: type the lengths")
-- The clip's own keys, on the local leader: fades.
keymap.group("<localleader>f", "fades", { view = "arrange" })
amap("<localleader>fi", "clip.fade.cursor in", "Fade the clip in up to the cursor; a count gives the beats")
amap("<localleader>fo", "clip.fade.cursor out", "Fade the clip out from the cursor; a count gives the beats")
amap("<localleader>ff", "clip.fade", "Fade the clip in and out: type the lengths")
amap("<localleader>fx", "clip.crossfade", "Crossfade the clip into the next one over a grid step")
for _, name in ipairs({ "arrange", "mixer" }) do
  map("grC", "track.color.pick", { view = name, desc = "Choose the track's colour" })
end
amap("<leader>al", "lane.pick", "Choose what to automate, and show its lane")
amap("<leader>aa", "lane.show", "Show or hide the track's automation lanes")
amap("<leader>aA", "lane.show all", "Show every track's automation lanes")
