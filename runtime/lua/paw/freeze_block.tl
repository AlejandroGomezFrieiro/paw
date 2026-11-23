-- Freezing a block of a subproject: what the block plays into its row,
-- rendered to a file that the row then plays in place of the block, so
-- that the subproject's devices rest.
--
--   paw.freeze_block.freeze(clip)     -- render it, and play the file
--   paw.freeze_block.unfreeze(clip)   -- play the subproject live again
--   paw.freeze_block.describe(clip)   -- "frozen, up to date" or "frozen, stale: ..."
--
-- A block inside a subproject is rendered where a block of the song places
-- it: through the blocks that the window was entered through, or else the
-- first ones (`paw.api.block_path`), in the time of that place.
--
-- The block's meta holds `frozen = { file, key, length, tail, path }`, so a freeze is
-- saved with the project and undone like any edit. The `key` says what the
-- file was made from (paw/bake_state.tl): the clips, devices, automation
-- and mix of the subproject's tracks (and of the subprojects inside it),
-- the block's place in the subproject, and the tempo over the block and
-- its tail, from its start. Two blocks that play the same part of the
-- subproject at places with the same tempo have the same key, and use one
-- file: `media/baked/<subproject>-<key>.wav`. `length` is the beats of the
-- file, the tail included, in the beats of the block's place, and `tail` its
-- seconds after the block's end. `path` is the blocks that the file was
-- rendered through, from the song to the block. The kernel plays the file and holds the
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
  path: {integer}
end

--- What `M.freeze` takes: `tail`, the seconds rendered after the block's
--- end (2); `through`, for a block inside a subproject, the blocks that
--- place it in the song (the window's way in), outer first.
local record Options
  tail: number
  through: {integer}
end

local record M
  type Frozen = Frozen
  type Options = Options
end

local nest_field = api.nest_get as function(id: integer, key: string): integer
local nest_name = api.nest_get as function(id: integer, key: string): string
local clip_list = api.clip_list as function(track: integer): {types.Clip}

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

-- The blocks that place block `c` in the song (`paw.api.block_path`),
-- through `through`. A block that no block of the song plays any more
-- counts as a block of the song: its key then says that it is stale.
local function path_of(c: types.Clip, through: {integer}): {integer}
  local ok, path = pcall(api.block_path, c.id, through) as (boolean, {integer})
  return ok and path or {c.id}
end

-- The song's beat where the tail of block `c` ends, on `path`.
local function tail_end(c: types.Clip, tail: number, path: {integer}): number
  return api.tempo_beat(api.tempo_seconds(api.block_song_beat(path, c.start + c.length)) + tail)
end

-- The tempo and meter that a block plays in, from its start to the end of
-- its tail, as text: the song's (from the block's start, so that two places
-- with the same tempo give the same text), and the own ones of the
-- subproject and of the subprojects on its path.
local function tempo_text(c: types.Clip, tail: number, path: {integer}): string
  local from, to = api.block_song_beat(path, c.start), tail_end(c, tail, path)
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
  for _, id in ipairs(path) do
    if api.nest_own_tempo(id) ~= nil then
      local own = api.nest_tempo_points(id)
      for _, p in ipairs(own.tempos) do
        out[#out + 1] = "own " .. num(p.beat) .. "=" .. num(p.bpm) .. tostring(p.ramp)
      end
      for _, p in ipairs(own.signatures) do
        out[#out + 1] = "own " .. num(p.beat) .. "=" .. p.num .. "/" .. p.den
      end
    end
  end
  return table.concat(out, ",")
end

--- The key of what block `c` plays now, with a tail of `tail` seconds, on
--- `path` (`paw.api.block_path`).
function M.key(c: types.Clip, tail: number, path: {integer}): bake_state.Key
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
  key.tempo = bake_state.stamp(tempo_text(c, tail, path))
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
  local now = M.key(c, frozen.tail or TAIL, path_of(c, frozen.path))
  return "frozen, " .. bake_state.describe(nest_name(c.nest, "name"), frozen.key, now)
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
--- file from now on. A block inside a subproject is rendered at the place
--- in the song of `opts.through`, else of the first blocks that place it.
--- A block frozen before is made current. One undo step. Returns the file.
function M.freeze(clip: integer, opts?: Options): string
  local c = block(clip)
  if not c then
    error("no block of a subproject here: `:freeze` freezes a track or a block", 0)
  end
  local tail = opts and opts.tail or TAIL
  -- Fails when no block of the song plays it: nothing to render.
  local path = api.block_path(clip, opts and opts.through)
  local key = M.key(c, tail, path)
  local file = file_for(c.nest, key)
  local from, to = api.block_song_beat(path, c.start), api.block_song_beat(path, c.start + c.length)
  -- A block with the same key rendered it already.
  if not api.fs_exists(file) then
    render.render(
      file, {block = clip, through = path, start = from, ["end"] = to, tail = tail, bits = 32, master = false}
    )
  end
  -- The file's length in the beats of the block's place, where it plays.
  local length = api.block_beat(path, tail_end(c, tail, path)) - c.start
  local meta = c.meta or {}
  meta.frozen = {file = file, key = key, length = length, tail = tail, path = path} as Frozen
  api.clip_set(clip, {meta = meta})
  return file
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
  -- A block can be frozen on the song's tracks and inside subprojects.
  for _, id in ipairs(api.track_list({all = true})) do
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
