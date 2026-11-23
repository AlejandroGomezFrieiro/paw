-- Bouncing: tracks rendered into the project as a new audio track.
--
--   paw.bounce(track)                         -- the whole track, after its fader (paw.bounce.track)
--   paw.bounce(track, { tap = "pre" })        -- before its fader; the fader stays live
--   paw.bounce.tracks({ a, b }, { start = 16, ["end"] = 32 })
--
-- The render goes through `paw.render` with `tap`, so the file holds the
-- tracks without their groups and the master. The new track goes where the
-- first track goes, so it plays through them once, as the old tracks did.
-- The `:bounce` command is in paw/defaults/project.lua.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local objects = require("paw.objects")
local render = require("paw.render")
local type types = require("paw.types")

--- What `paw.bounce` takes besides the tracks.
local record Options
  --- The name of the new track.
  name: string
  --- `"post"` (the default) or `"pre"`.
  tap: types.RenderTap
  --- The beats to render. Without them, from the first clip to the last.
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
  render.render(path, {tracks = ids, tap = tap, start = from, ["end"] = to, tail = opts.tail or 2, bits = 32})

  local name = opts.name or (#ids == 1 and first.name or string.format("%s + %d", first.name, #ids - 1)) .. " (bounced)"
  local id = api.track_add({name = name, index = place_below(first, heard), output = first.output, nest = first.nest})
  api.clip_add(id, {file = path, start = from, name = first.name})
  if tap == "pre" then
    copy_fader(first, id)
  end
  for _, old in ipairs(ids) do
    api.track_set(old, {mute = true})
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
--- and pan. `opts.start` and `opts["end"]` are the beats to render (from
--- the first clip to the end of the last by default), and `opts.tail` the
--- seconds after the end (2). `opts.name` names the new track ("<name>
--- (bounced)" by default). It uses `paw.render`, so `render.before` runs.
--- Returns the new track, or nil when there is nothing to render.
function M.track(track: integer | objects.Track, opts?: Options): objects.Track
  if track is integer then
    return M.tracks({track}, opts)
  end
  return M.tracks({track.id}, opts)
end

return setmetatable(
  M,
  {
    __call = function(_: M, track: integer | objects.Track, opts?: Options): objects.Track
      return M.track(track, opts)
    end,
  } as metatable<M>
)
