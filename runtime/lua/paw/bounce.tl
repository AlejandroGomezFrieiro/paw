-- Bouncing: tracks rendered into the project as a new audio track.
--
--   paw.bounce(track)                         -- the whole track, after its fader (paw.bounce.track)
--   paw.bounce(track, { tap = "pre" })        -- before its fader; the fader stays live
--   paw.bounce.tracks({ a, b }, { start = 16, ["end"] = 32 })
--
-- The render goes through `paw.render` with `tap`, so the file holds the
-- tracks without their groups and the master. The new track goes where the
-- first track goes, so it plays through them once, as the old tracks did.
-- A bounce of the whole tracks mutes the tracks. A bounce of a range of
-- time cuts their clips at its edges and mutes only the parts in it; each
-- muted part keeps the id of the new track in `meta.bounced`, for `K`.
-- The notes across its edges play whole in the new clip (see `sounding`).
-- The `:bounce` command is in paw/defaults/project.lua.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local edit = require("paw.edit")
local objects = require("paw.objects")
local util = require("paw.util")
local render = require("paw.render")
local type types = require("paw.types")

--- What `paw.bounce` takes besides the tracks.
local record Options
  --- The name of the new track.
  name: string
  --- `"post"` (the default) or `"pre"`.
  tap: types.RenderTap
  --- The beats to render. Without them, from the first clip to the last,
  --- and the whole tracks are muted. With them, only the clips in them.
  start: number
  ["end"]: number
  --- Seconds rendered after the end, for reverbs and delays (2).
  tail: number
end

local record M
  Options: Options
  metamethod __call: function(M, track: integer | objects.Track, opts?: Options): objects.Track
end

--- `ids` and each track whose sound reaches one of them through outputs:
--- the members of a group, and the members of the groups in it.
local function with_feeders(ids: {integer}): {integer: boolean}
  local heard: {integer: boolean} = {}
  for _, id in ipairs(ids) do
    heard[id] = true
  end
  local all = api.track_list({all = true})
  local grew = true
  while grew do
    grew = false
    for _, id in ipairs(all) do
      local output = api.track_get(id).output
      if not heard[id] and output and heard[output] then
        heard[id], grew = true, true
      end
    end
  end
  return heard
end

--- The beats from the first clip to the end of the last on `tracks`, or
--- nil when they hold no clip.
local function extent(tracks: {integer: boolean}): number, number
  local first: number
  local last: number
  for id in pairs(tracks) do
    for _, clip in ipairs(api.clip_list(id)) do
      first = math.min(first or clip.start, clip.start)
      last = math.max(last or 0, clip.start + clip.length)
    end
  end
  return first, last
end

--- The place for the new track in its list (from 1): below the last of
--- `heard` there.
local function place_below(first: types.Track, heard: {integer: boolean}): integer
  local list = api.track_list(first.nest and {nest = first.nest} or nil)
  local index = #list
  for i, id in ipairs(list) do
    if heard[id] then
      index = i
    end
  end
  return index + 1
end

--- A new file in the media folder for a bounce of `track`. A name that is
--- taken gets a number: the audio of a file is kept by its path, so a file
--- must not be written again under the same name.
local function new_file(track: types.Track): string
  local dir = api.media_dir()
  pcall(api.fs_mkdir, dir)
  local base = string.format("%s/%s-bounce-%d-%d", dir, (track.name:gsub("[^%w%-_]", "_")), os.time(), track.id)
  local path, n = base .. ".wav", 1
  while api.fs_exists(path) do
    n = n + 1
    path = string.format("%s-%d.wav", base, n)
  end
  return path
end

--- Give the new track the fader of the old one: its volume, pan, sends
--- and the automation of its volume and pan. A bounce before the fader
--- needs them to sound the same.
local function copy_fader(from: types.Track, to: integer)
  api.track_set(to, {volume = from.volume, pan = from.pan, sends = from.sends})
  for _, lane in ipairs(api.lane_list(from.id)) do
    if lane.target == "volume" or lane.target == "pan" then
      local copy = api.lane_add(to, {target = lane.target, enabled = lane.enabled, points = api.lane_points(lane.id)})
      api.lane_set_shapes(copy, api.lane_shapes(lane.id))
    end
  end
end

--- Cut the clips of `tracks` (a set of ids) at `from` and `to`. Returns
--- the clips that play between them, and those that play outside them.
local function cut_at(tracks: {integer: boolean}, from: number, to: number): {integer}, {integer}
  local inside: {integer} = {}
  local outside: {integer} = {}
  for track in pairs(tracks) do
    edit.arrange.clear(track, from, from)
    edit.arrange.clear(track, to, to)
    for _, clip in ipairs(api.clip_list(track)) do
      local within = clip.start >= from - 1e-9 and clip.start + clip.length <= to + 1e-9
      if clip.muted then
        -- A clip muted before is not in the sound, and stays as it is.
      elseif within then
        inside[#inside + 1] = clip.id
      else
        outside[#outside + 1] = clip.id
      end
    end
  end
  return inside, outside
end

local EPS = 1e-9

--- A copy of a note at another place and length.
local function with_note(n: types.Note, start: number, length: number): types.Note
  return {start = start, length = length, pitch = n.pitch, velocity = n.velocity, meta = n.meta, attr = n.attr}
end

--- Set `muted` on each clip of `ids`.
local function set_muted(ids: {integer}, muted: boolean)
  for _, id in ipairs(ids) do
    api.clip_set(id, {muted = muted})
  end
end

--- Whether a clip plays its notes as they are: a MIDI clip that does not
--- loop and is not a block. A bounce keeps the notes of such a clip whole.
local function plain(clip: types.Clip): boolean
  return clip.kind == "midi" and not clip.loop and not clip.nest
end

--- The notes of one clip that sound in a range, in beats of the song, as
--- the clip plays them: the end of a clip stops its notes.
local record Sounding
  clip: types.Clip
  notes: {types.Note}
  start: number
  stop: number
  --- The notes that start before the range and are held at its start.
  held: {types.Note}
end

--- The notes that sound in the range from the plain clips of `tracks` that
--- play: those that start in it, and those held at its start. A cut stops
--- a note at its edge, but the bounce must play these whole, as live.
local function sounding(tracks: {integer: boolean}, from: number, to: number): {Sounding}
  local out: {Sounding} = {}
  for track in pairs(tracks) do
    for _, clip in ipairs(api.clip_list(track)) do
      local finish = clip.start + clip.length
      if plain(clip) and not clip.muted and clip.start < to - EPS and finish > from + EPS then
        local s: Sounding = {clip = clip, notes = {}, held = {}, start = from, stop = to}
        for _, n in ipairs((api.clip_notes(clip.id))) do
          local start = clip.start + n.start
          local stop = math.min(start + n.length, finish)
          local held = start < from - EPS and stop > from + EPS
          if held or (start >= from - EPS and start < to - EPS) then
            s.notes[#s.notes + 1] = with_note(n, start, stop - start)
            s.start, s.stop = math.min(s.start, start), math.max(s.stop, stop)
            if held then
              s.held[#s.held + 1] = n
            end
          end
        end
        if #s.notes > 0 then
          out[#out + 1] = s
        end
      end
    end
  end
  return out
end

--- Take the held notes out of what is left of their clips before the
--- range: the bounce plays them now, from where they start.
local function take_held(list: {Sounding})
  local function key(n: types.Note): string
    return string.format("%.9f/%d", n.start, n.pitch)
  end
  for _, s in ipairs(list) do
    if #s.held > 0 then
      local gone: {string: boolean} = {}
      for _, n in ipairs(s.held) do
        gone[key(n)] = true
      end
      local keep: {types.Note} = {}
      for _, n in ipairs((api.clip_notes(s.clip.id))) do
        if not gone[key(n)] then
          keep[#keep + 1] = n
        end
      end
      api.clip_set_notes(s.clip.id, keep)
    end
  end
end

--- For the render: a clip for each of `list` that plays its notes whole.
--- Returns their ids, to remove after the render.
local function play_whole(list: {Sounding}): {integer}
  local ids: {integer} = {}
  for _, s in ipairs(list) do
    local notes: {types.Note} = {}
    for i, n in ipairs(s.notes) do
      notes[i] = with_note(n, n.start - s.start, n.length)
    end
    ids[#ids + 1] = api.clip_add(
      s.clip.track,
      {
        kind = "midi",
        start = s.start,
        length = s.stop - s.start,
        notes = notes,
        transpose = s.clip.transpose,
        velocity = s.clip.velocity,
      }
    )
  end
  return ids
end

--- Render the tracks of `ids` to audio, as one clip on a new track below
--- the last of them, and mute them. The new track plays its sound where the
--- first track sends its sound. `opts` is as for `paw.bounce.track`, and
--- `opts.tap = "pre"` takes one track only. Returns the new track, or nil
--- when there is nothing to render.
function M.tracks(ids: {integer}, opts?: Options): objects.Track
  opts = opts or {}
  if #ids == 0 then
    error("no track to bounce", 0)
  end
  local tap = opts.tap or "post"
  if tap ~= "post" and tap ~= "pre" then
    error("a bounce plays through its groups and the master again: tap=post or tap=pre, not tap=" .. tostring(tap), 0)
  end
  if tap == "pre" and #ids > 1 then
    error("tap=pre bounces one track at a time: the new track takes that track's fader", 0)
  end
  local first = api.track_get(ids[1])
  if not first then
    error("no track " .. tostring(ids[1]) .. " to bounce", 0)
  end
  local heard = with_feeders(ids)
  local from, to = opts.start, opts["end"]
  local whole = not from and not to
  if not from or not to then
    local clips_from, clips_to = extent(heard)
    if not clips_from then
      return nil
    end
    from, to = from or clips_from, to or clips_to
  end
  if to <= from then
    return nil
  end

  local path = new_file(first)
  -- A range of time: the clips are cut at its edges, and only the parts
  -- in it sound in the render. A cut stops a note at an edge, so the
  -- render plays the notes of the range whole from other clips: those
  -- that start in it, to their end, and those held at its start, from
  -- where they start. The parts before the range lose the held notes. So
  -- each note sounds in one place, and the song sounds as before.
  local inside: {integer} = {}
  local outside: {integer} = {}
  local whole_notes: {integer} = {}
  local start, finish = from, to
  if not whole then
    local list = sounding(heard, from, to)
    inside, outside = cut_at(heard, from, to)
    take_held(list)
    whole_notes = play_whole(list)
    for _, s in ipairs(list) do
      start, finish = math.min(start, s.start), math.max(finish, s.stop)
    end
    set_muted(outside, true)
    for _, clip in ipairs(inside) do
      if plain(api.clip_get(clip)) then
        api.clip_set(clip, {muted = true})
      end
    end
  end
  local ok, err = pcall(
    render.render, path, {tracks = ids, tap = tap, start = start, ["end"] = finish, tail = opts.tail or 2, bits = 32}
  ) as (boolean, string)
  for _, clip in ipairs(whole_notes) do
    api.clip_remove(clip)
  end
  set_muted(outside, false)
  if not ok then
    error(err, 0)
  end

  local name = opts.name or (#ids == 1 and first.name or string.format("%s + %d", first.name, #ids - 1)) .. " (bounced)"
  local id = api.track_add({name = name, index = place_below(first, heard), output = first.output, nest = first.nest})
  api.clip_add(id, {file = path, start = start, name = first.name})
  if tap == "pre" then
    copy_fader(first, id)
  end
  if whole then
    for _, old in ipairs(ids) do
      api.track_set(old, {mute = true})
    end
  end
  -- Each part of the range is muted, and keeps the new track for `K`. The
  -- tracks that feed a group are cut and muted too: they play its clips.
  for _, clip in ipairs(inside) do
    local meta = api.clip_get(clip).meta or {}
    api.clip_set(clip, {muted = true, meta = util.merge(meta, {bounced = id})})
  end
  return objects.track(id)
end

--- Render a track (its id, or the track) to audio, as one clip on a new
--- track below it, and mute it. `paw.bounce(track, opts)` is the same. The
--- new track plays its sound where the old one sends it. `opts.tap` is where the
--- render listens: `"post"` (the default) holds the track's devices, fader
--- and pan, but not its groups or the master, and the new track's fader
--- starts at 0 dB. `"pre"` is before the fader: the new track gets the
--- volume, pan and sends of the old one, and the automation of its volume
--- and pan. `opts.start` and `opts["end"]` are the beats to render. Without
--- them, it renders from the first clip to the end of the last, and mutes
--- the whole track. With them, it cuts the clips at those beats and mutes
--- only the parts between them, and `K` on such a part names the new
--- track. `opts.tail` is the seconds after the end (2). `opts.name` names the new track ("<name>
--- (bounced)" by default). It uses `paw.render`, so `render.before` runs.
--- Returns the new track, or nil when there is nothing to render.
function M.track(track: integer | objects.Track, opts?: Options): objects.Track
  if track is integer then
    return M.tracks({track}, opts)
  end
  return M.tracks({track.id}, opts)
end

--- What `K` says of a clip that a bounce muted: the track that plays it
--- now. Nil for another clip.
function M.describe(clip: types.Clip): string
  local bounced = clip.muted and clip.meta and clip.meta.bounced
  if not bounced then
    return nil
  end
  local track = api.track_get(math.tointeger(bounced as number))
  if not track then
    return "muted by a bounce, whose track is gone"
  end
  return string.format("muted by a bounce: “%s” plays it", track.name)
end

return setmetatable(
  M,
  {
    __call = function(_: M, track: integer | objects.Track, opts?: Options): objects.Track
      return M.track(track, opts)
    end,
  } as metatable<M>
)
