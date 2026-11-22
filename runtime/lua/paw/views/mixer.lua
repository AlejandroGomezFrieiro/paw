-- The mixer: one channel strip per track, the master after the last behind a
-- heavier rule. Each strip, top to bottom: the name on a plate in the
-- track's colour; where it plays into, its first devices and its sends when
-- there is room; the level meters for both sides beside the fader, with the
-- loudest of late held, a clip light on top and 0 dB marked on the fader's
-- rail; the peak and the fader in dB; the pan; and the M S R I chips.
local api = paw.api
local util = paw.util

-- `row` is the row of a strip the cursor is on (paw/mixer_rows.lua): "volume",
-- "pan", "send2", "insert1", "mute" ...
-- Each window of the mixer has its own scroll and row: the mixer shows in
-- any number of windows. The track of the cursor is one for them all.
local view = {
  scroll = 0,
  row = "volume",
  window_state = { "scroll", "geometry", "row" },
  window_fresh = { "geometry" },
}
paw.seats.fields("mixer", view, { "scroll", "geometry", "row" }, { scroll = 0, row = "volume" })
-- What moves on its own as the song plays is drawn as these roles, bound to
-- the live values: a window that paints them is sent no new scene for it.
view.live_roles = { "meter", "peak" }
local draw = paw.draw

local SCALE = 4 -- columns for the dB scale on the left

--- Columns a strip takes on a screen `w` wide, the gap after it included.
function view.strip_width(w) return w < 80 and 8 or 10 end

-- What the scale names: where the fader's cap is at each of these levels.
-- The meters beside it are linear in decibels from -60 (bottom) to 0 (top)
-- and have their loudest of late in numbers under them, so the scale is the
-- fader's and does not claim to be theirs.
local marks = { 6, 0, -6, -12, -24, -48 }

-- The fader's travel: most of it is the top twenty decibels, as on a desk.
-- Where the cap is for a level, from 0 at the bottom to 1 at the top, and
-- the level for a place.
local function fader_position(volume) return util.clamp((volume + 60) / 66, 0, 1) ^ 2.5 end
local function fader_volume(position) return util.clamp(position, 0, 1) ^ (1 / 2.5) * 66 - 60 end
view.fader_position, view.fader_volume = fader_position, fader_volume

local function fader_row(volume, rows) return math.floor(fader_position(volume) * (rows - 1) + 0.5) end
view.fader_row = fader_row

--- The rows of a strip `height` tall that name its devices: none (they fold
--- into one row that counts them), or four, the last saying how many more.
local function device_rows(height) return height >= 20 and 4 or 0 end

--- The rows above the fader, for a strip `height` tall: the most any kind of
--- strip (a track, a VCA, the master) fills there. Every strip starts its
--- fader on this row, so that one scale on the left serves them all.
local function above_fader(height)
  local plain = 1
    + (height >= 14 and 1 or 0)
    + device_rows(height)
    + (height >= 12 and 1 or 0)
    + (height >= 10 and height < 24 and 1 or 0)
    + (height >= 24 and 2 or 0)
  local vca = 1 + (height >= 12 and 3 or 0) + (height >= 24 and 2 or 0)
  return math.max(plain, vca)
end

-- `here` is the row the cursor is on, on the strip it is on (paw/mixer_rows.lua).
-- Its parts are roles (paw/roles/widgets.lua) and hit regions, which the
-- pointer works through `view.gestures` in a terminal and in a window.
local function strip(buf, x, t, index, selected, height, sw, here)
  local g = draw.g
  local hue = draw.track_hue(t, index)
  local w = sw - 1
  local id = t.id
  buf:fill(x, 0, w, height, " ", selected and "TrackHeaderSel" or "TrackHeader")
  buf:hit(x, 0, w, height, { kind = "strip", track = id })
  -- The name on a plate in the track's colour, lit for the track the cursor is on.
  buf:mark("chip", x, 0, w, 1, {
    text = t.name,
    style = selected and hue.title_cur or hue.plate,
    selected = selected,
    color = draw.track_colour(t, index),
    number = index,
  })
  -- What modules mark on the strip (`paw.ui.layer("mixer", "strip", ...)`).
  paw.ui.paint("mixer", "strip", { buf = buf, x = x, y = 0, width = w, height = height, track = t.id })
  -- Where each part is, for the pointer.
  local parts = { x = x, w = w, id = t.id }
  local y = 1
  local vca = t.meta and t.meta.vca == true
  -- Where it plays into, with room: a click chooses another.
  if not vca and height >= 14 then
    parts.output = y
    if t.master then
      buf:text(x + 1, y, util.fit(g.out .. " out", w - 1), "TrackIndex")
    else
      local ok, to = pcall(api.track_get, t.output or 0)
      buf:mark("button", x + 1, y, w - 1, 1, {
        text = g.out .. " " .. (t.output and ok and to.name or "Master"),
        style = "TrackInfo",
        hit = { kind = "output", track = id },
      })
    end
    y = y + 1
  end
  -- A VCA names the tracks it moves, with room; a track the VCAs it is under.
  if vca and height >= 12 then
    local members = paw.vca.members(t.id)
    for i = 1, 3 do
      local name = members[i] and api.track_get(members[i], "name")
      if i == 3 and #members > 3 then name = "+" .. (#members - 2) .. " more" end
      buf:text(x + 1, y, util.fit(name or (i == 1 and "no tracks" or ""), w - 1), name and "TrackInfo" or "TrackIndex")
      y = y + 1
    end
  elseif device_rows(height) > 0 then
    parts.devices, parts.slots = y, device_rows(height)
    local list = t.devices or {}
    for i = 1, parts.slots do
      local device = list[i]
      local ok, d = device ~= nil, nil
      if ok then
        ok, d = pcall(api.device_get, device)
      end
      if ok and d and i == parts.slots and #list > i then
        -- The last row counts those it has no room for, or names the one
        -- among them the cursor is on.
        local at = here and here.kind == "insert" and here.index >= i and here.index or nil
        local text = "+" .. (#list - i + 1) .. " more"
        if at then
          local okc, cur = pcall(api.device_get, list[at])
          if okc and cur then text = (cur.bypass and g.bypass or " ") .. cur.name end
        end
        buf:mark(
          "button",
          x + 1,
          y,
          w - 1,
          1,
          { text = text, style = "TrackInfo", hit = { kind = "insert", track = id, index = at or i } }
        )
      elseif ok and d then
        buf:mark("button", x + 1, y, w - 1, 1, {
          text = (d.bypass and g.bypass or " ") .. d.name,
          style = d.bypass and "TrackIndex" or "TrackInfo",
          off = d.bypass,
          hit = { kind = "insert", track = id, index = i },
        })
      else
        buf:text(x + 1, y, util.fit(i == 1 and g.dot or "", w - 1), "TrackIndex")
      end
      y = y + 1
    end
  end
  -- The VCAs the track is under.
  if not vca and not t.master and height >= 12 then
    local words = paw.frontend.vca_words(t.id)
    if words ~= "" then buf:text(x + 1, y, util.fit("vca " .. words, w - 1), "TrackInfo") end
    y = y + 1
  end
  -- The sends, with more room.
  if height >= 24 then
    parts.sends = y
    for i = 1, 2 do
      local send = (t.sends or {})[i]
      if send then
        local okt, to = pcall(api.track_get, send.target)
        local text = g.send
          .. (okt and to.name:sub(1, 3) or "?")
          .. " "
          .. string.format("%g", math.floor(send.level + 0.5))
        buf:mark(
          "button",
          x + 1,
          y,
          w - 1,
          1,
          { text = text, style = "TrackInfo", hit = { kind = "send", track = id, index = i } }
        )
      end
      y = y + 1
    end
  end

  -- With too little room for them, the devices and sends fold into one row
  -- that counts them (`3 ↗2`), or names the one the cursor is on: they are
  -- rows of the strip for `j` `k`, and must show.
  local devices, sends = t.devices or {}, t.sends or {}
  local fold_devices = not vca and not parts.devices and #devices > 0
  local fold_sends = not vca and not parts.sends and #sends > 0
  if (fold_devices or fold_sends) and height >= 10 then
    parts.compact = y
    local text
    if here and here.kind == "insert" and fold_devices then
      local ok, d = pcall(api.device_get, devices[here.index])
      text = (ok and d.bypass and g.bypass or "") .. (ok and d.name or "?")
    elseif here and here.kind == "send" and fold_sends then
      local send = sends[here.index]
      local okt, to = pcall(api.track_get, send.target)
      text = g.send .. (okt and to.name:sub(1, 3) or "?") .. " " .. string.format("%g", math.floor(send.level + 0.5))
    else
      text = (fold_devices and #devices .. " " or "") .. (fold_sends and g.send .. #sends or "")
    end
    buf:text(x + 1, y, util.fit(text, w - 1), "TrackInfo")
  end

  -- Meters and fader, over what the rows under them leave.
  y = above_fader(height)
  local rows = math.max(1, height - y - 4)
  local left, right, hold, clipped = draw.track_peak(id)
  -- The fader's rows, meters and all, are the fader's to the pointer, but
  -- for the meters' top row, the clip light, which a click puts out.
  buf:hit(x, y, w, rows, { kind = "fader", track = id })
  buf:mark(
    "meter",
    x + 1,
    y,
    2,
    rows,
    { levels = { left, right }, hold = hold, clipped = clipped, bind = "meter:" .. id }
  )
  buf:hit(x + 1, y, 2, 1, { kind = "peak", track = id })
  local fx = x + math.floor(w / 2) + 1
  buf:mark("fader", fx - 1, y, 3, rows, {
    at = fader_position(t.volume),
    zero = fader_position(0),
    value = t.volume,
    selected = selected,
  })
  y = y + rows
  -- The loudest of late, then the fader, in dB. A click on the peak puts
  -- out the clip light and lets the peak fall.
  local peak_w = math.min(5, w - 1)
  buf:mark(
    "peak",
    x + w - peak_w,
    y,
    peak_w,
    1,
    { hold = hold, clipped = clipped, bind = "meter:" .. id, hit = { kind = "peak", track = id } }
  )
  -- What modules label the strip with, on the peak's row (`paw.ui.layer("mixer", "strip_foot", ...)`).
  paw.ui.paint("mixer", "strip_foot", { buf = buf, x = x + 1, y = y, width = w - 1, track = id })
  local vol = draw.db_text(t.volume)
  buf:hit(x, y + 1, w, 1, { kind = "volume", track = id })
  buf:mark(
    "label",
    x + w - #vol,
    y + 1,
    #vol,
    1,
    { text = vol, style = selected and "Bright" or "TrackInfo", tone = selected and "text" or "text_2" }
  )
  local pan_w = math.min(7, w - 1)
  if not vca then
    buf:mark("knob", x + 1, y + 2, pan_w, 1, { value = t.pan or 0, hit = { kind = "pan", track = id } })
  end
  parts.fader, parts.rows, parts.vol, parts.pan, parts.pan_w, parts.chips = y - rows, rows, y + 1, y + 2, pan_w, y + 3
  local gap = w >= 8 and 1 or 0
  local function switches(list)
    for i, s in ipairs(list) do
      buf:mark("switch", x + 1 + (i - 1) * (1 + gap), y + 3, 1, 1, {
        letter = s[1],
        on = s[2] == true,
        style = s[3],
        tone = s[4],
        hit = { kind = "flag", track = id, flag = s[5] },
      })
    end
  end
  if vca then
    switches({ { "M", t.mute, "Mute", "mute", "mute" }, { "S", t.solo, "Solo", "solo", "solo" } })
    buf:text(x + 1, y + 2, "vca", "TrackIndex")
  elseif not t.master then
    switches({
      { "M", t.mute, "Mute", "mute", "mute" },
      { "S", t.solo, "Solo", "solo", "solo" },
      { "R", t.armed, "Armed", "rec", "armed" },
      { "I", t.monitor, "Monitor", "play_on", "monitor" },
    })
  else
    buf:text(x + 1, y + 3, "master", "TrackIndex")
  end
  parts.y = parts.fader
  parts.chip_gap = w >= 8 and 1 or 0
  return parts
end

--- Mark the row of the strip the cursor is on (`j` `k` move it): a mark
--- on the strip's left edge beside the row, or the chip itself lit. A row
--- the strip has no room to show is named in the title bar alone.
local function mark_row(buf, parts, row)
  local g = draw.g
  local y
  if row.kind == "insert" and parts.devices then
    y = parts.devices + math.min(row.index, parts.slots) - 1
  elseif row.kind == "send" and parts.sends and row.index <= 2 then
    y = parts.sends + row.index - 1
  elseif (row.kind == "insert" or row.kind == "send") and parts.compact then
    y = parts.compact
  elseif row.kind == "volume" then
    y = parts.vol
  elseif row.kind == "pan" then
    y = parts.pan
  end
  if y then
    -- Lit across the whole strip, brighter than the selected strip behind it.
    buf:fill(parts.x + 1, y, parts.w - 1, 1, nil, "CursorLine")
    return buf:text(parts.x, y, g.mark, "CursorLineMark")
  end
  if row.kind == "toggle" then
    local order = { mute = 0, solo = 1, armed = 2, monitor = 3 }
    buf:fill(parts.x + 1 + order[row.field] * (1 + parts.chip_gap), parts.chips, 1, 1, nil, "Cursor")
  end
end

--- The tracks in the order of the strips: VCAs after the others.
local function strip_order()
  local tracks, vcas = {}, {}
  for _, id in ipairs(paw.scope.tracks()) do
    local list = paw.vca.is_vca(id) and vcas or tracks
    list[#list + 1] = id
  end
  table.move(vcas, 1, #vcas, #tracks + 1, tracks)
  return tracks
end

function view:render(buf, ctx)
  local g = draw.g
  local tracks = strip_order()
  -- The row under the cursor, by name and value, on the right of the title.
  local row, row_track = paw.mixer_rows.current()
  local here
  if row and ctx.focused then
    local name, value = paw.mixer_rows.describe_row(row_track, row)
    here = name .. " " .. value
  end
  local body = paw.ui.titlebar(buf, {
    name = "Mixer",
    context = #tracks .. (#tracks == 1 and " track" or " tracks"),
    focused = ctx.focused,
    right = here,
  })
  local w, h = body.width, body.height
  body:fill(0, 0, w, h, " ", "TrackHeader")
  local sw = view.strip_width(w + 1)
  local room = math.max(1, math.floor((w - SCALE - sw - 1) / sw))
  local cursor_track = paw.cursor.track_id()
  local index = 1
  for i, id in ipairs(tracks) do
    if id == cursor_track then index = i end
  end
  -- On the master, the last tracks show beside it.
  if cursor_track == 0 then index = #tracks end
  if index <= self.scroll then self.scroll = index - 1 end
  if index > self.scroll + room then self.scroll = index - room end
  self.scroll = util.clamp(self.scroll, 0, math.max(0, #tracks - room))
  local x, shown, block, strips = SCALE, 0, nil, {}
  for col = 0, room - 1 do
    local id = tracks[self.scroll + col + 1]
    if not id then break end
    block = strip(
      body,
      x,
      api.track_get(id),
      self.scroll + col + 1,
      id == cursor_track,
      h,
      sw,
      id == cursor_track and ctx.focused and row or nil
    )
    if id == cursor_track and row and ctx.focused then mark_row(body, block, row) end
    strips[#strips + 1] = block
    x, shown = x + sw, shown + 1
  end
  -- The master, after the last track behind a heavier rule.
  body:fill(x, 0, 1, h, g.strip_sep, "Rule")
  -- The cursor reaches it too: `l` from the last strip, `$`.
  local on_master = cursor_track == 0
  local mst = strip(body, x + 1, api.track_get(0), nil, on_master, h, sw, on_master and ctx.focused and row or nil)
  if mst and on_master and row and ctx.focused then mark_row(body, mst, row) end
  block = mst or block
  strips[#strips + 1] = block
  -- The scale beside the first strip, on the rows the fader's cap takes.
  if block and block.rows >= 6 then
    local last = nil
    for _, mark in ipairs(marks) do
      local row = block.y + block.rows - 1 - fader_row(mark, block.rows)
      local label = (mark > 0 and "+" or "") .. mark
      if row ~= last then body:text(SCALE - 1 - #label, row, label, mark == 0 and "FaderZero" or "MeterScale") end
      last = row
    end
  end
  self.geometry = { sw = sw, shown = shown, strips = strips }
end

paw.ui.view("mixer", view)
return view
