-- "A song over two weeks": one person makes a song, a session a day. Each
-- day reopens what the day before saved. The details (tempo, notes, names,
-- levels, which part is reworked) come from the seed; the process is that
-- of a person: sketch, import, arrange, mix, change one's mind, export.
--
-- Each action gives its keys and the same change on the model
-- (tests/e2e/model.lua). See docs/explanation/about-the-e2e-tests.md.
-- short: 3
local M -- the model module, set by each day
local days = {}

local SCALE = { 55, 57, 59, 60, 62, 64, 65, 67, 69, 71, 72 }
local COLORS = { "#e0605a", "#d9ab3a", "#5fb56a", "#4aa3df", "#9a7ff0", "#e06b9a" }

--- A phrase of `count` notes of the scale, with lengths of 2 to 8 steps
--- (half a beat to two beats), that fits in `beats`.
local function phrase(r, count, beats, low, high)
  local out, at = {}, 0
  for _ = 1, count do
    local len = r.pick({ 2, 4, 4, 6, 8 })
    if at + len / 4 > beats then break end
    local pitch
    repeat pitch = r.pick(SCALE) until pitch >= (low or 0) and pitch <= (high or 127)
    out[#out + 1] = { pitch, len }
    at = at + len / 4
  end
  return out
end

--- Add a track below track `after` (0: the first track of an empty
--- project), name it, and give it a device.
local function add_track(E, after, name, device)
  local keys = after > 0 and E.go(after) or { "<Esc>" }
  for _, k in ipairs({ "o", "grn", "<C-u>" .. name .. "<CR>" }) do keys[#keys + 1] = k end
  if device then keys[#keys + 1] = "a" keys[#keys + 1] = device .. "<CR>" end
  E:act({ name = "add the track " .. name, keys = keys, apply = function(m)
    local t = M.new_track(name)
    if device then t.devices = { device } end
    table.insert(m.tracks, after + 1, t)
  end })
end

--- Draw a phrase in a new clip of one bar on track `i` at bar `bar`.
local function draw(E, i, bar, notes, what)
  local keys = E.go(i, bar)
  local draw_keys, model_notes, beats = E.draw(notes)
  for _, k in ipairs(draw_keys) do keys[#keys + 1] = k end
  keys[#keys + 1] = "<C-w>p"
  E:act({ name = what or ("draw notes on track " .. i .. " at bar " .. bar), keys = keys, focus = "arrange",
    apply = function(m)
      local t = m.tracks[i]
      local length = math.max(4, math.ceil(beats / 4) * 4)
      t.clips[#t.clips + 1] = { kind = "midi", start = (bar - 1) * 4, length = length, notes = model_notes }
      table.sort(t.clips, function(a, b) return a.start < b.start end)
      M.renote(t)
    end })
end

local function index_of(m, name)
  local _, i = M.track(m, name)
  return i
end

-- Day 1: the sketch. A tempo, a lead and a bass, a marker; a part drawn and
-- taken back; a look at the mixer and the help.
days[1] = function(E)
  M = E.Model
  local r = E.rng
  local tempo = r.int(84, 112)
  E:act({ name = "set the tempo", keys = { ":tempo " .. tempo .. "<CR>" }, says = tempo .. " bpm",
    apply = function(m) m.tempo = tempo end })
  add_track(E, 0, "Lead", "synth")
  draw(E, 1, 1, phrase(r, r.int(4, 7), 4, 60, 72), "draw the lead's first bar")
  add_track(E, 1, "Bass", "synth")
  draw(E, 2, 1, phrase(r, r.int(2, 4), 4, 55, 60), "draw the bass")
  -- A second bar of lead that the user does not like: drawn, then undone.
  local keys = E.go(1, 2)
  local dk = E.draw(phrase(r, 3, 4, 60, 72))
  for _, k in ipairs(dk) do keys[#keys + 1] = k end
  keys[#keys + 1] = "<C-w>p"
  -- One undo step: the clip that `i` made and the notes drawn into it.
  keys[#keys + 1] = "u"
  E:act({ name = "draw a second bar of lead, and undo it", keys = keys, focus = "arrange" })
  E:act({ name = "mark the intro", keys = { "<Esc>", "1|", ":marker Intro<CR>" }, says = "Intro",
    apply = function(m) m.markers[#m.markers + 1] = { name = "Intro", beat = 0 } end })
  E:act({ name = "look at the mixer", keys = { "<Space>mm" }, focus = "mixer" })
  E:act({ name = "close the mixer", keys = { "<Space>mm" }, focus = "arrange" })
  if r.chance(0.5) then
    -- Not timed: the first `:help` of a session takes over a second of
    -- processor time (a finding of the first run); later ones take 20 ms.
    E:act({ name = "read the help of a key", keys = { ":help gU<CR>" }, focus = "textbuf", slow = true })
    E:act({ name = "close the help", keys = { ":q<CR>" }, focus = "arrange" })
  end
end

-- Day 2: material from outside. A chorale from a MIDI file, a drum sample,
-- names and colors, a repeated bar, a clip deleted by mistake and brought back.
days[2] = function(E)
  M = E.Model
  local r = E.rng
  local lib = E.workdir .. "/library/"
  local file = "bwv269-aus-meines-herzens-grunde.mid"
  local parts = M.read_midi(lib .. file)
  local below = #E.model.tracks
  local keys = E.go(below, 3)
  keys[#keys + 1] = ":import " .. lib .. file .. "<CR>"
  E:act({ name = "import a Bach chorale at bar 3", keys = keys, slow = true, says = "imported",
    apply = function(m)
      for k, part in ipairs(parts) do
        local t = M.new_track(part.name)
        t.clips = M.ANY
        for _, n in ipairs(part.notes) do
          t.notes[#t.notes + 1] = { pitch = n.pitch, start = 8 + n.start, length = n.length, velocity = n.velocity }
        end
        M.sort_notes(t.notes)
        table.insert(m.tracks, below + k, t)
      end
    end })
  -- The imported parts have no instrument: give each a synth, and a name.
  local names = { "Choir", "Organ", "Voices", "Strings" }
  local first = r.int(0, #names - 1)
  for k, part in ipairs(parts) do
    local i = below + k
    local name = names[(first + k) % #names + 1]
    local keys2 = E.go(i)
    for _, x in ipairs({ "a", "synth<CR>", "grn", "<C-u>" .. name .. "<CR>" }) do keys2[#keys2 + 1] = x end
    E:act({ name = "give " .. part.name .. " a synth and the name " .. name, keys = keys2,
      apply = function(m) m.tracks[i].devices = { "synth" } m.tracks[i].name = name end })
  end
  -- A drum sample on a track of its own, under the cursor's track.
  local at = r.int(1, #E.model.tracks)
  keys = E.go(at, 1)
  keys[#keys + 1] = ":import " .. lib .. "drum-avk.wav<CR>"
  local seconds = M.wav_seconds(lib .. "drum-avk.wav")
  E:act({ name = "import a drum sample", keys = keys, slow = true, says = "imported",
    apply = function(m)
      local t = M.new_track("drum-avk")
      t.clips = { { kind = "audio", start = 0, length = seconds * m.tempo / 60, file = "drum-avk.wav" } }
      table.insert(m.tracks, at + 1, t)
    end })
  -- Colors for two tracks.
  for _ = 1, 2 do
    local i, color = r.int(1, #E.model.tracks), r.pick(COLORS)
    keys = E.go(i)
    keys[#keys + 1] = "grC"
    keys[#keys + 1] = color .. "<CR>"
    E:act({ name = "color track " .. i, keys = keys, apply = function(m) m.tracks[i].color = color end })
  end
  -- The lead's bar again after it.
  local lead = index_of(E.model, "Lead")
  keys = E.go(lead, 1)
  keys[#keys + 1] = "&"
  E:act({ name = "repeat the lead's first bar", keys = keys, apply = function(m)
    local t = m.tracks[lead]
    local c = t.clips[1]
    t.clips[#t.clips + 1] = { kind = "midi", start = c.start + c.length, length = c.length, notes = M.copy(c.notes) }
    M.renote(t)
  end })
  -- The bass clip deleted by mistake, and brought back.
  local bass = index_of(E.model, "Bass")
  keys = E.go(bass, 1)
  keys[#keys + 1] = "x"
  keys[#keys + 1] = "u"
  E:act({ name = "delete the bass clip by mistake, and undo", keys = keys })
  -- Levels by ear.
  for _ = 1, r.int(2, 3) do
    local i, db, up = r.int(1, #E.model.tracks), r.int(1, 6), r.chance(0.3)
    keys = E.go(i)
    keys[#keys + 1] = db .. (up and "+" or "-")
    E:act({ name = (up and "raise" or "lower") .. " track " .. i .. " by " .. db .. " dB", keys = keys,
      apply = function(m)
        -- The fader goes from -60 to +6 dB (docs/reference/mixer-view.md).
        local v = m.tracks[i].volume + (up and db or -db)
        m.tracks[i].volume = math.max(-60, math.min(6, v))
      end })
  end
end

-- Day 3: the mix and a first export. A reverb track with sends, pan and
-- levels typed in the mixer, a faster tempo, a marker, a WAV and a MIDI file.
days[3] = function(E)
  M = E.Model
  local r = E.rng
  local last = #E.model.tracks
  add_track(E, last, "Verb", "reverb")
  local lead = index_of(E.model, "Lead")
  for _, i in ipairs({ lead, index_of(E.model, "Bass") }) do
    local level = -r.int(6, 18)
    local keys = E.go(i)
    keys[#keys + 1] = ":send Verb " .. level .. "<CR>"
    E:act({ name = "send track " .. i .. " to the reverb", keys = keys, says = "Verb",
      apply = function(m) m.tracks[i].sends = { { target = "Verb", level = level } } end })
  end
  -- In the mixer: the strip of the lead, its pan and its level typed.
  local pan = r.int(1, 5) * 10
  local level = -r.int(1, 8)
  local keys = { "<Esc>", "<Space>mm", "0" }
  if lead > 1 then keys[#keys + 1] = (lead - 1) .. "l" end
  keys[#keys + 1] = "grpL" .. pan .. "<CR>"
  keys[#keys + 1] = "grv" .. level .. "<CR>"
  E:act({ name = "pan and level the lead in the mixer", keys = keys, focus = "mixer",
    apply = function(m) m.tracks[lead].pan = -pan / 100 m.tracks[lead].volume = level end })
  E:act({ name = "close the mixer", keys = { "<Space>mm" }, focus = "arrange" })
  -- A faster tempo; the clips keep their beats. The drum sample keeps its
  -- time (`timebase` "time"), so it is shorter in beats.
  local tempo = E.model.tempo + r.int(4, 12)
  E:act({ name = "a faster tempo", keys = { ":tempo " .. tempo .. "<CR>" }, says = tempo .. " bpm",
    apply = function(m)
      for _, t in ipairs(m.tracks) do
        if t.clips ~= M.ANY then
          for _, c in ipairs(t.clips) do
            if c.kind == "audio" then c.length = c.length * tempo / m.tempo end
          end
        end
      end
      m.tempo = tempo
    end })
  E:act({ name = "mark the chorale", keys = { "<Esc>", "3|", ":marker Chorale<CR>" }, says = "Chorale",
    apply = function(m) m.markers[#m.markers + 1] = { name = "Chorale", beat = 8 } end })
  local mix = E.workdir .. "/mix-day3.wav"
  E:act({ name = "export the mix", keys = { ":render " .. mix .. " wait=true<CR>" }, slow = true, says = "rendered",
    check = function(self)
      local f = io.open(mix, "rb")
      if not f or f:seek("end") < 1000 then self:fail("export the mix", "no WAV file at " .. mix) end
      f:close()
    end })
  local mid = E.workdir .. "/song-day3.mid"
  E:act({ name = "export the song as MIDI", keys = { ":export " .. mid .. "<CR>" }, slow = true,
    check = function(self)
      -- The file holds the notes of each MIDI track, read without paw.
      local parts = M.read_midi(mid)
      local want = {}
      for _, t in ipairs(self.model.tracks) do
        if #t.notes > 0 then want[#want + 1] = { name = t.name, notes = t.notes } end
      end
      local diffs = M.diff(want, parts, "song-day3.mid")
      if #diffs > 0 then self:fail("export the song as MIDI", table.concat(diffs, "\n", 1, math.min(6, #diffs))) end
    end })
end

--- The keys that open the clip at bar `bar` of track `i` in the piano roll.
local function roll(E, i, bar)
  local keys = E.go(i, bar)
  keys[#keys + 1] = "<CR>"
  return keys
end

local function add(list, ...)
  for _, k in ipairs({ ... }) do list[#list + 1] = k end
  return list
end

--- The clip of a track that starts at `beat`, in the model.
local function clip_at(t, beat)
  for _, c in ipairs(t.clips) do
    if c.start == beat then return c end
  end
  error("the model has no clip at beat " .. beat .. " on " .. t.name)
end

-- Day 4: the piano roll. The lead's first bar goes up (the person tries an
-- interval, takes it back and tries another), louder, and quantized.
days[4] = function(E)
  M = E.Model
  local r = E.rng
  local lead = index_of(E.model, "Lead")
  local tried, semis = r.int(5, 7), r.int(1, 4)
  local keys = add(roll(E, lead, 1), "vie", tried .. "<C-a>", "<Esc>", "u", "vie", semis .. "<C-a>", "vie", "]", "<Esc>")
  E:act({ name = "transpose the lead's first bar " .. semis .. " semitones up, and louder", keys = keys,
    focus = "pianoroll", apply = function(m)
      local t = m.tracks[lead]
      for _, n in ipairs(clip_at(t, 0).notes) do
        n.pitch = n.pitch + semis
        n.velocity = math.min(127, n.velocity + 10)
      end
      M.renote(t)
    end })
  -- The notes are on the grid: a quantize moves none of them.
  E:act({ name = "quantize the bar", keys = { "=ie" }, focus = "pianoroll" })
  E:act({ name = "back to the arrange view", keys = { "<Esc>", "<C-w>p" }, focus = "arrange" })
  -- The bass, one octave down, in its own roll; then back.
  local bass = index_of(E.model, "Bass")
  keys = add(roll(E, bass, 1), "vie", "12<C-x>", "<Esc>", "<C-w>p")
  E:act({ name = "the bass an octave down", keys = keys, focus = "arrange", apply = function(m)
    local t = m.tracks[bass]
    for _, n in ipairs(clip_at(t, 0).notes) do n.pitch = n.pitch - 12 end
    M.renote(t)
  end })
end

-- Day 5: a part played in. A new track takes a keyboard (the test port of
-- the null backend); the person records four bars from bar 5, a little
-- late on each note as people are, and quantizes the take.
days[5] = function(E)
  M = E.Model
  local r = E.rng
  local last = #E.model.tracks
  add_track(E, last, "Keys", "synth")
  local keys_track = last + 1
  -- A whole beat or two for each note: the grid of a beat in the roll
  -- takes the lateness of a loaded machine (up to half a beat) away.
  local played, at = {}, 0
  while at < 8 do
    local len = math.min(r.pick({ 1, 1, 2 }), 8 - at)
    played[#played + 1] = { pitch = r.pick(SCALE), start = at, length = len }
    at = at + len
  end
  if E.live then
    -- The keyboard: a port of the null backend (set up, not typed).
    paw.api.engine_restart({ backend = "null", test_midi = { "Keys A" } })
  end
  E:act({ name = "choose the keyboard and arm the track",
    keys = add(E.go(keys_track, 5), ":countin off<CR>", "IKeys A<CR>", "r"), focus = "arrange",
    check = function(self)
      if not paw.tracks()[keys_track].armed then self:fail("arm", "the track is not armed") end
    end })
  E:act({ name = "record two bars from bar 5", slow = true, run = function(self)
    self:type({ "R" })
    self:until_(function() return paw.transport.recording and paw.transport.playing end, "the recording")
    for _, n in ipairs(played) do
      self:until_beat(16 + n.start + 0.05)
      paw.midi.inject({ type = "note_on", pitch = n.pitch, velocity = 100, port = "Keys A", channel = 1 })
      self:until_beat(16 + n.start + n.length - 0.2)
      paw.midi.inject({ type = "note_off", pitch = n.pitch, port = "Keys A", channel = 1 })
    end
    self:until_beat(16 + 8.1)
    self:type({ "<Space><Space>" })
    self:until_(function() return not paw.transport.playing end, "the song to stop")
  end, apply = function(m)
    local t = m.tracks[keys_track]
    -- The take's clip ends where the recording stopped: not known.
    t.clips = M.ANY
    for _, n in ipairs(played) do
      -- Not yet quantized: the starts and lengths of the take are checked
      -- after the quantize.
      t.notes[#t.notes + 1] = { pitch = n.pitch, start = M.ANY, length = M.ANY, velocity = 100 }
    end
  end })
  E:act({ name = "quantize the take to the beat", keys = add(roll(E, keys_track, 5), "]g", "]g", "=ie", "<Esc>", "<C-w>p"),
    focus = "arrange", apply = function(m)
      local t = m.tracks[keys_track]
      t.notes = {}
      for _, n in ipairs(played) do
        t.notes[#t.notes + 1] = { pitch = n.pitch, start = 16 + n.start, length = n.length, velocity = 100 }
      end
      M.sort_notes(t.notes)
    end })
  E:act({ name = "disarm the track", keys = add(E.go(keys_track, 5), "r"), focus = "arrange" })
  if E.live then paw.api.engine_restart({ backend = "null" }) end
end

-- Day 6: automation. The lead fades in over two bars; the bass moves from
-- left to right; a look at the mixer, where a solo is tried and taken back.
days[6] = function(E)
  M = E.Model
  local r = E.rng
  local lead = index_of(E.model, "Lead")
  local low = -r.int(12, 24)
  E:act({ name = "a volume point at the lead's start", keys = add(E.go(lead, 1), ":lane.add " .. low .. "<CR>"),
    apply = function(m) M.automate(m.tracks[lead], "volume", 0, low) end })
  local top = E.model.tracks[lead].volume
  E:act({ name = "a second point, typed after A", keys = add(E.go(lead, 3), "A", "<C-u>" .. top .. "<CR>"),
    apply = function(m) M.automate(m.tracks[lead], "volume", 8, top) end })
  local bass = index_of(E.model, "Bass")
  E:act({ name = "the bass pans from left to right",
    keys = add(E.go(bass, 1), ":lane.add -0.5 target=pan<CR>", "4|", ":lane.add 0.5 target=pan<CR>"),
    apply = function(m)
      M.automate(m.tracks[bass], "pan", 0, -0.5)
      M.automate(m.tracks[bass], "pan", 12, 0.5)
    end })
  local i = r.int(1, #E.model.tracks)
  E:act({ name = "solo a track in the mixer, and take it back", keys = { "<Esc>", "<Space>mm", "0", (i > 1 and (i - 1) .. "l" or "0"), "s", "s" },
    focus = "mixer" })
  E:act({ name = "close the mixer", keys = { "<Space>mm" }, focus = "arrange" })
end

-- Day 7: the drum sample is too short: stretched to half speed. The first
-- two bars become the region "Verse", and a marker shows the bridge.
days[7] = function(E)
  M = E.Model
  local r = E.rng
  local drum = index_of(E.model, "drum-avk")
  local factor = r.pick({ 1.5, 2 })
  E:act({ name = "stretch the drum sample", keys = add(E.go(drum, 1), ":clip.stretch " .. factor .. "<CR>"),
    apply = function(m)
      local c = m.tracks[drum].clips[1]
      c.length = c.length * factor
    end })
  E:act({ name = "loop the first two bars, and make them a region",
    keys = add(E.go(1, 1), "gl2W", ":region Verse<CR>", "gL"), says = "Verse",
    apply = function(m)
      m.markers[#m.markers + 1] = { name = "Verse", beat = 0, length = 8 }
      table.sort(m.markers, M.marker_order)
    end })
  local bar = r.int(4, 6)
  E:act({ name = "a marker for the bridge, named when asked", keys = add(E.go(1, bar), "g'", "Bridge<CR>"),
    apply = function(m)
      m.markers[#m.markers + 1] = { name = "Bridge", beat = (bar - 1) * 4 }
      table.sort(m.markers, M.marker_order)
    end })
end

-- Day 8: fewer voices. The person deletes a voice of the chorale, does not
-- like it, brings it back, and deletes another for good.
days[8] = function(E)
  M = E.Model
  local r = E.rng
  local voices = {}
  for i, t in ipairs(E.model.tracks) do
    if t.clips == M.ANY and t.devices[1] == "synth" and t.name ~= "Keys" then voices[#voices + 1] = i end
  end
  local first = r.pick(voices)
  E:act({ name = "delete a voice, and undo", keys = add(E.go(first), "dd", "u"), focus = "arrange" })
  local gone = voices[(r.int(0, #voices - 1) + 1)]
  local name = E.model.tracks[gone].name
  E:act({ name = "delete the voice " .. name, keys = add(E.go(gone), "dd"), focus = "arrange",
    apply = function(m) table.remove(m.tracks, gone) end })
end

-- Day 9: finding things. The files buffer brings the drum sample again on
-- a new track; the pickers find a track and a marker.
days[9] = function(E)
  M = E.Model
  local lib = E.workdir .. "/library"
  -- `go` puts the file on a new track below the cursor's: the last.
  E:act({ name = "open the library in the files buffer", keys = add(E.go(#E.model.tracks), ":files " .. lib .. "<CR>"),
    focus = "textbuf" })
  local seconds = M.wav_seconds(lib .. "/drum-avk.wav")
  E:act({ name = "put the drum sample on a new track", keys = { "/drum<CR>", "go" }, slow = true,
    apply = function(m)
      local t = M.new_track("drum-avk")
      t.clips = { { kind = "audio", start = 0, length = seconds * m.tempo / 60, file = "drum-avk.wav" } }
      m.tracks[#m.tracks + 1] = t
    end })
  E:act({ name = "back to the arrange view", keys = { "<Esc>", ":b arrange<CR>" }, focus = "arrange" })
  local bass = index_of(E.model, "Bass")
  E:act({ name = "find the bass with the track picker", keys = { "<Esc>", "<Space>ft", "Bass<CR>" }, focus = "arrange",
    check = function(self)
      local t = paw.cursor.track()
      if not t or t.name ~= "Bass" then self:fail("pick a track", "the cursor is on " .. tostring(t and t.name)) end
    end })
  E:act({ name = "go to the bridge with the marker picker", keys = { "<Esc>", "<Space>fm", "Bridge<CR>" }, focus = "arrange",
    check = function(self)
      local want = 0
      for _, m in ipairs(self.model.markers) do if m.name == "Bridge" then want = m.beat end end
      if paw.cursor.beat ~= want then self:fail("pick a marker", "the cursor is at beat " .. paw.cursor.beat) end
    end })
  E:act({ name = "mute the second drum track", keys = add(E.go(#E.model.tracks), "M"),
    apply = function(m) m.tracks[#m.tracks].mute = true end })
  E:act({ name = "look at the bass's notes", keys = add(E.go(bass, 1), "<CR>", "<Esc>", "<C-w>p"), focus = "arrange" })
end

-- Day 10: the undo tree. Two ideas for the lead's level; the person goes
-- back through the states in time with g-.
days[10] = function(E)
  M = E.Model
  local r = E.rng
  local lead = index_of(E.model, "Lead")
  E:act({ name = "load the undo tree", keys = { ":ext.load undotree<CR>" } })
  local first, second = r.int(2, 5), r.int(1, 3)
  local function level(db) return math.max(-60, math.min(6, E.model.tracks[lead].volume + db)) end
  local a = level(-first)
  E:act({ name = "the lead " .. first .. " dB down", keys = add(E.go(lead), first .. "-"),
    apply = function(m) m.tracks[lead].volume = a end })
  E:act({ name = "undo it", keys = { "u" }, apply = function(m) m.tracks[lead].volume = level(first) end })
  local b = level(second)
  E:act({ name = "the lead " .. second .. " dB up instead", keys = { second .. "+" },
    apply = function(m) m.tracks[lead].volume = b end })
  E:act({ name = "g- goes to the first idea, on the other branch", keys = { "g-" },
    apply = function(m) m.tracks[lead].volume = a end })
  E:act({ name = "the undo tree's window, and closed", keys = { "<Space>pu", "<Esc>" }, focus = "arrange" })
end

-- Day 11: the project takes its files in, and the stems go to a friend.
days[11] = function(E)
  M = E.Model
  E:act({ name = "copy the outside files into the project", keys = { "<Esc>", ":media.collect<CR>" }, slow = true,
    check = function(self)
      for _, t in ipairs(paw.tracks()) do
        for _, c in ipairs(t:clips()) do
          local file = c:get().file
          if file and not file:find(self.workdir .. "/project/media/", 1, true) then
            self:fail("media.collect", "a clip still plays " .. file)
          end
        end
      end
    end })
  -- A stem for each track that sounds: not muted, with clips. Its name is
  -- the track's, in renders/stems inside the project's folder.
  E:act({ name = "render a stem for each track", keys = { ":render stems tracks<CR>", "y" }, slow = true,
    check = function(self)
      local want = {}
      for _, t in ipairs(self.model.tracks) do
        if not t.mute and (t.clips == M.ANY or #t.clips > 0) then want[#want + 1] = t.name .. ".wav" end
      end
      table.sort(want)
      local dir = self.workdir .. "/project/renders/stems"
      local got
      self:until_(function()
        got = {}
        local pipe = io.popen("ls '" .. dir .. "' 2>/dev/null")
        for line in pipe:lines() do if line:find("%.wav$") then got[#got + 1] = line end end
        pipe:close()
        return #got >= #want
      end, "the stems in " .. dir, 120000)
      table.sort(got)
      if table.concat(got, " ") ~= table.concat(want, " ") then
        self:fail("stems", "the stems are " .. table.concat(got, " ") .. ", the model's tracks " .. table.concat(want, " "))
      end
    end })
end

-- Day 12: rework. The bass is played again, the second bar of lead goes,
-- and the song slows down a little.
days[12] = function(E)
  M = E.Model
  local r = E.rng
  local bass = index_of(E.model, "Bass")
  E:act({ name = "delete the bass clip", keys = add(E.go(bass, 1), "x"), apply = function(m)
    table.remove(m.tracks[bass].clips, 1)
    M.renote(m.tracks[bass])
  end })
  draw(E, bass, 1, phrase(r, r.int(3, 5), 4, 48, 55), "draw a new bass")
  local lead = index_of(E.model, "Lead")
  E:act({ name = "delete the lead's second bar", keys = add(E.go(lead, 2), "x"), apply = function(m)
    local t = m.tracks[lead]
    for k, c in ipairs(t.clips) do if c.start == 4 then table.remove(t.clips, k) break end end
    M.renote(t)
  end })
  local tempo = E.model.tempo - r.int(2, 6)
  E:act({ name = "a slower tempo, typed with grt", keys = { "<Esc>", "grt", "<C-u>" .. tempo .. "<CR>" },
    apply = function(m)
      for _, t in ipairs(m.tracks) do
        if t.clips ~= M.ANY then
          for _, c in ipairs(t.clips) do
            if c.kind == "audio" then c.length = c.length * tempo / m.tempo end
          end
        end
      end
      m.tempo = tempo
    end })
end

-- Day 13: the arrangement grows. The lead's bar repeats twice more, the
-- last copy is muted, and a voice of the chorale comes in later.
days[13] = function(E)
  M = E.Model
  local lead = index_of(E.model, "Lead")
  E:act({ name = "repeat the lead's bar twice", keys = add(E.go(lead, 1), "2&"), apply = function(m)
    local t = m.tracks[lead]
    local c = t.clips[1]
    for k = 1, 2 do
      t.clips[#t.clips + 1] = { kind = "midi", start = c.start + k * c.length, length = c.length, notes = M.copy(c.notes) }
    end
    table.sort(t.clips, function(a, b) return a.start < b.start end)
    M.renote(t)
  end })
  E:act({ name = "mute the last copy", keys = add(E.go(lead, 3), "~"), apply = function(m)
    clip_at(m.tracks[lead], 8).muted = true
  end })
end

-- Day 14: the last mix. Levels, a final render and a MIDI file; the help of
-- the render is read first.
days[14] = function(E)
  M = E.Model
  local r = E.rng
  for _ = 1, 2 do
    local i, db = r.int(1, #E.model.tracks), r.int(1, 3)
    E:act({ name = "lower track " .. i .. " by " .. db .. " dB", keys = add(E.go(i), db .. "-"),
      apply = function(m) m.tracks[i].volume = math.max(-60, m.tracks[i].volume - db) end })
  end
  E:act({ name = "read the help of :render", keys = { ":help :render<CR>" }, focus = "textbuf", slow = true })
  E:act({ name = "close the help", keys = { ":q<CR>" }, focus = "arrange" })
  local mix = E.workdir .. "/final.wav"
  E:act({ name = "render the final mix", keys = { ":render " .. mix .. " wait=true<CR>" }, slow = true, says = "rendered" })
  local mid = E.workdir .. "/final.mid"
  E:act({ name = "export the song as MIDI", keys = { ":export " .. mid .. "<CR>" }, slow = true,
    check = function(self)
      local parts = M.read_midi(mid)
      local want = {}
      for _, t in ipairs(self.model.tracks) do
        -- A muted clip is not in the file (docs/how-to/export-midi.md).
        local playing = M.copy(t)
        if t.clips ~= M.ANY then
          playing.clips = {}
          for _, c in ipairs(t.clips) do
            if not c.muted then playing.clips[#playing.clips + 1] = c end
          end
          M.renote(playing)
        end
        if #playing.notes > 0 then want[#want + 1] = { name = t.name, notes = playing.notes } end
      end
      local diffs = M.diff(want, parts, "final.mid")
      if #diffs > 0 then self:fail("export the song as MIDI", table.concat(diffs, "\n", 1, math.min(6, #diffs))) end
    end })
end

return { days = days }
