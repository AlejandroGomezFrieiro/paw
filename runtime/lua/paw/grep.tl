-- `paw.grep`: every piece of text in the project, searched as Vim's
-- `:vimgrep` searches files, the places found going into the quickfix list.
--
--   :vimgrep /pizz/            part, clip, marker and device names, lyrics,
--   :vimgrep /^la$/ lyric      articulations, comments, the project's tags
--   :lvimgrep /verse/          into the window's location list
--
-- The text comes from sources, each a function given `add(record)`; a
-- record is `{ text, field, location, where }` (`paw.contracts.GrepRecord`):
-- what it says, what kind of text it is ("part", "lyric"), where it is (an
-- address or a location), and that place in a few words. Extensions add
-- theirs (`paw.contracts.GrepSource`):
--
--   paw.grep.source("chords", function(add)
--     add({ text = "Cmaj7", field = "chord", location = "paw://clip/4", where = "Verse 5.1.00" })
--   end)
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local A = require("paw.address")
local derived = require("paw.derived")
local tree = require("paw.query.tree")
local command = require("paw.command")
local registry = require("paw.registry")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type util = require("paw.util")
local type partial = require("paw.partial")
local type objects = require("paw.objects")
local type MarkersModule = require("paw.markers")
local type MusicModule = require("paw.music")
local type RegexModule = require("paw.regex")
local type QueryModule = require("paw.query")
local type QfModule = require("paw.qf")

local type Record = contracts.GrepRecord
local type Source = contracts.GrepSource

--- A record as `paw.grep.records` gives it: its location is a table.
local record Found
  text: string
  field: string
  location: contracts.Location
  where: string
end

--- How `matcher` tests text: a regular expression (`paw.regex`), the words
--- each anywhere, or as the pickers match.
local enum Mode
  "regex"
  "exact"
  "fuzzy"
end

--- What `paw.grep.search` takes: the mode, and the fields to search (a
--- set; all without it).
local record SearchOptions
  mode: Mode
  fields: {string: boolean}
end

--- What `paw.grep.vimgrep` takes: `loc` the window's location list, `add`
--- to add to the current list.
local record VimgrepOptions
  loc: boolean
  add: boolean
end

--- What this module reads of the meta of the project, a part, a clip or
--- a note.
local record Meta
  comment: string
  lyric: string
  tags: {string: string}
end

--- `paw.pick` (paw/pick.tl), the part of it that this module calls: how a
--- query matches a line, as the pickers match.
local record Pick
  match: function(query: string, text: string, want_positions?: boolean, mode?: string): number, {integer}
end

local record Paw is partial.Paw
  pick: Pick
  markers: MarkersModule
  music: MusicModule
  regex: RegexModule
  time: objects.Time
  query: QueryModule
  qf: QfModule
end
local paw = (_G as {string: Paw}).paw

local record M
  type Found = Found
  type Mode = Mode
  type SearchOptions = SearchOptions
  type VimgrepOptions = VimgrepOptions
  --- The sources by name, with the extension that added each one.
  sources: registry.Registry<Source>
  --- The names of the sources, in the order they were added.
  order: {string}
end
M.order = {}

-- A new source goes last in `M.order`, and a source that goes leaves it.
M.sources = registry.new(
  "grep",
  "grep sources",
  {
    changed = function(name: string, fn: Source)
      for i = #M.order, 1, -1 do
        if M.order[i] == name then
          if fn then
            return
          end
          table.remove(M.order, i)
        end
      end
      if fn then
        M.order[#M.order + 1] = name
      end
    end,
  }
)

--- Add a source of text, or replace the one of that name.
function M.source(name: string, fn: Source)
  M.sources:put(name, fn)
end

local function try<T, R>(fn: function(T): R, value: T): R
  local ok, v = pcall(fn, value)
  if ok then
    return v
  end
end

local function meta_of(m: types.Meta): Meta
  return type(m) == "table" and m as Meta or nil
end

local function str(v: string): string
  return type(v) == "string" and v ~= "" and v or nil
end

-- The records of the parts and the clips are kept by `paw.derived` (the
-- search index of the design `derived.md`, D3): after an edit, a search
-- makes again the records of the clips that the edit changed, and the job
-- `derived` does it in slices before. The records are shared from search
-- to search: a consumer reads them and does not change them.

--- Text on one line, as a record has it.
local function one_line(text: string): string
  return (tostring(text):gsub("[\r\n\t]", " "))
end

--- The records of a part: its name, its comment and its devices' names.
local function part_records(ctx: derived.Ctx, id: integer, out: {Found})
  local t = ctx:part(id, {"name", "meta", "devices"})
  if not t then
    return
  end
  local loc: contracts.Location = {uri = A.part(id)}
  local function add(text: string, field: string, location: contracts.Location)
    if text then
      out[#out + 1] = {text = one_line(text), field = field, location = location, where = t.name}
    end
  end
  add(t.name, "part", loc)
  local m = meta_of(t.meta)
  add(m and str(m.comment), "comment", loc)
  for _, d in ipairs(t.devices or {}) do
    ctx:source("device:" .. d)
    local device = try(api.device_get, d)
    if device then
      add(device.name, "device", {uri = A.device(d)})
    end
  end
end

--- The records of a clip: its name and comment, and what its notes carry
--- in words (lyrics and articulations).
local function clip_records(c: types.Clip, part: string, notes: {QueryModule.Node}): {Found}
  local out: {Found} = {}
  local function add(text: string, field: string, location: contracts.Location, where: string)
    if text then
      out[#out + 1] = {text = one_line(text), field = field, location = location, where = where}
    end
  end
  local loc: contracts.Location = {uri = A.clip(c.id)}
  local where = part .. " " .. paw.time.format(c.start)
  add(c.name, "clip", loc, where)
  local cm = meta_of(c.meta)
  add(cm and str(cm.comment), "comment", loc, where)
  for i = 1, #notes do
    local node = notes[i]
    local n = node.data as types.Note
    local m = meta_of(n.meta)
    if m and next(m as {string: string}) then
      local nloc: contracts.Location = n.id and {uri = A.note(c.id, n.id)} or loc
      local nwhere: string
      local function at(): string
        nwhere = nwhere or (c.name .. " " .. paw.time.format(c.start + n.start) .. " " .. paw.music.name(n.pitch))
        return nwhere
      end
      local lyric = str(m.lyric)
      if lyric then
        add(lyric, "lyric", nloc, at())
      end
      for _, name in ipairs(paw.query.articulations(node)) do
        add(name, "art", nloc, at())
      end
    end
  end
  return out
end

local function same_records(a: {Found}, b: {Found}): boolean
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    local x, y = a[i], b[i]
    if
      x.text ~= y.text
      or x.field ~= y.field
      or x.where ~= y.where
      or x.location.uri ~= y.location.uri
      or not tree.same_data(x.location.selector as util.Data, y.location.selector as util.Data)
    then
      return false
    end
  end
  return true
end

local part_name = api.part_get as function(id: integer, key: string): string

local clip_spec: derived.Spec<integer, {Found}, boolean> = {
  name = "grep.clip",
  kind = "family",
  make = function(ctx: derived.Ctx, id: integer): {Found}
    local node = ctx:get(tree.clip, id)
    if not node then
      return {}
    end
    local c = node.data as types.Clip
    ctx:part(c.part, {"name"})
    -- The places are written in bars and beats.
    ctx:tempo()
    -- The articulations of the notes (`paw.query.marks`).
    ctx:source("note_marks")
    return clip_records(c, part_name(c.part, "name"), ctx:get(tree.notes, id))
  end,
  same = same_records,
  bytes = function(list: {Found}): integer return 64 + 200 * #list end,
  limit = 8 * 1048576,
}
local clip_node = derived.node(clip_spec)

--- The records of a part, and those of its clips, in order.
local record PartRecords
  part: {Found}
  clips: {Found}
end

local function same_part(a: PartRecords, b: PartRecords): boolean
  return same_records(a.part, b.part) and tree.same_list(a.clips, b.clips)
end

local part_spec: derived.Spec<integer, PartRecords, boolean> = {
  name = "grep.part",
  kind = "family",
  make = function(ctx: derived.Ctx, id: integer): PartRecords
    local v: PartRecords = {part = {}, clips = {}}
    part_records(ctx, id, v.part)
    local clips = ctx:get(tree.part, id).clips
    for i = 1, #clips do
      local list = ctx:get(clip_node, clips[i].id)
      for k = 1, #list do
        v.clips[#v.clips + 1] = list[k]
      end
    end
    return v
  end,
  same = same_part,
}
local part_node = derived.node(part_spec)

local all_spec: derived.Spec<integer, PartRecords, boolean> = {
  name = "grep.all",
  kind = "join",
  label = "search",
  make = function(ctx: derived.Ctx): PartRecords
    local v: PartRecords = {part = {}, clips = {}}
    local ids = ctx:parts()
    for i = 1, #ids do
      local part = ctx:get(part_node, ids[i])
      for k = 1, #part.part do
        v.part[#v.part + 1] = part.part[k]
      end
      for k = 1, #part.clips do
        v.clips[#v.clips + 1] = part.clips[k]
      end
      -- The first reading of a large project goes on at the next slice.
      ctx:pause()
    end
    return v
  end,
  same = same_part,
}
local all_node = derived.node(all_spec)

-- The records of the parts and the clips, read once for each `collect`.
local all_now: PartRecords

local function all_records(): PartRecords
  if not all_now then
    all_node:want(0)
    all_now = all_node:get(0, true)
  end
  return all_now
end

M.source(
  "parts",
  function(add: function(Record))
    local list = all_records().part
    for i = 1, #list do
      add(list[i] as Record)
    end
  end
)

M.source(
  "clips",
  function(add: function(Record))
    local list = all_records().clips
    for i = 1, #list do
      add(list[i] as Record)
    end
  end
)

M.source(
  "markers",
  function(add: function(Record))
    for _, m in ipairs(paw.markers.list()) do
      local name = str(m.name)
      if name then
        add(
          {
            text = name,
            field = m.length and "region" or "marker",
            location = {uri = A.marker(m.id), selector = {time = {m.beat, m.beat}}},
            where = paw.time.format(m.beat),
          }
        )
      end
    end
  end
)

M.source(
  "project",
  function(add: function(Record))
    local meta = meta_of(api.project_get().meta) or {}
    for key, value in pairs(type(meta.tags) == "table" and meta.tags or {}) do
      if str(value) then
        add({text = value, field = "tag", location = {uri = A.project()}, where = key})
      end
    end
    if str(meta.comment) then
      add({text = meta.comment, field = "comment", location = {uri = A.project()}, where = "project"})
    end
  end
)

--- Give each record of each source to `found`, in the order the sources
--- were added. A source that fails is passed over and logged.
local function collect(found: function(Found))
  local function add(r: Record)
    if r and r.text then
      local location = r.location
      if location is string then
        r.location = {uri = location}
      end
      r.text = tostring(r.text):gsub("[\r\n\t]", " ")
      found(r as Found)
    end
  end
  all_now = nil
  for _, name in ipairs(M.order) do
    local ok, err = pcall(function(): string M.sources:get(name)(add) end)
    if not ok then
      api.log("grep: " .. name .. ": " .. tostring(err))
    end
  end
end

--- Every record of every source, in the order the sources were added.
--- A source that fails is passed over and logged. paw keeps the records of
--- the parts and the clips from one search to the next, so read a record
--- and don't change it.
function M.records(): {Found}
  local out: {Found} = {}
  collect(function(r: Found) out[#out + 1] = r end)
  return out
end

--- The records of `records` read in slices, for a picker (`paw.slices`):
--- each call of the function gives the records found in about `ms`
--- milliseconds, and true when all are read.
function M.reader(): function(ms: number): {Found}, boolean
  local batch: {Found} = {}
  local deadline: number = 0
  local job = coroutine.create(
    function()
      -- The job `derived` reads the records of the parts and the clips
      -- in its own slices: wait for it (a second at most).
      local since = api.now()
      while not all_node:fresh(0) and api.now() - since < 1000 do
        all_node:want(0)
        all_node:get(0)
        coroutine.yield()
      end
      collect(
        function(r: Found)
          batch[#batch + 1] = r
          -- A source that calls `add` from inside a function of the kernel
          -- cannot stop there: it goes on to the next record that can.
          if api.real_ms() >= deadline and coroutine.isyieldable() then
            coroutine.yield()
          end
        end
      )
    end
  )
  return function(ms: number): {Found}, boolean
    -- A budget of work: on the wall clock.
    deadline = api.real_ms() + ms
    batch = {}
    local ok, err = coroutine.resume(job)
    if not ok then
      error(tostring(err), 0)
    end
    return batch, coroutine.status(job) == "dead"
  end
end

--- A test of text: `mode` "regex" (`paw.regex`), "exact" (the words, each
--- anywhere) or "fuzzy" (as the pickers match). Raises an error for a bad
--- regular expression.
function M.matcher(pattern: string, mode?: Mode): function(text: string): boolean
  mode = mode or "regex"
  if mode == "regex" then
    local re = paw.regex.compile(pattern)
    return function(text: string): boolean return re:find(text) ~= nil end
  end
  return function(text: string): boolean return paw.pick.match(pattern, text, false, mode) ~= nil end
end

--- The records whose text matches `pattern`. `opts.mode` is as `matcher`
--- takes it. `opts.fields` is a set of fields to search (all without it).
function M.search(pattern: string, opts?: SearchOptions): {Found}
  opts = opts or {}
  local test = M.matcher(pattern, opts.mode)
  local out: {Found} = {}
  for _, r in ipairs(M.records()) do
    if (not opts.fields or opts.fields[r.field]) and test(r.text) then
      out[#out + 1] = r
    end
  end
  return out
end

--- Records as quickfix entries: `lyric: la`.
function M.entries(records: {Found}): {QfModule.Item}
  local out: {QfModule.Item} = {}
  for i, r in ipairs(records) do
    out[i] = {location = r.location, text = r.field .. ": " .. r.text}
  end
  return out
end

--- The fields text can be found in, for completion.
function M.fields(): {string}
  local seen: {string: boolean} = {}
  local out: {string} = {}
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
local function parse(given: string): string, string, {string: boolean}
  local text = (given or ""):match("^%s*(.-)%s*$")
  local delim = text:sub(1, 1)
  local pattern, flags, rest: string, string, string
  if delim ~= "" and not delim:match("[%w%s\\\"|]") then
    local close = 2
    while close <= #text do
      local c = text:sub(close, close)
      if c == "\\" then
        close = close + 1
      elseif c == delim then
        break
      end
      close = close + 1
    end
    pattern = text:sub(2, close - 1)
    flags, rest = text:sub(close + 1):match("^(%a*)%s*(.*)$")
  else
    pattern, rest = text:match("^(%S*)%s*(.*)$")
    flags = ""
  end
  local fields: {string: boolean}
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
function M.vimgrep(line: string, opts?: VimgrepOptions): {Found}
  opts = opts or {}
  local pattern, flags, fields = parse(line)
  if not pattern or pattern == "" then
    paw.notify("usage: vimgrep /pattern/ [fields]: `vimgrep /pizz/`, `vimgrep /^la/ lyric`", "warn")
    return nil
  end
  local ok, found = pcall(M.search, pattern, {mode = "regex", fields = fields} as SearchOptions)
  if not ok then
    paw.notify(tostring(found), "error")
    return nil
  end
  if #found == 0 then
    paw.notify("nothing in the project matches /" .. pattern .. "/", "warn")
    return nil
  end
  local entries = M.entries(found)
  local title = "vimgrep /" .. pattern .. "/"
  local stack = opts.loc and paw.qf.loc_stack(nil, true) or paw.qf.stack()
  if opts.add then
    local list = paw.qf.current(stack)
    if list then
      title = list.title
      local before: {QfModule.Item} = {}
      for _, e in ipairs(list.entries) do
        before[#before + 1] = {location = e.location, text = e.text, level = e.level, source = e.source}
      end
      for _, e in ipairs(entries) do
        before[#before + 1] = e
      end
      entries = before
    end
  end
  paw.qf.set(entries, {title = title, win = opts.loc or nil, source = "vimgrep"})
  paw.notify(string.format("%d match%s of /%s/", #found, #found == 1 and "" or "es", pattern))
  if not flags:find("j", 1, true) then
    paw.qf.jump(1, stack)
  end
  return found
end

local type Context = command.Context
local type Result = command.Result
local function complete_fields(_: string, info: command.Info): {string}
  return info.index > 1 and M.fields() or {}
end
command.define(
  "vimgrep",
  function(ctx: Context): Result M.vimgrep(ctx.args[1] as string) end,
  {
    raw = true,
    complete = complete_fields,
    desc = "Every piece of text in the project that matches a regular expression, in the quickfix list: `vimgrep /pizz/`, `vimgrep /^la/ lyric`; `/j` stays where it is",
  }
)
command.define(
  "lvimgrep",
  function(ctx: Context): Result M.vimgrep(ctx.args[1] as string, {loc = true}) end,
  {raw = true, complete = complete_fields, desc = "As `vimgrep`, into the window's location list"}
)
command.define(
  "vimgrepadd",
  function(ctx: Context): Result M.vimgrep(ctx.args[1] as string, {add = true}) end,
  {
    raw = true,
    complete = complete_fields,
    desc = "As `vimgrep`, adding to the quickfix list rather than making a new one",
  }
)
command.alias("vim", "vimgrep")

return M
