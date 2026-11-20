-- Markers and regions: named places and named stretches of the song.
--
-- A marker is a beat with a name; a region is a marker with a length. They
-- belong to the project (`project.meta.markers`), move with the beats when
-- the tempo changes, are saved with it and undone like any edit.
--
--   :marker Chorus          -- a marker at the cursor
--   :region Verse           -- a region over the selection, or over the loop
--   ]' and ['               -- the next marker or region start, the one before
--   :marker.list            -- all of them; choose one to go there
--   :region.loop Verse      -- loop a region
--   :render out.wav range=Verse     -- a region is a range to render
--   :render.regions out/    -- every region to a file of its own
--
-- In scripts: `paw.markers.add(16, "Chorus")`, `paw.markers.add(0, "Intro", { length = 16 })`,
-- `paw.markers.list()`, `paw.markers.find("Chorus")`, `paw.markers.remove(id)`.
local api = paw.api
local M = {}

--- Each marker and region, in order of time: { id, beat, name, length, color }.
--- A region has a `length` in beats. A marker has no length.
function M.list()
  local list = api.project_get().meta.markers
  if type(list) ~= "table" then return {} end
  local out = {}
  for i, m in ipairs(list) do out[i] = m end
  table.sort(out, function(a, b)
    if a.beat ~= b.beat then return a.beat < b.beat end
    return a.id < b.id
  end)
  return out
end

local function save(list)
  local meta = api.project_get().meta
  meta.markers = #list > 0 and list or nil
  api.project_set("meta", meta)
end

--- The regions alone.
function M.regions()
  local out = {}
  for _, m in ipairs(M.list()) do
    if m.length then out[#out + 1] = m end
  end
  return out
end

--- What a marker is called on screen: its name, or its number in the song.
function M.label(marker)
  if marker.name and marker.name ~= "" then return marker.name end
  for i, m in ipairs(M.list()) do
    if m.id == marker.id then return tostring(i) end
  end
  return "?"
end

--- Add a marker at a beat. With `opts.length`, add a region from there. Returns it.
function M.add(beat, name, opts)
  opts = opts or {}
  assert(type(beat) == "number" and beat >= 0, "a marker is at a beat from 0 up")
  if opts.length ~= nil then assert(type(opts.length) == "number" and opts.length > 0, "a region has a length above 0") end
  local list, id = M.list(), 1
  for _, m in ipairs(list) do id = math.max(id, m.id + 1) end
  local marker = { id = id, beat = beat, name = name and tostring(name) or "", length = opts.length, color = opts.color }
  list[#list + 1] = marker
  save(list)
  return marker
end

--- The marker or region of a number (its place in the song), of an id
--- given as `{ id = n }`, or of a name. Nil if there is none.
function M.find(which)
  local list = M.list()
  if type(which) == "table" then
    for _, m in ipairs(list) do
      if m.id == which.id then return m end
    end
    return nil
  end
  local n = tonumber(which)
  if n and list[n] then return list[n] end
  local name = tostring(which):lower()
  for _, m in ipairs(list) do
    if m.name:lower() == name then return m end
  end
  for _, m in ipairs(list) do
    if m.name ~= "" and m.name:lower():find(name, 1, true) == 1 then return m end
  end
end

--- A region by number, id or name.
function M.region(which)
  local m = M.find(which)
  if m and m.length then return m end
  -- A marker and a region may share a name: the region is the one meant.
  local name = tostring(which):lower()
  for _, r in ipairs(M.regions()) do
    if r.name:lower() == name then return r end
  end
end

--- Change a marker: `fields` may hold beat, name, length (false makes a
--- region a marker again) and color.
function M.set(id, fields)
  local list, found = M.list(), nil
  for _, m in ipairs(list) do
    if m.id == id then
      found = m
      if fields.beat then m.beat = math.max(0, fields.beat) end
      if fields.name then m.name = tostring(fields.name) end
      if fields.length ~= nil then m.length = fields.length and math.max(1e-6, fields.length) or nil end
      if fields.color ~= nil then m.color = fields.color or nil end
    end
  end
  if not found then error("no marker " .. tostring(id), 2) end
  save(list)
  return found
end

--- Remove a marker by id.
function M.remove(id)
  local list, gone = {}, false
  for _, m in ipairs(M.list()) do
    if m.id == id then gone = true else list[#list + 1] = m end
  end
  if gone then save(list) end
  return gone
end

--- The marker or region start nearest a beat within `reach` beats (half a
--- grid step by default), or the region the beat is inside.
function M.at(beat, reach)
  reach = reach or paw.opt.grid / 2
  local best, far
  for _, m in ipairs(M.list()) do
    local d = math.abs(m.beat - beat)
    if d <= reach and (not far or d < far) then best, far = m, d end
  end
  if best then return best end
  for _, m in ipairs(M.list()) do
    if m.length and beat >= m.beat and beat < m.beat + m.length then best = m end
  end
  return best
end

--- The first marker after a beat, and the last before it.
function M.next(beat)
  for _, m in ipairs(M.list()) do
    if m.beat > beat + 1e-9 then return m end
  end
end

--- The last marker before a beat, or nil.
function M.prev(beat)
  local found
  for _, m in ipairs(M.list()) do
    if m.beat < beat - 1e-9 then found = m end
  end
  return found
end

-- A region is a range to render: `paw.render(path, { range = "Verse" })`.
do
  local ranges = require("paw.render").ranges
  setmetatable(ranges, {
    __index = function(_, name)
      local region = M.region(name)
      if region then return function() return region.beat, region.beat + region.length end end
    end,
  })
end

--- Render every region to a file of its own in `dir`, named after it:
--- `01 Intro.wav`. `opts` is as for `paw.render`, plus `format` ("wav",
--- "flac", "mp3", "ogg" or "opus"). Returns the files.
function M.render_regions(dir, opts)
  opts = opts or {}
  local regions = M.regions()
  if #regions == 0 then error("there are no regions to render: `:region name` makes one", 0) end
  pcall(paw.api.fs_mkdir, dir)
  local files = {}
  for i, region in ipairs(regions) do
    local each = {}
    for k, v in pairs(opts) do each[k] = v end
    each.format, each.range = nil, nil
    each.start, each["end"] = region.beat, region.beat + region.length
    local name = M.label(region):gsub("[/%z]", "_")
    files[i] = string.format("%s/%02d %s.%s", dir, i, name, opts.format or "wav")
    paw.render(files[i], each)
  end
  return files
end

-- Commands -----------------------------------------------------------------------

local function describe(m)
  return (m.length and "region " or "marker ") .. "“" .. M.label(m) .. "” at " .. paw.time.format(m.beat)
end

local function names()
  local out = {}
  for _, m in ipairs(M.list()) do
    if m.name ~= "" then out[#out + 1] = m.name end
  end
  return out
end

--- The marker a command is about: the one named (or given as `id=`, as a
--- frontend's menus do), or the one at the cursor.
local function wanted(ctx, regions_only)
  if ctx.args.id then
    local m = M.find({ id = tonumber(ctx.args.id) })
    if not m then paw.notify("that marker is gone", "warn") end
    return m
  end
  local word = ctx.args[1] and table.concat(ctx.args, " ")
  local m
  if word then
    m = regions_only and M.region(word) or M.find(word)
    if not m then paw.notify("no " .. (regions_only and "region" or "marker") .. " `" .. word .. "`", "warn") end
  else
    m = M.at(paw.cursor.beat)
    if m and regions_only and not m.length then m = nil end
    if not m then paw.notify("no " .. (regions_only and "region" or "marker") .. " at the cursor", "warn") end
  end
  return m
end

--- A name for a new marker that has none: "Marker 3" for the third.
function M.default_name()
  local taken, n = {}, #M.list() + 1
  for _, m in ipairs(M.list()) do taken[m.name] = true end
  while taken["Marker " .. n] do n = n + 1 end
  return "Marker " .. n
end

paw.command("marker", function(ctx)
  local name = table.concat(ctx.args, " "):match("^%s*(.-)%s*$")
  if name == "" then name = M.default_name() end
  local m = M.add(tonumber(ctx.args.at) or paw.cursor.beat, name)
  paw.notify(describe(m))
end, { desc = "Put a marker at the cursor: `marker Chorus`; alone, it is called Marker 1, Marker 2...; `at=` a beat instead" })

paw.command("marker.new", function()
  local beat = paw.cursor.beat
  paw.ui.input({ prompt = "Marker name: ", text = M.default_name(), label = "Put a marker" }, function(name)
    paw.commands.run("marker", { name, at = beat })
  end)
end, { desc = "Put a marker at the cursor, asking for its name (Marker 1, Marker 2... if none is typed)" })

paw.command("marker.remove", function(ctx)
  local m = wanted(ctx)
  if not m then return end
  M.remove(m.id)
  paw.notify("removed the " .. describe(m))
end, { desc = "Remove the marker or region at the cursor, or the one named or numbered: `marker.remove Chorus`", complete = names })

paw.command("marker.rename", function(ctx)
  local m = ctx.args.id and M.find({ id = tonumber(ctx.args.id) }) or M.at(paw.cursor.beat)
  if not m then return paw.notify("no marker at the cursor", "warn") end
  if ctx.args[1] then return M.set(m.id, { name = table.concat(ctx.args, " ") }) end
  paw.ui.input({ prompt = (m.length and "Region" or "Marker") .. " name: ", text = m.name }, function(name)
    M.set(m.id, { name = name })
  end)
end, { desc = "Name the marker or region at the cursor: `marker.rename Bridge`; alone, asks" })

-- For a frontend, where a marker is dragged: `marker.set id=3 beat=17.5`.
paw.command("marker.set", function(ctx)
  local id = tonumber(ctx.args.id)
  if not (id and M.find({ id = id })) then return paw.notify("that marker is gone", "warn") end
  M.set(id, { beat = tonumber(ctx.args.beat), length = tonumber(ctx.args.length), name = ctx.args.name and tostring(ctx.args.name) })
end, { desc = "Move or change a marker by its id: `marker.set id=3 beat=16`" })

paw.command("marker.move", function()
  local m = M.at(paw.cursor.beat, math.huge)
  if not m then return paw.notify("there are no markers", "warn") end
  M.set(m.id, { beat = paw.cursor.beat })
end, { desc = "Bring the nearest marker to the cursor" })

paw.command("marker.next", function(ctx)
  local beat = paw.cursor.beat
  for _ = 1, ctx.count or 1 do
    local m = M.next(beat)
    if not m then break end
    beat = m.beat
  end
  paw.cursor.set_beat(beat)
end, { desc = "Go to the next marker or region start" })

paw.command("marker.prev", function(ctx)
  local beat = paw.cursor.beat
  for _ = 1, ctx.count or 1 do
    local m = M.prev(beat)
    if not m then break end
    beat = m.beat
  end
  paw.cursor.set_beat(beat)
end, { desc = "Go to the marker or region start before the cursor" })

paw.command("marker.goto", function(ctx)
  local m = wanted(ctx)
  if m then paw.cursor.set_beat(m.beat) end
end, { desc = "Go to a marker or region by number or name: `marker.goto 3`, `marker.goto Chorus`", complete = names })

paw.command("marker.list", function()
  local list = M.list()
  if #list == 0 then return paw.notify("there are no markers: `:marker name` puts one at the cursor") end
  local items = {}
  for i, m in ipairs(list) do
    local where = paw.time.format(m.beat)
    if m.length then where = where .. " – " .. paw.time.format(m.beat + m.length) end
    items[i] = { text = string.format("%2d  %-7s %-24s %s", i, m.length and "region" or "marker", M.label(m), where), beat = m.beat,
      name = M.label(m), kind = m.length and "region" or "marker" }
  end
  paw.pick({ title = "Markers and regions", items = items, on_choose = function(item) paw.cursor.set_beat(item.beat) end,
    -- What is typed finds a name, not the number of the line: `Chorus 2`.
    search = function(item) return item.name .. " " .. item.kind end,
    primary = function(item) return item.name end })
end, { desc = "List the markers and regions; choose one to go there" })

paw.command("region", function(ctx)
  local from, to
  local sel = paw.keymap.selection()
  if sel and sel.c0 and sel.c1 and sel.c1 > sel.c0 then
    from, to = sel.c0, sel.c1
  else
    local t = api.transport_get()
    if t.loop_end > t.loop_start then from, to = t.loop_start, t.loop_end end
  end
  if not from then return paw.notify("a region is made over the selection or the loop: select a stretch of time first", "warn") end
  local m = M.add(from, table.concat(ctx.args, " "), { length = to - from })
  paw.notify(describe(m) .. ", " .. string.format("%g", to - from) .. " beats")
end, { desc = "Make a region over the selection, or over the loop: `region Verse`" })

paw.command("region.remove", function(ctx)
  local m = wanted(ctx, true)
  if not m then return end
  M.remove(m.id)
  paw.notify("removed the " .. describe(m))
end, { desc = "Remove the region at the cursor, or the one named", complete = names })

paw.command("region.loop", function(ctx)
  local m = wanted(ctx, true)
  if not m then return end
  local t = paw.transport
  t.loop_start, t.loop_end, t.loop_enabled = m.beat, m.beat + m.length, true
  paw.notify("looping " .. describe(m))
end, { desc = "Loop the region at the cursor, or the one named: `region.loop Verse`", complete = names })

paw.command("render.regions", function(ctx)
  local dir = ctx.args[1]
  if not dir then return paw.notify("render.regions: which directory? `render.regions out`", "warn") end
  local opts = {}
  for k, v in pairs(ctx.args) do
    if type(k) == "string" then opts[k] = v end
  end
  opts.background = api.ui_attached() or nil
  local files = M.render_regions(dir, opts)
  paw.notify(string.format("rendering %d region%s into %s", #files, #files == 1 and "" or "s", dir))
end, { desc = "Render every region to a file of its own: `render.regions out`, `render.regions out format=flac bits=24`, `render.regions out format=mp3 quality=best`" })

-- On the arrange view's ruler ------------------------------------------------------

local function draw(view, layer)
  local list = M.list()
  if #list == 0 then return end
  local ruler = layer.ruler2 or layer.ruler
  local width = ruler.width
  -- Regions first, as bands; then every name where it starts, each given
  -- the room up to the next one.
  for _, m in ipairs(list) do
    if m.length then
      local x0, x1 = math.max(0, layer.x(m.beat)), math.min(width, layer.x(m.beat + m.length))
      if x1 > x0 then ruler:fill(x0, 0, x1 - x0, 1, " ", "Region") end
    end
  end
  for i, m in ipairs(list) do
    local x = layer.x(m.beat)
    local stop = width
    for j = i + 1, #list do
      local nx = layer.x(list[j].beat)
      if nx > x then stop = math.min(stop, nx) break end
    end
    if x >= 0 and x < width and stop > x then
      local text = (m.length and "▏" or "▼") .. M.label(m)
      -- Cut where the next one starts; nothing is padded over a region's band.
      if api.str_width(text) > stop - x then text = paw.util.fit(text, stop - x) end
      ruler:text(x, 0, text, m.length and "RegionName" or "Marker")
    end
  end
end

local arrange = paw.ui.views.arrange
if arrange and arrange.layers then
  arrange.layers.timeline_markers = draw
  arrange.ruler2.timeline_markers = function() return #M.list() > 0 end
end

return M
