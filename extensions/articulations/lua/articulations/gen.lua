-- Maps made from what a library says about itself: an SFZ's keyswitches
-- (`sw_*`, `sw_label`, `label_keyN`), a Decent Sampler preset's keyswitch
-- bindings, a folder of samples named by articulation, a sampler device's
-- `describe`, and Reaticulate's `.reabank` files (read, and written back).
-- Names get their M2-123 codes from the words libraries use
-- (`articulations.m2`); what no word names gets a code of the library's
-- own (classification 1A and up).
--
--   local gen = require("articulations.gen")
--   local spec = gen.sfz("/libs/Violins.sfz")      -- a map as data, or nil and why
--   gen.text(spec)                                  -- as an .art.toml
--   local banks, stats = gen.reabank(text)          -- one spec per bank
--   gen.to_reabank(map)                             -- a map as a bank
local api = paw.api
local music = paw.music
local toml = require("articulations.toml")
local m2 = require("articulations.m2")
local maps = require("articulations.maps")

local M = {}

local function slug(text)
  local s = tostring(text or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  return s ~= "" and s or "art"
end
M.slug = slug

local function read(path)
  local text = maps.read(path)
  if not text then error("cannot read " .. tostring(path), 0) end
  return text
end

--- Give a spec's articulations their codes: a guessed one where a word
--- names it, a variation of it where two would share one, and one of the
--- library's own where nothing does. Returns how many got a guessed code.
function M.code(arts)
  local taken, coded = {}, 0
  local custom = { type = 0x1A, n = 0 }
  for _, a in ipairs(arts) do
    local code = a.m2 or a.guess
    if code then
      coded = coded + 1
      local attr = m2.parse(code)
      -- Two of one code: the next free variation of it.
      local v = 0
      while taken[m2.code(attr)] and v < 15 do
        v = v + 1
        attr.data = bit.bor(bit.band(attr.data, 0xF0FF), bit.lshift(v, 8))
      end
      a.m2 = m2.code(attr)
    else
      repeat
        a.m2 = string.format("%02X.%X%s", custom.type, math.floor(custom.n / 16), custom.n % 16 == 0 and "" or string.format("%X", custom.n % 16))
        custom.n = custom.n + 1
        if custom.n == 256 then custom.type, custom.n = custom.type + 1, 0 end
      until not taken[a.m2]
    end
    taken[a.m2] = true
    M.fill(a)
  end
  return coded
end

-- What the score shows for the articulations it has a sign or a word for,
-- by code: a mark on the note, or a technique's text over the run.
local MARKS = { ["11.0"] = "staccato", ["11.1"] = "staccato", ["11.4"] = "staccatissimo", ["10.6"] = "marcato" }
local TEXTS = {
  ["11.A"] = "pizz.", ["11.B"] = "Bartók pizz.", ["11.C"] = "col legno", ["11.D"] = "col legno", ["12.0"] = "trem.",
  ["14.0"] = "harm.", ["14.1"] = "harm.", ["14.2"] = "col legno", ["14.3"] = "flaut.", ["10.8"] = "senza vib.",
}
-- The colour of each classification (Reaticulate's classes).
local CLASSES = { [0x10] = "long", [0x11] = "short", [0x12] = "long-dark", [0x13] = "long-dark", [0x14] = "long-light",
  [0x15] = "fx", [0x16] = "textured", [0x17] = "fx" }

--- Fill in what a coded articulation leaves out, from the profile: its
--- tag (`stc`, `pz`), its class, and the mark or text the score shows.
function M.fill(a)
  local attr = m2.parse(a.m2)
  local d = attr and paw.attr.describe(attr)
  if not (d and d.code) then return a end
  local base = string.format("%X.%X", attr.type, bit.rshift(attr.data, 12) % 16)
  a.tag = a.tag or d.tag
  local class = CLASSES[attr.type]
  if base == "10.2" or base == "10.3" then class = "legato" end
  if base == "11.A" or base == "11.B" then class = "short-light" end
  a.class = a.class or class
  a.mark = a.mark or MARKS[base]
  a.text = a.text or TEXTS[base]
  return a
end

--- A spec as the text of an `.art.toml`: `{ name, generated, source, match,
--- range, keyswitches, default, chase, family, arts = { { id, name, m2, out,
--- tag, class, text, range, program, icon } } }`.
function M.text(spec)
  local lines = { "# paw articulation map, one instrument" .. (spec.comment and ("\n# " .. spec.comment) or ""), "format = 1" }
  for _, key in ipairs({ "name", "family", "generated", "source", "match", "range", "comfortable", "keyswitches", "default", "send", "chase" }) do
    if spec[key] ~= nil then lines[#lines + 1] = key .. " = " .. toml.inline(spec[key]) end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "[art]"
  local taken = {}
  for _, a in ipairs(spec.arts) do
    local id = a.id or slug(a.name)
    local base, n = id, 2
    while taken[id] do
      id, n = base .. "-" .. n, n + 1
    end
    taken[id] = true
    a.id = id
    local fields = {}
    for _, k in ipairs({ "m2", "out", "tag", "name", "class", "mark", "text", "range", "program", "icon" }) do
      if a[k] ~= nil and a[k] ~= "" then fields[#fields + 1] = k .. " = " .. toml.inline(a[k]) end
    end
    lines[#lines + 1] = toml.key(id) .. " = { " .. table.concat(fields, ", ") .. " }"
  end
  if spec.mods and #spec.mods > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[mod]"
    for _, m in ipairs(spec.mods) do
      lines[#lines + 1] = toml.key(m.id) .. " = " .. toml.inline({ m2 = m.m2, out = m.out, off = m.off, text = m.text }, { "m2", "out", "off", "text" })
    end
  end
  -- Dynamics on the modulation wheel and expression, as most sampled
  -- orchestral libraries take them, unless the spec says otherwise (`linked
  -- = false` for none): `\c` then draws them as one curve.
  if spec.linked ~= false then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[linked]"
    lines[#lines + 1] = spec.linked or 'dynamics = { cc = [1, 11], curve = ["linear", "linear"], default = 0.7, name = "Dynamics" }'
  end
  return table.concat(lines, "\n") .. "\n"
end

local function range_text(lo, hi)
  if not lo then return nil end
  return music.name(lo) .. "-" .. music.name(hi)
end

-- SFZ ------------------------------------------------------------------------------

--- An SFZ's text with its comments gone, `#include`s read in (relative to
--- the first file's directory, as SFZ has them) and `#define`s put in.
local function sfz_source(path, root, defines, depth)
  if depth > 16 then error("#include goes deeper than 16 files: " .. path, 0) end
  local text = read(path):gsub("/%*.-%*/", " "):gsub("//[^\n]*", "")
  local out = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local name, value = line:match("^%s*#define%s+(%$[%w_]+)%s+(.-)%s*$")
    local file = line:match('^%s*#include%s+"([^"]+)"')
    if name then
      defines[#defines + 1] = { name, value }
    elseif file then
      out[#out + 1] = sfz_source(root .. "/" .. file, root, defines, depth + 1)
    else
      -- Longest names first, so that $A does not eat $AB.
      table.sort(defines, function(a, b) return #a[1] > #b[1] end)
      for _, d in ipairs(defines) do line = line:gsub(d[1]:gsub("%$", "%%$"), (d[2]:gsub("%%", "%%%%"))) end
      out[#out + 1] = line
    end
  end
  return table.concat(out, "\n")
end

--- The headers and their opcodes of an SFZ, in order: `{ { header, ops } }`.
function M.sfz_headers(text)
  local out = {}
  for header, body in text:gmatch("<(%w+)>([^<]*)") do
    local ops = {}
    -- A value runs to the next `name=` (sample paths and labels have spaces).
    local s = " " .. body:gsub("%s+", " ") .. " "
    local starts = {}
    for at, name in s:gmatch("()%s([%w_]+)=") do starts[#starts + 1] = { at = at, name = name } end
    for i, st in ipairs(starts) do
      local from = st.at + #st.name + 2
      local to = starts[i + 1] and starts[i + 1].at - 1 or #s
      ops[st.name] = s:sub(from, to):gsub("^%s+", ""):gsub("%s+$", "")
    end
    out[#out + 1] = { header = header, ops = ops }
  end
  return out
end

local function sfz_key(v)
  return v and maps.key(v)
end

--- A map spec from an SFZ's keyswitches, or nil and why.
function M.sfz(path)
  local dir = path:match("^(.*)/[^/]*$") or "."
  local text = sfz_source(path, dir, {}, 0)
  local levels = { control = {}, global = {}, master = {}, group = {} }
  local order = { "control", "global", "master", "group", "region" }
  local switches, by_key = {}, {}
  local lo, hi, sw_lo, sw_hi, sw_default
  local labels = {}
  local function reset(from)
    local found = false
    for _, name in ipairs(order) do
      if name == from then found = true end
      if found and levels[name] then levels[name] = {} end
    end
  end
  for _, h in ipairs(M.sfz_headers(text)) do
    if levels[h.header] then
      reset(h.header)
      for k, v in pairs(h.ops) do levels[h.header][k] = v end
    end
    for k, v in pairs(h.ops) do
      local n = k:match("^label_key(%d+)$")
      if n then labels[tonumber(n)] = v end
    end
    if h.header == "region" then
      local op = {}
      for _, name in ipairs({ "control", "global", "master", "group" }) do
        for k, v in pairs(levels[name]) do op[k] = v end
      end
      for k, v in pairs(h.ops) do op[k] = v end
      sw_lo, sw_hi = sfz_key(op.sw_lokey) or sw_lo, sfz_key(op.sw_hikey) or sw_hi
      sw_default = sfz_key(op.sw_default) or sw_default
      local key = sfz_key(op.key)
      local rlo, rhi = sfz_key(op.lokey) or key or 0, sfz_key(op.hikey) or key or 127
      local sw = sfz_key(op.sw_last) or sfz_key(op.sw_lolast)
      local held = sfz_key(op.sw_down)
      local k = sw or held
      if k then
        local s = by_key[k]
        if not s then
          s = { key = k, held = held ~= nil and sw == nil, label = op.sw_label, lo = rlo, hi = rhi }
          by_key[k] = s
          switches[#switches + 1] = s
        end
        s.label = s.label or op.sw_label
        s.lo, s.hi = math.min(s.lo, rlo), math.max(s.hi, rhi)
      end
      -- The keys the instrument plays: those of regions that are no keyswitch themselves.
      if not (sw_lo and rlo >= sw_lo and rhi <= (sw_hi or sw_lo)) then
        lo, hi = math.min(lo or rlo, rlo), math.max(hi or rhi, rhi)
      end
    end
  end
  if #switches == 0 then return nil, path:match("[^/]+$") .. " has no keyswitches (sw_last, sw_down)" end
  table.sort(switches, function(a, b) return a.key < b.key end)
  local arts, default = {}, nil
  for _, s in ipairs(switches) do
    local name = s.label or labels[s.key] or ("Keyswitch " .. music.name(s.key))
    local a = { name = name, guess = m2.guess(name), out = (s.held and "hold=" or "ks=") .. music.name(s.key),
      range = range_text(s.lo, s.hi) }
    arts[#arts + 1] = a
    if s.key == sw_default then default = a end
  end
  local coded = M.code(arts)
  local spec = {
    name = path:match("([^/]+)%.[^.]*$") or path, generated = "sfz:" .. path, match = { "sfz:" .. path:match("[^/]+$") },
    range = range_text(lo, hi), keyswitches = range_text(sw_lo or switches[1].key, sw_hi or switches[#switches].key), arts = arts,
  }
  M.text(spec)  -- gives the articulations their ids
  spec.default = (default or arts[1]).id
  return spec, { articulations = #arts, coded = coded }
end

-- Decent Sampler ---------------------------------------------------------------------

--- The elements of an XML text, as a tree of `{ name, attrs, kids }`:
--- enough for a preset's groups and its MIDI bindings.
function M.xml(text)
  text = text:gsub("^\239\187\191", ""):gsub("<!%-%-.-%-%->", ""):gsub("<%?.-%?>", ""):gsub("<!%[CDATA%[.-%]%]>", "")
  local root = { name = "", attrs = {}, kids = {} }
  local stack = { root }
  for close, name, attrs, empty in text:gmatch("<(/?)([%w_:%.%-]+)(.-)(/?)>") do
    if close == "/" then
      if #stack > 1 then table.remove(stack) end
    else
      local el = { name = name, attrs = {}, kids = {} }
      for k, _, v in attrs:gmatch("([%w_:%.%-]+)%s*=%s*([\"'])(.-)%2") do
        el.attrs[k] = v:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&")
      end
      local top = stack[#stack]
      top.kids[#top.kids + 1] = el
      if empty ~= "/" then stack[#stack + 1] = el end
    end
  end
  return root
end

local function each(el, name, fn)
  for _, kid in ipairs(el.kids) do
    if kid.name == name then fn(kid) end
    each(kid, name, fn)
  end
end

--- A map spec from a Decent Sampler preset's text (`.dspreset`), or nil and why.
function M.ds_text(text, name)
  local root = M.xml(text)
  local groups = {}
  each(root, "group", function(g)
    local lo, hi
    each(g, "sample", function(s)
      local a, b = tonumber(s.attrs.loNote or s.attrs.rootNote), tonumber(s.attrs.hiNote or s.attrs.rootNote)
      if a then lo = math.min(lo or a, a) end
      if b then hi = math.max(hi or b, b) end
    end)
    groups[#groups + 1] = { name = g.attrs.name or g.attrs.tags or ("Group " .. (#groups + 1)), lo = lo, hi = hi }
  end)
  local arts = {}
  local all_lo, all_hi
  for _, g in ipairs(groups) do
    if g.lo then all_lo, all_hi = math.min(all_lo or g.lo, g.lo), math.max(all_hi or g.hi, g.hi) end
  end
  each(root, "midi", function(midi)
    for _, note in ipairs(midi.kids) do
      if note.name == "note" and tonumber(note.attrs.note) then
        local on, lo, hi = {}, nil, nil
        for _, b in ipairs(note.kids) do
          local value = tostring(b.attrs.translationValue or ""):lower()
          if b.name == "binding" and b.attrs.parameter == "ENABLED" and (b.attrs.level or "group") == "group"
            and (value == "true" or value == "1") then
            local i = tonumber(b.attrs.position or b.attrs.groupIndex)
            local g = i and groups[i + 1]
            if g then
              on[#on + 1] = g.name
              if g.lo then lo, hi = math.min(lo or g.lo, g.lo), math.max(hi or g.hi, g.hi) end
            end
          end
        end
        if #on > 0 then
          local label = table.concat(on, " + ")
          arts[#arts + 1] = { name = label, guess = m2.guess(label), out = "ks=" .. music.name(tonumber(note.attrs.note)), range = range_text(lo, hi),
            key = tonumber(note.attrs.note) }
        end
      end
    end
  end)
  if #arts == 0 then return nil, (name or "the preset") .. " has no keyswitches (<midi><note> bindings that enable groups)" end
  local coded = M.code(arts)
  local ks_lo, ks_hi
  for _, a in ipairs(arts) do
    ks_lo, ks_hi = math.min(ks_lo or a.key, a.key), math.max(ks_hi or a.key, a.key)
    a.key = nil
  end
  local spec = { name = name, range = range_text(all_lo, all_hi), keyswitches = range_text(ks_lo, ks_hi), arts = arts }
  M.text(spec)
  spec.default = arts[1].id
  return spec, { articulations = #arts, coded = coded }
end

--- A map spec from a `.dspreset` file, or from the first preset in a
--- `.dslibrary` (a zip, `paw.zip`).
function M.ds(path)
  local name = path:match("([^/]+)%.[^.]*$") or path
  local text = read(path)
  if path:lower():match("%.dslibrary$") then
    local files, err = paw.zip.read(text)
    if not files then return nil, path .. ": " .. err end
    local names = {}
    for file in pairs(files) do
      if file:lower():match("%.dspreset$") then names[#names + 1] = file end
    end
    table.sort(names)
    if #names == 0 then return nil, path .. " holds no .dspreset" end
    text = files[names[1]]
  end
  local spec, stats = M.ds_text(text, name)
  if not spec then return nil, stats end
  spec.generated, spec.match = "dspreset:" .. path, { "dspreset:" .. path:match("[^/]+$") }
  return spec, stats
end

-- Folders ------------------------------------------------------------------------------

local AUDIO = { wav = true, flac = true, ogg = true, aif = true, aiff = true }

--- A map spec from a folder whose folders are articulations (VSCO 2 CE's
--- layout: `Violin/Spiccato/Violin_Spic_A4_v1_rr1.wav`). The notes' names
--- in the files give each its range.
function M.folder(dir)
  dir = dir:gsub("/+$", "")
  local arts, all_lo, all_hi = {}, nil, nil
  local subs = {}
  for _, item in ipairs(api.read_dir(dir)) do
    if item.is_dir then subs[#subs + 1] = item.name end
  end
  table.sort(subs)
  for _, sub in ipairs(subs) do
    local lo, hi, count = nil, nil, 0
    for _, f in ipairs(api.read_dir(dir .. "/" .. sub)) do
      local ext = f.name:match("%.(%w+)$")
      if not f.is_dir and ext and AUDIO[ext:lower()] then
        count = count + 1
        for word in f.name:gsub("%.%w+$", ""):gmatch("[^_%s%-]+") do
          local ok, p = pcall(music.pitch, word:sub(1, 1):upper() .. word:sub(2))
          if ok and p >= 0 and p <= 127 then
            lo, hi = math.min(lo or p, p), math.max(hi or p, p)
            break
          end
        end
      end
    end
    if count > 0 then
      local name = sub:gsub("_", " ")
      arts[#arts + 1] = { name = name, guess = m2.guess(name), out = "attr", range = range_text(lo, hi) }
      if lo then all_lo, all_hi = math.min(all_lo or lo, lo), math.max(all_hi or hi, hi) end
    end
  end
  if #arts < 1 then return nil, dir .. " has no folders of samples to be articulations" end
  local coded = M.code(arts)
  local spec = { name = dir:match("[^/]+$"), generated = "folder:" .. dir, match = { "folder:" .. dir:match("[^/]+$") },
    range = range_text(all_lo, all_hi), arts = arts, comment = "Played by the attribute alone: a sampler that reads the folder chooses the samples." }
  M.text(spec)
  local sus
  for _, a in ipairs(arts) do
    if not sus and a.m2 == "10.0" then sus = a end
  end
  spec.default = (sus or arts[1]).id
  return spec, { articulations = #arts, coded = coded }
end

-- A sampler device's describe ------------------------------------------------------------

--- A map spec from what a sampler device says of its instrument
--- (`device_call(id, "describe")`: `{ name, format, range = { lo, hi },
--- keyswitches = { { pitch, name } }, articulations = { { name, m2?, keyswitch? } } }`).
function M.describe(d)
  local arts = {}
  local ks = {}
  for _, k in ipairs(d.keyswitches or {}) do ks[k.name or ""] = k.pitch end
  for _, a in ipairs(d.articulations or {}) do
    local key = tonumber(a.keyswitch) or ks[a.name or ""]
    arts[#arts + 1] = { name = a.name or "?", m2 = a.m2 and m2.parse(a.m2) and m2.code(m2.parse(a.m2)) or nil,
      guess = m2.guess(a.name), out = key and ("ks=" .. music.name(key) .. " attr") or "attr" }
  end
  if #arts == 0 then
    for _, k in ipairs(d.keyswitches or {}) do
      arts[#arts + 1] = { name = k.name or music.name(k.pitch), guess = m2.guess(k.name), out = "ks=" .. music.name(k.pitch) }
    end
  end
  if #arts == 0 then return nil, (d.name or "the device") .. " names no articulations or keyswitches" end
  local coded = M.code(arts)
  local klo, khi
  for _, k in ipairs(d.keyswitches or {}) do
    if tonumber(k.pitch) then klo, khi = math.min(klo or k.pitch, k.pitch), math.max(khi or k.pitch, k.pitch) end
  end
  local range = d.range and (d.range.lo or d.range[1]) and range_text(d.range.lo or d.range[1], d.range.hi or d.range[2]) or nil
  local spec = { name = d.name or "Sampler", generated = "describe:" .. tostring(d.format or "?") .. ":" .. tostring(d.name or ""),
    match = { "describe:" .. tostring(d.name or "") }, range = range, keyswitches = range_text(klo, khi), arts = arts }
  M.text(spec)
  spec.default = arts[1].id
  return spec, { articulations = #arts, coded = coded }
end

-- Reaticulate ----------------------------------------------------------------------------

--- `//! k=v k="v w"` as a table.
local function reabank_attrs(text, into)
  local at = 1
  while true do
    local s, e, k = text:find("([%w%-]+)=", at)
    if not s then return into end
    local v
    if text:sub(e + 1, e + 1) == '"' then
      local close = text:find('"', e + 2, true) or #text + 1
      v, at = text:sub(e + 2, close - 1), close + 1
    else
      v = text:match("^%S*", e + 1)
      at = e + 1 + #v
    end
    into[k] = v
  end
end

--- Numbers of a list such as `1,11,16-21,64-69`.
local function numbers(text)
  local out = {}
  for part in tostring(text or ""):gmatch("[^,%s]+") do
    local a, b = part:match("^(%d+)%-(%d+)$")
    if a then
      for n = tonumber(a), tonumber(b) do out[#out + 1] = n end
    elseif tonumber(part) then
      out[#out + 1] = tonumber(part)
    end
  end
  return out
end

--- Reaticulate's output events (`cc:32,40/note:24`) as an out line, and
--- whether every one could be said.
function M.out_of_reaticulate(o)
  local words, whole = {}, true
  for ev in tostring(o or ""):gmatch("[^/]+") do
    local kind, ch, args = ev:match("^%-?([%a%-]*)@?([%d%.%-]*):?([%d,%-]*)")
    local a = {}
    for n in (args or ""):gmatch("[^,]+") do a[#a + 1] = tonumber(n) end
    if kind == "cc" and a[1] and a[2] then
      words[#words + 1] = "cc" .. a[1] .. "=" .. a[2]
    elseif (kind == "note" or kind == "note-hold") and a[1] then
      words[#words + 1] = (kind == "note" and "ks=" or "hold=") .. music.name(a[1]) .. (a[2] and a[2] ~= 127 and a[2] > 0 and (":" .. a[2]) or "")
    elseif kind == "program" and a[1] then
      words[#words + 1] = "pc=" .. a[1]
    elseif kind == "pitch" and a[1] then
      words[#words + 1] = "bend=" .. string.format("%.4g", math.max(-1, math.min(1, a[1] / 8192)))
    else
      whole = false
    end
    local channel = tonumber((ch or ""):match("^(%d+)"))
    if channel and channel >= 1 and channel <= 16 then words[#words + 1] = "ch=" .. channel end
  end
  return table.concat(words, " "), whole
end

local PLAIN_ICONS = { [""] = true, ["note-eighth"] = true, ["note-whole"] = true, ["note-quarter"] = true, fx = true }

--- The banks of a `.reabank` text, each a map spec, and how many
--- articulations there were and how many got a code from their icon or name.
function M.reabank(text)
  local banks, attrs = {}, {}
  local stats = { banks = 0, articulations = 0, coded = 0, by_icon = 0, outs_lost = 0 }
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("\r$", ""):gsub("^%s+", "")
    if line:sub(1, 3) == "//!" then
      reabank_attrs(line:sub(4), attrs)
    elseif line:match("^Bank%s") then
      local name = line:match("^Bank%s+%S+%s+%S+%s+(.*)$") or "Bank"
      banks[#banks + 1] = { name = name, attrs = attrs, arts = {} }
      attrs = {}
    elseif line:match("^%d+%s") and #banks > 0 then
      local program, name = line:match("^(%d+)%s+(.-)%s*$")
      table.insert(banks[#banks].arts, { program = tonumber(program), name = name, attrs = attrs })
      attrs = {}
    elseif not line:match("^//") then
      attrs = {}
    end
  end
  local out, by_id = {}, {}
  for _, bank in ipairs(banks) do
    if bank.attrs.id then by_id[bank.attrs.id] = bank end
  end
  for _, bank in ipairs(banks) do
    stats.banks = stats.banks + 1
    local arts, mods = {}, {}
    -- A clone has the articulations of another bank.
    local source = bank.attrs.clone and #bank.arts == 0 and by_id[bank.attrs.clone] or bank
    for _, a in ipairs(source.arts) do
      stats.articulations = stats.articulations + 1
      local icon = a.attrs.i or ""
      -- Icons first: "trill m2" and "trill M2" differ only by case, which names lose.
      local by_icon = not PLAIN_ICONS[icon] and m2.guess(icon) or nil
      local code = by_icon or m2.guess(a.name) or m2.guess(icon)
      if code then stats.coded = stats.coded + 1 end
      if code and not m2.guess(a.name) then stats.by_icon = stats.by_icon + 1 end
      local outline, whole = M.out_of_reaticulate(a.attrs.o)
      if not whole then stats.outs_lost = stats.outs_lost + 1 end
      arts[#arts + 1] = { name = a.name, guess = code, out = outline, class = a.attrs.c, program = a.program,
        icon = icon ~= "" and icon or nil }
    end
    M.code(arts)
    local group = bank.attrs.g or "Reaticulate"
    local name = bank.attrs.n or bank.name
    local spec = { name = name, family = nil, source = "reaticulate:" .. (bank.attrs.id or name),
      match = { "reaticulate:" .. group .. "/" .. name }, chase = bank.attrs.chase and numbers(bank.attrs.chase) or nil,
      arts = arts, mods = mods, file = slug(group:gsub("/", " ")) .. "/" .. slug(name), group = group }
    if #arts > 0 then
      M.text(spec)
      spec.default = arts[1].id
      for _, a in ipairs(arts) do
        if a.m2 == "10.0" then
          spec.default = a.id
          break
        end
      end
      out[#out + 1] = spec
    end
  end
  return out, stats
end

-- Spitfire's UACC numbers, by code: what Reaticulate's banks use as program numbers.
local UACC = { ["10.0"] = 1, ["10.2"] = 20, ["11.0"] = 40, ["11.5"] = 42, ["11.4"] = 41, ["11.A"] = 56, ["11.B"] = 57,
  ["11.C"] = 58, ["12.0"] = 11, ["13.0"] = 70, ["13.2"] = 71, ["14.0"] = 10, ["10.6"] = 52, ["10.4"] = 23 }

--- A map as a Reaticulate bank (`.reabank` text). What a bank cannot say
--- (ranges, keyswitch rows, codes, notation marks) is left out.
function M.to_reabank(map)
  local lines = {
    "//! g=\"paw\" n=\"" .. map.name:gsub('"', "'") .. "\"",
  }
  if #map.chase > 0 then
    local nums = {}
    for i, n in ipairs(map.chase) do nums[i] = tostring(n) end
    lines[#lines + 1] = "//! chase=" .. table.concat(nums, ",")
  end
  lines[#lines + 1] = "Bank * * paw - " .. map.name
  lines[#lines + 1] = ""
  local used, next_free = {}, 100
  for _, a in ipairs(map.arts) do
    local program = a.program or UACC[a.code]
    if not program or used[program] then
      while used[next_free] do next_free = next_free + 1 end
      program = next_free
    end
    used[program] = true
    local outs, channel = {}, nil
    for _, e in ipairs(a.events) do
      if e.type == "note" then
        outs[#outs + 1] = "note:" .. e.key .. (e.velocity ~= 100 and ("," .. e.velocity) or "")
      elseif e.type == "hold" then
        outs[#outs + 1] = "note-hold:" .. e.key .. (e.velocity ~= 100 and ("," .. e.velocity) or "")
      elseif e.type == "cc" then
        outs[#outs + 1] = "cc:" .. e.number .. "," .. e.value
      elseif e.type == "program" then
        outs[#outs + 1] = "program:" .. e.program
      elseif e.type == "bend" then
        outs[#outs + 1] = "pitch:" .. math.floor(e.value * 8192 + 0.5)
      elseif e.type == "channel" then
        channel = e.channel
      end
    end
    if channel then
      if #outs == 0 then outs[1] = "@" .. channel else
        for i, o in ipairs(outs) do outs[i] = o:gsub("^([%a%-]+)", "%1@" .. channel) end
      end
    end
    local head = "//! c=" .. (a.class or "default") .. " i=" .. (a.icon or a.id)
    if #outs > 0 then head = head .. " o=" .. table.concat(outs, "/") end
    lines[#lines + 1] = head
    lines[#lines + 1] = program .. " " .. a.name
  end
  return table.concat(lines, "\n") .. "\n"
end

return M
