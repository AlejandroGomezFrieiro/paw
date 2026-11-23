-- `paw.clip_kinds`: kinds of clip that extensions define.
--
-- A clip of a kind (a film, lyrics, light cues) keeps the kind's own data,
-- and what the kind compiled from it: the sound it plays (MIDI or audio),
-- the signals it sends, the files it uses. So a project plays without the
-- extension. The core never looks inside the data. The kind says how it is
-- saved: `serialize` turns it into plain data (text, numbers, booleans,
-- and lists and maps of them, or one text in the kind's own format, as
-- `.lrc`), and `deserialize` turns that back. Bytes (pictures, sound) go
-- in media files, never in the data. An extension defines a kind:
--
--   paw.clip_kinds.define("film", {
--     title = "Film clip", letter = "F",
--     version = 2,                              -- the version of its data
--     serialize = function(data) return { file = data.file, scenes = data.scenes } end,
--     deserialize = function(stored, version)  -- version 1 called the file `path`
--       return { file = version == 1 and stored.path or stored.file, scenes = stored.scenes or 1 }
--     end,
--     create = function(args) return { file = args[1], scenes = 1 } end,
--     check = function(data) if not data.file then return "no file" end end,
--     compile = function(data, clip) return { media = { { role = "source", path = data.file } } } end,
--     describe = function(clip) return clip:data().file end,
--   })
--
-- and from then on `paw.clip_kinds.add(track, "film", { "intro.mp4" })`
-- makes a clip of it, `clip:data()` reads its data (`deserialize`), and
-- `clip:set_data(d)` (`paw.clip_kinds.set`) stores `serialize(d)` and
-- compiles it again, as one undo step. The contract is
-- `paw.contracts.ClipKind<D>`, where `D` is the record of the kind's data.
-- The kind's functions run under `paw.opt.clip_kind_limit` milliseconds
-- (50): they must be fast.
--
-- Each clip keeps the version of its data, and `deserialize` gets it: the
-- kind moves older data to its record there. When the project opens and
-- when the kind is defined, a clip of an older version is stored again in
-- the kind's version. A clip of a newer version (made by a newer
-- extension) plays, shows and moves, but the kind does not change it.
-- Without its kind, a clip keeps its data, and `K` says which kind it was.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local objects = require("paw.objects")
local options = require("paw.options")
local registry = require("paw.registry")
local limit = require("paw.limit")
local events = require("paw.events")
local kernel = require("paw.events.kernel")

--- `paw.insert` (paw/insert.tl), the part of it this module calls: a
--- kind with an `insert` key gets that key in the arrange view's insert mode.
local record Insert
  add: function(key: string, spec: contracts.InsertKind): contracts.InsertKind
  remove: function(key: string)
  get: function(key: string): contracts.InsertKind
end
local record Paw is partial.Paw
  insert: Insert
end
local runtime = (_G as {string: Paw}).paw

local record M
  --- A kind's data as this module keeps it: it gives it to the kind's
  --- own functions and never reads it.
  record Data
  end

  --- The kinds that are defined by name, with the extension that defined
  --- each one. `define` puts one, `remove` takes it away.
  kinds: registry.Registry<contracts.ClipKind<Data>>
  --- Their names, in the order they were defined.
  order: {string}
end
M.order = {}

--- Keep `M.order` and the kernel's kinds as the kinds are: a kind that
--- goes is no longer made, and the kind below it (if any) comes back.
local function keep_order(name: string, spec: contracts.ClipKind<M.Data>)
  local at: integer
  for i, other in ipairs(M.order) do
    if other == name then
      at = i
    end
  end
  if spec then
    api.clip_kind_define(name)
    if not at then
      M.order[#M.order + 1] = name
    end
  else
    if at then
      table.remove(M.order, at)
    end
    pcall(api.clip_kind_remove, name)
  end
end
M.kinds = registry.new("clip_kinds", "kinds of clip", {changed = keep_order})

local budget = options.define("clip_kind_limit", 50, {min = 0})

local function builtin(kind: string): boolean
  return kind == "midi" or kind == "audio"
end

local function id_of(clip: integer | objects.Clip): integer
  if clip is objects.Clip then
    return clip.id
  end
  return clip
end

-- Running the kind's functions ----------------------------------------------------

--- Call one of a kind's functions under the kinds' time limit: true and its
--- results, or false and the error.
local function guarded<R>(
  spec: contracts.ClipKind<M.Data>, what: string, fn: function(): (R, string)
): boolean, R, string
  return pcall(limit.within, budget:get(), spec.name .. "'s " .. what, fn) as (boolean, R, string)
end

--- Call one of a kind's functions that gives a value, or nil and why: the
--- value, or nil and why (an error is a why).
local function run<R>(spec: contracts.ClipKind<M.Data>, what: string, fn: function(): (R, string)): R, string
  local ok, result, why = guarded(spec, what, fn)
  if not ok then
    return nil, what .. " failed: " .. tostring(result)
  end
  if result == nil then
    return nil, why or (what .. " gave nothing")
  end
  return result
end

-- Data -----------------------------------------------------------------------

local function version_of(custom: types.CustomContent): integer
  return custom.version or 1
end

-- How the kernel keeps plain data: these two functions are the only ones
-- that know it. Text is kept as text, with the kind's file extension; the
-- rest as a table, which the kernel checks is plain data (the path of what
-- is not, in its error) and saves as JSON.
local function store(spec: contracts.ClipKind<M.Data>, value: contracts.KindJson): types.KindData
  if value is string then
    return {text = {ext = spec.ext or "txt", text = value}}
  end
  return {json = value}
end

local function stored(custom: types.CustomContent): contracts.KindJson, string
  if custom.data.text then
    return custom.data.text.text
  end
  return custom.data.json as contracts.KindJson
end

--- A kind's data as the kernel keeps it, by the kind's `serialize`.
local function serialized(spec: contracts.ClipKind<M.Data>, data: M.Data): types.KindData, string
  local value, why = run(spec, "serialize", function(): (contracts.KindJson, string) return spec.serialize(data) end)
  if value == nil then
    return nil, why
  end
  return store(spec, value)
end

--- A clip's data, by the kind's `deserialize` of what is stored and its
--- version (the kind migrates older versions there).
local function deserialized(spec: contracts.ClipKind<M.Data>, custom: types.CustomContent): M.Data, string
  local value, why = stored(custom)
  if why then
    return nil, why
  end
  return run(spec, "deserialize", function(): (M.Data, string) return spec.deserialize(value, version_of(custom)) end)
end

--- Why the kind cannot read a clip's data: it is of a newer version.
local function newer(spec: contracts.ClipKind<M.Data>, custom: types.CustomContent): string
  local version = version_of(custom)
  if version > spec.version then
    return string.format(
      "this clip was made by a newer %s extension (data %d, this one knows %d)", spec.name, version, spec.version
    )
  end
end

--- What is wrong with data, by the kind's `check`; nil when it is good.
local function wrong(spec: contracts.ClipKind<M.Data>, data: M.Data): string
  if data == nil then
    return "the data is nil"
  end
  if not spec.check then
    return nil
  end
  local ok, why = guarded(spec, "check", function(): (string, string) return spec.check(data) end)
  if not ok then
    return "check failed: " .. tostring(why)
  end
  return why
end

--- What a clip of the kind holds with `data`: checked, encoded and
--- compiled, as `clip_set_custom` takes it, and the natural length.
local function made(
  spec: contracts.ClipKind<M.Data>, data: M.Data, where: contracts.ClipInfo
): types.CustomSet, string, number
  local bad = wrong(spec, data)
  if bad then
    return nil, bad
  end
  local kept, why = serialized(spec, data)
  if not kept then
    return nil, why
  end
  local out: contracts.Compiled = {}
  if spec.compile then
    local compiled, err = run(
      spec, "compile", function(): (contracts.Compiled, string) return spec.compile(data, where) end
    )
    if not compiled then
      return nil, err
    end
    out = compiled
  end
  local set: types.CustomSet = {data = kept, version = spec.version, timeline = spec.timeline, sound = out.sound}
  -- An empty list would cross as a table of no kind; none is nil.
  if out.signals and #out.signals > 0 then
    set.signals = out.signals
  end
  if out.media and #out.media > 0 then
    set.media = out.media
  end
  return set, nil, out.length
end

local function info(c: types.Clip, custom: types.CustomContent): contracts.ClipInfo
  return {
    id = c.id,
    track = c.track,
    start = c.start,
    length = c.length,
    offset = custom.offset or 0,
    timeline = custom.timeline or "beats",
  }
end

--- The kind of a clip that the kind can change, with the clip and its
--- content; or an error that says why not.
local function changeable(id: integer): contracts.ClipKind<M.Data>, types.Clip, types.CustomContent
  local c = api.clip_get(id)
  local custom = api.clip_custom(id)
  local spec = M.kinds:get(c.kind)
  if not spec then
    error("load the extension that defines `" .. c.kind .. "`: no extension here defines it", 0)
  end
  local why = newer(spec, custom)
  if why then
    error(why, 0)
  end
  return spec, c, custom
end

--- Give a clip what its kind made, as one undo step; the kernel's refusal
--- (data that is not plain, with its path) names the kind.
local function keep(spec: contracts.ClipKind<M.Data>, id: integer, set: types.CustomSet)
  local ok, err = pcall(api.clip_set_custom, id, set) as (boolean, string)
  if not ok then
    error("kind `" .. spec.name .. "`: " .. tostring(err), 0)
  end
end

-- Defining kinds -------------------------------------------------------------

--- The clips of the project, on the timeline and among the cues, whose
--- kind is not built in.
local function custom_clips(): {types.Clip}
  local out: {types.Clip} = {}
  for _, track in ipairs(api.track_list({all = true})) do
    for _, list in ipairs({api.clip_list(track), api.cue_list(track)}) do
      for _, c in ipairs(list) do
        if not builtin(c.kind) then
          out[#out + 1] = c
        end
      end
    end
  end
  return out
end

--- Move the clips of the kind `name` (of each kind when nil) whose data is
--- of an older version to their kind's version, by its `deserialize`, and
--- compile them again. Says how many moved; a clip whose migration fails
--- stays as it was, with a message. Gives how many moved.
function M.migrate(name?: string): integer
  local moved: {string: integer} = {}
  local total = 0
  for _, c in ipairs(custom_clips()) do
    local spec = M.kinds:get(c.kind)
    if spec and (name == nil or name == c.kind) then
      local custom = api.clip_custom(c.id)
      local from = version_of(custom)
      if from < spec.version then
        local data, why = deserialized(spec, custom)
        local set: types.CustomSet
        if data ~= nil then
          set, why = made(spec, data, info(c, custom))
        end
        if set then
          local ok: boolean
          ok, why = pcall(keep, spec, c.id, set) as (boolean, string)
          if not ok then
            set = nil
          end
        end
        if set then
          moved[c.kind] = (moved[c.kind] or 0) + 1
          total = total + 1
        else
          runtime.notify(
            string.format(
              "%s: clip %s stays at data version %d: %s",
              spec.name,
              c.name ~= "" and c.name or tostring(c.id),
              from,
              why
            ),
            "warn"
          )
        end
      end
    end
  end
  for _, kind in ipairs(M.order) do
    local n = moved[kind]
    if n then
      runtime.notify(
        string.format(
          "%s: %d %s moved to data version %d", kind, n, n == 1 and "clip" or "clips", M.kinds:get(kind).version
        )
      )
    end
  end
  return total
end

--- Define a kind of clip (see above). `name` is a lowercase word that is
--- not a built-in kind (`midi`, `audio`): what a clip of the kind keeps.
--- Defining a kind again replaces it. Clips of an older version of its
--- data are migrated.
function M.define<D>(name: string, spec: contracts.ClipKind<D>): contracts.ClipKind<D>
  if type(name) ~= "string" then
    error("a kind of clip is named by a word", 2)
  end
  if type(spec) ~= "table" then
    error("clip_kinds.define takes a name and a table", 2)
  end
  local version = spec.version or 1
  if type(spec.serialize) ~= "function" or type(spec.deserialize) ~= "function" then
    error("kind `" .. name .. "`: give serialize and deserialize: the kind says how its data is saved", 2)
  end
  if math.type(version) ~= "integer" or version < 1 then
    error(name .. ": the version of a kind's data is a whole number from 1", 2)
  end
  if spec.timeline and spec.timeline ~= "beats" and spec.timeline ~= "seconds" then
    error(name .. ": a kind's timeline is `beats` or `seconds`", 2)
  end
  api.clip_kind_define(name)
  spec.name = name
  spec.title = spec.title or (name:sub(1, 1):upper() .. name:sub(2) .. " clip")
  spec.letter = spec.letter or name:sub(1, 1):upper()
  spec.version = version
  spec.timeline = spec.timeline or "beats"
  M.kinds:put(name, spec as contracts.ClipKind<M.Data>)
  if spec.insert and runtime.insert then
    local editor = spec.editor
    runtime.insert.add(
      spec.insert,
      {
        kind = name,
        desc = "A " .. spec.title:sub(1, 1):lower() .. spec.title:sub(2),
        open = editor
          and function(_: contracts.InsertContext, item: contracts.InsertedItem)
            editor(objects.clip(item.id))
          end or nil,
      }
    )
  end
  if M.migrate(name) > 0 then
    api.undo_label(name .. ": data version " .. version)
  end
  return spec
end

--- Forget a kind: no new clips of it. The clips of it that the project
--- has stay as they are, data and all, until something defines it again.
function M.remove(name: string)
  local spec = M.kinds:remove(name)
  local key = spec and spec.insert
  if key and runtime.insert and runtime.insert.get(key) and runtime.insert.get(key).kind == name then
    runtime.insert.remove(key)
  end
end

--- The names of the defined kinds, in the order they were defined.
function M.list(): {string}
  local out: {string} = {}
  for i, name in ipairs(M.order) do
    out[i] = name
  end
  return out
end

--- The kind `name` as defined, or nil. `D` is the record of its data.
function M.spec<D>(name: string): contracts.ClipKind<D>
  return M.kinds:get(name) as contracts.ClipKind<D>
end

local function need(name: string): contracts.ClipKind<M.Data>
  local spec = M.kinds:get(name)
  if spec then
    return spec
  end
  local known = #M.order == 0 and "no extension has defined one" or ("there are " .. table.concat(M.order, ", "))
  error("no kind of clip `" .. tostring(name) .. "`: " .. known, 0)
end

-- Clips of a kind ----------------------------------------------------------------

--- A new clip of the kind `name` on `track`: `data`, or what the kind's
--- `create` makes of `args` (the words, and `name`, `start` and `length`
--- of the clip). Its length is `args.length`, or the length the kind
--- compiled, or a bar of 4 beats. One undo step.
function M.add<D>(track: integer | objects.Track, name: string, args?: contracts.ClipKindArgs, data?: D): objects.Clip
  local spec = need(name)
  args = args or {}
  args.track = track is objects.Track and track.id or track as integer
  local value = data as M.Data
  if value == nil then
    if not spec.create then
      error("kind `" .. name .. "`: give the clip's data: the kind has no create", 0)
    end
    local why: string
    value, why = run(spec, "create", function(): (M.Data, string) return spec.create(args) end)
    if value == nil then
      error("kind `" .. name .. "`: " .. why, 0)
    end
  end
  local where: contracts.ClipInfo = {
    track = args.track, start = args.start or 0, length = args.length, offset = 0, timeline = spec.timeline
  }
  local set, why, natural = made(spec, value, where)
  if not set then
    error("kind `" .. name .. "`: " .. why, 0)
  end
  local ok, id = pcall(
    api.clip_add,
    args.track,
    {
      kind = name,
      name = args.name,
      start = args.start,
      length = args.length or natural or 4,
      data = set.data,
      version = set.version,
      timeline = set.timeline,
      sound = set.sound,
      signals = set.signals,
      media = set.media,
    }
  ) as (boolean, integer)
  if not ok then
    error("kind `" .. name .. "`: " .. tostring(id), 0)
  end
  return objects.clip(id)
end

--- Give a clip of a kind new data: the kind checks it and compiles it
--- again, and the data, sound, signals and files change together, as one
--- undo step. Refused without the kind, and for a clip that a newer
--- version of the kind made.
function M.set<D>(clip: integer | objects.Clip, data: D)
  local id = id_of(clip)
  local spec, c, custom = changeable(id)
  local set, why = made(spec, data as M.Data, info(c, custom))
  if not set then
    error("kind `" .. spec.name .. "`: " .. why, 0)
  end
  keep(spec, id, set)
end

--- Compile a clip of a kind again from its data (after something that it
--- links to changed). One undo step.
function M.compile(clip: integer | objects.Clip)
  local id = id_of(clip)
  local spec, c, custom = changeable(id)
  local data, why = deserialized(spec, custom)
  local set: types.CustomSet
  if data ~= nil then
    set, why = made(spec, data, info(c, custom))
  end
  if not set then
    error("kind `" .. spec.name .. "`: " .. why, 0)
  end
  keep(spec, id, set)
end

--- The data of a clip of a kind, by its kind's `deserialize`: nil for a
--- MIDI or audio clip, and nil and why when the kind cannot read it.
--- Without its kind, the plain data as it is stored.
function M.data<D>(clip: integer | objects.Clip): D, string
  local id = id_of(clip)
  local c = api.clip_get(id)
  if builtin(c.kind) then
    return nil
  end
  local custom = api.clip_custom(id)
  local spec = M.kinds:get(c.kind)
  if not spec then
    local value, why = stored(custom)
    return value as D, why
  end
  local bad = newer(spec, custom)
  if bad then
    return nil, bad
  end
  local value, why = deserialized(spec, custom)
  if why then
    return nil, "kind `" .. spec.name .. "`: " .. why
  end
  return value as D
end

--- The data of a clip of a kind (`paw.clip_kinds.data`).
objects.Clip.data = function<D>(self: objects.Clip): D, string return M.data(self) end
--- Give a clip of a kind new data, as one undo step (`paw.clip_kinds.set`).
objects.Clip.set_data = function<D>(self: objects.Clip, data: D) M.set(self, data) end

--- A few words on a clip of a kind, for `K`: `Film clip · intro.mp4`, or
--- "film (no extension here defines it)". Nil for a MIDI or audio clip.
function M.describe(clip: integer | objects.Clip): string
  local id = id_of(clip)
  local c = api.clip_get(id)
  if builtin(c.kind) then
    return nil
  end
  local spec = M.kinds:get(c.kind)
  if not spec then
    return c.kind .. " (no extension here defines it)"
  end
  if spec.describe then
    local ok, words = guarded(spec, "describe", function(): (string, string) return spec.describe(objects.clip(id)) end)
    if not ok then
      runtime.notify(spec.name .. ": describe failed: " .. tostring(words), "warn")
    elseif words and words ~= "" then
      return spec.title .. " · " .. words
    end
  end
  return spec.title
end

local look_failed: {string: boolean} = {}

--- How a clip of a kind looks in the arrange view, by its kind's `look`:
--- nil without the kind, or when `look` fails (said once per kind).
function M.look(clip: integer | objects.Clip, ctx: contracts.ClipLookContext): contracts.ClipLook
  local id = id_of(clip)
  local spec = M.kinds:get(api.clip_get(id).kind)
  if not spec or not spec.look then
    return nil
  end
  local ok, look = guarded(
    spec, "look", function(): (contracts.ClipLook, string) return spec.look(objects.clip(id), ctx) end
  )
  if ok then
    return look
  end
  if not look_failed[spec.name] then
    look_failed[spec.name] = true
    runtime.notify(spec.name .. ": look failed: " .. tostring(look), "warn")
  end
  return nil
end

-- Edits ---------------------------------------------------------------------------

--- `beats` after a clip's start, in its timeline: beats, or seconds.
local function span(c: types.Clip, custom: types.CustomContent, beats: number): number
  if custom.timeline == "seconds" then
    return api.tempo_seconds(c.start + beats) - api.tempo_seconds(c.start)
  end
  return beats
end

--- A clip's kind and data when the kind can read them, else nil (the
--- edits then only move the offset).
local function readable(c: types.Clip, custom: types.CustomContent): contracts.ClipKind<M.Data>, M.Data
  local spec = M.kinds:get(c.kind)
  if not spec or newer(spec, custom) then
    return nil
  end
  local data = deserialized(spec, custom)
  if data == nil then
    return nil
  end
  return spec, data
end

--- What a piece of a clip holds: `data` from `offset`, compiled for the
--- piece at `start` for `length` beats. Without the kind, the clip's data,
--- sound, signals and files as they are.
local function piece(
  spec: contracts.ClipKind<M.Data>,
  c: types.Clip,
  custom: types.CustomContent,
  data: M.Data,
  offset: number,
  start: number,
  length: number
): types.CustomSet
  local set: types.CustomSet
  if spec then
    local why: string
    set, why = made(
      spec,
      data,
      {
        id = c.id,
        track = c.track,
        start = start,
        length = length,
        offset = offset,
        timeline = custom.timeline or "beats",
      }
    )
    if not set then
      error("kind `" .. spec.name .. "`: " .. why, 0)
    end
  else
    set = {data = custom.data, sound = custom.sound, signals = custom.signals, media = custom.media}
  end
  set.offset = offset
  return set
end

--- What the two halves of a clip of a kind hold when it is split `at`
--- beats after its start, as `paw.api.clip_set_custom` takes it: by the
--- kind's `split`, or (without it, or without the kind) the same data,
--- with the right half starting where the cut is in it. The caller makes
--- the halves.
function M.split(clip: integer | objects.Clip, at: number): types.CustomSet, types.CustomSet
  local id = id_of(clip)
  local c, custom = api.clip_get(id), api.clip_custom(id)
  local offset = custom.offset or 0
  local cut = offset + span(c, custom, at)
  local spec, data = readable(c, custom)
  local left, right, right_offset = data, data, cut
  if spec and spec.split then
    local ok, why = guarded(
      spec, "split", function(): (boolean, string) left, right = spec.split(data, cut); return true end
    )
    if not ok then
      error("kind `" .. spec.name .. "`: split failed: " .. tostring(why), 0)
    end
    right_offset = 0
  end
  return piece(spec, c, custom, left, offset, c.start, at),
    piece(spec, c, custom, right, right_offset, c.start + at, c.length - at)
end

--- What a clip of a kind holds when it is cut to the beats `from` to `to`
--- after its start: by the kind's `trim`, or the same data with its
--- offset moved to `from`. The caller moves the clip's start and length.
function M.trim(clip: integer | objects.Clip, from: number, to: number): types.CustomSet
  local id = id_of(clip)
  local c, custom = api.clip_get(id), api.clip_custom(id)
  local offset = custom.offset or 0
  local first, last = offset + span(c, custom, from), offset + span(c, custom, to)
  local spec, data = readable(c, custom)
  if spec and spec.trim then
    local trimmed, why = run(spec, "trim", function(): (M.Data, string) return spec.trim(data, first, last) end)
    if trimmed == nil then
      error("kind `" .. spec.name .. "`: " .. why, 0)
    end
    return piece(spec, c, custom, trimmed, 0, c.start + from, to - from)
  end
  return piece(spec, c, custom, data, first, c.start + from, to - from)
end

--- What a clip of a kind holds when what it plays moves `by` beats later
--- under it: by the kind's `slip` (given the new offset), or the same data
--- with its offset moved.
function M.slip(clip: integer | objects.Clip, by: number): types.CustomSet
  local id = id_of(clip)
  local c, custom = api.clip_get(id), api.clip_custom(id)
  local offset = (custom.offset or 0) - span(c, custom, by)
  local spec, data = readable(c, custom)
  if spec and spec.slip then
    local ok, why = guarded(
      spec, "slip", function(): (boolean, string) data, offset = spec.slip(data, offset); return true end
    )
    if not ok then
      error("kind `" .. spec.name .. "`: slip failed: " .. tostring(why), 0)
    end
  end
  return piece(spec, c, custom, data, offset, c.start, c.length)
end

-- A project that opens is not an action: its clips move to their kinds'
-- versions without an undo step, and it stays unchanged until an edit of
-- the user (the next save writes the new data).
events.on(
  kernel.project_loaded,
  function()
    -- With no kind, nothing to migrate, unless an extension waits for a
    -- kind of clip: migrate's `get` loads it (paw/lazy.tl).
    if #M.order == 0 and not (registry.waiting and registry.waiting(M.kinds)) then
      return
    end
    local clean = not api.undo_pending()
    if M.migrate() > 0 and clean then
      api.undo_reset()
    end
  end
)

return M
