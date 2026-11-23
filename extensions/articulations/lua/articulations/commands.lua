-- Commands and keys: `:art` over Ex ranges and `:g` matches, the `art`
-- field of patterns, binding maps, the track's default and pen, modifiers,
-- making maps from libraries and banks, and the piano roll's keys: `\a`
-- (the articulation popover, heard as the highlight moves), `\A`
-- (modifiers), `\a` in insert mode (the pen) and the text objects `ia` `aa`.
local api = paw.api
local util = paw.util
local art = require("articulations")
local maps = art.maps
local m2 = art.m2
local gen = require("articulations.gen")
local keymap = paw.keymap
local command = paw.command

local M = {}
local roll = paw.ui.views:get("pianoroll")

local function fail(text) error(text, 0) end

local function words(ctx) return (tostring(ctx.args[1] or ""):match("^%s*(.-)%s*$")) end

--- The track the roll or the cursor is on.
local function current_track()
  local clip = roll:clip()
  if paw.ui.focused == "pianoroll" and clip then return clip:get().track end
  local t = paw.cursor.track()
  return t and t.id
end

--- The notes a command works on, as `{ clip, place, note, track }`: what
--- its range holds (`:5,8art`, `:'<,'>art`, the matches of `:g`), else
--- the note under the roll's cursor.
local function places_of(ctx)
  local out = {}
  if ctx.range then
    for _, item in ipairs(paw.ex.items(ctx.range, "note")) do
      out[#out + 1] = { clip = item.clip.id, place = item.place, note = item.note, track = item.track }
    end
    return out
  end
  if paw.ui.focused == "pianoroll" or roll:clip() then
    local note, place, portion = roll:note_at(roll.pitch, roll.beat)
    if note then
      local n = portion.clip:notes()[place]
      out[1] = { clip = portion.id, place = place, note = n, track = portion.track }
    end
  end
  return out
end
M.places_of = places_of

local function tracks_of(places)
  local seen, out = {}, {}
  for _, p in ipairs(places) do
    if not seen[p.track] then
      seen[p.track], out[#out + 1] = true, p.track
    end
  end
  return out
end

--- Set an articulation by what is typed, on places of possibly several
--- tracks: each track's own map says what the text means.
local function set_by_text(places, text)
  local by_track = {}
  for _, p in ipairs(places) do
    by_track[p.track] = by_track[p.track] or {}
    table.insert(by_track[p.track], p)
  end
  local changed, said = 0, nil
  for _, track in ipairs(tracks_of(places)) do
    local map = art.map_of(track)
    local choice, why = art.lookup(map, text)
    if choice == nil then fail(why) end
    changed = changed + art.set(by_track[track], choice)
    said = choice and (choice.art and choice.art.name or m2.describe(choice.attr)) or "no articulation (the default)"
  end
  return changed, said
end

command("art", function(ctx)
  local text = words(ctx)
  if text == "" then return M.popover() end
  local places = places_of(ctx)
  if #places == 0 then fail("no note here: put the cursor on a note, or give a range (`:'<,'>art stc`)") end
  local changed, said = set_by_text(places, text)
  paw.notify(
    string.format("%s on %d note%s", said, #places, #places == 1 and "" or "s")
      .. (changed < #places and string.format(" (%d had it)", #places - changed) or "")
  )
end, {
  range = true,
  raw = true,
  label = "Articulation",
  desc = "Give notes an articulation: the note under the cursor, or a range (`:'<,'>art stc`, `:5,8art pizz`, `:g/art=pizz/art arco`); `none` takes it away; alone, the popover",
  complete = function(text)
    local map = art.map_of(current_track())
    local out = {}
    if map then
      for _, a in ipairs(map.arts) do
        out[#out + 1] = a.id
      end
    end
    out[#out + 1] = "none"
    return out
  end,
})
paw.commands.get("art").items = true

-- `:g/art=pizz/`, `:s/art=pizz/art=stc/`: a note's articulation by its tag
-- (or its code where no map names it); "" for none.
paw.ex.field("art", {
  level = "note",
  type = "text",
  desc = "the note's articulation: its tag (`stc`), or its M2-123 code; empty for none",
  get = function(item) return art.tag_of(item.track, item.note) or "" end,
  set = function(item, value, change)
    local choice, why = art.lookup(art.map_of(item.track), value)
    if choice == nil then fail(why) end
    for k, v in pairs(art.attr_fields(item.note, choice and choice.attr)) do
      change[k] = v
    end
  end,
})

-- Binding ----------------------------------------------------------------------------

local function need_track()
  local id = current_track()
  if not id then fail("no track here") end
  return id
end

command("art.map", function(ctx)
  local which = words(ctx)
  local track = need_track()
  if which == "" and #maps.matching(track) == 0 then return M.pick_map(track) end
  maps.forget()
  local map = art.bind(track, which ~= "" and which or nil)
  paw.notify(string.format("%s: %d articulations, %s by default", map.name, #map.arts, map.by_id[map.default].name))
end, {
  raw = true,
  desc = "Bind an articulation map to the track: `art.map violin-section`; alone, the one whose `match` names its instrument, else a list",
  complete = function()
    local out = {}
    for _, f in ipairs(maps.list()) do
      out[#out + 1] = f.id
    end
    return out
  end,
})

command("art.unmap", function()
  local track = need_track()
  art.unbind(track)
  paw.notify("no articulation map: the notes keep their articulations")
end, { desc = "Take the track's articulation map away (the notes keep their articulations)" })

command("art.maps", function()
  local lines = { { text = "Articulation maps", style = "Title" }, "" }
  for _, f in ipairs(maps.list()) do
    local map, err = maps.load(f.file, f.id)
    lines[#lines + 1] = string.format(
      "  %-32s %-9s %s",
      f.id,
      f.kind,
      map and (map.name .. " · " .. #map.arts .. " articulations") or ("error: " .. tostring(err))
    )
  end
  if #lines == 2 then
    lines[#lines + 1] = "  none yet: put .art.toml files in " .. api.env().config_dir .. "/articulations"
  end
  paw.ui.page("Articulation maps", lines)
end, { desc = "List the articulation maps there are, where they are from, and any that does not read" })

command("art.shift", function(ctx)
  local track = need_track()
  local text = words(ctx)
  local map = art.map_of(track)
  if not map then fail("the track has no articulation map: :art.map") end
  local now = (art.info(track) or {}).shift or 0
  if text == "" then
    paw.notify(
      string.format(
        "%s: keyswitches %s, shifted %+d keys",
        map.name,
        map.keyswitches and (paw.music.name(map.keyswitches[1]) .. "-" .. paw.music.name(map.keyswitches[2])) or "none",
        now
      )
    )
    return
  end
  -- `+12`, `-1`, `0`; `+1oct`, `-2oct` in octaves; with `+`/`-` from where it is now only with `rel`.
  local sign, n, unit = text:match("^([%+%-]?)(%d+)%s*(o?c?t?)$")
  if not n then fail("`" .. text .. "`: a number of keys (`-12`, `+1`, `0`) or of octaves (`-1oct`)") end
  local shift = tonumber(n) * (unit == "oct" and 12 or 1) * (sign == "-" and -1 or 1)
  if unit ~= "" and unit ~= "oct" then fail("`" .. text .. "`: a number of keys (`-12`) or of octaves (`-1oct`)") end
  local moved = art.set_shift(track, shift)
  local ks = moved.keyswitches
  paw.notify(
    string.format(
      "%s: keyswitches shifted %+d keys%s",
      moved.name,
      shift,
      ks and (", now " .. paw.music.name(ks[1]) .. "-" .. paw.music.name(ks[2])) or ""
    )
  )
end, {
  raw = true,
  label = "Shift keyswitches",
  desc = "Move the keyswitches of the track's map by keys (`art.shift -12`) or octaves (`art.shift +1oct`), for an instrument whose keyswitch area you moved; `art.shift 0` puts them back; alone, says where they are",
})

-- A plugin put on a track with no map binds the map whose `match` names it.
paw.option.define("art_auto_map", true)
local known_devices = {}
local function know_all()
  for _, t in ipairs(api.track_list()) do
    local ok, devices = pcall(api.track_get, t, "devices")
    for _, d in ipairs(ok and devices or {}) do
      known_devices[type(d) == "table" and d.id or d] = true
    end
  end
end
M.know_all = know_all
know_all()
paw.on("project.loaded", function()
  known_devices = {}
  know_all()
end)
--- The map whose `match` names a plugin device (`device_get`'s table), or nil.
function M.plugin_map(device)
  if type(device) ~= "table" or type(device.plugin) ~= "table" then return nil end
  for _, f in ipairs(maps.list()) do
    local map = maps.load(f.file, f.id)
    for _, entry in ipairs(map and map.match or {}) do
      if maps.plugin_matches(entry, device) then return map end
    end
  end
end

--- Bind the map of a plugin to its track, when the track has none, as its
--- own undo step. Returns the map bound, or nil.
function M.auto_map(track, device)
  if not paw.opt.art_auto_map then return nil end
  local info = art.info(track)
  if info and info.map then return nil end
  local map = M.plugin_map(device)
  if not map then return nil end
  api.undo_checkpoint()
  if not pcall(art.bind, track, map.id) then return nil end
  api.undo_checkpoint()
  paw.notify(string.format("%s: articulation map %s bound (:art.unmap takes it away)", device.name or map.name, map.id))
  return map
end

-- Only a device added after the project opened: a project that opens keeps
-- the maps that it has.
paw.on("device.added", function(e)
  if not e or not e.id or known_devices[e.id] then return end
  known_devices[e.id] = true
  if not paw.opt.art_auto_map or not e.track then return end
  paw.defer(function()
    local ok, d = pcall(api.device_get, e.id)
    if ok then M.auto_map(e.track, d) end
  end, 0)
end)

--- A picker of every map, to bind one to a track.
function M.pick_map(track)
  local items = {}
  for _, f in ipairs(maps.list()) do
    local map = maps.load(f.file, f.id)
    if map then items[#items + 1] = { id = f.id, map = map, kind = f.kind } end
  end
  paw.pick({
    title = "Articulation map",
    items = items,
    format = function(it) return string.format("%-32s %s · %d articulations", it.id, it.map.name, #it.map.arts) end,
    empty = "No maps: put .art.toml files in " .. api.env().config_dir .. "/articulations, or :art.generate a library",
    on_choose = function(it) paw.commands.exec("art.map " .. it.id) end,
  })
end

local function lookup_one(track, text)
  local map = art.map_of(track)
  local choice, why = art.lookup(map, text)
  if choice == nil then fail(why) end
  return choice, map
end

command("art.default", function(ctx)
  local track = need_track()
  local text = words(ctx)
  local map = art.map_of(track)
  if not map then fail("the track has no articulation map: :art.map") end
  if text == "" then return M.popover({ mode = "default" }) end
  local choice = lookup_one(track, text)
  if not choice or not choice.art then fail("the default is one of the map's articulations: " .. art.names(map)) end
  art.set_track(track, "default", choice.art.id)
  paw.notify("by default " .. choice.art.name)
end, {
  raw = true,
  label = "Default articulation",
  desc = "The articulation the track's notes without one play: `art.default sustain`",
})

command("art.pen", function(ctx)
  local track = need_track()
  local text = words(ctx)
  if text == "" then return M.popover({ mode = "pen" }) end
  local choice = lookup_one(track, text)
  local id = choice and (choice.art and choice.art.id or m2.code(choice.attr)) or nil
  art.set_track(track, "pen", id)
  paw.notify(id and ("new notes: " .. (choice.art and choice.art.name or id)) or "new notes: no articulation")
  api.ui_redraw()
end, {
  raw = true,
  label = "Articulation pen",
  desc = "The articulation notes entered from now on get (insert mode, the mouse): `art.pen stc`; `none` for none",
})

-- Modifiers ---------------------------------------------------------------------------

--- Write a modifier's events at the start of a stretch of a clip and its
--- `off` events at the end, as controller moves of the clip.
local function write_mod(clip_id, mod, from, to)
  local clip = paw.clip(clip_id)
  local list = clip:controls()
  local function add(events, at)
    for _, e in ipairs(events) do
      if e.type == "cc" then list[#list + 1] = { start = at, type = "cc", number = e.number, value = e.value / 127 } end
      if e.type == "program" then
        list[#list + 1] = { start = at, type = "program", program = e.program, bank = e.bank }
      end
      if e.type == "bend" then list[#list + 1] = { start = at, type = "bend", value = e.value } end
    end
  end
  add(mod.on_events, from)
  add(mod.off_events, to)
  clip:set_controls(list)
end

command("art.mod", function(ctx)
  local text = words(ctx)
  if text == "" then return M.popover({ mode = "mod" }) end
  local places = places_of(ctx)
  if #places == 0 then fail("no note here: put the cursor on a note, or give a range") end
  local map = art.map_of(places[1].track)
  if not map or #map.mods == 0 then fail("the track's map has no modifiers ([mod] in its file)") end
  local mod
  for _, m in ipairs(map.mods) do
    if m.id == text or m.tag == text or (m.text or ""):lower() == text:lower() or m.id:sub(1, #text) == text then
      mod = mod or m
    end
  end
  if not mod then fail("`" .. text .. "` is no modifier of " .. map.name) end
  local spans = {}
  for _, p in ipairs(places) do
    local s = spans[p.clip] or { from = math.huge, to = -math.huge }
    spans[p.clip] = s
    s.from, s.to = math.min(s.from, p.note.start), math.max(s.to, p.note.start + p.note.length)
  end
  for id, s in pairs(spans) do
    write_mod(id, mod, s.from, s.to)
  end
  paw.notify((mod.text or mod.name) .. " over " .. #places .. " note" .. (#places == 1 and "" or "s"))
end, {
  range = true,
  raw = true,
  label = "Modifier",
  desc = "A modifier of the map (con sord., sul pont.) over the notes: its controllers at their start, its `off` at their end: `:'<,'>art.mod con-sord`",
})

-- The popover --------------------------------------------------------------------------

--- The phrase that lets an articulation be heard: the notes it is for,
--- after the keyswitch notes that tell a MIDI 1.0 instrument; its
--- controllers and program are sent first.
local function hear(track, places, a)
  local notes, from, to = {}, math.huge, -math.huge
  for _, p in ipairs(places) do
    local c = api.clip_get(p.clip)
    from, to = math.min(from, c.start + p.note.start), math.max(to, c.start + p.note.start + p.note.length)
  end
  if from == math.huge then return end
  local lead = 0
  if a then
    for _, e in ipairs(a.events) do
      if e.type == "note" or e.type == "hold" then
        notes[#notes + 1] = { pitch = e.key, start = 0, length = 1 / 16, velocity = e.velocity or 100 }
        lead = 1 / 8
      elseif e.type == "cc" then
        pcall(api.midi_send, track, { type = "cc", number = e.number, value = e.value / 127 })
      elseif e.type == "program" then
        pcall(api.midi_send, track, { type = "program", program = e.program, bank = e.bank })
      end
    end
  end
  for _, p in ipairs(places) do
    local c = api.clip_get(p.clip)
    notes[#notes + 1] = {
      pitch = p.note.pitch,
      start = lead + c.start + p.note.start - from,
      length = p.note.length,
      velocity = p.note.velocity,
    }
  end
  paw.audition.phrase(track, notes, { length = lead + (to - from), at = from, loop = false })
end

--- The popover: the track's articulations, numbered, each heard on the
--- notes it is for as the highlight rests on it (the edit a trial, taken
--- back unless chosen). `opts.mode`: nil for notes, "default", "pen", "mod".
function M.popover(opts)
  opts = opts or {}
  local mode = opts.mode
  local range = ""
  if not mode and keymap.mode == "x" and keymap.selection() then
    range = "'<,'>"
    keymap.set_mode("n")
  end
  local entering = keymap.mode == "i"
  if entering and not mode then mode = "pen" end
  local track = need_track()
  local map = art.map_of(track)
  if not map and mode ~= "pen" and mode ~= nil then fail("the track has no articulation map: :art.map") end
  local places = {}
  if not mode or mode == "mod" then
    places = places_of(range ~= "" and { range = paw.ex.selection_range() } or {})
    if #places == 0 then fail("no note here: put the cursor on a note, or choose some in visual mode") end
  end
  local items = {}
  local info = art.info(track) or {}
  if mode == "mod" then
    for i, m in ipairs(map and map.mods or {}) do
      items[#items + 1] = { i = i, mod = m }
    end
  elseif map then
    for i, a in ipairs(map.arts) do
      items[#items + 1] = { i = i, art = a }
    end
    if not mode or mode == "pen" then items[#items + 1] = { i = 0, none = true } end
  else
    -- No map: the profile's own names.
    for i, word in ipairs({ "10.0", "10.2", "11.0", "11.4", "11.5", "11.A", "11.C", "12.0", "13.0", "13.2", "14.0" }) do
      items[#items + 1] = { i = i, code = word, attr = m2.parse(word) }
    end
    items[#items + 1] = { i = 0, none = true }
  end
  local title = ({ default = "Default articulation", pen = "Articulation pen", mod = "Modifier" })[mode]
    or string.format("Articulation · %d note%s", #places, #places == 1 and "" or "s")
  local function word_of(it)
    if it.none then return "none" end
    if it.mod then return it.mod.id end
    if it.art then return it.art.id end
    return it.code
  end
  paw.pick({
    title = title,
    items = items,
    top = true,
    height = math.min(20, #items + 4),
    format = function(it)
      if it.none then return "0 —    none                     the track's default plays" end
      if it.mod then
        return string.format(
          "%d %-4s %-22s %-14s %s",
          it.i,
          it.mod.tag,
          it.mod.text or it.mod.name,
          it.mod.m2 or "",
          it.mod.out
        )
      end
      if it.art then
        local here = (mode == "default" and info.default == it.art.id or mode == "pen" and info.pen == it.art.id)
            and " ◂"
          or ""
        return string.format(
          "%d %-4s %-22s %-5s %s%s",
          it.i,
          it.art.tag,
          it.art.name,
          it.art.code,
          it.art.out ~= "" and it.art.out or "attribute",
          here
        )
      end
      return string.format("%d %-4s %s", it.i, it.code, m2.describe(it.attr))
    end,
    primary = function(it) return word_of(it) end,
    audition_key = "articulations",
    audition = not mode
        and function(it)
          local a = it.art
          paw.audition.try(function() art.set(places, it.none and false or { attr = a and a.attr or it.attr }) end)
          hear(track, places, a or (it.none and art.default_of(track, map)) or nil)
          return (a and a.name or it.none and "none" or m2.describe(it.attr))
            .. " · "
            .. #places
            .. " note"
            .. (#places == 1 and "" or "s")
        end
      or nil,
    on_choose = function(it)
      paw.audition.revert()
      local name = ({ default = "art.default", pen = "art.pen", mod = "art.mod" })[mode] or "art"
      local line = (mode == "mod" and range or (not mode and range or "")) .. name .. " " .. word_of(it)
      paw.state.last_cmdline = line
      require("paw.views.cmdline").remember("cmdline", line)
      local ok, err = pcall(paw.commands.exec, line)
      if not ok then paw.notify(tostring(err), "error") end
      if entering and keymap.mode ~= "i" then keymap.set_mode("i") end
    end,
    on_cancel = function()
      paw.audition.revert()
      if entering and keymap.mode ~= "i" then keymap.set_mode("i") end
    end,
  })
end

-- Making maps ---------------------------------------------------------------------------

--- Write a spec as a generated map, and bind it to a track when given one.
local function save_generated(spec, track)
  local name = gen.slug(spec.name)
  local path = maps.generated_dir() .. "/" .. name .. maps.SUFFIX
  maps.write(path, gen.text(spec))
  maps.forget()
  if track then art.bind(track, path) end
  return path
end

command("art.generate", function(ctx)
  local what = words(ctx)
  local track = current_track()
  local spec, stats
  if what == "" or what == "device" then
    if not track then fail("no track here") end
    for _, id in ipairs(api.track_get(track).devices or {}) do
      local ok, answer = pcall(api.device_call, id, "describe")
      local d = ok and type(answer) == "string" and paw.json.decode(answer)
      if type(d) == "table" then
        spec, stats = gen.describe(d)
        if spec then break end
      end
    end
    if not spec then
      fail("no device of the track describes its instrument: name a library, `art.generate /libs/Violins.sfz`")
    end
  else
    local path = what:gsub("^~", os.getenv("HOME") or "~")
    local lower = path:lower()
    if lower:match("%.sfz$") then
      spec, stats = gen.sfz(path)
    elseif lower:match("%.dspreset$") or lower:match("%.dslibrary$") then
      spec, stats = gen.ds(path)
    elseif #api.read_dir(path) > 0 then
      spec, stats = gen.folder(path)
    else
      fail("`" .. what .. "`: an .sfz, a .dspreset or .dslibrary, or a folder of samples named by articulation")
    end
    if not spec then fail(stats) end
  end
  local file = save_generated(spec, track)
  paw.notify(
    string.format(
      "%s: %d articulations, %d named by a code of the profile; written to %s%s",
      spec.name,
      stats.articulations,
      stats.coded,
      file,
      track and " and bound to the track" or ""
    )
  )
end, {
  raw = true,
  desc = "Make an articulation map from a library and bind it: `art.generate /libs/Violins.sfz`, a .dspreset, a folder of samples; alone, from a device that describes its instrument",
  complete = "files",
})

command("art.import", function(ctx)
  local path = words(ctx):gsub("^~", os.getenv("HOME") or "~")
  if path == "" then fail("which .reabank? `art.import ~/Reaticulate.reabank`") end
  local text = maps.read(path)
  if not text then fail("cannot read " .. path) end
  local specs, stats = gen.reabank(text)
  local dir = api.env().config_dir .. "/articulations/reaticulate"
  for _, spec in ipairs(specs) do
    maps.write(dir .. "/" .. spec.file .. maps.SUFFIX, gen.text(spec))
  end
  maps.forget()
  paw.notify(
    string.format(
      "%d banks, %d articulations (%d%% named by a code of the profile) into %s",
      #specs,
      stats.articulations,
      stats.articulations > 0 and math.floor(100 * stats.coded / stats.articulations + 0.5) or 0,
      dir
    )
  )
end, {
  raw = true,
  desc = "Read a Reaticulate .reabank: each bank an articulation map of its own, in <config>/articulations/reaticulate",
  complete = "files",
})

command("art.export", function(ctx)
  local args = words(ctx)
  local kind, path = args:match("^(%S*)%s*(.-)$")
  if kind ~= "reabank" then fail("`art.export reabank [file]`: the track's map as a Reaticulate bank") end
  local track = need_track()
  local map = art.map_of(track)
  if not map then fail("the track has no articulation map") end
  path = path ~= "" and path:gsub("^~", os.getenv("HOME") or "~")
    or (api.env().data_dir .. "/articulations/" .. gen.slug(map.name) .. ".reabank")
  maps.write(path, gen.to_reabank(map))
  paw.notify("written " .. path)
end, { raw = true, desc = "Write the track's map as a Reaticulate bank: `art.export reabank [file]`" })

command("art.new", function(ctx)
  local name = words(ctx)
  if name == "" then fail("`art.new <name>`: a map to fill in, in <config>/articulations") end
  local path = api.env().config_dir .. "/articulations/" .. gen.slug(name) .. maps.SUFFIX
  if maps.read(path) then fail(path .. " is there already") end
  local spec = {
    name = name,
    keyswitches = "C1-B1",
    default = "sustain",
    comment = "Fill in what the instrument is told (out) and the keys it plays (range).",
    arts = {
      { id = "sustain", m2 = "10.0", out = "ks=C1", tag = "sus", name = "Sustain", class = "long" },
      { id = "legato", m2 = "10.2", out = "ks=C#1", tag = "leg", name = "Legato", class = "legato" },
      {
        id = "staccato",
        m2 = "11.0",
        out = "ks=D1",
        tag = "stc",
        name = "Staccato",
        class = "short",
        mark = "staccato",
      },
      {
        id = "pizzicato",
        m2 = "11.A",
        out = "ks=D#1",
        tag = "pz",
        name = "Pizzicato",
        class = "short-light",
        text = "pizz.",
      },
      { id = "tremolo", m2 = "12.0", out = "ks=E1", tag = "trm", name = "Tremolo", class = "long-dark" },
    },
  }
  maps.write(path, gen.text(spec))
  maps.forget()
  paw.notify("written " .. path .. ": `art.map " .. gen.slug(name) .. "` binds it")
end, { raw = true, desc = "Write a map to fill in: `art.new Cellos`, in <config>/articulations" })

-- Keyswitches in clips into attributes -------------------------------------------------

--- The articulation each keyswitch note and each switching controller
--- value stands for in a map. A controller switches when two articulations
--- set it to different values and it is not drawn (`chase`, `[linked]`),
--- or when it is CC32 (UACC). A value of a range (`cc58=0-15`) stands for
--- the articulation of that range. Returns `by_key`, and a function of a
--- controller and a value (0 to 127) that gives the articulation, or nil.
local function switches(map)
  local by_key, values = {}, {}
  local drawn = {}
  for _, n in ipairs(map.chase or {}) do
    drawn[n] = true
  end
  for _, l in ipairs(map.linked or {}) do
    for _, n in ipairs(l.cc) do
      drawn[n] = true
    end
  end
  local function add(number, lo, hi, a)
    values[number] = values[number] or {}
    table.insert(values[number], { lo = lo, hi = hi, art = a })
  end
  for _, a in ipairs(map.arts) do
    for _, e in ipairs(a.events) do
      if (e.type == "note" or e.type == "hold") and not by_key[e.key] then by_key[e.key] = a end
      if e.type == "cc" then add(e.number, e.lo or e.value, e.hi or e.value, a) end
    end
    -- UACC: a bank's program number is the CC32 value that selects it.
    if a.program then add(32, a.program, a.program, a) end
  end
  local by_cc = {}
  for number, list in pairs(values) do
    local seen, distinct = {}, 0
    for _, v in ipairs(list) do
      if not seen[v.lo] then
        seen[v.lo], distinct = true, distinct + 1
      end
    end
    if number == 32 or (not drawn[number] and distinct >= 2) then by_cc[number] = list end
  end
  local function find(number, v)
    for _, r in ipairs(by_cc[number] or {}) do
      if v >= r.lo and v <= r.hi then return r.art end
    end
  end
  return by_key, find
end
M.switches = switches

--- Turn the keyswitch notes and switching controller moves (CC32, a
--- controller whose values choose articulations) of a clip into attributes
--- on the notes that follow them: the keyswitch notes and those moves go,
--- the notes get the articulation. Returns how many notes got one.
function M.from_keyswitches(clip_id)
  local c = api.clip_get(clip_id)
  local map = art.map_of(c.track)
  if not map then fail("the track has no articulation map: :art.map") end
  local by_key, by_cc = switches(map)
  local changes = {}
  for _, n in ipairs(api.clip_notes(clip_id)) do
    if by_key[n.pitch] then changes[#changes + 1] = { at = n.start, art = by_key[n.pitch] } end
  end
  local controls, kept = paw.clip(clip_id):controls(), {}
  local dropped = false
  for _, ctl in ipairs(controls) do
    local found = ctl.type == "cc" and by_cc(ctl.number, math.floor(ctl.value * 127 + 0.5))
    if found then
      changes[#changes + 1] = { at = ctl.start, art = found }
      dropped = true
    else
      kept[#kept + 1] = ctl
    end
  end
  table.sort(changes, function(a, b) return a.at < b.at end)
  if #changes == 0 then return 0 end
  local notes = api.clip_notes(clip_id)
  local set, remove, count = {}, {}, 0
  for place, n in ipairs(notes) do
    if by_key[n.pitch] then
      remove[#remove + 1] = place
    else
      local current
      for _, ch in ipairs(changes) do
        if ch.at <= n.start + 1e-9 then current = ch.art end
      end
      if current and not art.same(art.attr_of(n), current.attr) then
        set[#set + 1] = util.merge(art.attr_fields(n, current.attr), { index = place })
        count = count + 1
      end
    end
  end
  paw.clip(clip_id):edit_notes({ set = set, remove = remove })
  if dropped then paw.clip(clip_id):set_controls(kept) end
  return count, #remove
end

command("art.from-keyswitches", function()
  local clip = roll:clip() or paw.cursor.clip()
  if not clip then fail("no clip here") end
  local ids = roll:clip() and paw.roll_clips.ids() or { clip.id }
  local total, gone = 0, 0
  for _, id in ipairs(ids) do
    local n, r = M.from_keyswitches(id)
    total, gone = total + n, gone + (r or 0)
  end
  paw.notify(
    string.format(
      "%d notes given the articulation of the keyswitch before them; %d keyswitch notes taken out",
      total,
      gone
    )
  )
end, {
  label = "Keyswitches into articulations",
  desc = "Turn the keyswitch notes and switching controller moves (CC32, a controller whose values choose articulations) of the clip into the articulations of the notes after them",
})

-- Keys ---------------------------------------------------------------------------------

keymap.set("<localleader>a", function() M.popover() end, {
  view = "pianoroll",
  mode = { "n", "x" },
  desc = "Articulation of the note under the cursor, or of the selection: a list heard as you move",
  repeatable = false,
})
keymap.set(
  "<localleader>a",
  function() M.popover({ mode = "pen" }) end,
  { view = "pianoroll", mode = "i", desc = "The articulation notes are entered with (the pen)" }
)
keymap.set("<localleader>A", function() M.popover({ mode = "mod" }) end, {
  view = "pianoroll",
  mode = { "n", "x" },
  desc = "A modifier of the map (con sord., sul pont.) over the note or the selection",
  repeatable = false,
})

--- The run of notes around the cursor that have the articulation of the
--- note under it, in time, as a region of the roll; with `around`, up to
--- the next note after the run.
local function run_region(around)
  local clip = roll:clip()
  if not clip then return end
  local note, place, portion = roll:note_at(roll.pitch, roll.beat)
  if not note then return end
  local notes = portion.clip:notes()
  local want = art.attr_of(notes[place])
  local first, last = place, place
  while first > 1 and art.same(art.attr_of(notes[first - 1]), want) do
    first = first - 1
  end
  while last < #notes and art.same(art.attr_of(notes[last + 1]), want) do
    last = last + 1
  end
  local r0, r1, c0, c1 = 127, 0, math.huge, -math.huge
  for i = first, last do
    local n = notes[i]
    r0, r1 = math.min(r0, n.pitch), math.max(r1, n.pitch)
    c0, c1 = math.min(c0, n.start), math.max(c1, n.start + n.length)
  end
  if around and notes[last + 1] then c1 = math.max(c1, notes[last + 1].start) end
  return { view = "pianoroll", kind = "block", r0 = r0, r1 = r1, c0 = c0 + portion.offset, c1 = c1 + portion.offset }
end

keymap.textobject(
  "ia",
  function() return run_region(false) end,
  { view = "pianoroll", desc = "The run of notes with the articulation of the one under the cursor" }
)
keymap.textobject(
  "aa",
  function() return run_region(true) end,
  { view = "pianoroll", desc = "The run of notes with the articulation under the cursor, and the gap after it" }
)

return M
