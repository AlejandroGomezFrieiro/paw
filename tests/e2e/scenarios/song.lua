-- "A song over two weeks": one person makes a song, a session a day. Each
-- day reopens what the day before saved. The details (tempo, notes, names,
-- levels, which part is reworked) come from the seed; the process is that
-- of a person: sketch, import, arrange, mix, change one's mind, export.
--
-- Each action gives its keys and the same change on the model
-- (tests/e2e/model.lua). See docs/explanation/about-the-e2e-tests.md.
-- short: 2
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
  -- Two undo steps: `i` made the clip, the drawing filled it. One `u`
  -- leaves an empty clip (a finding of the first run of this scenario: the
  -- user sees it and presses `u` again).
  keys[#keys + 1] = "u"
  keys[#keys + 1] = "u"
  E:act({ name = "draw a second bar of lead, and undo it", keys = keys, focus = "arrange" })
  E:act({ name = "mark the intro", keys = { "<Esc>", "1|", ":marker Intro<CR>" }, says = "Intro",
    apply = function(m) m.markers[#m.markers + 1] = { name = "Intro", beat = 0 } end })
  E:act({ name = "look at the mixer", keys = { "<Space>m" }, focus = "mixer" })
  E:act({ name = "close the mixer", keys = { "<Space>m" }, focus = "arrange" })
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
  local verb = last + 1
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
  local keys = { "<Esc>", "<Space>m", "0" }
  if lead > 1 then keys[#keys + 1] = (lead - 1) .. "l" end
  keys[#keys + 1] = "grpL" .. pan .. "<CR>"
  keys[#keys + 1] = "grv" .. level .. "<CR>"
  E:act({ name = "pan and level the lead in the mixer", keys = keys, focus = "mixer",
    apply = function(m) m.tracks[lead].pan = -pan / 100 m.tracks[lead].volume = level end })
  E:act({ name = "close the mixer", keys = { "<Space>m" }, focus = "arrange" })
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

return { days = days }
