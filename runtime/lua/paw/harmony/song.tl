-- The built-in reading of the whole song, kept up to date clip by clip:
-- what `paw.harmony` asks for the chords and keys of the song.
--
-- It keeps the notes of each clip by the clip's stamp (the kernel's hash of
-- its notes), all the notes sorted by start, the windows of the chord
-- reading (`paw.harmony.read.window`) and the pitch classes of each bar.
-- After an edit it looks again only at the tracks that the kernel said
-- changed, and reads again only the windows and bars where a clip's notes
-- changed; the walk over the windows that picks the chords, and the one
-- over the bars that picks the keys, are quick and are done again whole.
-- So the reading is the one that `paw.harmony.read` makes of all the notes
-- at once, and a change that leaves the notes as they are (a fader, a
-- device) reads nothing.
--
-- The work goes in slices: `update(ms)` stops after about `ms`
-- milliseconds and goes on at the next call, so that a key can come in
-- between; `update()` finishes it.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local read = require("paw.harmony.read")
local type types = require("paw.types")

--- A note of the song, in project beats, with its track and its clip.
local record Note is read.Note
  track: integer
  clip: integer
end

--- A clip as the reading keeps it: its notes that sound, in project beats
--- and sorted by start, and what they were read from (`key`: its stamp,
--- start and length). `from` and `to` are where its notes start and end
--- (nil when none sounds); `longest` is its longest note.
local record Clip
  id: integer
  key: string
  notes: {Note}
  from: number
  to: number
  longest: number
end

--- What the reading needs to know besides the notes: the length of a
--- window (`paw.opt.harmony_step`), the beats of a bar where the song
--- starts, where bar `n` starts, and which tracks are drums.
local record Options
  step: number
  bar: number
  bar_start: function(n: integer): number
  is_drums: function(t: types.Track): boolean
end

local record M
  type Note = Note
  type Options = Options
  reset: function()
end

-- What is kept between readings.
local heard: {integer: {Clip}} = {} -- each track's clips that sound, in its order
local order: {integer} = {} -- the tracks, in order
local sorted: {Note} = {} -- every note, by start (then by clip)
local longest: number = 0 -- the longest note
local last: number = 0 -- where the last note ends
local windows: {read.Window} = {}
local step_of: number -- the step the windows were made with
local bars: {number} = {}
local hist: {read.Weights} = {} -- the pitch classes of each bar, of the notes
local chords: {read.Chord} = {}
local keys: {read.Key} = {}
local bar_of: number -- the bar the chords were decoded with
local stamp = 0 -- goes up when the reading may have changed
local notes_list: {Note} -- `notes()`, made when asked

-- What is left to do.
local all = true -- look at every track
local marked: {integer: boolean} = {} -- the tracks to look at
local timed = true -- the bars may have moved
local job: thread -- the pass under way
local until_ms: number -- when the slice under way ends (nil: never)

--- Stop here if the slice's time is up; the pass goes on at the next call.
local function pause()
  if until_ms and api.now() >= until_ms then
    coroutine.yield()
  end
end

--- Whether note `a` comes before `b`: by start, then by clip. A clip's own
--- notes keep their order.
local function before(a: Note, b: Note): boolean
  return a.start < b.start or (a.start == b.start and a.clip < b.clip)
end

--- Two lists of notes in that order made one.
local function merge(x: {Note}, y: {Note}): {Note}
  if #y == 0 then
    return x
  end
  if #x == 0 then
    return y
  end
  local out: {Note} = {}
  local i, j, nx, ny = 1, 1, #x, #y
  while i <= nx and j <= ny do
    if before(y[j], x[i]) then
      out[#out + 1] = y[j]
      j = j + 1
    else
      out[#out + 1] = x[i]
      i = i + 1
    end
  end
  for k = i, nx do
    out[#out + 1] = x[k]
  end
  for k = j, ny do
    out[#out + 1] = y[k]
  end
  return out
end

--- The notes of several clips in that order: merged two by two.
local function merge_clips(list: {Clip}): {Note}
  table.sort(list, function(a: Clip, b: Clip): boolean return a.id < b.id end)
  local runs: {{Note}} = {}
  for _, c in ipairs(list) do
    runs[#runs + 1] = c.notes
  end
  if #runs == 0 then
    return {}
  end
  while #runs > 1 do
    local next_runs: {{Note}} = {}
    for k = 1, #runs, 2 do
      next_runs[#next_runs + 1] = runs[k + 1] and merge(runs[k], runs[k + 1]) or runs[k]
    end
    runs = next_runs
    pause()
  end
  return runs[1]
end

--- A clip's notes that sound, in project beats: those that a trim of its
--- edges hides are left out.
local function read_clip(track: integer, c: types.Clip, key: string): Clip
  local clip: Clip = {id = c.id, key = key, notes = {}, longest = 0}
  local list = api.clip_notes(c.id)
  for _, n in ipairs(list) do
    if n.start >= 0 and n.start < c.length then
      local note: Note = {
        pitch = n.pitch,
        start = c.start + n.start,
        length = math.min(n.length, c.length - n.start),
        velocity = n.velocity,
        track = track,
        clip = c.id,
      }
      clip.notes[#clip.notes + 1] = note
      clip.from = math.min(clip.from or math.huge, note.start)
      clip.to = math.max(clip.to or -math.huge, note.start + note.length)
      clip.longest = math.max(clip.longest, note.length)
    end
  end
  return clip
end

--- What changed in one pass: the stretches of time whose notes changed,
--- the clips whose old notes go, and the clips whose new notes come.
local record Changes
  spans: {{number}}
  gone: {integer: boolean}
  came: {Clip}
end

local function went(ch: Changes, c: Clip)
  ch.gone[c.id] = true
  if c.from then
    ch.spans[#ch.spans + 1] = {c.from, c.to}
  end
end

local function arrived(ch: Changes, c: Clip)
  ch.came[#ch.came + 1] = c
  if c.from then
    ch.spans[#ch.spans + 1] = {c.from, c.to}
  end
end

--- Look at track `id` again: its clips that sound now against the ones
--- kept. A clip whose stamp, start and length are the same is kept.
local function look(id: integer, opts: Options, ch: Changes)
  local was = heard[id] or {}
  local ok, t = pcall(api.track_get, id)
  local now: {Clip} = {}
  if ok and not t.mute and not opts.is_drums(t) then
    local by_id: {integer: Clip} = {}
    for _, c in ipairs(was) do
      by_id[c.id] = c
    end
    for _, c in ipairs(api.clip_list(id)) do
      if c.kind == "midi" and not c.muted then
        local key = string.format("%s:%.17g:%.17g", tostring(c.stamp), c.start, c.length)
        local kept = by_id[c.id]
        by_id[c.id] = nil
        if kept and kept.key == key then
          now[#now + 1] = kept
        else
          if kept then
            went(ch, kept)
          end
          local clip = read_clip(id, c, key)
          now[#now + 1] = clip
          arrived(ch, clip)
        end
      end
    end
    for _, c in ipairs(was) do
      if by_id[c.id] then
        went(ch, c)
      end
    end
  else
    for _, c in ipairs(was) do
      went(ch, c)
    end
  end
  heard[id] = ok and now or nil
end

--- Whether a change in `spans` can touch what is read from `from` to `to`.
local function touched(spans: {{number}}, from: number, to: number): boolean
  for _, s in ipairs(spans) do
    if s[1] < to + 1e-9 and s[2] > from - 1e-9 then
      return true
    end
  end
  return false
end

--- Bar starts from the first bar to past `upto`, by the tempo map.
local function bar_starts(upto: number, opts: Options): {number}
  local out, n: {number}, integer = {}, 1
  repeat
    out[#out + 1] = opts.bar_start(n)
    n = n + 1
  until out[#out] > upto or n > 100000
  return out
end

local function same<T>(a: {T}, b: {T}): boolean
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

--- One pass: look at the tracks marked, then read again what their
--- changes touch.
local function pass(opts: Options)
  local everything, looking, retime = all, marked, timed
  all, marked, timed = false, {}, false
  local ch: Changes = {spans = {}, gone = {}, came = {}}
  local listed = api.track_list()
  local present: {integer: boolean} = {}
  for _, id in ipairs(listed) do
    present[id] = true
  end
  for id, clips in pairs(heard) do
    if not present[id] then
      for _, c in ipairs(clips) do
        went(ch, c)
      end
      heard[id] = nil
    end
  end
  for _, id in ipairs(listed) do
    if everything or looking[id] or heard[id] == nil then
      look(id, opts, ch)
      pause()
    end
  end
  if not same(order, listed) or #ch.spans > 0 or next(ch.gone) then
    notes_list = nil
  end
  order = listed

  -- The notes, sorted: the ones that went out, the ones that came merged
  -- in. When much changed, all of them are merged again.
  local changed = #ch.spans > 0 or next(ch.gone) ~= nil or #ch.came > 0
  local was_longest = longest
  if changed then
    local moved = 0
    for _, c in ipairs(ch.came) do
      moved = moved + #c.notes
    end
    if everything or moved > #sorted // 4 then
      local list: {Clip} = {}
      for _, clips in pairs(heard) do
        for _, c in ipairs(clips) do
          list[#list + 1] = c
        end
      end
      sorted = merge_clips(list)
    else
      local kept: {Note} = {}
      for _, n in ipairs(sorted) do
        if not ch.gone[n.clip] then
          kept[#kept + 1] = n
        end
      end
      sorted = merge(kept, merge_clips(ch.came))
    end
    longest, last = 0, 0
    for _, clips in pairs(heard) do
      for _, c in ipairs(clips) do
        if c.from then
          longest, last = math.max(longest, c.longest), math.max(last, c.to)
        end
      end
    end
    pause()
  end

  -- The windows: the ones whose notes changed are read again. A window
  -- that was weighed with its beat depends on the longest note too.
  local spans = #ch.spans <= 64 and ch.spans or nil
  local restep = step_of ~= opts.step
  if restep then
    windows, step_of = {}, opts.step
  end
  local made: {read.Window} = {}
  local rewindowed = restep
  if changed or restep then
    local step = opts.step
    local at: number = 0
    local i = 0
    while at < last - 1e-9 do
      i = i + 1
      local len = math.min(step, last - at)
      local win = windows[i]
      if
        not win
        or win.at ~= at
        or win.length ~= len
        or (win.beat and longest ~= was_longest)
        or not spans
        or touched(spans, at - 1, at + len + 1)
      then
        win = read.window(sorted, longest, at, len, step)
        rewindowed = true
        pause()
      end
      made[i] = win
      at = at + step
    end
    if #made ~= #windows then
      rewindowed = true
    end
    windows = made
  end

  -- The bars, and the pitch classes of each.
  local rebar = false
  if changed or retime or #bars == 0 then
    local starts = bar_starts(last, opts)
    local moved_bars = not same(starts, bars)
    if moved_bars or changed then
      local h: {read.Weights} = {}
      for b = 1, #starts - 1 do
        if not moved_bars and hist[b] and spans and not touched(spans, starts[b], starts[b + 1]) then
          h[b] = hist[b]
        else
          h[b] = read.bar_weights(sorted, longest, starts[b], starts[b + 1])
          pause()
        end
      end
      hist, bars, rebar = h, starts, true
    end
  end

  if rewindowed or opts.bar ~= bar_of then
    chords, bar_of = read.decode(windows, opts.bar), opts.bar
    rebar = true
  end
  if rebar then
    keys = read.key_path(hist, bars, chords)
    stamp = stamp + 1
  end
end

--- Whether there is work left: tracks to look at, or a pass under way.
function M.busy(opts?: Options): boolean
  return job ~= nil
    or all
    or timed
    or next(marked) ~= nil
    or (opts ~= nil and (opts.step ~= step_of or opts.bar ~= bar_of))
end

--- Bring the reading up to date. With `budget`, stop after about that
--- many milliseconds: true when it is up to date.
function M.update(opts: Options, budget?: number): boolean
  until_ms = budget and api.now() + budget or nil
  while true do
    if not job then
      if not M.busy(opts) then
        return true
      end
      job = coroutine.create(function() pass(opts) end)
    end
    local ok, err = coroutine.resume(job)
    if not ok then
      job = nil
      M.reset()
      error(tostring(err), 0)
    end
    if coroutine.status(job) ~= "dead" then
      return false
    end
    job = nil
    if until_ms and api.now() >= until_ms then
      return not M.busy(opts)
    end
  end
end

--- Look at track `id` again at the next update (every track when nil).
function M.mark(id?: integer)
  if id then
    marked[id] = true
  else
    all = true
  end
end

--- Make the bars again at the next update: the meter may have changed.
function M.retime()
  timed = true
end

--- Forget all of it: the next update reads the whole song.
function M.reset()
  heard, order, sorted, longest, last = {}, {}, {}, 0, 0
  windows, step_of, bars, hist, chords, keys, bar_of = {}, nil, {}, {}, {}, {}, nil
  notes_list, job, all, marked, timed = nil, nil, true, {}, true
  stamp = stamp + 1
end

--- A number that goes up each time the reading may have changed.
function M.stamp(): integer
  return stamp
end

--- The chords and the keys of the last update.
function M.reading(): {read.Chord}, {read.Key}
  return chords, keys
end

--- Each note that sounds, track by track and clip by clip, as of the last
--- update.
function M.notes(): {Note}
  if not notes_list then
    local out: {Note} = {}
    for _, id in ipairs(order) do
      for _, c in ipairs(heard[id] or {}) do
        for _, n in ipairs(c.notes) do
          out[#out + 1] = n
        end
      end
    end
    notes_list = out
  end
  return notes_list
end

return M
