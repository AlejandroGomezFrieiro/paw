-- The mixer as a grid, so that the grammar works on it as it does on the
-- timeline: `h` `l` go from strip to strip and `j` `k` along a strip's rows,
-- top to bottom as they are drawn: its devices (inserts), its sends, the
-- fader, the pan, then mute, solo, arm and the input monitor. `+` `-` (and
-- `Ctrl-a` `Ctrl-x` with a count) change the row under the cursor, `[` `]`
-- the strip's pan; `d` clears rows, `y` `p` copy them from strip to strip,
-- `gc` mutes, and a selection over strips does any of these to them all.
local api, util = paw.api, paw.util
local keymap = paw.keymap
local view = paw.ui.views:get("mixer")
local M = {}

local TOGGLES = { mute = "Mute", solo = "Solo", armed = "Arm", monitor = "Monitor" }

--- The rows of a track's strip, top to bottom: { key, kind, index }.
function M.rows(id)
  local t = api.track_get(id)
  local vca = t.meta and t.meta.vca == true
  local out = {}
  if not vca then
    for i, device in ipairs(t.devices or {}) do
      out[#out + 1] = { key = "insert" .. i, kind = "insert", index = i, device = device }
    end
    for i, send in ipairs(t.sends or {}) do
      out[#out + 1] = { key = "send" .. i, kind = "send", index = i, send = send }
    end
  end
  out[#out + 1] = { key = "volume", kind = "volume" }
  if not vca then out[#out + 1] = { key = "pan", kind = "pan" } end
  if not t.master then
    for _, field in ipairs(vca and { "mute", "solo" } or { "mute", "solo", "armed", "monitor" }) do
      out[#out + 1] = { key = field, kind = "toggle", field = field }
    end
  end
  return out
end

--- Where the cursor is along a track's strip: the row of the kind it was
--- last on, the nearest of its kind when this strip has fewer, or the fader.
local function index_on(id, key)
  local rows = M.rows(id)
  key = key or view.row or "volume"
  for i, row in ipairs(rows) do
    if row.key == key then return i, rows end
  end
  local kind, n = key:match("^(%a+)(%d+)$")
  local last
  for i, row in ipairs(rows) do
    if kind and row.kind == kind and row.index <= tonumber(n) then last = i end
  end
  if last then return last, rows end
  for i, row in ipairs(rows) do
    if row.key == "volume" then return i, rows end
  end
  return 1, rows
end

--- The row under the cursor, and the track it is on.
function M.current()
  local id = paw.cursor.track_id()
  if not id then return nil end
  local i, rows = index_on(id)
  return rows[i], id, i
end

--- Put the cursor on row `i` (1 for the top) of the cursor track's strip.
function M.to(i)
  local id = paw.cursor.track_id()
  if not id then return end
  local rows = M.rows(id)
  local row = rows[util.clamp(i, 1, #rows)]
  if row then view.row = row.key end
  api.ui_redraw()
end

--- What a row is called and holds, for the title bar and `K`.
function M.describe_row(id, row)
  local t = api.track_get(id)
  if row.kind == "volume" then return "volume", paw.draw.db_text(t.volume) end
  if row.kind == "pan" then return "pan", string.format("%+.2f", t.pan or 0) end
  if row.kind == "send" then
    local ok, to = pcall(api.track_get, row.send.target)
    return "send to " .. (ok and to.name or "?"), string.format("%+.1f dB", row.send.level)
  end
  if row.kind == "insert" then
    local ok, d = pcall(api.device_get, row.device)
    return "insert " .. row.index .. (ok and " " .. d.name or ""), ok and (d.bypass and "off" or "on") or ""
  end
  return TOGGLES[row.field]:lower(), t[row.field] and "on" or "off"
end

-- Changing rows --------------------------------------------------------------------

--- Move the value of a row by `steps`: decibels on the fader and the sends,
--- tenths on the pan, and on or off for the rest (`steps` above 0 is on).
local function nudge(id, row, steps)
  local track = paw.track(id)
  if row.kind == "volume" then
    track.volume = util.fader_db(track.volume, track.volume + steps)
  elseif row.kind == "pan" then
    track.pan = util.clamp(util.round(track.pan + 0.1 * steps, 0.01), -1, 1)
  elseif row.kind == "send" then
    local sends = api.track_get(id).sends
    local send = sends[row.index]
    if send then
      send.level = util.fader_db(send.level, send.level + steps)
      api.track_set(id, "sends", sends)
    end
  elseif row.kind == "insert" then
    paw.device(row.device).bypass = steps < 0
  elseif row.kind == "toggle" then
    track[row.field] = steps > 0
  end
end

--- Put a row back as a new track has it: the fader at 0 dB, the pan in the
--- middle, toggles off; a send or an insert is taken away.
local function clear(id, rows)
  local track = paw.track(id)
  local sends, devices = {}, {}
  for _, row in ipairs(rows) do
    if row.kind == "volume" then
      track.volume = 0
    elseif row.kind == "pan" then
      track.pan = 0
    elseif row.kind == "toggle" then
      track[row.field] = false
    elseif row.kind == "send" then
      sends[row.index] = true
    elseif row.kind == "insert" then
      devices[#devices + 1] = row.device
    end
  end
  -- From the last, so that the places of those before stay where they were.
  for i = #api.track_get(id).sends, 1, -1 do
    if sends[i] then paw.frontend.act.remove_send(id, i) end
  end
  for _, device in ipairs(devices) do
    paw.device(device):remove()
  end
end

--- What a row holds, to paste on another strip.
local function value_of(id, row)
  local t = api.track_get(id)
  if row.kind == "volume" or row.kind == "pan" then return t[row.kind] end
  if row.kind == "toggle" then return t[row.field] end
  if row.kind == "send" then return util.merge({}, row.send) end
  if row.kind == "insert" then return paw.device(row.device):snapshot() end
end

local function paste_row(id, entry)
  local track = paw.track(id)
  if entry.kind == "volume" or entry.kind == "pan" then
    track[entry.kind] = entry.value
  elseif entry.kind == "toggle" then
    track[entry.field] = entry.value
  elseif entry.kind == "send" then
    if entry.value.target == id then return end
    local sends, found = api.track_get(id).sends, false
    for _, send in ipairs(sends) do
      if send.target == entry.value.target then
        send.level, send.pre, found = entry.value.level, entry.value.pre, true
      end
    end
    if not found then sends[#sends + 1] = util.merge({}, entry.value) end
    api.track_set(id, "sends", sends)
  elseif entry.kind == "insert" then
    paw.restore_device(entry.value, track)
  end
end

-- Another project starts on the fader again.
paw.on("project.loaded", function() view.row = "volume" end)

-- The grid ------------------------------------------------------------------------------

--- The tracks whose strips a region covers.
local function strips(region)
  local list, out = paw.groups.rows(), {}
  for r = region.r0, region.r1 do
    if list[r] then out[#out + 1] = list[r] end
  end
  return out
end

--- The rows a region covers on a strip: whole strips take the row the
--- cursor is on, as `V` and a value key mean "this row on each strip".
local function rows_in(id, region)
  local rows = M.rows(id)
  if region.kind == "line" then
    local i = index_on(id)
    return { rows[i] }
  end
  -- A motion along the strip (`dj`) covers the row it lands on, as `j`
  -- covers whole lines in Vim; a selection ends where its extent says.
  local first = math.floor(region.c0 + 0.5)
  local last = region.visual and math.ceil(region.c1 - 0.5) - 1 or math.floor(region.c1 + 0.5)
  -- The columns count the rows of the strip the cursor is on; another strip
  -- may have more devices or sends, so its rows are found by what they are.
  local here = paw.cursor.track_id()
  local wanted = {}
  for i, row in ipairs(here and M.rows(here) or rows) do
    if i >= first and i <= math.max(first, last) then wanted[row.key] = true end
  end
  local out = {}
  for _, row in ipairs(rows) do
    if wanted[row.key] then out[#out + 1] = row end
  end
  return out
end

-- Rows are strips (tracks in the arrange view's order), columns the rows of
-- a strip from the top, counted from 1.
view.grid = {
  get = function()
    local id = paw.cursor.track_id()
    return paw.cursor.row() or 1, id and (index_on(id)) or 1
  end,
  set = function(row, col)
    local list = paw.groups.rows()
    local id = list[util.clamp(row, 1, math.max(1, #list))]
    -- The strip after the last track is the master's.
    if row > #list and paw.cursor.master_reachable() then id = 0 end
    local _, before = view.grid.get()
    if id and id ~= paw.cursor.track_id() then paw.cursor.set_track(id) end
    -- Going to another strip keeps the kind of row (the fader stays the
    -- fader); only a column that moved picks a row by its place.
    if col and math.floor(col + 0.5) ~= before then M.to(math.floor(col + 0.5)) end
  end,
  step = function() return 1 end,
  rows = true,
  -- Strips by name, the master's too, for `/`.
  search = function(text)
    local wanted, hits = text:lower(), {}
    local list = paw.groups.rows()
    local _, col = view.grid.get()
    for row, id in ipairs(list) do
      if api.track_get(id, "name"):lower():find(wanted, 1, true) then hits[#hits + 1] = { row = row, col = col } end
    end
    if api.track_get(0, "name"):lower():find(wanted, 1, true) then hits[#hits + 1] = { row = #list + 1, col = col } end
    return hits
  end,
  -- The row under the cursor is a cell: a selection takes it in.
  extent = function(_, col) return math.floor(col + 0.5) + 1 end,
}

-- Keys -------------------------------------------------------------------------------------

local map = keymap.set
local motion = { motion = true }
local far = { motion = true, jump = true }
local function mmap(lhs, rhs, desc, opts) map(lhs, rhs, util.merge({ view = "mixer", desc = desc }, opts)) end
local function count(n, ctx) return n * (ctx.count or 1) end

mmap("l", "cursor.down", "Next strip", motion)
mmap("h", "cursor.up", "Previous strip", motion)
mmap("<Right>", "cursor.down", "Next strip", motion)
mmap("<Left>", "cursor.up", "Previous strip", motion)
mmap("j", function(ctx)
  local _, _, i = M.current()
  if i then M.to(i + (ctx.count or 1)) end
end, "Down the strip: the next row", motion)
mmap("k", function(ctx)
  local _, _, i = M.current()
  if i then M.to(i - (ctx.count or 1)) end
end, "Up the strip: the row above", motion)
mmap("<Down>", function(ctx)
  local _, _, i = M.current()
  if i then M.to(i + (ctx.count or 1)) end
end, "Down the strip: the next row", motion)
mmap("<Up>", function(ctx)
  local _, _, i = M.current()
  if i then M.to(i - (ctx.count or 1)) end
end, "Up the strip: the row above", motion)
mmap("gg", function(ctx) M.to(ctx.count or 1) end, "The strip's top row, or row N", far)
mmap("G", function(ctx)
  local id = paw.cursor.track_id()
  if id then M.to(ctx.count or #M.rows(id)) end
end, "The strip's bottom row, or row N", far)
mmap("0", "cursor.first_track", "The first strip", far)
mmap("^", "cursor.first_track", "The first strip", far)
mmap("$", function(ctx)
  -- The master is the last strip; a count or a selection counts tracks only.
  if not ctx.count and paw.cursor.master_reachable() then return paw.cursor.set_track(0) end
  paw.commands.exec("cursor.last_track", ctx)
end, "The last strip: the master", far)
mmap("|", function(ctx)
  local list = paw.groups.rows()
  local id = list[util.clamp(ctx.count or 1, 1, math.max(1, #list))]
  if id then paw.cursor.set_track(id) end
end, "Strip N", far)
mmap("w", function(ctx) M.to_kind(1, ctx.count) end, "The next kind of row: inserts, sends, fader, toggles", motion)
mmap("b", function(ctx) M.to_kind(-1, ctx.count) end, "The kind of row before", motion)
mmap("e", function(ctx) M.to_kind_end(ctx.count) end, "The last row of this kind, or the next kind's", motion)

--- Go to the first row of the next (`dir` 1) or previous kind.
function M.to_kind(dir, n)
  local row, _, i = M.current()
  if not row then return end
  local rows = M.rows(paw.cursor.track_id())
  for _ = 1, n or 1 do
    local kind = rows[i].kind == "toggle" and "toggle" or rows[i].kind
    local j = i + dir
    while rows[j] and rows[j].kind == kind do
      j = j + dir
    end
    if not rows[j] then break end
    if dir < 0 then
      local k = rows[j].kind
      while rows[j - 1] and rows[j - 1].kind == k do
        j = j - 1
      end
    end
    i = j
  end
  M.to(i)
end

--- Move the mixer's cursor to the last row of its kind (or `n` kinds on).
function M.to_kind_end(n)
  local row, _, i = M.current()
  if not row then return end
  local rows = M.rows(paw.cursor.track_id())
  for _ = 1, n or 1 do
    local j = i
    if rows[j + 1] and rows[j + 1].kind ~= rows[j].kind then j = j + 1 end
    while rows[j + 1] and rows[j + 1].kind == rows[j].kind do
      j = j + 1
    end
    i = j
  end
  M.to(i)
end

-- The value under the cursor: `+` `-` and `Ctrl-a` `Ctrl-x`, with a count.
local function main(sign)
  return function(ctx)
    local row, id = M.current()
    if row then nudge(id, row, sign * (ctx.count or 1)) end
  end
end
local function second(sign)
  return function(ctx)
    local track = paw.cursor.track()
    if track and not (track:get().meta or {}).vca then
      track.pan = util.clamp(util.round(track.pan + count(0.1, ctx) * sign, 0.01), -1, 1)
    end
  end
end
mmap("+", main(1), "The row up: 1 dB, a tenth of pan, on", { role = "main+" })
mmap("-", main(-1), "The row down: 1 dB, a tenth of pan, off", { role = "main-" })
mmap("<C-a>", main(1), "The row up by the count", { role = "main+" })
mmap("<C-x>", main(-1), "The row down by the count", { role = "main-" })
mmap("]", second(1), "Pan right", { role = "second+" })
mmap("[", second(-1), "Pan left", { role = "second-" })
mmap("x", function(ctx)
  local row, id, i = M.current()
  if not row then return end
  local rows = M.rows(id)
  clear(id, { unpack(rows, i, math.min(#rows, i + (ctx.count or 1) - 1)) })
end, "Clear the row: 0 dB, centre, off; a send or insert goes")
mmap("<CR>", function()
  local row = M.current()
  if not row then return end
  if row.kind == "volume" then return paw.commands.exec("track.volume.set") end
  if row.kind == "pan" then return paw.commands.exec("track.pan.set") end
  local _, id = M.current()
  if row.kind == "insert" then
    if not paw.device(row.device).editor then return paw.notify("this device has no window of its own", "warn") end
    return api.device_editor(row.device)
  end
  if row.kind == "send" then
    local name = M.describe_row(id, row)
    return paw.ui.ask_value({ label = name, now = row.send.level, unit = "dB", min = -60, max = 6 }, function(v)
      local sends = api.track_get(id).sends
      if sends[row.index] then
        sends[row.index].level = v
        api.track_set(id, "sends", sends)
      end
    end)
  end
  paw.track(id)[row.field] = not api.track_get(id, row.field)
end, "Type the row's value, switch it, or show the insert's window")

--- The curve of the row under the cursor, for `gC` and `:curve.open`.
function view:curve_uri()
  local row, id = M.current()
  if row and (row.kind == "volume" or row.kind == "pan") then
    return paw.address.lane(paw.track(id):automate(row.kind).id)
  end
  return nil, "only the fader and the pan have curves here"
end
mmap("gC", "curve.open", "Edit the row's automation curve (the fader or the pan)")

--- What `K` shows before the track: the row under the cursor.
function view:describe()
  local row, id = M.current()
  if not row then return nil end
  local name, value = M.describe_row(id, row)
  return { { text = "Row  " .. name .. "  " .. value, style = "Title" }, "" }
end

--- The insert under the cursor, for `ge`.
function M.device()
  local row = M.current()
  return row and row.kind == "insert" and paw.device(row.device) or nil
end

-- Operators over strips and rows.
local function op(lhs, fn, desc, opts) keymap.operator(lhs, fn, util.merge({ view = "mixer", desc = desc }, opts)) end
local function each(region, fn)
  for _, id in ipairs(strips(region)) do
    fn(id, rows_in(id, region))
  end
end
op("d", function(region, ctx)
  if region.kind == "line" and region.r0 > #paw.groups.rows() then
    return paw.notify("the master's strip stays: `x` clears a row of it", "warn")
  end
  if region.kind == "line" then
    local first = region.r0
    keymap.setreg(paw.edit.arrange.delete(region), ctx.register)
    local list = api.track_list()
    if #list > 0 then paw.cursor.set_track(paw.groups.rows()[util.clamp(first, 1, #paw.groups.rows())]) end
    return
  end
  each(region, clear)
end, "Delete: whole strips cut the tracks, rows go back to how a new track has them")
op("y", function(region, ctx)
  if region.kind == "line" then return keymap.setreg(paw.edit.arrange.yank(region), ctx.register, true) end
  local id = strips(region)[1]
  if not id then return end
  local out = {}
  for _, row in ipairs(rows_in(id, region)) do
    out[#out + 1] = { kind = row.kind, field = row.field, value = value_of(id, row) }
  end
  keymap.setreg({ kind = "mixrows", rows = out }, ctx.register, true)
  paw.notify(#out .. (#out == 1 and " row" or " rows") .. " yanked")
end, "Yank: whole strips their tracks, rows their settings")
op("gc", function(region)
  local ids = strips(region)
  local all = #ids > 0
  for _, id in ipairs(ids) do
    all = all and api.track_get(id, "mute")
  end
  for _, id in ipairs(ids) do
    paw.track(id).mute = not all
  end
end, "Mute or unmute the strips", { role = "mute" })

local function paste(before)
  return function(ctx)
    local value = keymap.getreg(ctx.register)
    if value and value.kind == "mixrows" then
      local id = paw.cursor.track_id()
      if id then
        for _, entry in ipairs(value.rows) do
          paste_row(id, entry)
        end
      end
      return
    end
    paw.edit.arrange.paste(value, before, ctx.count)
  end
end
mmap("p", paste(false), "Paste rows' settings on this strip, or tracks after it")
mmap("P", paste(true), "Paste rows' settings on this strip, or tracks before it")

-- On a selection: the value keys act on every strip and row selected.
local function vop(lhs, fn, desc, role)
  map(lhs, nil, { view = "mixer", mode = "x", desc = desc, role = role, operator = fn })
end
local function each_value(sign)
  return function(region, ctx)
    each(region, function(id, rows)
      for _, row in ipairs(rows) do
        nudge(id, row, sign * (ctx.count or 1))
      end
    end)
  end
end
vop("+", each_value(1), "The rows selected up", "main+")
vop("-", each_value(-1), "The rows selected down", "main-")
vop("<C-a>", each_value(1), "The rows selected up by the count", "main+")
vop("<C-x>", each_value(-1), "The rows selected down by the count", "main-")
local function each_pan(sign)
  return function(region, ctx)
    for _, id in ipairs(strips(region)) do
      local track = paw.track(id)
      if not (api.track_get(id, "meta") or {}).vca then
        track.pan = util.clamp(util.round(track.pan + count(0.1, ctx) * sign, 0.01), -1, 1)
      end
    end
  end
end
vop("]", each_pan(1), "Pan the strips selected right", "second+")
vop("[", each_pan(-1), "Pan the strips selected left", "second-")
vop("x", function(region) each(region, clear) end, "Clear the rows selected")
vop("p", function(region, ctx)
  local value = keymap.getreg(ctx.register)
  if not (value and value.kind == "mixrows") then
    return paw.notify("no rows in the register: `y` on some first", "warn")
  end
  for _, id in ipairs(strips(region)) do
    for _, entry in ipairs(value.rows) do
      paste_row(id, entry)
    end
  end
end, "Paste the rows' settings on every strip selected")

-- The keys the mixer had before the rule (`paw.opt.keys = "classic"`).
local classic = keymap.classic
local function cmap(lhs, rhs, desc, opts) classic(lhs, rhs, util.merge({ view = "mixer", desc = desc }, opts)) end
cmap("k", "track.volume by=1", "Volume up 1 dB", { mode = "n" })
cmap("j", "track.volume by=-1", "Volume down 1 dB", { mode = "n" })
cmap(">", "track.pan by=0.1", "Pan right")
cmap("<lt>", "track.pan by=-0.1", "Pan left")
cmap("gg", "cursor.first_track", "First track, or track N", { motion = true, linewise = true, jump = true })
cmap("G", "cursor.last_track", "Last track, or track N", { motion = true, linewise = true, jump = true })

return M
