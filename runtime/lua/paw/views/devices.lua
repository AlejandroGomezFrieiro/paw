-- The device panel: the cursor track's device chain and every parameter,
-- then where the track's sound goes. One view for both frontends: its
-- parts are roles (paw/roles/widgets.lua) and hit regions, which a window
-- paints as widgets and the pointer works through `view.gestures`
-- (paw/views/panels_mouse.lua) in a terminal and in a window alike.
local api = paw.api
local util = paw.util

-- `pin` is the track a window shows whatever the cursor is on, or nil to
-- follow the cursor. Each window of the panel has its own row, scroll and
-- pin: two panels show the devices of two tracks. `row_track` is the track
-- the row was chosen on.
local view = {
  row = 1,
  scroll = 0,
  pin = nil,
  window_state = { "row", "scroll", "geometry", "pin", "row_track" },
  window_fresh = { "geometry" },
}
paw.seats.fields("devices", view, { "row", "scroll", "geometry", "pin", "row_track" }, { row = 1, scroll = 0 })
-- A parameter that a lane moves is drawn bound to its live value: a
-- window moves it as the song plays with no new scene.
view.live_roles = { "param" }

-- Built-in effects that show what they do under their name: how many rows,
-- and the function that draws them (in `paw.views.device_pictures`).
local pictures = require("paw.views.device_pictures")

-- Reading a plugin with hundreds of parameters is not free, so the rows are
-- kept until the project changes: an edit made by the key just typed counts
-- at once, for the keys typed after it in the same breath (a macro, `ddj`).
-- Each track's rows are kept on their own: two windows on two tracks do not
-- read each other's again.
local cache = { revision = -1, tracks = {} }

--- The panel as a flat list of rows: a device heading, then its parameters.
local function rows_for(track_id)
  local edits = api.project_get("edits")
  if cache.revision ~= paw.frontend.revision or cache.edits ~= edits then
    cache = { revision = paw.frontend.revision, edits = edits, tracks = {} }
  end
  local kept = cache.tracks[track_id or false]
  if kept then return kept end
  local rows = {}
  for _, id in ipairs(track_id and api.track_get(track_id).devices or {}) do
    local device = api.device_get(id)
    rows[#rows + 1] = { device = device }
    local picture = device.format == "builtin" and pictures[device.kind]
    if picture and not device.missing then
      for line = 1, picture.rows do
        rows[#rows + 1] = { device = device, picture = picture, line = line }
      end
    end
    -- The host's wet/dry mix and output gain come last, after the device's own.
    for _, param in ipairs(device.param_info) do
      rows[#rows + 1] =
        { device = device, param = param, value = device.params[param.key], host = paw.fx.host_params[param.key] }
    end
  end
  cache.tracks[track_id or false] = rows
  return rows
end

--- The pinned track of the window, if it is still in the project.
local function pinned(self)
  local id = self.pin
  if id and id ~= 0 and pcall(api.track_get, id) then return id end
end

--- The id of the track whose devices the window shows: its pinned track,
--- else the cursor's.
function view:track_id() return pinned(self) or paw.cursor.track_id() end

--- The track the window shows, as a `paw.Track`, or nil.
function view:track()
  local id = self:track_id()
  return id and paw.track(id) or nil
end

function view:rows()
  local id = self:track_id()
  -- Another track: the cursor starts again on its first device, not on
  -- the row that it had in the chain before.
  if self.row_track ~= id then
    self.row_track, self.row, self.scroll = id, 1, 0
  end
  return rows_for(id)
end

-- Another project can have a track with the same id: its cursor starts
-- again on the first device too.
paw.on("project.loaded", function() view.row_track = nil end)

--- Its title where a window shows one over it: the track it shows.
function view:title_of()
  local track = self:track()
  if not track then return "Devices" end
  local n = #api.track_get(track.id).devices
  return "Devices · "
    .. track.name
    .. (pinned(self) and " (pinned)" or "")
    .. (n > 0 and " · " .. n .. (n == 1 and " device" or " devices") or "")
end

--- The track that a name stands for: its number, `paw://track/3`, or its name.
local function track_named(target)
  local id = tonumber(target) or tonumber(tostring(target):match("^paw://track/(%d+)"))
  if id then return id ~= 0 and pcall(api.track_get, id) and id or nil end
  for _, other in ipairs(api.track_list()) do
    if api.track_get(other, "name") == target then return other end
  end
end
view.track_named = track_named

--- Pin the window to a track (`:e devices://Bass`, `:vs devices://3`).
function view:open_target(target)
  local id = track_named(target)
  if not id then return false, "no track `" .. tostring(target) .. "`" end
  self.pin, self.row, self.scroll = id, 1, 0
end

--- What a saved layout keeps of the window: the number of its pinned track.
function view:window_target() return pinned(self) end

--- Pin the window to `track` (an id), or with nil follow the cursor again.
--- It says what it did.
function view:set_pin(track)
  self.pin, self.row, self.scroll = track, 1, 0
  if track then
    paw.notify(
      "the device panel stays on " .. api.track_get(track, "name") .. "; `:devices.pin` again follows the cursor"
    )
  else
    paw.notify("the device panel follows the cursor track")
  end
  api.ui_redraw()
end

--- Keys and commands typed in a pinned window act on its track: the track
--- of "the cursor" is the window's while that window has the keyboard, or
--- while paw draws it.
paw.cursor.lens = function()
  local u = paw.ui
  local L = paw.layout
  local win = u.drawing_win
  if win then
    if win.view ~= "devices" or L.bound("devices") ~= win then return nil end
  else
    if u.focused ~= "devices" or u.float then return nil end
    win = L.current()
    if not (win and win.view == "devices" and L.bound("devices") == win) then return nil end
  end
  return pinned(view)
end

-- Automation ------------------------------------------------------------------------------

--- The lanes that play on a track, by device and parameter: `lanes[device][key]`.
local function playing_lanes(track)
  local out = {}
  if not track or track.automation == "off" then return out end
  for _, lane in ipairs(api.lane_list(track.id)) do
    if lane.target == "param" and lane.enabled and lane.point_count > 0 then
      out[lane.device] = out[lane.device] or {}
      out[lane.device][lane.param] = lane.id
    end
  end
  return out
end

-- The parameters each window of each seat last drew bound to a lane, by
-- their binding, for the live values (`view.live_values`): `{ param,
-- value, lane }` each, by seat and window.
local bound = {}

--- Where a parameter sits and what it reads, at the song's position when a
--- lane moves it.
local function shown_value(p, value, lane)
  if lane then
    local ok, v = pcall(api.lane_value_at, lane, api.transport_get().position)
    if ok and v then value = v end
  end
  local range = p.max - p.min
  return range ~= 0 and paw.params.fraction(p, value) or 0, paw.frontend.format_value(p, value)
end

--- What the live values carry for the parameters drawn bound (paw/scene.tl):
--- `params[bind]` is `{ fraction, text }`.
function view.live_values()
  local out = {}
  for _, wins in pairs(bound) do
    for _, binds in pairs(wins) do
      for bind, b in pairs(binds) do
        local fraction, text = shown_value(b.param, b.value, b.lane)
        out[bind] = { fraction = math.floor(fraction * 10000 + 0.5) / 10000, text = text }
      end
    end
  end
  return { params = out }
end

--- Whether it shows what moves on its own beside the bound parameters: an
--- effect's picture (gain reduction, loudness, a tuner's needle). A
--- window then gets it drawn again ten times a second while the song plays.
function view:moving() return self.geometry ~= nil and self.geometry.pictures == true end
view.redraw_every = 100

-- Drawing ---------------------------------------------------------------------------------

--- Where the parts of a row of a panel `w` wide are: the name's width, the
--- slider's first column and width, the value's width, and the column of
--- the automate and learn buttons (nil when there is no room for them).
function view.layout(w)
  local tools = w >= 36 and w - 4 or nil
  local right = tools and tools - 1 or w - 1
  local name_w = math.min(12, math.max(4, w - 24))
  local value_w = 9
  local bar_at = 2 + name_w + 1
  return {
    name_w = name_w,
    bar_at = bar_at,
    bar = math.max(3, right - bar_at - value_w),
    value_w = value_w,
    tools = tools,
    right = right,
  }
end

--- A button of the heading of a device, `glyph` two columns wide at `x`.
local function tool(buf, x, y, glyph, icon, hit, enabled, label)
  buf:mark("button", x, y, 2, 1, {
    text = glyph,
    style = enabled == false and "Faint" or "DeviceFormat",
    icon = icon,
    quiet = true,
    off = enabled == false,
    hit = hit,
    label = label,
  })
end

--- A device's heading on row `y`: its name and preset on the left; on the
--- right its power, its buttons and what it says of itself.
local function heading(buf, y, w, index, d, devices, chosen)
  local g = paw.draw.g
  buf:mark("band", 0, y, w, 1, { off = d.bypass, selected = chosen or nil })
  buf:hit(0, y, w, 1, { kind = "row", index = index })
  local name = util.fit(d.name, math.max(1, w - 16)):gsub("%s+$", "")
  local style = d.bypass and "DeviceOff" or "DeviceName"
  buf:text(1, y, g.open .. " ", style)
  buf:mark("label", 3, y, api.str_width(name), 1, {
    text = name,
    style = style,
    font = "title",
    strike = d.bypass,
    tone = d.bypass and "text_3" or "text",
    hit = { kind = "device", index = index, device = d.id },
  })
  local after = 4 + api.str_width(name)
  -- The preset it holds, if one was loaded or saved; a caret when none was.
  -- Either opens the menu of presets.
  local preset = type(d.meta) == "table" and d.meta.preset
  local room = w - 16 - api.str_width(name) - 6
  if preset and room > 3 then
    local shown = util.fit(preset, room):gsub("%s+$", "")
    buf:mark("button", after, y, api.str_width(shown), 1, {
      text = shown,
      style = "Param",
      menu = true,
      quiet = true,
      tone = "text_2",
      hit = { kind = "preset", device = d.id },
    })
    after = after + api.str_width(shown) + 1
  elseif room > 1 then
    buf:mark(
      "button",
      after - 1,
      y,
      2,
      1,
      { text = " " .. g.open, style = "Faint", menu = true, quiet = true, hit = { kind = "preset", device = d.id } }
    )
    after = after + 2
  end
  -- What modules mark on the device (`paw.ui.layer("devices", "device", ...)`):
  -- from `x`, `width` columns up to its on/off chip.
  paw.ui.paint("devices", "device", { buf = buf, x = after, y = y, width = math.max(0, w - 6 - after), device = d.id })
  -- A device that is not running says so, and what brings it back.
  local status = d.status
  local mark = status == "loading" and { "loading", "Warn", nil, "circle" }
    or status == "offline" and { "offline: o", "Dim", "offline", "plugs" }
    or status == "missing" and { "not installed", "Error", nil, "warning" }
    or (d.stopped or d.missing) and { "stopped: gR restarts", "Error", "stopped", "warning" }
  local at
  if mark then
    at = math.max(2, w - #mark[1] - 1)
    buf:mark("button", at, y, #mark[1], 1, {
      text = mark[1],
      style = mark[2],
      quiet = true,
      tone = mark[2] == "Error" and "error" or "text_3",
      icon = mark[4],
      hit = mark[3] and { kind = "status", device = d.id, status = mark[3] } or nil,
    })
  else
    at = w - (d.bypass and 6 or 5)
    buf:mark(
      "power",
      at,
      y,
      d.bypass and 5 or 4,
      1,
      { on = not d.bypass, hit = { kind = "power", device = d.id }, label = "power of " .. d.name }
    )
  end
  if not mark then
    if d.format ~= "builtin" and at - #d.format - 1 > after then
      at = at - #d.format - 1
      buf:mark(
        "label",
        at,
        y,
        #d.format,
        1,
        { text = d.format, style = "DeviceFormat", font = "sans", tone = "text_3" }
      )
    end
    -- How much of it is heard, when not all of it: `+` `-` here change it.
    local wet = d.params.fx_wet
    if wet and wet < 100 then
      local text = string.format("wet %d%%", math.floor(wet + 0.5))
      if at - #text - 1 > after then
        at = at - #text - 1
        buf:mark("label", at, y, #text, 1, { text = text, style = "ParamValue", tone = "text_2" })
      end
    end
    -- The track it listens to as its side-chain (`gS` chooses it), and how
    -- many of its further output pairs play somewhere (`O`): a click on
    -- either chooses in a menu.
    local further = #(d.ports and d.ports.outputs or {}) - 1
    local routed = 0
    for _ in pairs(d.outputs or {}) do
      routed = routed + 1
    end
    for _, part in ipairs({
      further > 0 and { string.format("outs %d/%d", routed, further), "outputs" } or false,
      paw.routes.sidechain_text(d) and { "key " .. paw.routes.sidechain_text(d), "sidechain" } or false,
    }) do
      local width = part and api.str_width(part[1]) or 0
      if part and at - width - 1 > after then
        at = at - width - 1
        buf:mark("button", at, y, width, 1, {
          text = part[1],
          style = "ParamValue",
          quiet = true,
          tone = "text_2",
          menu = true,
          hit = { kind = part[2], device = d.id },
        })
      end
    end
  end
  -- Its buttons, with the room left: away, down and up the chain, its window.
  local list = {
    { g.remove, "remove", "remove" },
    { g.move_down, "down", "down", d.index < devices },
    { g.move_up, "up", "up", d.index > 1 },
  }
  if d.editor ~= nil and d.format ~= "builtin" then list[#list + 1] = { g.editor, "window", "editor" } end
  for _, b in ipairs(list) do
    if at - 2 <= after then break end
    at = at - 2
    tool(buf, at, y, b[1], b[2], { kind = b[3], device = d.id }, b[4], b[3] .. " " .. d.name)
  end
end

--- A parameter's row `y`: its name, its slider and value, and its buttons.
local function param_row(buf, y, lay, index, row, chosen, lanes, binds)
  local d, p = row.device, row.param
  buf:hit(0, y, lay.right, 1, { kind = "row", index = index })
  buf:mark("label", 2, y, lay.name_w, 1, {
    text = p.name,
    style = chosen and "Bright" or row.host and "DeviceFormat" or "Param",
    font = "sans",
    capital = true,
    tone = chosen and "text" or row.host and "text_3" or "text_2",
    hit = { kind = "row", index = index },
  })
  paw.ui.paint("devices", "param", { buf = buf, x = 1, y = y, width = buf.width, device = d.id, param = p.key })
  local lane = lanes[d.id] and lanes[d.id][p.key]
  local fraction, text = shown_value(p, row.value, lane)
  local bind = lane and ("param:" .. d.id .. ":" .. p.key) or nil
  if bind then binds[bind] = { param = p, value = row.value, lane = lane } end
  buf:mark("param", lay.bar_at, y, lay.right - lay.bar_at, 1, {
    fraction = fraction,
    text = text,
    bar = lay.bar,
    steps = #p.choices > 0 and #p.choices or nil,
    centred = p.min < 0 and p.max > 0 or nil,
    dim = d.bypass or nil,
    bind = bind,
    style = chosen and "ParamBar" or "ParamBarDim",
    off_style = "ParamBarOff",
    value_style = chosen and "Bright" or "ParamValue",
    label = p.name .. " of " .. d.name,
    hit = { kind = "param", index = index, device = d.id, key = p.key, bar = lay.bar },
  })
  if lay.tools then
    buf:mark("button", lay.tools, y, 2, 1, {
      text = "A",
      style = lane and "ParamBar" or "Faint",
      icon = "automate",
      quiet = true,
      on = lane ~= nil,
      hit = { kind = "automate", device = d.id, key = p.key },
    })
    buf:mark("button", lay.tools + 2, y, 2, 1, {
      text = "L",
      style = "Faint",
      icon = "learn",
      quiet = true,
      hit = { kind = "learn", device = d.id, key = p.key },
    })
  end
end

--- Where the track's sound goes, from row `y`: the add line, then (not
--- for the master) the track it plays into and its sends. Returns how many
--- rows that takes, with `draw` false to only count them.
local function footer(buf, y, w, track, draw)
  local g = paw.draw.g
  local routing = not track.master and paw.frontend.routing(track.id) or nil
  local n = 1 + (routing and 1 + #routing.sends or 0)
  if not draw then return n end
  buf:mark("button", 1, y, math.min(w - 2, 16), 1, {
    text = "+ add a device",
    style = "EmptyKey",
    icon = "plus",
    hit = { kind = "add" },
    label = "add a device",
  })
  if not routing then return n end
  local out = util.fit(g.out .. " " .. routing.output, math.max(1, w - 12)):gsub("%s+$", "")
  buf:mark("button", 1, y + 1, api.str_width(out) + 2, 1, {
    text = out .. " " .. g.open,
    style = "TrackInfo",
    menu = true,
    hit = { kind = "output", track = track.id },
    label = "output",
  })
  if w >= 20 then
    buf:mark(
      "button",
      w - 8,
      y + 1,
      7,
      1,
      { text = "+ send", style = "TrackInfo", icon = "plus", hit = { kind = "send_add", track = track.id } }
    )
  end
  -- Each send: the track, its level on a slider, before the fader or not, and away.
  local name_w = math.min(10, math.max(4, w - 26))
  for i, send in ipairs(routing.sends) do
    local sy = y + 1 + i
    buf:mark("label", 1, sy, name_w, 1, {
      text = util.fit(g.send .. " " .. send.name, name_w):gsub("%s+$", ""),
      style = "TrackInfo",
      font = "sans",
      tone = "text_2",
    })
    local level = string.format("%.1f dB", send.level)
    local width = math.max(4, w - name_w - 2 - 6 - 1)
    buf:mark("param", name_w + 2, sy, width, 1, {
      fraction = util.clamp((send.level + 60) / 66, 0, 1),
      text = level,
      bar = math.max(3, width - 9),
      style = "ParamBarDim",
      off_style = "ParamBarOff",
      value_style = "ParamValue",
      hit = { kind = "send", track = track.id, index = i, bar = math.max(3, width - 9) },
      label = "send to " .. send.name,
    })
    buf:mark("button", w - 5, sy, 3, 1, {
      text = "pre",
      style = send.pre and "Bright" or "Faint",
      on = send.pre,
      hit = { kind = "send_pre", track = track.id, index = i },
    })
    buf:mark("button", w - 2, sy, 2, 1, {
      text = g.remove,
      style = "Faint",
      icon = "remove",
      quiet = true,
      hit = { kind = "send_remove", track = track.id, index = i },
    })
  end
  return n
end

function view:render(buf, ctx)
  local g = paw.draw.g
  local track = self:track()
  local rows = self:rows()
  local devices = 0
  for _, row in ipairs(rows) do
    if not row.param and not row.picture then devices = devices + 1 end
  end
  local inner = paw.ui.titlebar(buf, {
    name = "Devices",
    context = track and (track.name .. (pinned(self) and " · pinned" or "")) or nil,
    focused = ctx.focused,
    right = devices > 0 and tostring(devices) or nil,
  })
  local w, h = inner.width, inner.height
  -- The bound parameters of this window, kept apart from its other windows'.
  local mine = bound[paw.seats.current] or {}
  bound[paw.seats.current] = mine
  for id in pairs(mine) do
    if not paw.layout.alive(id) then mine[id] = nil end
  end
  local binds = {}
  mine[ctx.win and ctx.win.id or 0] = binds
  -- Where the track's sound goes, after the chain, when there is room for
  -- it and three rows of the chain above.
  local foot = track and footer(inner, 0, w, track, false) or 0
  if foot > 0 and h - foot - 1 < 3 then foot = h >= 5 and 1 or 0 end
  if #rows == 0 then
    inner:text(2, 1, "No devices.", "Empty")
    inner:text(2, 3, "a", "EmptyKey")
    inner:text(5, 3, "add one", "Empty")
    self.geometry = { list = 0, foot = 5 }
    if foot > 0 and h > 6 then footer(inner, 5, w, track, true) end
    return
  end
  local list = math.max(1, h - (foot > 0 and foot + 1 or 0))
  self.row = util.clamp(self.row, 1, #rows)
  if self.row <= self.scroll then self.scroll = self.row - 1 end
  if self.row > self.scroll + list then self.scroll = self.row - list end
  self.scroll = util.clamp(self.scroll, 0, math.max(0, #rows - list))
  local lay = view.layout(w)
  local lanes = playing_lanes(track)
  local shown, drawn_pictures = 0, false
  for y = 0, list - 1 do
    local index = y + 1 + self.scroll
    local row = rows[index]
    if not row then break end
    shown = y + 1
    local chosen = index == self.row and ctx.focused
    local d = row.device
    -- The row of the keyboard's cursor, lit under what is drawn there.
    if chosen then inner:fill(0, y, w, 1, " ", "Selected") end
    if row.picture then
      -- Drawn whole from its first row, or from the top when scrolled into it.
      inner:hit(0, y, w, 1, { kind = "row", index = index })
      drawn_pictures = true
      if row.line == 1 or y == 0 then
        local box = inner:sub(2, y - (row.line - 1), math.max(1, w - 3), row.picture.rows)
        row.picture.draw(box, d, chosen)
      end
    elseif not row.param then
      heading(inner, y, w, index, d, devices, chosen)
    else
      param_row(inner, y, lay, index, row, chosen, lanes, binds)
    end
    if chosen then inner:text(0, y, g.mark, "SelectedMark") end
  end
  self.geometry = { list = list, foot = foot > 0 and shown + 1 or nil, lay = lay, pictures = drawn_pictures }
  if foot > 0 then footer(inner, shown + 1, w, track, true) end
end

--- Move the selected parameter by `steps` out of 100 across its range.
function view:adjust(steps)
  local row = self:rows()[self.row]
  if not row then return end
  if row.picture then return end
  -- On the device's own line: its wet/dry mix.
  if not row.param then
    local wet = api.device_get(row.device.id).params.fx_wet
    if wet then api.device_set_param(row.device.id, "fx_wet", util.clamp(wet + steps, 0, 100)) end
    return
  end
  -- The value now, not the row's: the rows are kept until the screen is
  -- drawn again, and keys typed faster than that (a macro, `.`) each count.
  local p = row.param
  api.device_set_param(row.device.id, p.key, paw.params.step(p, view.value(row), steps))
end

--- A parameter row's value as it is now.
function view.value(row) return api.device_get(row.device.id).params[row.param.key] end

function view:selected()
  local row = self:rows()[self.row]
  return row and paw.device(row.device.id), row
end

paw.ui.view("devices", view)
return view
