-- The semantic difference between two versions of a project, as a tree of
-- changes: tracks added, removed and renamed, devices and parameters
-- changed, clips moved, added and removed, notes summarised per clip,
-- automation, the tempo map, the markers, and the same inside each
-- subproject, under the subproject's name. It reads projects as they are
-- in their files (decoded JSON), so it needs nothing of the kernel.
--
-- A node is `{ sign, text, address, trail, change, children }`: `sign` is
-- "+", "-" or "~"; `address` says where in the project it is (paw://...) so
-- that a view can go there; `trail` is the text of the way to it, for a
-- quickfix entry; `change` is set on what changed itself, as against a
-- heading over what changed inside it.
local data = require("projdiff.data")

local M = {}
-- Numbers as they are read, not as they are kept (`data.short`).
local num = data.short
local function show(v, limit) return data.show(v, limit, true) end

-- Notes, controls and points listed under their clip or lane before "more".
local SHOWN = 30

local function node(sign, text, o)
  o = o or {}
  o.sign, o.text, o.children = sign, text, o.children or {}
  return o
end

local function add(parent, child)
  if child then parent.children[#parent.children + 1] = child end
  return child
end

local function count(n)
  local total = (n.change and 1 or 0) + (n.hidden or 0)
  for _, child in ipairs(n.children) do
    total = total + count(child)
  end
  return total
end

local function union_keys(a, b)
  local keys = {}
  for k in pairs(a) do
    keys[k] = true
  end
  for k in pairs(b) do
    keys[k] = true
  end
  return data.sorted_keys(keys)
end

--- One line under `parent` for each field of two objects that differs.
local function fields(parent, a, b, skip, o)
  a, b = a or {}, b or {}
  for _, k in ipairs(union_keys(a, b)) do
    if not (skip and skip[k]) and not data.equal(a[k], b[k]) then
      local sign = a[k] == nil and "+" or b[k] == nil and "-" or "~"
      add(
        parent,
        node(
          sign,
          k .. ": " .. show(a[k]) .. " -> " .. show(b[k]),
          { address = o.address, trail = o.trail, change = true }
        )
      )
    end
  end
end

--- The items of two lists matched by `field`, in the order of the second
--- list and then what is only in the first.
local function match(a, b, field)
  local A, B = data.by(a, field), data.by(b, field)
  local out = {}
  for _, k in ipairs(B.order) do
    out[#out + 1] = { key = k, a = A.by[k], b = B.by[k] }
  end
  for _, k in ipairs(A.order) do
    if B.by[k] == nil then out[#out + 1] = { key = k, a = A.by[k] } end
  end
  return out, A, B
end

--- Whether the items two lists have in common are in another order.
local function reordered(A, B)
  local first, second = {}, {}
  for _, k in ipairs(A.order) do
    if B.by[k] ~= nil then first[#first + 1] = k end
  end
  for _, k in ipairs(B.order) do
    if A.by[k] ~= nil then second[#second + 1] = k end
  end
  for i = 1, #first do
    if first[i] ~= second[i] then return true end
  end
  return false
end

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

local function sign_of(p) return p.a == nil and "+" or p.b == nil and "-" or "~" end

-- Notes and controls ---------------------------------------------------------

local function note_text(n)
  return string.format(
    "%s at %s, %s long, velocity %s",
    data.pitch(n.pitch),
    num(n.start or 0),
    num(n.length or 0),
    num(n.velocity or 100)
  )
end

local function more(parent, shown, total, o)
  if total > shown then
    add(parent, node(" ", "… " .. (total - shown) .. " more", { address = o.address, trail = o.trail }))
  end
end

--- What changed among the notes of a clip, under one heading.
local function notes_node(a, b, clip)
  local address = "paw://clip/" .. clip.id
  local trail = clip.trail
  local field = data.key_field(a, b)
  local lines, added, removed, changed = {}, 0, 0, 0
  if field == "id" then
    for _, p in ipairs((match(a, b, "id"))) do
      local where = { address = address .. "/note/" .. p.key, trail = trail .. " › note " .. p.key, change = true }
      if p.a == nil then
        added = added + 1
        lines[#lines + 1] = node("+", "note " .. p.key .. " " .. note_text(p.b), where)
      elseif p.b == nil then
        removed = removed + 1
        where.address = address
        lines[#lines + 1] = node("-", "note " .. p.key .. " " .. note_text(p.a), where)
      elseif not data.equal(p.a, p.b) then
        changed = changed + 1
        local parts = {}
        for _, k in ipairs(union_keys(p.a, p.b)) do
          if not data.equal(p.a[k], p.b[k]) then
            local x, y = p.a[k], p.b[k]
            if k == "pitch" then
              x, y = data.pitch(x), data.pitch(y)
            else
              x, y = show(x, 24), show(y, 24)
            end
            parts[#parts + 1] = k .. " " .. tostring(x) .. " -> " .. tostring(y)
          end
        end
        lines[#lines + 1] =
          node("~", "note " .. p.key .. " " .. data.pitch(p.b.pitch) .. ": " .. table.concat(parts, ", "), where)
      end
    end
  else
    -- Notes without ids (an old file) are told apart by what they are.
    local seen = {}
    for _, n in ipairs(a) do
      local k = data.canon(n)
      seen[k] = (seen[k] or 0) + 1
    end
    for _, n in ipairs(b) do
      local k = data.canon(n)
      if (seen[k] or 0) > 0 then
        seen[k] = seen[k] - 1
      else
        added = added + 1
        lines[#lines + 1] =
          node("+", "note " .. note_text(n), { address = address, trail = trail .. " › notes", change = true })
      end
    end
    for _, n in ipairs(a) do
      local k = data.canon(n)
      if (seen[k] or 0) > 0 then
        seen[k] = seen[k] - 1
        removed = removed + 1
        lines[#lines + 1] =
          node("-", "note " .. note_text(n), { address = address, trail = trail .. " › notes", change = true })
      end
    end
  end
  if added + removed + changed == 0 then return nil end
  local parts = {}
  if added > 0 then parts[#parts + 1] = "+" .. added end
  if removed > 0 then parts[#parts + 1] = "-" .. removed end
  if changed > 0 then parts[#parts + 1] = "~" .. changed end
  local head = node("~", "notes " .. table.concat(parts, " "), { address = address, trail = trail .. " › notes" })
  for i = 1, math.min(#lines, SHOWN) do
    add(head, lines[i])
  end
  more(head, SHOWN, #lines, head)
  -- What is not listed still counts as changes.
  head.hidden = math.max(0, #lines - SHOWN)
  return head
end

local function control_text(c)
  local what = c.type or "control"
  if c.number then what = what .. " " .. c.number end
  return string.format("%s at %s = %s", what, num(c.start or 0), num(c.value or 0))
end

--- Controllers are told apart by what they are, as notes without ids.
local function controls_node(a, b, clip)
  local seen, lines = {}, {}
  for _, c in ipairs(a) do
    local k = data.canon(c)
    seen[k] = (seen[k] or 0) + 1
  end
  local where = { address = "paw://clip/" .. clip.id, trail = clip.trail .. " › controls", change = true }
  local added, removed = 0, 0
  for _, c in ipairs(b) do
    local k = data.canon(c)
    if (seen[k] or 0) > 0 then
      seen[k] = seen[k] - 1
    else
      added = added + 1
      lines[#lines + 1] = node("+", control_text(c), { address = where.address, trail = where.trail, change = true })
    end
  end
  for _, c in ipairs(a) do
    local k = data.canon(c)
    if (seen[k] or 0) > 0 then
      seen[k] = seen[k] - 1
      removed = removed + 1
      lines[#lines + 1] = node("-", control_text(c), { address = where.address, trail = where.trail, change = true })
    end
  end
  if #lines == 0 then return nil end
  local head = node("~", "controls +" .. added .. " -" .. removed, { address = where.address, trail = where.trail })
  for i = 1, math.min(#lines, SHOWN) do
    add(head, lines[i])
  end
  more(head, SHOWN, #lines, head)
  head.hidden = math.max(0, #lines - SHOWN)
  return head
end

-- Clips ----------------------------------------------------------------------

local function clip_label(c) return string.format('clip %d "%s"', c.id, c.name or "") end

local function clip_summary(c)
  local content = c.content or {}
  if content.kind == "audio" then return "audio " .. tostring(content.file) end
  if content.kind == "nest" then return "subproject " .. tostring(content.nest) end
  return plural(#(content.notes or {}), "note")
end

local function clip_node(a, b, track)
  local c = b or a
  local address = "paw://clip/" .. c.id
  local trail = track.trail .. " › " .. clip_label(c)
  if not a or not b then
    return node(
      a and "-" or "+",
      clip_label(c) .. ", at beat " .. num(c.start) .. ", " .. num(c.length) .. " beats long, " .. clip_summary(c),
      { address = a and track.address or address, trail = trail, change = true }
    )
  end
  if data.equal(a, b) then return nil end
  local head = node("~", clip_label(b), { address = address, trail = trail })
  if a.name ~= b.name then head.text = string.format('clip %d "%s" -> "%s"', b.id, a.name or "", b.name or "") end
  local o = { address = address, trail = trail }
  fields(head, a, b, { id = true, content = true, meta = true, name = true }, o)
  if a.name ~= b.name then
    add(
      head,
      node("~", "name: " .. show(a.name) .. " -> " .. show(b.name), { address = address, trail = trail, change = true })
    )
  end
  local ca, cb = a.content or {}, b.content or {}
  if ca.kind ~= cb.kind then
    add(
      head,
      node(
        "~",
        "content: " .. show(ca.kind) .. " -> " .. show(cb.kind),
        { address = address, trail = trail, change = true }
      )
    )
  elseif cb.kind == "midi" then
    local clip = { id = b.id, trail = trail }
    add(head, notes_node(ca.notes or {}, cb.notes or {}, clip))
    add(head, controls_node(ca.controls or {}, cb.controls or {}, clip))
  else
    fields(head, ca, cb, { kind = true }, o)
  end
  fields(head, a.meta, b.meta, nil, { address = address, trail = trail .. " › meta" })
  return #head.children > 0 and head or nil
end

-- Devices --------------------------------------------------------------------

local function device_label(d)
  local text = "device " .. d.id .. " " .. tostring(d.name or d.kind)
  if d.name and d.name ~= d.kind then text = text .. " (" .. tostring(d.kind) .. ")" end
  return text
end

local function device_node(a, b, track)
  local d = b or a
  local address = track.address .. "/device/" .. d.id
  local trail = track.trail .. " › " .. device_label(d)
  if not a or not b then
    return node(
      a and "-" or "+",
      device_label(d),
      { address = a and track.address or address, trail = trail, change = true }
    )
  end
  if data.equal(a, b) then return nil end
  local head = node("~", device_label(b), { address = address, trail = trail })
  local o = { address = address, trail = trail }
  fields(head, a, b, { id = true, params = true, state = true, meta = true }, o)
  local pa, pb = a.params or {}, b.params or {}
  for _, k in ipairs(union_keys(pa, pb)) do
    if pa[k] ~= pb[k] then
      add(
        head,
        node(
          pa[k] == nil and "+" or pb[k] == nil and "-" or "~",
          string.format("%s: %s -> %s", k, show(pa[k]), show(pb[k])),
          { address = address .. "/param/" .. k, trail = trail .. " › " .. k, change = true }
        )
      )
    end
  end
  if a.state ~= b.state then
    add(
      head,
      node(
        "~",
        string.format("plugin state changed (%d -> %d bytes)", #(a.state or ""), #(b.state or "")),
        { address = address, trail = trail .. " › state", change = true }
      )
    )
  end
  fields(head, a.meta, b.meta, nil, { address = address, trail = trail .. " › meta" })
  return #head.children > 0 and head or nil
end

-- Lanes (automation) ---------------------------------------------------------

local function lane_label(l)
  local t = l.target or {}
  if t.kind == "param" then
    return string.format("lane %d: %s of device %s", l.id, tostring(t.param), tostring(t.device))
  end
  return string.format("lane %d: %s", l.id, tostring(t.kind))
end

local function point_text(p) return "beat " .. num(p[1]) .. " = " .. num(p[2]) end

local function lane_node(a, b, track)
  local l = b or a
  local address = "paw://lane/" .. l.id
  local trail = track.trail .. " › " .. lane_label(l)
  if not a or not b then
    return node(
      a and "-" or "+",
      lane_label(l) .. ", " .. plural(#(l.points or {}), "point"),
      { address = a and track.address or address, trail = trail, change = true }
    )
  end
  if data.equal(a, b) then return nil end
  local head = node("~", lane_label(b), { address = address, trail = trail })
  fields(head, a, b, { id = true, points = true }, { address = address, trail = trail })
  local lines, added, removed, moved = {}, 0, 0, 0
  for _, p in ipairs((match(a.points or {}, b.points or {}, 1))) do
    local where = { address = address, trail = trail .. " › points", change = true }
    if p.a == nil then
      added = added + 1
      lines[#lines + 1] = node("+", point_text(p.b), where)
    elseif p.b == nil then
      removed = removed + 1
      lines[#lines + 1] = node("-", point_text(p.a), where)
    elseif p.a[2] ~= p.b[2] then
      moved = moved + 1
      lines[#lines + 1] = node("~", "beat " .. num(p.key) .. ": " .. num(p.a[2]) .. " -> " .. num(p.b[2]), where)
    end
  end
  if #lines > 0 then
    local parts = {}
    if added > 0 then parts[#parts + 1] = "+" .. added end
    if removed > 0 then parts[#parts + 1] = "-" .. removed end
    if moved > 0 then parts[#parts + 1] = "~" .. moved end
    local points =
      add(head, node("~", "points " .. table.concat(parts, " "), { address = address, trail = trail .. " › points" }))
    for i = 1, math.min(#lines, SHOWN) do
      add(points, lines[i])
    end
    more(points, SHOWN, #lines, points)
    points.hidden = math.max(0, #lines - SHOWN)
  end
  return #head.children > 0 and head or nil
end

-- Tracks ---------------------------------------------------------------------

--- `nest` is the subproject that holds the track, if any: its master
--- track is named as the song's master is.
local function track_label(t, nest)
  if t.id == 0 or (nest and nest.master == t.id) then return "master" end
  return string.format('track %d "%s"', t.id, t.name or "")
end

local function send_node(p, track)
  local s = p.b or p.a
  local where = { address = track.address, trail = track.trail .. " › send to track " .. s.target, change = true }
  local text = "send to track " .. s.target
  if not p.a then return node("+", text .. " at " .. num(s.level) .. " dB", where) end
  if not p.b then return node("-", text, where) end
  local o = node("~", text, where)
  local parts = {}
  for _, k in ipairs(union_keys(p.a, p.b)) do
    if not data.equal(p.a[k], p.b[k]) then parts[#parts + 1] = k .. " " .. show(p.a[k]) .. " -> " .. show(p.b[k]) end
  end
  o.text = text .. ": " .. table.concat(parts, ", ")
  return o
end

--- The changes of one track. `within` is the subproject that holds it, as
--- `{ nest, trail }`, or nil for a track of the song.
local function track_node(a, b, within)
  local t = b or a
  local address = "paw://track/" .. t.id
  local label = track_label(t, within and within.nest)
  local track = { address = address, trail = within and (within.trail .. " › " .. label) or label }
  if not a or not b then
    local head =
      node(a and "-" or "+", label, { address = a and "paw://project" or address, trail = track.trail, change = true })
    local from = t
    for _, d in ipairs(from.devices or {}) do
      add(head, node(" ", device_label(d)))
    end
    for _, c in ipairs(from.clips or {}) do
      add(head, node(" ", clip_label(c) .. ", " .. clip_summary(c)))
    end
    return head
  end
  if data.equal(a, b) then return nil end
  local head = node("~", label, { address = address, trail = track.trail })
  if a.name ~= b.name then head.text = string.format('track %d "%s" -> "%s"', b.id, a.name or "", b.name or "") end
  local skip = { id = true, devices = true, clips = true, lanes = true, sends = true, cues = true, meta = true }
  fields(head, a, b, skip, track)
  fields(head, a.meta, b.meta, nil, { address = address, trail = track.trail .. " › meta" })

  local sends = match(a.sends, b.sends, "target")
  for _, p in ipairs(sends) do
    if not data.equal(p.a, p.b) then add(head, send_node(p, track)) end
  end

  local devices, DA, DB = match(a.devices, b.devices, "id")
  for _, p in ipairs(devices) do
    add(head, device_node(p.a, p.b, track))
  end
  if reordered(DA, DB) then
    add(head, node("~", "devices in another order", { address = address, trail = track.trail, change = true }))
  end
  local clips = match(a.clips, b.clips, "id")
  for _, p in ipairs(clips) do
    add(head, clip_node(p.a, p.b, track))
  end
  local lanes = match(a.lanes, b.lanes, "id")
  for _, p in ipairs(lanes) do
    add(head, lane_node(p.a, p.b, track))
  end
  -- Clips off the timeline, which cues play (the clip launcher's slots).
  for _, p in ipairs((match(a.cues, b.cues, "id"))) do
    local n = clip_node(p.a, p.b, track)
    if n then
      n.text = n.text .. " (off the timeline)"
      add(head, n)
    end
  end
  return #head.children > 0 and head or nil
end

-- The project ----------------------------------------------------------------

local TEMPO_FIELDS = { tempo = true, sig_num = true, sig_den = true, tempo_ramp = true }

local function tempo_group(a, b)
  local head = node("~", "Tempo map", { address = "paw://tempo", trail = "tempo map" })
  local o = { address = "paw://tempo", trail = "tempo map" }
  fields(head, a, b, setmetatable({}, { __index = function(_, k) return not TEMPO_FIELDS[k] end }), o)
  for _, p in ipairs((match(a.tempo_changes, b.tempo_changes, "beat"))) do
    if not data.equal(p.a, p.b) then
      local text = "tempo at beat " .. num(p.key)
      if not p.a then
        text = text .. ": " .. num(p.b.bpm) .. " bpm" .. (p.b.ramp and " ramping" or "")
      elseif not p.b then
        text = text .. " (was " .. num(p.a.bpm) .. " bpm)"
      else
        text = text .. ": " .. num(p.a.bpm) .. " -> " .. num(p.b.bpm) .. " bpm"
      end
      add(
        head,
        node(sign_of(p), text, { address = o.address, trail = o.trail .. " › beat " .. num(p.key), change = true })
      )
    end
  end
  for _, p in ipairs((match(a.sig_changes, b.sig_changes, "beat"))) do
    if not data.equal(p.a, p.b) then
      local function sig(s) return s and (s.num .. "/" .. s.den) or "none" end
      add(
        head,
        node(
          sign_of(p),
          "time signature at beat " .. num(p.key) .. ": " .. sig(p.a) .. " -> " .. sig(p.b),
          { address = o.address, trail = o.trail .. " › beat " .. num(p.key), change = true }
        )
      )
    end
  end
  return #head.children > 0 and head or nil
end

local function marker_text(m)
  local text = (m.length and "region" or "marker")
    .. " "
    .. m.id
    .. " "
    .. show(m.name or "")
    .. " at beat "
    .. num(m.beat or 0)
  if m.length then text = text .. ", " .. num(m.length) .. " beats long" end
  return text
end

local function markers_group(a, b)
  local head = node("~", "Markers", { address = "paw://project", trail = "markers" })
  for _, p in ipairs((match(a, b, "id"))) do
    if not data.equal(p.a, p.b) then
      local m = p.b or p.a
      local where = {
        address = p.b and ("paw://marker/" .. p.key) or "paw://project",
        trail = "markers › " .. show(m.name or p.key),
        change = true,
      }
      if not p.a or not p.b then
        add(head, node(sign_of(p), marker_text(m), where))
      else
        local parts = {}
        for _, k in ipairs(union_keys(p.a, p.b)) do
          if not data.equal(p.a[k], p.b[k]) then
            parts[#parts + 1] = k .. " " .. show(p.a[k]) .. " -> " .. show(p.b[k])
          end
        end
        add(
          head,
          node(
            "~",
            (m.length and "region " or "marker ")
              .. p.key
              .. " "
              .. show(m.name or "")
              .. ": "
              .. table.concat(parts, ", "),
            where
          )
        )
      end
    end
  end
  return #head.children > 0 and head or nil
end

-- Subprojects ----------------------------------------------------------------
--
-- The tracks of a subproject are in the project's one list of tracks, with
-- the subproject's id in `nest`; `nests` holds the rest (name, length, tempo,
-- meter, master track). A subproject shows as a heading, with its fields,
-- its tracks and the subprojects that its clips place under it.

local function nest_label(n) return string.format('subproject %d "%s"', n.id, n.name or "") end

--- The subproject that places each subproject of project `p`, by id: the
--- subproject of the first track with a clip of it, or false when a track
--- of the song places it (the song comes first: it is where the user meets it).
local function placers(p)
  local out = {}
  for _, t in ipairs(p.tracks or {}) do
    for _, list in ipairs({ t.clips or {}, t.cues or {} }) do
      for _, c in ipairs(list) do
        local content = c.content or {}
        if content.kind == "nest" and content.nest ~= nil and out[content.nest] ~= false then
          out[content.nest] = t.nest or false
        end
      end
    end
  end
  return out
end

--- The heading that each subproject goes under, by id: the id of a
--- subproject, or false for the top of the diff. A subproject that no clip
--- places, one placed by a subproject that the files do not have, or one in
--- a loop of subprojects (the last two only in a file that paw did not
--- write) goes to the top.
local function parents(a, b, ids)
  local in_a, in_b = placers(a), placers(b)
  local parent, known = {}, {}
  for _, id in ipairs(ids) do
    known[id] = true
  end
  for _, id in ipairs(ids) do
    local p = in_b[id]
    if p == nil then p = in_a[id] end
    parent[id] = known[p] and p or false
  end
  for _, id in ipairs(ids) do
    local at, steps = parent[id], 0
    while at and at ~= id and steps <= #ids do
      at, steps = parent[at], steps + 1
    end
    if at then parent[id] = false end
  end
  return parent
end

--- The changes of every subproject, in the order of `b` and then the
--- removed ones, each under the heading that `parents` gives.
--- `tracks[id]` holds the matched pairs of the subproject's tracks.
local function nest_nodes(a, b, tracks)
  local list = match(a.nests, b.nests, "id")
  local ids = {}
  for i, p in ipairs(list) do
    ids[i] = p.key
  end
  local parent = parents(a, b, ids)
  -- `above` is the trail of the subprojects that hold this one, or nil.
  local function build(p, above)
    local n = p.b or p.a
    local label = nest_label(n)
    local trail = above and (above .. " › " .. label) or label
    local o = { address = "paw://project", trail = trail }
    local head = node(sign_of(p), label, o)
    if p.a and p.b then
      if p.a.name ~= p.b.name then
        head.text = string.format('subproject %d "%s" -> "%s"', n.id, p.a.name or "", p.b.name or "")
      end
      fields(head, p.a, p.b, { id = true, meta = true }, o)
      fields(head, p.a.meta, p.b.meta, nil, { address = o.address, trail = trail .. " › meta" })
    else
      -- Added or removed: a change itself, over its tracks added or removed.
      head.change = true
    end
    local within = { nest = n, trail = trail }
    for _, t in ipairs(tracks[n.id] or {}) do
      add(head, track_node(t.a, t.b, within))
    end
    for _, child in ipairs(list) do
      if parent[child.key] == n.id then add(head, build(child, trail)) end
    end
    return (head.change or #head.children > 0) and head or nil
  end
  local out = {}
  for _, p in ipairs(list) do
    if parent[p.key] == false then out[#out + 1] = build(p) end
  end
  return out
end

--- The changes from project `a` to project `b` (both as `file.project`):
--- `{ children = { node... }, count = number of changes }`.
function M.diff(a, b)
  a, b = a or {}, b or {}
  local root = { children = {} }

  local project = node("~", "Project", { address = "paw://project", trail = "project" })
  local skip = setmetatable(
    { tracks = true, master = true, meta = true, nests = true },
    { __index = function(_, k) return TEMPO_FIELDS[k] or k == "tempo_changes" or k == "sig_changes" or nil end }
  )
  fields(project, a, b, skip, { address = "paw://project", trail = "project" })
  local ma, mb = a.meta or {}, b.meta or {}
  for _, k in ipairs(union_keys(ma, mb)) do
    if k ~= "markers" and not data.equal(ma[k], mb[k]) then
      add(
        project,
        node(
          ma[k] == nil and "+" or mb[k] == nil and "-" or "~",
          "meta." .. k .. ": " .. show(ma[k]) .. " -> " .. show(mb[k]),
          { address = "paw://project", trail = "project › meta." .. k, change = true }
        )
      )
    end
  end
  local tracks, TA, TB = match(a.tracks, b.tracks, "id")
  if reordered(TA, TB) then
    add(project, node("~", "tracks in another order", { address = "paw://project", trail = "project", change = true }))
  end
  add(root, #project.children > 0 and project or nil)
  add(root, tempo_group(a, b))
  add(root, markers_group(ma.markers, mb.markers))
  if a.master or b.master then add(root, track_node(a.master, b.master)) end
  -- A track shows under the subproject that holds it now, or held it when
  -- it was removed.
  local in_nest, known = {}, {}
  for _, list in ipairs({ a.nests or {}, b.nests or {} }) do
    for _, n in ipairs(list) do
      known[n.id] = true
    end
  end
  for _, p in ipairs(tracks) do
    local nest = (p.b or p.a).nest
    -- A track of a subproject that the files do not have shows as the song's.
    if not known[nest] then
      add(root, track_node(p.a, p.b))
    else
      in_nest[nest] = in_nest[nest] or {}
      table.insert(in_nest[nest], p)
    end
  end
  for _, n in ipairs(nest_nodes(a, b, in_nest)) do
    add(root, n)
  end

  local total = 0
  for _, child in ipairs(root.children) do
    child.count = count(child)
    total = total + child.count
  end
  root.count = total
  return root
end

--- Every node of a tree with its depth, in order, for showing as lines
--- (`open(node)` says whether a node's children are shown).
function M.flatten(root, open)
  local out = {}
  local function walk(n, depth)
    out[#out + 1] = { node = n, depth = depth }
    if #n.children > 0 and (not open or open(n)) then
      for _, child in ipairs(n.children) do
        walk(child, depth + 1)
      end
    end
  end
  for _, n in ipairs(root.children) do
    walk(n, 0)
  end
  return out
end

--- The changes as text, one line each, indented by depth.
function M.lines(root)
  local out = {}
  for _, row in ipairs(M.flatten(root)) do
    out[#out + 1] = string.rep("  ", row.depth) .. row.node.sign .. " " .. row.node.text
  end
  return out
end

--- The changes that are changes themselves, for a quickfix list:
--- `{ address, text }` where the text names the way there.
function M.entries(root)
  local out = {}
  local function walk(n)
    if n.change then
      out[#out + 1] = { address = n.address, text = (n.trail or "") .. ": " .. n.sign .. " " .. n.text, sign = n.sign }
    end
    for _, child in ipairs(n.children) do
      walk(child)
    end
  end
  for _, n in ipairs(root.children) do
    walk(n)
  end
  return out
end

return M
