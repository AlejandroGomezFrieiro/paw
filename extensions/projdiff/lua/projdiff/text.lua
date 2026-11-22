-- A project as stable, line-oriented text: what `git diff` shows of a
-- project file through the textconv driver. One line for each track, device,
-- clip, note, lane and point, with the fields of each in order, so that a
-- change to one thing is a change to one line, and a note moved is not a
-- hundred lines of JSON.
local data = require("projdiff.data")

local M = {}

--- A checksum of a long string (a plugin's saved state), for a line that
--- says whether it changed without holding it.
local function checksum(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 4294967296
  end
  return string.format("%08x", h)
end

local function value(v) return data.show(v, math.huge) end

-- What names a thing comes first on its line.
local FIRST = { "id", "kind", "name" }

--- `key=value` for the fields of an object that are not in `skip`: the ones
--- that name it, then the rest by key.
local function props(obj, skip)
  local out, named = {}, {}
  for _, k in ipairs(FIRST) do
    named[k] = true
    if obj[k] ~= nil and not (skip and skip[k]) then out[#out + 1] = k .. "=" .. value(obj[k]) end
  end
  for _, k in ipairs(data.sorted_keys(obj)) do
    if not named[k] and not (skip and skip[k]) then out[#out + 1] = k .. "=" .. value(obj[k]) end
  end
  return table.concat(out, " ")
end

local function line(out, depth, kind, text)
  out[#out + 1] = string.rep("  ", depth) .. kind .. (text ~= "" and (" " .. text) or "")
end

local function by_start(list)
  local sorted = {}
  for i, item in ipairs(list or {}) do
    sorted[i] = { i = i, item = item }
  end
  table.sort(sorted, function(a, b)
    local x, y = a.item.start or a.item.beat or 0, b.item.start or b.item.beat or 0
    if x ~= y then return x < y end
    local p, q = a.item.pitch or 0, b.item.pitch or 0
    if p ~= q then return p < q end
    local m, n = a.item.id or 0, b.item.id or 0
    if m ~= n then return m < n end
    return a.i < b.i
  end)
  for i, entry in ipairs(sorted) do
    sorted[i] = entry.item
  end
  return sorted
end

local function device(out, d, depth)
  line(out, depth, "device", props(d, { params = true, state = true, outputs = true, meta = true }))
  for _, k in ipairs(data.sorted_keys(d.params or {})) do
    line(out, depth + 1, "param", k .. "=" .. value(d.params[k]))
  end
  if d.state then line(out, depth + 1, "state", "bytes=" .. #d.state .. " checksum=" .. checksum(d.state)) end
  if d.outputs and next(d.outputs) then line(out, depth + 1, "outputs", value(d.outputs)) end
  if d.meta and next(d.meta) then line(out, depth + 1, "meta", value(d.meta)) end
end

local function clip(out, c, depth)
  local content = c.content or {}
  local head = props(c, { content = true, meta = true })
  local detail = props(content, { notes = true, controls = true })
  line(out, depth, "clip", head .. " " .. detail)
  for _, n in ipairs(by_start(content.notes)) do
    line(
      out,
      depth + 1,
      "note",
      props(n, { pitch = true, meta = true })
        .. " pitch="
        .. tostring(n.pitch)
        .. "("
        .. data.pitch(n.pitch)
        .. ")"
        .. (n.meta and next(n.meta) and (" meta=" .. value(n.meta)) or "")
    )
  end
  for _, ctl in ipairs(by_start(content.controls)) do
    line(out, depth + 1, "control", props(ctl))
  end
  if c.meta and next(c.meta) then line(out, depth + 1, "meta", value(c.meta)) end
end

local function lane(out, l, depth)
  line(out, depth, "lane", props(l, { points = true, shapes = true }))
  for _, p in ipairs(l.points or {}) do
    line(out, depth + 1, "point", "beat=" .. data.num(p[1]) .. " value=" .. data.num(p[2]))
  end
  for _, s in ipairs(l.shapes or {}) do
    line(out, depth + 1, "shape", props(s))
  end
end

local function track(out, t, kind)
  line(out, 0, kind, props(t, { devices = true, clips = true, lanes = true, sends = true, cues = true, meta = true }))
  for _, s in ipairs(t.sends or {}) do
    line(out, 1, "send", props(s))
  end
  for _, d in ipairs(t.devices or {}) do
    device(out, d, 1)
  end
  for _, c in ipairs(t.clips or {}) do
    clip(out, c, 1)
  end
  for _, l in ipairs(t.lanes or {}) do
    lane(out, l, 1)
  end
  for _, c in ipairs(t.cues or {}) do
    line(out, 1, "cue", value(c))
  end
  if t.meta and next(t.meta) then line(out, 1, "meta", value(t.meta)) end
end

--- The text of a project (`file.project`) as lines.
function M.lines(p)
  local out = {}
  line(
    out,
    0,
    "project",
    props(p, { tracks = true, master = true, meta = true, tempo_changes = true, sig_changes = true })
  )
  for _, c in ipairs(p.tempo_changes or {}) do
    line(out, 0, "tempo-change", props(c))
  end
  for _, c in ipairs(p.sig_changes or {}) do
    line(out, 0, "sig-change", props(c))
  end
  local meta = p.meta or {}
  for _, m in ipairs(by_start(meta.markers)) do
    line(out, 0, m.length and "region" or "marker", props(m))
  end
  for _, k in ipairs(data.sorted_keys(meta)) do
    if k ~= "markers" then line(out, 0, "meta." .. k, value(meta[k])) end
  end
  if p.master then track(out, p.master, "master") end
  for _, t in ipairs(p.tracks or {}) do
    track(out, t, "track")
  end
  return out
end

--- The same as one string, ending in a newline.
function M.text(p) return table.concat(M.lines(p), "\n") .. "\n" end

return M
