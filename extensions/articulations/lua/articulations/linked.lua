-- Linked controllers: what an instrument plays from several controllers at
-- once (dynamics on CC1 and CC11, each through a curve of its own) drawn
-- as one lane. The map names them:
--
--   [linked]
--   dynamics = { cc = [1, 11], curve = ["linear", "0:0.3 1:1"], default = 0.7 }
--
-- and the lane is a curve of its own address (`paw.curves`):
-- `paw://clip/7/control/cc/1#linked=dynamics`, opened in the curve view
-- (`\c`, `:art.lane`) like any curve, drawn and edited with its keys;
-- every point written writes every controller of the link through its
-- curve, in one edit. With no moves the lane stands at the instrument's
-- `default`, and a drawing that starts after the clip's start begins it
-- there.
local api = paw.api
local util = paw.util
local art = require("articulations")

local M = {}

--- The value `x` (0..1) a curve gives `y` for, by halving: curves are
--- taken to rise.
local function inverse(fn, y)
  local lo, hi = 0, 1
  for _ = 1, 30 do
    local mid = (lo + hi) / 2
    if fn(mid) < y then
      lo = mid
    else
      hi = mid
    end
  end
  return (lo + hi) / 2
end
M.inverse = inverse

--- The linked controllers of a part's map by id, or nil.
function M.entry(part, id)
  local map = art.map_of(part)
  for _, l in ipairs(map and map.linked or {}) do
    if l.id == id or id == nil then return l, map end
  end
end

--- The address of a linked lane of a clip.
function M.uri(clip_id, entry)
  return "paw://clip/" .. clip_id .. "/control/cc/" .. entry.cc[1] .. "#linked=" .. entry.id
end

paw.curves.provide("articulations.linked", function(uri, parts)
  if parts.kind ~= "control" or not parts.fragment then return nil end
  local id = parts.fragment:match("^linked=([%w_%-]+)$")
  if not id then return nil end
  local c = api.clip_get(parts.clip)
  local entry = M.entry(c.part, id)
  if not entry then return nil, "the part's map links no controllers as `" .. id .. "`" end
  local mine = {}
  for _, n in ipairs(entry.cc) do
    mine[n] = true
  end
  local t = {
    uri = uri,
    kind = "control",
    clip = parts.clip,
    part = c.part,
    linked = entry,
    shapes = { hold = true },
    min = 0,
    max = 1,
    lo = 0,
    hi = 1,
    step = 1 / 127,
    scale = 127,
  }
  local ccs = {}
  for i, n in ipairs(entry.cc) do
    ccs[i] = "CC" .. n
  end
  t.name = function() return entry.name .. " (" .. table.concat(ccs, " ") .. ") · " .. api.clip_get(parts.clip).name end
  t.format = function(v) return tostring(math.floor(v * 127 + 0.5)) end
  t.flat = entry.default and function() return entry.default end or nil
  -- The lane is read back from its first controller, through that one's curve.
  t.points = function()
    local start = api.clip_get(parts.clip).start
    local out = {}
    for _, ctl in ipairs(api.clip_controls(parts.clip)) do
      if ctl.type == "cc" and ctl.number == entry.cc[1] and not ctl.key then
        out[#out + 1] =
          { beat = start + ctl.start, value = inverse(entry.curves[1], ctl.value), shape = "hold", tension = 0 }
      end
    end
    return out
  end
  t.write = function(points)
    local cl = api.clip_get(parts.clip)
    local list = {}
    for _, ctl in ipairs(api.clip_controls(parts.clip)) do
      if not (ctl.type == "cc" and mine[ctl.number] and not ctl.key) then list[#list + 1] = ctl end
    end
    local first = points[1]
    if first and entry.default and first.beat > cl.start + 1e-9 then
      table.insert(points, 1, { beat = cl.start, value = entry.default })
    end
    for _, q in ipairs(points) do
      local v = util.clamp(q.value, 0, 1)
      for i, n in ipairs(entry.cc) do
        list[#list + 1] =
          { start = q.beat - cl.start, type = "cc", number = n, value = util.clamp(entry.curves[i](v), 0, 1) }
      end
    end
    table.sort(list, function(a, b)
      if a.start ~= b.start then return a.start < b.start end
      return (a.number or -1) < (b.number or -1)
    end)
    api.clip_set_controls(parts.clip, list)
  end
  return t
end)

--- Open a linked lane of the roll's clip (the map's first, or by id) in the curve view.
function M.open(id)
  local roll = paw.ui.views:get("pianoroll")
  local clip = roll:clip() or paw.cursor.clip()
  if not clip then error("no clip here", 0) end
  local c = clip:get()
  local entry = M.entry(c.part, id)
  if not entry then
    local map = art.map_of(c.part)
    error(
      map
          and ("the map links no controllers" .. (id and (" as `" .. id .. "`") or "") .. ": [linked] in " .. tostring(
            map.file
          ))
        or "the part has no articulation map: :art.map",
      0
    )
  end
  local beat = roll:clip() and (c.start + roll.beat) or paw.cursor.beat
  return require("paw.views.curve").open(M.uri(c.id, entry), { beat = beat })
end

paw.command("art.lane", function(ctx)
  local id = (tostring(ctx.args[1] or ""):match("^%s*(.-)%s*$"))
  local win, why = M.open(id ~= "" and id or nil)
  if not win and why then error(why, 0) end
end, {
  raw = true,
  desc = "Open the clip's linked controllers (dynamics on CC1 and CC11) as one curve: `art.lane dynamics`; alone, the map's first",
})

paw.keymap.set(
  "<localleader>c",
  function() paw.commands.exec("art.lane") end,
  { view = "pianoroll", desc = "The instrument's linked controllers (dynamics) as one curve", repeatable = false }
)

return M
