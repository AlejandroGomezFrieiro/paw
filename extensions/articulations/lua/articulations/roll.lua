-- The piano roll set up by a track's map: the playable range shaded, the
-- keyswitch rows labelled with their articulations, each note's tag and
-- colour, a band of the articulation in time above the ruler, the pen new
-- notes are entered with, and `K` saying what a note plays.
local api = paw.api
local util = paw.util
local art = require("articulations")
local m2 = art.m2

local M = {}
local roll = paw.ui.views.pianoroll

local function palette() return require("paw.theme").palette end

local function styles()
  local c, mix = palette(), paw.draw.mix
  paw.ui.hl("ArtOutOfRange", { fg = c.line, bg = "#08090b" })
  paw.ui.hl("ArtUncomfortable", { fg = c.line, bg = mix(c.bg, "#08090b", 0.5) })
  paw.ui.hl("ArtKeyswitchRow", { fg = c.line, bg = mix(c.bg, c.accent, 0.07) })
  paw.ui.hl("ArtBand", { fg = c.dim, bg = c.bg_alt })
  paw.ui.hl("ArtBandEdge", { fg = c.line_hi, bg = c.bg_alt })
end
styles()
paw.on("theme.changed", styles)

--- The keyswitch keys of a map: `{ [pitch] = art }`.
function M.keyswitch_keys(map)
  if map.keyswitch_keys then return map.keyswitch_keys end
  local keys = {}
  map.keyswitch_keys = keys
  for _, a in ipairs(map.arts) do
    for _, e in ipairs(a.events) do
      if (e.type == "note" or e.type == "hold") and not keys[e.key] then keys[e.key] = a end
    end
  end
  return keys
end

local function inside(range, pitch) return range and pitch >= range[1] and pitch <= range[2] end

--- What a map says of a row: a keyswitch's label, or a shade outside the
--- playable or comfortable range.
function M.row(map, pitch)
  local keys = M.keyswitch_keys(map)
  local a = keys[pitch]
  if a then return { label = a.tag, style = paw.draw.hue(a.colour).note, shade = "ArtKeyswitchRow", art = a } end
  if inside(map.keyswitches, pitch) then return { shade = "ArtKeyswitchRow" } end
  if map.range and not inside(map.range, pitch) then return { shade = "ArtOutOfRange" } end
  if map.comfortable and not inside(map.comfortable, pitch) then return { shade = "ArtUncomfortable" } end
end

roll.rows("articulations", function(pitch, track)
  local map = art.map_of(track)
  return map and M.row(map, pitch)
end)

-- The tags and colours of the notes, over the roll's own notes.
roll.layer("articulations", 22, function(L)
  for _, part in ipairs(L.parts) do
    local track = part.track
    local chosen = {}
    for _, place in ipairs(paw.frontend.chosen_notes(part.id)) do
      chosen[place] = true
    end
    local shown, places = part.clip:notes({
      from = L.from - part.offset,
      to = L.to - part.offset,
      low = math.max(0, L.top - L.rows + 1),
      high = L.top,
    })
    for k, note in ipairs(shown) do
      local attr = art.attr_of(note)
      if attr then
        local tag, a = art.tag_of(track, note)
        local row = L.top - note.pitch
        local x0, x1 = L.x(note.start + part.offset), L.x(note.start + part.offset + note.length)
        local nw = math.max(1, x1 - x0)
        local at_cursor = L.under_part and L.under_part.id == part.id and places[k] == L.under_place
        local style
        if at_cursor then
          style = "NoteCursor"
        elseif chosen[places[k]] then
          style = paw.draw.track_hue(api.track_get(track)).title_cur
        else
          style = paw.draw.note_style(paw.draw.hue(a and a.colour or art.maps.colour()), note.velocity)
          L.roll:fill(x0, row, nw, 1, " ", style)
          L.roll:text(x0, row, paw.draw.g.clip_start, style)
        end
        if nw >= 3 and tag then L.roll:text(x0 + 1, row, util.fit(tag, nw - 1):gsub("%s+$", ""), style) end
      end
    end
  end
end)

--- The articulation of the active clip in time, as segments `{ from, to,
--- tag, art }` (roll beats): the top line's, a new segment where it changes.
function M.segments(clip)
  local c = clip:get()
  local default = art.default_of(c.track)
  local out = {}
  local notes = clip:notes()
  -- The top line: of the notes that start together, the highest.
  local tops = {}
  for _, n in ipairs(notes) do
    local last = tops[#tops]
    if last and math.abs(last.start - n.start) < 1e-9 then
      if n.pitch > last.pitch then tops[#tops] = n end
    else
      tops[#tops + 1] = n
    end
  end
  for _, n in ipairs(tops) do
    local tag, a = art.tag_of(c.track, n)
    if not tag then
      tag, a = default and default.tag, default
    end
    tag = tag or "·"
    local last = out[#out]
    if last and last.tag == tag then
      last.to = n.start + n.length
    else
      if last then last.to = math.max(last.to, n.start) end
      out[#out + 1] = { from = n.start, to = n.start + n.length, tag = tag, art = a }
    end
  end
  return out
end

roll.band("articulations", 10, {
  title = "art",
  active = function(clip)
    local c = clip:get()
    return art.map_of(c.track) ~= nil
  end,
  paint = function(buf, B)
    buf:fill(0, 0, B.width, 1, " ", "ArtBand")
    local line = paw.opt.ascii and "-" or "─"
    local edge = paw.opt.ascii and "|" or "│"
    for _, s in ipairs(M.segments(B.clip)) do
      local x0, x1 = B.x(s.from), B.x(s.to)
      if x1 > 0 and x0 < B.width then
        local style = s.art and paw.draw.hue(s.art.colour).fg or "ArtBand"
        buf:fill(math.max(0, x0), 0, math.max(0, math.min(B.width, x1) - math.max(0, x0)), 1, line, style)
        if x0 >= 0 then buf:text(x0, 0, edge .. s.tag, style) end
      end
    end
    -- The pen, at the right.
    local pen = art.pen(B.data.track)
    if pen then
      local text = " pen " .. (pen.art and pen.art.tag or m2.code(pen.attr)) .. " "
      buf:text(math.max(0, B.width - api.str_width(text)), 0, text, "ArtBandEdge")
    end
  end,
})

-- `K` on a note.
roll.describer("articulations", function(note, part)
  local track = part and part.track
  if not track then return nil end
  local attr = art.attr_of(note)
  local map = art.map_of(track)
  -- Without a map the roll's own line says the attribute.
  if not map then return nil end
  if not attr then
    local d = art.default_of(track, map)
    local lines = { "  articulation  none: the track's default plays, " .. (d and d.name or "?"), articulation = true }
    local delay = d and d.delay or map.delay
    if delay then lines[2] = "  delay         " .. art.maps.delay_text(delay) end
    return lines
  end
  local a, exact = art.resolve(map, attr)
  if not a then
    return { "  articulation  " .. m2.describe(attr) .. ", which " .. map.name .. " cannot play", articulation = true }
  end
  -- As the map writes it; in paw's key names too when they differ (a map
  -- whose `middle_c` is C3, a track whose keyswitches are shifted).
  local send = a.send or a.out
  local sent = a.out ~= "" and ", sent as " .. a.out or ""
  if send ~= "" and send ~= a.out then
    sent = a.out ~= "" and (", sent as " .. send .. " (" .. a.out .. " in the map)") or (", sent as " .. send)
  end
  local how = exact and "" or ", played as " .. a.name .. " (" .. a.code .. ") by M2-123's fallback"
  local lines = {
    "  articulation  " .. (exact and a.name .. " (" .. a.code .. ")" or m2.describe(attr)) .. how .. sent,
    articulation = true,
  }
  local delay = a.delay or map.delay
  if delay then
    lines[2] = "  delay         " .. art.maps.delay_text(delay) .. (a.delay and "" or " (the instrument's)")
  end
  return lines
end)

-- The piano roll's pencil (`a` in insert mode) takes its articulations
-- from here: the names of the track's map (or the words libraries use,
-- without a map), and the fields that give a note one.
if paw.roll_draw and paw.roll_draw.articulation then
  paw.roll_draw.articulation({
    names = function(track)
      local map = art.map_of(track)
      local out, seen = {}, {}
      local function add(name)
        if name and not seen[name] then
          seen[name], out[#out + 1] = true, name
        end
      end
      if map then
        for _, a in ipairs(map.arts) do
          add(a.id)
          add(a.name)
        end
      else
        for _, w in ipairs(m2.words) do
          add(w[1])
        end
      end
      add("none")
      return out
    end,
    apply = function(track, text, note)
      local choice, why = art.lookup(art.map_of(track), text)
      if choice == nil then return nil, why end
      return art.attr_fields(note, choice and choice.attr or nil)
    end,
  })
end

-- New notes take the pen of their track.
roll.entering("articulations", function(note, clip)
  local pen = art.pen(clip:get().track)
  if pen then
    for k, v in pairs(art.attr_fields(note, pen.attr)) do
      note[k] = v
    end
  end
end)

return M
