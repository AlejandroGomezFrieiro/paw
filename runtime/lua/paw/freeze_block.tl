-- Freezing a block of a subproject: what the block plays into its row,
-- rendered to a file that the row then plays in place of the block, so
-- that the subproject's devices rest.
--
--   paw.freeze_block.freeze(clip)     -- render it, and play the file
--   paw.freeze_block.unfreeze(clip)   -- play the subproject live again
--   paw.freeze_block.describe(clip)   -- "frozen, up to date" or "frozen, stale: ..."
--
-- The block's meta holds `frozen = { file, key, length, tail }`, so a freeze is
-- saved with the project and undone like any edit. The `key` says what the
-- file was made from (paw/bake_state.tl): the clips, devices, automation
-- and mix of the subproject's tracks (and of the subprojects inside it),
-- the block's place in the subproject, and the tempo over the block and
-- its tail, from its start. Two blocks that play the same part of the
-- subproject at places with the same tempo have the same key, and use one
-- file: `media/baked/<subproject>-<key>.wav`. `length` is the beats of the
-- file, the tail included, and `tail` its seconds after the block's end. The kernel plays the file and holds the
-- subproject's tracks while no live block plays it:
-- crates/paw-core/src/freeze.rs and crates/paw-core/src/sync/nests.rs.
--
-- An edit inside the subproject does not render again: `K` and the status
-- line say that the block is stale, and `:freeze` makes it current again.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local bake_state = require("paw.bake_state")
local render = require("paw.render")
local type types = require("paw.types")

--- What the meta of a frozen block holds.
local record Frozen
  file: string
  key: bake_state.Key
  length: number
  tail: number
end

--- What `M.freeze` takes: `tail`, the seconds rendered after the block's
--- end (2).
local record Options
  tail: number
end

local record M
  type Frozen = Frozen
  type Options = Options
end

local nest_field = api.nest_get as function(id: integer, key: string): integer
local nest_name = api.nest_get as function(id: integer, key: string): string
local clip_list = api.clip_list as function(track: integer): {types.Clip}
local track_nest = api.track_get as function(id: integer, key: string): integer

-- The seconds a freeze renders after the block's end when nothing is given.
local TAIL = 2

local function num(x: number): string
  return string.format("%.17g", x)
end

local function block(id: integer): types.Clip
  local ok, c = pcall(api.clip_get, id) as (boolean, types.Clip)
  if ok and c.kind == "nest" then
    return c
  end
  return nil
end

local function stem_of(c: types.Clip): integer
  local play = c.play
  if play is types.NestTrack then
    return play.track
  end
  return nil
end

--- What block `clip` is frozen to, `{ file, key, length, tail }`, or nil.
function M.frozen(clip: integer): Frozen
  local c = block(clip)
  local f = c and c.meta and c.meta.frozen as Frozen
  if f and f.file then
    return f
  end
  return nil
end

-- The tracks that a block plays: the subproject's tracks and its master,
-- or the one track of a stem; and the tracks of each subproject that
-- these place, at any depth.
local function tracks_of(c: types.Clip): {integer}
  local out: {integer} = {}
  local seen: {integer: boolean} = {}
  local function add(id: integer)
    if seen[id] then
      return
    end
    seen[id] = true
    out[#out + 1] = id
    for _, inner in ipairs(clip_list(id)) do
      if inner.nest then
        for _, t in ipairs(api.track_list({nest = inner.nest})) do
          add(t)
        end
        add(nest_field(inner.nest, "master"))
      end
    end
  end
  local stem = stem_of(c)
  if stem then
    add(stem)
    return out
  end
  for _, t in ipairs(api.track_list({nest = c.nest})) do
    add(t)
  end
  add(nest_field(c.nest, "master"))
  return out
end

-- The song's beat where the tail of block `c` ends.
local function tail_end(c: types.Clip, tail: number): number
  return api.tempo_beat(api.tempo_seconds(c.start + c.length) + tail)
end

-- The tempo and meter that a block plays in, from its start to the end of
-- its tail, as text: the song's (from the block's start, so that two places
-- with the same tempo give the same text), and the subproject's own.
local function tempo_text(c: types.Clip, tail: number): string
  local from, to = c.start, tail_end(c, tail)
  local num_at, den_at = api.tempo_signature(from)
  local out: {string} = {num(api.tempo_at(from)), num(api.tempo_at(to)), num_at .. "/" .. den_at, num(to - from)}
  local song = api.tempo_points()
  for _, p in ipairs(song.tempos) do
    if p.beat > from and p.beat < to then
      out[#out + 1] = num(p.beat - from) .. "=" .. num(p.bpm) .. tostring(p.ramp)
    end
  end
  for _, p in ipairs(song.signatures) do
    if p.beat > from and p.beat < to then
      out[#out + 1] = num(p.beat - from) .. "=" .. p.num .. "/" .. p.den
    end
  end
  if api.nest_own_tempo(c.id) ~= nil then
    local own = api.nest_tempo_points(c.id)
    for _, p in ipairs(own.tempos) do
      out[#out + 1] = "own " .. num(p.beat) .. "=" .. num(p.bpm) .. tostring(p.ramp)
    end
    for _, p in ipairs(own.signatures) do
      out[#out + 1] = "own " .. num(p.beat) .. "=" .. p.num .. "/" .. p.den
    end
  end
  return table.concat(out, ",")
end

--- The key of what block `c` plays now, with a tail of `tail` seconds.
function M.key(c: types.Clip, tail: number): bake_state.Key
  local offset = c.offset or 0
  local key = bake_state.make({tracks = tracks_of(c), from = offset, to = offset + c.length})
  -- The block's own place in the subproject is a part of its clips.
  local place = {
    num(offset),
    num(c.length),
    tostring(stem_of(c)),
    tostring(c.loop),
    num(c.loop_start or 0),
    num(c.loop_length or 0),
    num(tail),
  }
  key.clips = bake_state.stamp(key.clips .. "|" .. table.concat(place, ","))
  key.tempo = bake_state.stamp(tempo_text(c, tail))
  return key
end

--- What `K` says of a frozen block: "frozen, up to date", "frozen,
--- stale: Ballad changed since: clips". Nil for a block that plays live.
function M.describe(clip: integer): string
  local frozen = M.frozen(clip)
  if not frozen then
    return nil
  end
  -- A freeze made before paw kept its key: nothing to compare.
  if not frozen.key then
    return "frozen"
  end
  local c = block(clip)
  return "frozen, " .. bake_state.describe(nest_name(c.nest, "name"), frozen.key, M.key(c, frozen.tail or TAIL))
end

--- The file that a freeze with `key` of a block of subproject `nest`
--- renders to: in `baked` of the project's media folder, named by the key,
--- so that blocks with the same key share it.
local function file_for(nest: integer, key: bake_state.Key): string
  local dir = api.media_dir() .. "/baked"
  pcall(api.fs_mkdir, api.media_dir())
  pcall(api.fs_mkdir, dir)
  local rate = tostring(api.engine_get().sample_rate)
  local name = nest_name(nest, "name"):gsub("[^%w%-_]", "_")
  return string.format("%s/%s-%s.wav", dir, name, bake_state.id(key, rate))
end

--- Freeze block `clip`: render what it plays into its row, and play the
--- file from now on. A block frozen before is made current. One undo step.
--- Returns the file.
function M.freeze(clip: integer, opts?: Options): string
  local c = block(clip)
  if not c then
    error("no block of a subproject here: `:freeze` freezes a track or a block", 0)
  end
  if track_nest(c.track, "nest") then
    error("this block is inside a subproject: freeze the block of the song that holds it", 0)
  end
  local tail = opts and opts.tail or TAIL
  local key = M.key(c, tail)
  local path = file_for(c.nest, key)
  -- A block with the same key rendered it already.
  if not api.fs_exists(path) then
    render.render(
      path, {block = clip, start = c.start, ["end"] = c.start + c.length, tail = tail, bits = 32, master = false}
    )
  end
  local meta = c.meta or {}
  meta.frozen = {file = path, key = key, length = tail_end(c, tail) - c.start, tail = tail} as Frozen
  api.clip_set(clip, {meta = meta})
  return path
end

--- Play block `clip`'s subproject live again. The file stays, as undo can
--- bring the freeze back.
function M.unfreeze(clip: integer)
  if not M.frozen(clip) then
    error("this block is not frozen", 0)
  end
  local meta = block(clip).meta
  meta.frozen = nil
  api.clip_set(clip, {meta = meta})
end

--- The names of the subprojects that have a frozen block that is stale,
--- for the status line. Empty when there is none.
function M.stale(): {string}
  local out: {string} = {}
  if #api.nest_list() == 0 then
    return out
  end
  local seen: {string: boolean} = {}
  -- Only a block of the song can be frozen: the song's tracks are enough.
  for _, id in ipairs(api.track_list()) do
    for _, c in ipairs(clip_list(id)) do
      local said = c.nest and M.describe(c.id)
      if said and said:find("stale", 1, true) then
        local name = nest_name(c.nest, "name")
        if not seen[name] then
          seen[name] = true
          out[#out + 1] = name
        end
      end
    end
  end
  return out
end

return M
