-- `paw.grep`: every piece of text in the project, searched as Vim's
-- `:vimgrep` searches files, the places found going into the quickfix list.
--
--   :vimgrep /pizz/            track, clip, marker and device names, lyrics,
--   :vimgrep /^la$/ lyric      articulations, comments, the project's tags
--   :lvimgrep /verse/          into the window's location list
--
-- The text comes from sources, each a function given `add(record)`; a
-- record is `{ text, field, location, where }`: what it says, what kind of
-- text it is ("track", "lyric"), where it is (an address or a location),
-- and that place in a few words. Extensions add theirs:
--
--   paw.grep.source("chords", function(add)
--     add({ text = "Cmaj7", field = "chord", location = "paw://clip/4", where = "Verse 5.1.00" })
--   end)
local api = paw.api
local A = paw.address

local M = { sources = {}, order = {} }

--- Add a source of text, or replace the one of that name.
--- @type function(name: string, fn: contracts.GrepSource)
function M.source(name, fn)
  if not M.sources[name] then M.order[#M.order + 1] = name end
  M.sources[name] = fn
end

local function try(fn, ...)
  local ok, v = pcall(fn, ...)
  if ok then return v end
end

local function str(v) return type(v) == "string" and v ~= "" and v or nil end

M.source("tracks", function(add)
  for _, id in ipairs(api.track_list()) do
    local t = api.track_get(id)
    local loc = { uri = A.track(id) }
    add({ text = t.name, field = "track", location = loc, where = t.name })
    local comment = type(t.meta) == "table" and str(t.meta.comment)
    if comment then add({ text = comment, field = "comment", location = loc, where = t.name }) end
    for _, d in ipairs(t.devices or {}) do
      local device = try(api.device_get, d)
      if device then add({ text = device.name, field = "device", location = { uri = A.device(d) }, where = t.name }) end
    end
  end
end)

M.source("clips", function(add)
  for _, id in ipairs(api.track_list()) do
    local track = api.track_get(id, "name")
    for _, c in ipairs(api.clip_list(id)) do
      local loc = { uri = A.clip(c.id) }
      local where = track .. " " .. paw.time.format(c.start)
      add({ text = c.name, field = "clip", location = loc, where = where })
      local comment = type(c.meta) == "table" and str(c.meta.comment)
      if comment then add({ text = comment, field = "comment", location = loc, where = where }) end
      if c.kind == "midi" then
        -- What notes carry in words: lyrics and articulations.
        for _, n in ipairs(api.clip_notes(c.id)) do
          local m = n.meta
          if type(m) == "table" and next(m) then
            local nloc = n.id and { uri = A.note(c.id, n.id) } or loc
            local nwhere
            local function at()
              nwhere = nwhere or (c.name .. " " .. paw.time.format(c.start + n.start) .. " " .. paw.music.name(n.pitch))
              return nwhere
            end
            local lyric = str(m.lyric)
            if lyric then add({ text = lyric, field = "lyric", location = nloc, where = at() }) end
            for _, name in ipairs(paw.query.articulations({ data = n })) do
              add({ text = name, field = "art", location = nloc, where = at() })
            end
          end
        end
      end
    end
  end
end)

M.source("markers", function(add)
  for _, m in ipairs(paw.markers.list()) do
    local name = str(m.name)
    if name then
      add({ text = name, field = m.length and "region" or "marker", location = { uri = A.marker(m.id), selector = { time = { m.beat, m.beat } } },
        where = paw.time.format(m.beat) })
    end
  end
end)

M.source("project", function(add)
  local meta = api.project_get().meta or {}
  for key, value in pairs(type(meta.tags) == "table" and meta.tags or {}) do
    if str(value) then add({ text = value, field = "tag", location = { uri = A.project() }, where = key }) end
  end
  if str(meta.comment) then add({ text = meta.comment, field = "comment", location = { uri = A.project() }, where = "project" }) end
end)

--- Every record of every source, in the order the sources were added.
--- A source that fails is passed over and logged.
function M.records()
  local out = {}
  local function add(r)
    if r and r.text then
      if type(r.location) == "string" then r.location = { uri = r.location } end
      r.text = tostring(r.text):gsub("[\r\n\t]", " ")
      out[#out + 1] = r
    end
  end
  for _, name in ipairs(M.order) do
    local ok, err = pcall(M.sources[name], add)
    if not ok then api.log("grep: " .. name .. ": " .. tostring(err)) end
  end
  return out
end

--- A test of text: `mode` "regex" (`paw.regex`), "exact" (the words, each
--- anywhere) or "fuzzy" (as the pickers match). Raises an error for a bad
--- regular expression.
function M.matcher(pattern, mode)
  mode = mode or "regex"
  if mode == "regex" then
    local re = paw.regex.compile(pattern)
    return function(text) return re:find(text) ~= nil end
  end
  return function(text) return paw.pick.match(pattern, text, false, mode) ~= nil end
end

--- The records whose text matches `pattern`. `opts.mode` is as `matcher`
--- takes it. `opts.fields` is a set of fields to search (all without it).
function M.search(pattern, opts)
  opts = opts or {}
  local test = M.matcher(pattern, opts.mode)
  local out = {}
  for _, r in ipairs(M.records()) do
    if (not opts.fields or opts.fields[r.field]) and test(r.text) then out[#out + 1] = r end
  end
  return out
end

--- Records as quickfix entries: `lyric: la`.
function M.entries(records)
  local out = {}
  for i, r in ipairs(records) do out[i] = { location = r.location, text = r.field .. ": " .. r.text } end
  return out
end

--- The fields text can be found in, for completion.
function M.fields()
  local seen, out = {}, {}
  for _, r in ipairs(M.records()) do
    if not seen[r.field] then
      seen[r.field] = true
      out[#out + 1] = r.field
    end
  end
  table.sort(out)
  return out
end

--- Read `:vimgrep`'s argument: `/pattern/flags fields…`, or a word and fields.
local function parse(arg)
  arg = (arg or ""):match("^%s*(.-)%s*$")
  local delim = arg:sub(1, 1)
  local pattern, flags, rest
  if delim ~= "" and not delim:match("[%w%s\\\"|]") then
    local close = 2
    while close <= #arg do
      local c = arg:sub(close, close)
      if c == "\\" then close = close + 1 elseif c == delim then break end
      close = close + 1
    end
    pattern = arg:sub(2, close - 1)
    flags, rest = arg:sub(close + 1):match("^(%a*)%s*(.*)$")
  else
    pattern, rest = arg:match("^(%S*)%s*(.*)$")
    flags = ""
  end
  local fields
  for word in (rest or ""):gmatch("%S+") do
    -- Vim's files to search (`%` the file open, `##` the argument list)
    -- are the project here, which is searched whole.
    if word ~= "%" and word ~= "##" and word ~= "*" then
      fields = fields or {}
      fields[word] = true
    end
  end
  return pattern, flags or "", fields
end

--- What `:vimgrep` does: search, fill the list, go to the first place found
--- unless the flags hold `j`. `opts.loc` the window's location list,
--- `opts.add` adds to the current list. Returns the records found.
function M.vimgrep(arg, opts)
  opts = opts or {}
  local pattern, flags, fields = parse(arg)
  if not pattern or pattern == "" then return paw.notify("usage: vimgrep /pattern/ [fields]: `vimgrep /pizz/`, `vimgrep /^la/ lyric`", "warn") end
  local ok, found = pcall(M.search, pattern, { mode = "regex", fields = fields })
  if not ok then return paw.notify(tostring(found), "error") end
  if #found == 0 then return paw.notify("nothing in the project matches /" .. pattern .. "/", "warn") end
  local entries = M.entries(found)
  local title = "vimgrep /" .. pattern .. "/"
  local stack = opts.loc and paw.qf.loc_stack(nil, true) or paw.qf.stack()
  if opts.add then
    local list = paw.qf.current(stack)
    if list then
      title = list.title
      local before = {}
      for _, e in ipairs(list.entries) do before[#before + 1] = { location = e.location, text = e.text, level = e.level, source = e.source } end
      for _, e in ipairs(entries) do before[#before + 1] = e end
      entries = before
    end
  end
  paw.qf.set(entries, { title = title, win = opts.loc or nil, source = "vimgrep" })
  paw.notify(string.format("%d match%s of /%s/", #found, #found == 1 and "" or "es", pattern))
  if not flags:find("j", 1, true) then paw.qf.jump(1, stack) end
  return found
end

local command = paw.command
local function complete_fields(_, info) return info.index > 1 and M.fields() or {} end
command("vimgrep", function(ctx) M.vimgrep(ctx.args[1]) end, { raw = true, complete = complete_fields,
  desc = "Every piece of text in the project that matches a regular expression, in the quickfix list: `vimgrep /pizz/`, `vimgrep /^la/ lyric`; `/j` stays where it is" })
command("lvimgrep", function(ctx) M.vimgrep(ctx.args[1], { loc = true }) end, { raw = true, complete = complete_fields,
  desc = "As `vimgrep`, into the window's location list" })
command("vimgrepadd", function(ctx) M.vimgrep(ctx.args[1], { add = true }) end, { raw = true, complete = complete_fields,
  desc = "As `vimgrep`, adding to the quickfix list rather than making a new one" })
command.alias("vim", "vimgrep")

return M
