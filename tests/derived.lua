-- Tests of paw/derived.tl through its first consumer, the chord reading of
-- the song (paw/harmony/song.tl): an edit reads again what it changed,
-- and the reading is the one of all the notes at once.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local derived = require("paw.derived")
local song = require("paw.harmony.song")

--- The notes that sound, read from the project without the graph.
local function sounding()
  local out = {}
  for _, id in ipairs(api.track_list()) do
    local t = api.track_get(id)
    if not t.mute and not paw.harmony.is_drums(t) then
      for _, c in ipairs(api.clip_list(id)) do
        if c.kind == "midi" and not c.muted then
          for _, n in ipairs(api.clip_notes(c.id)) do
            if n.start >= 0 and n.start < c.length then
              out[#out + 1] = {
                pitch = n.pitch,
                start = c.start + n.start,
                length = math.min(n.length, c.length - n.start),
                velocity = n.velocity,
              }
            end
          end
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.start < b.start or (a.start == b.start and a.pitch < b.pitch) end)
  return out
end

local function text(chords, keys)
  local out = {}
  for _, c in ipairs(chords) do
    out[#out + 1] = string.format("%.17g+%.17g:%d%s/%s", c.at, c.length, c.root, c.quality, tostring(c.bass))
  end
  out[#out + 1] = "|"
  for _, k in ipairs(keys) do
    out[#out + 1] = string.format("%.17g+%.17g:%d%s", k.at, k.length, k.tonic, k.mode)
  end
  return table.concat(out, " ")
end

--- The reading of the graph, and the one of all the notes at once.
local function both()
  song.update()
  local opts = { step = paw.opt.harmony_step, bar = paw.time.bar(0), bar_start = paw.time.bar_start }
  return text(song.reading()), text(song.whole(sounding(), opts))
end

local function made()
  local n = 0
  for _, s in ipairs(derived.stats()) do
    if s.name:match("^harmony%.") then n = n + s.made end
  end
  return n
end

test("derived: after random edits, the chord reading is the reading of all the notes at once", function()
  local rand = math.random
  math.randomseed(77)
  local quarter = function(lo, hi) return rand(lo * 4, hi * 4) / 4 end
  local function random_notes(length)
    local notes = {}
    for _ = 1, rand(3, 12) do
      notes[#notes + 1] = {
        pitch = rand(36, 84),
        start = quarter(-0.5, length - 0.25),
        length = quarter(0.25, 2),
        velocity = rand(30, 120),
      }
    end
    return notes
  end
  local function clips()
    local out = {}
    for _, id in ipairs(api.track_list()) do
      for _, c in ipairs(api.clip_list(id)) do
        out[#out + 1] = c
      end
    end
    return out
  end
  local edits = {
    function(c) -- a note's pitch
      local notes = api.clip_notes(c.id)
      if #notes > 0 then
        notes[rand(#notes)].pitch = rand(36, 84)
        api.clip_set_notes(c.id, notes)
      end
    end,
    function(c) -- a note more
      local notes = api.clip_notes(c.id)
      notes[#notes + 1] = random_notes(c.length)[1]
      api.clip_set_notes(c.id, notes)
    end,
    function(c) -- a note less
      local notes = api.clip_notes(c.id)
      table.remove(notes, rand(math.max(1, #notes)))
      api.clip_set_notes(c.id, notes)
    end,
    function(c) api.clip_set(c.id, { start = rand(0, 3) * 4 }) end,
    function(c) api.clip_set(c.id, { length = quarter(1, 8) }) end,
    function(c) api.clip_set(c.id, { muted = not c.muted }) end,
    function(c) api.track_set(c.track, { mute = not api.track_get(c.track, "mute") }) end,
    function(c) api.track_set(c.track, { volume = rand(-12, 0) }) end,
    function(c) api.clip_add(c.track, { start = rand(0, 3) * 4, length = 4, notes = random_notes(4) }) end,
    function(c) api.clip_remove(c.id) end,
    function() api.project_set({ sig_num = rand(2, 5) }) end,
  }
  local steps = { 0.5, 0.5, 0.25, 1, 0.75 }
  local bad, read = nil, 0
  for set = 1, 300 do
    fresh()
    paw.opt.harmony_step = steps[set % #steps + 1]
    for t = 1, rand(1, 3) do
      local id = api.track_add({ name = "Track " .. t })
      for _ = 1, rand(1, 2) do
        local length = rand(1, 2) * 4
        api.clip_add(id, { start = rand(0, 2) * 4, length = length, notes = random_notes(length) })
      end
    end
    paw.flush()
    local got, want = both()
    for e = 1, 6 do
      local list = clips()
      if #list == 0 then break end
      edits[rand(#edits)](list[rand(#list)])
      api.undo_checkpoint()
      -- Some edits are read together, as when keys come faster than the reading.
      if e % 2 == 0 or rand(2) == 1 then
        paw.flush()
        got, want = both()
        if got ~= want then bad = bad or string.format("set %d, edit %d", set, e) end
      end
    end
    paw.flush()
    got, want = both()
    if got ~= want then bad = bad or string.format("set %d, at its end:\n%s\n%s", set, got, want) end
    if #song.reading() > 0 then read = read + 1 end
  end
  paw.opt.harmony_step = 0.5
  eq(bad, nil, "every reading agrees with the reading of all notes")
  eq(read > 150, true, "chords were read in most sets: " .. read)
end)

test("derived: a mute reads again only the muted track's windows, and a volume change nothing", function()
  fresh()
  local tracks = {}
  for t = 1, 4 do
    local notes = {}
    for beat = 0, 31.5, 0.5 do
      notes[#notes + 1] = { pitch = 48 + t * 5 + (beat * 2) % 7, start = beat, length = 0.5, velocity = 90 }
    end
    tracks[t] = paw.add_track({ name = "Part " .. t })
    tracks[t]:add_clip({ start = 0, length = 32, notes = notes })
  end
  paw.flush()
  song.update()
  local windows = song.stats("harmony.track_window")
  local before = windows.made
  local count = 64 -- 32 beats in windows of half a beat

  -- `M` in the arrange view mutes the track under the cursor.
  paw.ui.focus("arrange")
  paw.cursor.set_track(tracks[2].id)
  paw.keymap.feed("M")
  paw.flush()
  eq(api.track_get(tracks[2].id, "mute"), true, "M muted the track")
  song.update()
  eq(song.stats("harmony.track_window").made - before, count, "only the muted track's windows were made again")

  local muted = song.stats("harmony.track_window").made
  paw.keymap.feed("M")
  paw.flush()
  song.update()
  eq(song.stats("harmony.track_window").made, muted, "the unmute gives the track's windows back as they were")

  api.track_set(tracks[3].id, { volume = -6 })
  api.undo_checkpoint()
  paw.flush()
  local all = made()
  song.update()
  eq(made(), all, "a volume change reads nothing")

  local said = {}
  for _, item in ipairs(paw.health.run("derived").items) do
    said[#said + 1] = item.text
  end
  local text = table.concat(said, "\n")
  eq(text:find("harmony.track_window (family): 256 values", 1, true) ~= nil, true, ":checkhealth derived:\n" .. text)
end)

test("derived: after :quantize of one bar, the job reads only that bar's windows, a few entries at a time", function()
  fresh()
  -- Four tracks of eight one-bar clips, with notes off the beat.
  local tracks = {}
  for t = 1, 4 do
    tracks[t] = paw.add_track({ name = "Part " .. t })
    for bar = 0, 7 do
      local notes = {}
      for beat = 0, 3 do
        notes[#notes + 1] = { pitch = 50 + t * 4 + bar, start = beat + 0.1, length = 0.5, velocity = 90 }
      end
      tracks[t]:add_clip({ start = bar * 4, length = 4, notes = notes })
    end
  end
  paw.flush()
  song.update()
  local before = song.stats("harmony.track_window")
  local bars_before = song.stats("harmony.track_bar").made

  T.keys(":3quantize 1/4<CR>")
  paw.flush()
  -- The job in slices of no time at all: each stops at the next entry to make.
  local widest, count = 0, made()
  while not derived.run(0) do
    widest = math.max(widest, made() - count)
    count = made()
  end
  widest = math.max(widest, made() - count)
  local windows = song.stats("harmony.track_window")
  -- The window that ends where a moved note now starts is not read again.
  eq(windows.made - before.made, 4 * 8, "only the 8 windows of bar 3 on each of the 4 tracks are made again")
  eq(windows.hits - before.hits, 0, "no window of the other bars is looked at")
  eq(song.stats("harmony.track_bar").made - bars_before, 4, "and of the bars for the key, only bar 3 of each track")
  eq(widest <= 8, true, "a slice makes a few entries, not the windows of the song: " .. widest)
  local got, want = both()
  eq(got, want, "and the reading is the one of all the notes")
end)

test("derived: after :quantize, the spans compared grow with the bars changed, not with the song", function()
  --- The spans of the windows and bars compared with the change of the
  --- tracks, after `:<range>quantize` on two tracks of one-bar clips.
  local function checked(bars, range)
    fresh()
    for t = 1, 2 do
      local track = paw.add_track({ name = "Part " .. t })
      for bar = 0, bars - 1 do
        local notes = {}
        for beat = 0, 3 do
          notes[#notes + 1] = { pitch = 50 + t * 4 + bar % 12, start = beat + 0.1, length = 0.5, velocity = 90 }
        end
        track:add_clip({ start = bar * 4, length = 4, notes = notes })
      end
    end
    paw.flush()
    song.update()
    local before = song.stats("harmony.track").checked
    T.keys(":" .. range .. "quantize 1/4<CR>")
    paw.flush()
    song.update()
    return song.stats("harmony.track").checked - before
  end
  local short, long = checked(8, "3"), checked(32, "3")
  eq(short > 0, true, "the change of bar 3 was compared with the spans that read it")
  eq(long, short, "a song four times as long compares as many spans")
  eq(checked(32, "3,6") > long, true, "four bars compare more spans than one")
end)

test("derived: an error deep in the job leaves no value half made: the next reading is right", function()
  fresh()
  local clips = {}
  for t = 1, 3 do
    local notes = {}
    for beat = 0, 7 do
      notes[#notes + 1] = { pitch = 48 + t * 4 + beat % 3, start = beat, length = 1, velocity = 90 }
    end
    clips[t] = paw.add_track({ name = "Part " .. t }):add_clip({ start = 0, length = 8, notes = notes })
  end
  paw.flush()
  song.update()
  local notes = clips[2]:notes()
  notes[1].pitch = 70
  clips[2]:set_notes(notes)
  api.undo_checkpoint()
  paw.flush()
  -- The kernel fails to give the notes of a clip while the job reads them.
  local clip_notes = api.clip_notes
  T.after(function() api.clip_notes = clip_notes end)
  api.clip_notes = function() error("the notes are not there") end
  T.fails(function()
    while not derived.run(0) do
    end
  end, "the notes are not there", "the job stops at the error")
  api.clip_notes = clip_notes
  local got, want = both()
  eq(got, want, "then the reading is the one of all the notes")
end)

test("derived: K on a note names its chord, and says the chord is being read after an edit", function()
  fresh()
  local notes = {}
  for i, p in ipairs({ 48, 60, 64, 67, 53, 57, 60, 65 }) do
    notes[i] = { pitch = p, start = i <= 4 and 0 or 4, length = 4, velocity = 90 }
  end
  local clip = paw.add_track({ name = "Piano" }):add_clip({ start = 0, length = 8, notes = notes })
  paw.flush()
  paw.harmony.chords()
  local roll = paw.ui.views:get("pianoroll")
  roll:edit(clip)
  paw.ui.focus("pianoroll")
  local function said()
    paw.keymap.feed("K")
    local text = table.concat(api.ui_snapshot(160, 40), "\n")
    paw.ui.close()
    return text
  end
  roll.pitch, roll.beat = 60, 0
  local text = said()
  eq(text:find("the chord here: C", 1, true) ~= nil, true, "K names the chord:\n" .. text)
  -- `x` deletes the E: the chords are read again in slices, after the key.
  roll.pitch = 64
  paw.keymap.feed("x")
  paw.flush()
  roll.pitch = 60
  text = said()
  eq(text:find("the chord here: reading", 1, true) ~= nil, true, "until then, K says so:\n" .. text)
  T.advance_until(function() return paw.harmony.fresh() end, "the reading", 5000)
  text = said()
  eq(text:find("the chord here: C5", 1, true) ~= nil, true, "then K names the new chord:\n" .. text)
end)
