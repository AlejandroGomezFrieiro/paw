-- Articulation maps: one `.art.toml` file per instrument, read into the
-- table the rest of the extension works with, and found where they live.
--
-- Looked up in this order, the first of an id wins:
--   1. <config>/articulations/**.art.toml        the user's own
--   2. beside a library: Violins.art.toml next to Violins.sfz
--   3. articulations/ inside any loaded extension
--   4. <data>/articulations/generated/           made from a library
--
-- A map read from its file:
--   { id, file, name, family, match = { "sfz:..." }, range = { lo, hi },
--     comfortable, keyswitches, default = "sustain", send, chase, labels,
--     arts = { { id, code = "11.A", attr = { type, data }, out = "ks=E1",
--                events, tag, name, class, colour, mark, text, range, mono, group }, ... },
--     by_id, by_code, mods = { { id, m2, out, off, text, group } }, hash }
local api = paw.api
local music = paw.music
local toml = require("articulations.toml")
local m2 = require("articulations.m2")

local M = {}

M.SUFFIX = ".art.toml"

-- Colours of Reaticulate's classes, so that imported banks keep theirs.
M.colours = {
  default = "#8a8f98",
  long = "#4a7fd0",
  ["long-light"] = "#86abe8",
  ["long-dark"] = "#2c5596",
  short = "#d08a3c",
  ["short-light"] = "#e8b27a",
  ["short-dark"] = "#93581f",
  legato = "#4caf6d",
  ["legato-light"] = "#86d29f",
  ["legato-dark"] = "#2c7a47",
  fx = "#b05cc8",
  ["fx-light"] = "#d293e2",
  ["fx-dark"] = "#76378a",
  textured = "#a2a447",
  ["textured-light"] = "#c6c87e",
  ["textured-dark"] = "#6d6f26",
}

--- A colour for a class name or `#rrggbb`.
function M.colour(class)
  if type(class) == "string" and class:match("^#%x%x%x%x%x%x$") then return class:lower() end
  return M.colours[class or "default"] or M.colours.default
end

--- How many keys a map's names are off paw's, from its `middle_c`: a
--- vendor whose chart calls middle C (60) `C3` names every key an octave
--- lower than paw does, so its names are read 12 keys higher. Nil and why
--- for a `middle_c` that is not C-1 to C6.
function M.offset(middle_c)
  if middle_c == nil then return 0 end
  local octave = tonumber(tostring(middle_c):match("^[Cc](%-?%d)$"))
  if not octave or octave < -1 or octave > 6 then return nil end
  return (4 - octave) * 12
end

--- A key as a map writes it (`D1`, `C#1`, `24`), or nil. `offset` (from
--- `M.offset`) moves a name, not a number: a number is a MIDI key.
function M.key(text, offset)
  text = tostring(text or "")
  local n = tonumber(text)
  if n then return (n >= 0 and n <= 127 and n == math.floor(n)) and n or nil end
  local ok, pitch = pcall(music.pitch, text)
  if ok then
    pitch = pitch + (offset or 0)
    if pitch >= 0 and pitch <= 127 then return pitch end
  end
end

--- A range of keys (`G3-A7`, `55-100`, `C-1-G9`), as `{ lo, hi }`, or nil.
function M.range(text, offset)
  if type(text) == "table" then
    local lo, hi = M.key(text[1], offset), M.key(text[2], offset)
    return lo and hi and { math.min(lo, hi), math.max(lo, hi) } or nil
  end
  text = tostring(text or ""):gsub("%s", "")
  -- The dash between two keys is the one followed by a letter or digit, not a minus of an octave.
  for at in text:gmatch("()%-") do
    local lo, hi = M.key(text:sub(1, at - 1), offset), M.key(text:sub(at + 1), offset)
    if lo and hi then return { math.min(lo, hi), math.max(lo, hi) } end
  end
  local one = M.key(text, offset)
  if one then return { one, one } end
end

--- The events an `out` line stands for, or nil and why:
---   ks=D1 ks=D1:127 hold=D1 cc32=40 cc58=0-15 pc=12 pc=12/258 ch=2 bend=0.5 attr
--- `offset` (from `M.offset`) is how the map names keys. A controller
--- written as a range of values (`cc58=0-15`, an instrument that takes any
--- value of the range) sends the middle of it, and reads back any of it.
function M.events(text, offset)
  local out = {}
  for word in tostring(text or ""):gmatch("%S+") do
    local name, value = word:match("^([%w]+)=(.+)$")
    name = name and name:lower()
    if word == "attr" then
      out[#out + 1] = { type = "attr" }
    elseif name == "ks" or name == "hold" then
      local key, vel = value:match("^([^:]+):?(%d*)$")
      local pitch = M.key(key, offset)
      if not pitch then return nil, "`" .. word .. "`: `" .. tostring(key) .. "` is not a key (D1, C#1, 26)" end
      vel = tonumber(vel)
      if vel and (vel < 1 or vel > 127) then return nil, "`" .. word .. "`: a velocity runs from 1 to 127" end
      out[#out + 1] =
        { type = name == "ks" and "note" or "hold", key = pitch, velocity = vel or 100, given = vel ~= nil }
    elseif name and name:match("^cc%d+$") then
      local number = tonumber(name:sub(3))
      local lo, hi = value:match("^(%d+)%-(%d+)$")
      lo, hi = tonumber(lo), tonumber(hi)
      local v = lo and math.floor((lo + hi) / 2) or tonumber(value)
      if number > 127 or not v or v < 0 or v > 127 or (lo and (lo > hi or hi > 127)) then
        return nil, "`" .. word .. "`: a controller and its value run from 0 to 127 (`cc58=0-15` for a range of values)"
      end
      out[#out + 1] = { type = "cc", number = number, value = v, lo = lo, hi = hi }
    elseif name == "pc" then
      local program, bank = value:match("^(%d+)/?(%d*)$")
      program = tonumber(program)
      if not program or program > 127 then
        return nil, "`" .. word .. "`: a program runs from 0 to 127 (`pc=12`, `pc=12/258` with a bank)"
      end
      out[#out + 1] = { type = "program", program = program, bank = tonumber(bank) }
    elseif name == "ch" then
      local ch = tonumber(value)
      if not ch or ch < 1 or ch > 16 then return nil, "`" .. word .. "`: a channel runs from 1 to 16" end
      out[#out + 1] = { type = "channel", channel = ch }
    elseif name == "bend" then
      local v = tonumber(value)
      if not v or v < -1 or v > 1 then return nil, "`" .. word .. "`: a bend runs from -1 to 1" end
      out[#out + 1] = { type = "bend", value = v }
    else
      return nil, "`" .. word .. "` is not an event: ks=D1, hold=D1, cc32=40, pc=12, ch=2, bend=0.5 or attr"
    end
  end
  return out
end

--- An out line written back from its events, in the map's own words.
function M.out_text(events)
  local words = {}
  for _, e in ipairs(events) do
    if e.type == "note" or e.type == "hold" then
      words[#words + 1] = (e.type == "note" and "ks=" or "hold=")
        .. music.name(e.key)
        .. ((e.velocity and (e.given or e.velocity ~= 100)) and ":" .. e.velocity or "")
    elseif e.type == "cc" then
      words[#words + 1] = "cc" .. e.number .. "=" .. e.value
    elseif e.type == "program" then
      words[#words + 1] = "pc=" .. e.program .. (e.bank and "/" .. e.bank or "")
    elseif e.type == "channel" then
      words[#words + 1] = "ch=" .. e.channel
    elseif e.type == "bend" then
      words[#words + 1] = "bend=" .. e.value
    elseif e.type == "attr" then
      words[#words + 1] = "attr"
    end
  end
  return table.concat(words, " ")
end

--- A delay as a map writes it (`"-80ms"`, `"-0.08s"`, `-80` in ms), in
--- milliseconds, or nil.
function M.delay(v)
  if type(v) == "number" then return v end
  local n, unit = tostring(v or ""):gsub("%s", ""):match("^([%+%-]?[%d%.]+)(m?s)$")
  n = tonumber(n)
  if not n then return nil end
  return unit == "s" and n * 1000 or n
end

--- A delay written back: `"-80ms"`.
function M.delay_text(ms)
  local r = math.floor(ms + 0.5)
  return (r > 0 and "+" or "") .. r .. "ms"
end

--- The shape of a linked controller: `linear`, `exp`, `log`, `s`, or
--- points `"0:0 0.5:0.3 1:1"`, as a function of 0..1 to 0..1; nil and why.
function M.curve(text)
  text = tostring(text or "linear")
  if text == "linear" then
    return function(x) return x end
  end
  if text == "exp" then
    return function(x) return x * x end
  end
  if text == "log" then
    return function(x) return math.sqrt(x) end
  end
  if text == "s" then
    return function(x) return x * x * (3 - 2 * x) end
  end
  local pts = {}
  for a, b in text:gmatch("([%d%.]+):([%d%.]+)") do
    pts[#pts + 1] = { tonumber(a), tonumber(b) }
  end
  if #pts < 2 then
    return nil, "`" .. text .. '` is not a curve: linear, exp, log, s, or points such as "0:0 0.5:0.3 1:1"'
  end
  table.sort(pts, function(p, q) return p[1] < q[1] end)
  return function(x)
    if x <= pts[1][1] then return pts[1][2] end
    for i = 2, #pts do
      local p, q = pts[i - 1], pts[i]
      if x <= q[1] then return p[2] + (q[2] - p[2]) * (x - p[1]) / math.max(1e-9, q[1] - p[1]) end
    end
    return pts[#pts][2]
  end
end

--- A short hash of a text (FNV-1a, 32 bits), to tell whether a file changed.
function M.hash(text)
  local h = 0x811c9dc5
  for i = 1, #text do
    h = bit.bxor(h, text:byte(i))
    h = bit.tobit(h * 0x01000193)
  end
  return bit.tohex(h)
end

local ART_FIELDS = {
  m2 = true,
  out = true,
  tag = true,
  name = true,
  class = true,
  colour = true,
  color = true,
  mark = true,
  text = true,
  range = true,
  mono = true,
  group = true,
  program = true,
  icon = true,
  delay = true,
}
local TOP_FIELDS = {
  format = true,
  name = true,
  family = true,
  match = true,
  range = true,
  comfortable = true,
  keyswitches = true,
  default = true,
  send = true,
  chase = true,
  labels = true,
  art = true,
  mod = true,
  generated = true,
  source = true,
  delay = true,
  linked = true,
  middle_c = true,
  checked = true,
}

--- Read a map from its text. Returns the map, or nil and what is wrong.
function M.parse(text, file)
  local t, err = toml.parse(text)
  local where = file and (file:match("[^/]+$") .. ": ") or ""
  if not t then return nil, where .. err end
  local function bad(why) return nil, where .. why end
  if t.format ~= 1 then return bad("`format = 1` is missing (this is the first format of the maps)") end
  for k in pairs(t) do
    if not TOP_FIELDS[k] then return bad("`" .. k .. "` is not a field of a map") end
  end
  if type(t.art) ~= "table" or next(t.art) == nil then
    return bad("a map needs an `[art]` table with at least one articulation")
  end
  local map = {
    file = file,
    name = t.name or (file and file:match("([^/]+)%.art%.toml$")) or "articulations",
    family = t.family,
    match = type(t.match) == "table" and t.match or (t.match and { t.match } or {}),
    send = t.send or "change",
    chase = t.chase or {},
    labels = t.labels or {},
    generated = t.generated,
    source = t.source,
    arts = {},
    by_id = {},
    by_code = {},
    mods = {},
    hash = M.hash(text),
  }
  if map.send ~= "change" and map.send ~= "every" then return bad('`send` is "change" or "every"') end
  local offset = M.offset(t.middle_c)
  if not offset then
    return bad(
      '`middle_c = "' .. tostring(t.middle_c) .. '"`: the name the instrument gives key 60, C-1 to C6 ("C3", "C4")'
    )
  end
  map.offset, map.middle_c, map.checked = offset, t.middle_c, t.checked
  for _, name in ipairs({ "range", "comfortable", "keyswitches" }) do
    if t[name] ~= nil then
      map[name] = M.range(t[name], offset)
      if not map[name] then
        return bad("`" .. name .. " = " .. tostring(t[name]) .. "`: a range of keys is written `G3-A7` or `55-100`")
      end
    end
  end
  for _, id in ipairs(toml.keys(t.art)) do
    local a = t.art[id]
    if type(a) ~= "table" then
      return bad("articulation `" .. id .. "` is a table: `" .. id .. ' = { m2 = "11.0", out = "ks=D1" }`')
    end
    for k in pairs(a) do
      if not ART_FIELDS[k] then return bad("articulation `" .. id .. "`: `" .. k .. "` is not one of its fields") end
    end
    local attr, why = m2.parse(a.m2)
    if not attr then return bad("articulation `" .. id .. "`: " .. why) end
    local events, why2 = M.events(a.out or "", offset)
    if not events then return bad("articulation `" .. id .. "`: " .. why2) end
    local art = {
      -- `out` as the map writes it; `send` in paw's key names, as the core takes it.
      id = id,
      code = m2.code(attr),
      attr = attr,
      out = a.out or "",
      send = M.out_text(events),
      events = events,
      name = a.name or id:gsub("-", " "):gsub("^%l", string.upper),
      tag = a.tag or id:sub(1, 3),
      class = a.class or a.colour or a.color,
      mark = a.mark,
      text = a.text,
      mono = a.mono,
      group = a.group,
      program = tonumber(a.program),
      icon = a.icon,
    }
    art.colour = M.colour(art.class)
    if a.delay ~= nil then
      art.delay = M.delay(a.delay)
      if not art.delay then return bad("articulation `" .. id .. '`: `delay` is written "-80ms"') end
    end
    if a.range then
      art.range = M.range(a.range, offset)
      if not art.range then return bad("articulation `" .. id .. "`: `range` is written `G3-E7`") end
    end
    map.arts[#map.arts + 1] = art
    map.by_id[id] = art
    -- Two of one code: the first is the one an attribute plays.
    if not map.by_code[art.code] then map.by_code[art.code] = art end
  end
  if t.mod then
    for _, id in ipairs(toml.keys(t.mod)) do
      local m = t.mod[id]
      if type(m) ~= "table" then return bad("modifier `" .. id .. "` is a table") end
      local on, why = M.events(m.out or "", offset)
      local off, why2 = M.events(m.off or "", offset)
      if not on or not off then return bad("modifier `" .. id .. "`: " .. (why or why2)) end
      map.mods[#map.mods + 1] = {
        id = id,
        m2 = m.m2,
        out = m.out or "",
        off = m.off or "",
        on_events = on,
        off_events = off,
        text = m.text,
        name = m.name or m.text or id,
        group = m.group,
        tag = m.tag or id:sub(1, 3),
      }
    end
  end
  if t.delay ~= nil then
    map.delay = M.delay(t.delay)
    if not map.delay then return bad('`delay` is written "-80ms"') end
  end
  -- Controllers drawn as one: `dynamics = { cc = [1, 11], curve = ["linear", "s"], default = 0.7 }`.
  map.linked = {}
  for _, id in ipairs(t.linked and toml.keys(t.linked) or {}) do
    local l = t.linked[id]
    if type(l) ~= "table" or type(l.cc) ~= "table" or #l.cc == 0 then
      return bad("linked `" .. id .. "` names its controllers: `cc = [1, 11]`")
    end
    local entry = {
      id = id,
      name = l.name or (id:gsub("^%l", string.upper)),
      cc = {},
      curves = {},
      curve_text = {},
      default = tonumber(l.default),
    }
    for i, n in ipairs(l.cc) do
      if type(n) ~= "number" or n < 0 or n > 127 then
        return bad("linked `" .. id .. "`: a controller runs from 0 to 127")
      end
      local text = type(l.curve) == "table" and l.curve[i] or l.curve or "linear"
      local fn, why = M.curve(text)
      if not fn then return bad("linked `" .. id .. "`: " .. why) end
      entry.cc[i], entry.curves[i], entry.curve_text[i] = n, fn, text
    end
    map.linked[#map.linked + 1] = entry
  end
  local default = t.default
  if default ~= nil and not map.by_id[default] then
    return bad('`default = "' .. tostring(default) .. '"` names no articulation of the map')
  end
  map.default = default or (map.by_code["10.0"] and map.by_code["10.0"].id) or map.arts[1].id
  -- The keyswitch rows: as the map says, else every key an articulation is switched with.
  if not map.keyswitches then
    local lo, hi
    for _, art in ipairs(map.arts) do
      for _, e in ipairs(art.events) do
        if e.type == "note" or e.type == "hold" then
          lo, hi = math.min(lo or e.key, e.key), math.max(hi or e.key, e.key)
        end
      end
    end
    if lo then map.keyswitches = { lo, hi } end
  end
  return map
end

-- Files ------------------------------------------------------------------------

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end
M.read = read

--- Write a file, making its directory.
function M.write(path, text)
  local dir = path:match("^(.*)/[^/]*$")
  if dir then pcall(paw.api.fs_mkdir, dir) end
  local f, err = io.open(path, "wb")
  if not f then error("cannot write " .. path .. ": " .. tostring(err), 0) end
  f:write(text)
  f:close()
  return path
end

--- Where maps live, in the order they are looked in: `{ dir, kind }`.
function M.dirs()
  local env = api.env()
  local out = { { dir = env.config_dir .. "/articulations", kind = "user" } }
  for _, ext in ipairs(paw.ext.list()) do
    if ext.ok and not ext.path:match("%.lua$") then
      out[#out + 1] = { dir = ext.path .. "/articulations", kind = "extension" }
    end
  end
  out[#out + 1] = { dir = M.generated_dir(), kind = "generated" }
  return out
end

--- Where maps made from a library are kept.
function M.generated_dir() return api.env().data_dir .. "/articulations/generated" end

local function walk(dir, rel, into)
  for _, item in ipairs(api.read_dir(dir)) do
    local path = dir .. "/" .. item.name
    if item.is_dir then
      walk(path, rel .. item.name .. "/", into)
    elseif item.name:sub(-#M.SUFFIX) == M.SUFFIX then
      into[#into + 1] = { id = rel .. item.name:sub(1, -#M.SUFFIX - 1), file = path }
    end
  end
end

local cache = {} -- by file: { text, map, err }

--- A map from its file, read again only when the file changed. Returns the
--- map, or nil and what is wrong.
function M.load(file, id)
  local known = cache[file]
  -- Drawing asks many times a second: the file is looked at again after a while.
  local now = api.now()
  if known and now - known.checked < 1000 then
    if known.map and id then known.map.id = id end
    return known.map, known.err
  end
  local text = read(file)
  if not text then
    cache[file] = nil
    return nil, "cannot read " .. file
  end
  if known and known.text == text then
    known.checked = now
    if known.map and id then known.map.id = id end
    return known.map, known.err
  end
  local map, err = M.parse(text, file)
  if map then map.id = id or file:match("([^/]+)%.art%.toml$") end
  cache[file] = { text = text, map = map, err = err, checked = now }
  return map, err
end

--- Forget what was read, so that every file is read again.
function M.forget() cache = {} end

--- Every map file there is: `{ id, file, kind }`, the first of an id kept.
function M.list()
  local out, seen = {}, {}
  for _, d in ipairs(M.dirs()) do
    local found = {}
    walk(d.dir, "", found)
    table.sort(found, function(a, b) return a.id < b.id end)
    for _, f in ipairs(found) do
      if not seen[f.id] then
        seen[f.id] = true
        f.kind = d.kind
        out[#out + 1] = f
      end
    end
  end
  return out
end

--- The map file beside a library (`Violins.sfz` -> `Violins.art.toml`), if there is one.
function M.beside(library)
  local base = tostring(library or ""):gsub("%.[^./]*$", "")
  local file = base .. M.SUFFIX
  if read(file) then return file end
end

--- Find a map by its id, its file, or its name. Returns the map, or nil and why.
function M.find(which)
  which = tostring(which or "")
  if which:sub(-#M.SUFFIX) == M.SUFFIX and read(which) then return M.load(which) end
  local list = M.list()
  for _, f in ipairs(list) do
    if f.id == which then return M.load(f.file, f.id) end
  end
  -- The end of an id: `basic-articulations` for `reaticulate/spitfire/basic-articulations`.
  for _, f in ipairs(list) do
    if f.id:sub(-#which - 1) == "/" .. which then return M.load(f.file, f.id) end
  end
  local lower = which:lower()
  for _, f in ipairs(list) do
    local map = M.load(f.file, f.id)
    if map and (map.name:lower() == lower or f.id:lower():match("[^/]+$") == lower) then return map end
  end
  return nil, "no articulation map `" .. which .. "`: :art.maps lists them"
end

-- The schemes of `match` that name a plugin: by its format, or any format.
M.PLUGIN_SCHEMES =
  { clap = "clap", vst3 = "vst3", vst = "vst", vst2 = "vst", lv2 = "lv2", ladspa = "ladspa", plugin = true }

--- Whether a `match` entry that names a plugin (`vst3:MODO BASS 2`,
--- `clap:org.surge-synth-team.surge-xt`, `plugin:Circvit Bass`) names a
--- device: the device is that plugin, in that format (any format for
--- `plugin:`), and the text is its id or its name, or a part of its name.
--- Case does not matter.
function M.plugin_matches(entry, device)
  local scheme, text = tostring(entry):match("^(%w+):(.+)$")
  local format = scheme and M.PLUGIN_SCHEMES[scheme:lower()]
  local p = type(device) == "table" and device.plugin
  if not format or type(p) ~= "table" then return false end
  local fmt = tostring(p.format or device.format or ""):lower()
  if fmt == "vst2" then fmt = "vst" end
  if format ~= true and fmt ~= format then return false end
  text = text:lower()
  local id, name = tostring(p.id or ""):lower(), tostring(p.name or device.name or ""):lower()
  return id == text or name == text or (name ~= "" and name:find(text, 1, true) ~= nil)
end

--- Whether a `match` entry names a library or device kind (`sfz:`,
--- `dspreset:`, `describe:`): the device's kind, its name or what it has
--- loaded hold the entry's text (without the scheme).
local function names_device(entry, devices)
  local text = tostring(entry):gsub("^%w+:", ""):lower()
  local base = text:match("([^/]+)$") or text
  for _, d in ipairs(devices) do
    for _, field in ipairs({ d.kind, d.name, d.preset, d.library }) do
      if type(field) == "string" and field ~= "" then
        local f = field:lower()
        if f == text or f:find(text, 1, true) or f:find(base, 1, true) or text:find(f, 1, true) then return true end
      end
    end
  end
  return false
end

--- Whether one of a map's `match` entries names a device of a list.
local function matches(map, devices)
  for _, entry in ipairs(map.match) do
    local scheme = tostring(entry):match("^(%w+):")
    if scheme and M.PLUGIN_SCHEMES[scheme:lower()] then
      for _, d in ipairs(devices) do
        if M.plugin_matches(entry, d) then return true end
      end
    elseif names_device(entry, devices) then
      return true
    end
  end
  return false
end
M.matches = matches

--- A map with its keyswitches moved by `shift` keys (an instrument whose
--- keyswitch area the person moved): the keys of `ks` and `hold`, of its
--- modifiers, and its keyswitch rows. The keys that it plays stay. Nil and
--- why when a keyswitch would leave 0 to 127. The same map for 0.
local shifted = setmetatable({}, { __mode = "k" })
function M.shift(map, shift)
  shift = math.floor(tonumber(shift) or 0)
  if shift == 0 then return map end
  shifted[map] = shifted[map] or {}
  if shifted[map][shift] then return shifted[map][shift] end
  local function move(events)
    local out = {}
    for i, e in ipairs(events) do
      out[i] = e
      if e.type == "note" or e.type == "hold" then
        local key = e.key + shift
        if key < 0 or key > 127 then return nil end
        out[i] = { type = e.type, key = key, velocity = e.velocity, given = e.given }
      end
    end
    return out
  end
  local copy = setmetatable({ shift = shift, arts = {}, by_id = {}, by_code = {}, mods = {} }, { __index = map })
  for i, a in ipairs(map.arts) do
    local events = move(a.events)
    if not events then return nil, a.name .. ": a keyswitch moved " .. shift .. " keys leaves the keys 0 to 127" end
    local b = setmetatable({ events = events, send = M.out_text(events) }, { __index = a })
    copy.arts[i], copy.by_id[a.id] = b, b
  end
  for code, a in pairs(map.by_code) do
    copy.by_code[code] = copy.by_id[a.id]
  end
  for i, m in ipairs(map.mods) do
    local on, off = move(m.on_events), move(m.off_events)
    if not on or not off then
      return nil, (m.text or m.id) .. ": a keyswitch moved " .. shift .. " keys leaves the keys 0 to 127"
    end
    copy.mods[i] = setmetatable({ on_events = on, off_events = off }, { __index = m })
  end
  if map.keyswitches then
    copy.keyswitches = { math.max(0, map.keyswitches[1] + shift), math.min(127, map.keyswitches[2] + shift) }
  end
  shifted[map][shift] = copy
  return copy
end

--- The maps whose `match` names a device of a part.
function M.matching(part)
  local devices = {}
  for _, id in ipairs(api.part_get(part).devices or {}) do
    local ok, d = pcall(api.device_get, id)
    if ok then devices[#devices + 1] = d end
  end
  local out = {}
  if #devices == 0 then return out end
  for _, f in ipairs(M.list()) do
    local map = M.load(f.file, f.id)
    if map and matches(map, devices) then out[#out + 1] = map end
  end
  return out
end

return M
