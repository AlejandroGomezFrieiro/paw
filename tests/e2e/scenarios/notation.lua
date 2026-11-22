-- "Write a melody in the score" (the notation extension): the person
-- brings in a Bach chorale, writes a melody over it in the notation view,
-- corrects notes there, and writes the score as MusicXML and LilyPond. The
-- notes are the truth: after each edit in the score, the MIDI notes are
-- what the model says, and a MusicXML file opened again gives them back.
-- See docs/explanation/about-the-e2e-tests.md.
-- short: 2
local M -- the model module, set by each day
local days = {}

local FILE = "bwv510-gib-dich-zufrieden.mid"
local LETTER = { c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11 }
local STEP = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }

--- The pitch that note entry gives a letter after the pitch `before`: the
--- octave nearest the note before, within a fourth (the extension's
--- reference, "Note entry"). The scenario does not type `f` or `b`, the
--- letters that a key with one sharp or one flat alters.
local function nearest(letter, before)
  local best
  for octave = -1, 9 do
    local p = (octave + 1) * 12 + LETTER[letter]
    if not best or math.abs(p - before) < math.abs(best - before) then best = p end
  end
  return best
end

--- The notes of a MusicXML file in the order of the file, read without
--- paw: `{ { pitch, part } }`. A note that a tie continues is not a new note.
local function read_musicxml(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("*a")
  f:close()
  local out, parts = {}, 0
  for part in text:gmatch("<part [^>]*>(.-)</part>") do
    parts = parts + 1
    for note in part:gmatch("<note[ >](.-)</note>") do
      if not note:find("<rest") and not note:find('<tie type="stop"', 1, true) then
        local step, octave = note:match("<step>(%a)</step>"), note:match("<octave>(%d+)</octave>")
        local alter = tonumber(note:match("<alter>(%-?%d+)</alter>") or "0")
        out[#out + 1] = { pitch = (tonumber(octave) + 1) * 12 + STEP[step] + alter, part = parts }
      end
    end
  end
  return out, parts
end

--- The model's notes of a track, in the order of time, as pitches.
local function pitches(t)
  local out = {}
  for _, n in ipairs(t.notes) do
    out[#out + 1] = n.pitch
  end
  return out
end

local function load_notation(E)
  E:act({ name = "load the notation extension", keys = { "<Esc>", ":ext.load notation<CR>" } })
end

-- Day 1: the chorale comes in, each voice with a synth. The person adds a
-- flute, sketches a bar in the piano roll and writes the melody over it in
-- the score, then corrects two notes there.
days[1] = function(E)
  M = E.Model
  local r = E.rng
  local parts = M.read_midi(E.workdir .. "/library/" .. FILE)
  E:act({
    name = "import the chorale",
    keys = { "<Esc>", ":import " .. E.workdir .. "/library/" .. FILE .. "<CR>" },
    slow = true,
    says = "imported",
    apply = function(m)
      for _, part in ipairs(parts) do
        local t = M.new_track(part.name)
        t.clips = M.ANY
        for _, n in ipairs(part.notes) do
          t.notes[#t.notes + 1] = M.copy(n)
        end
        m.tracks[#m.tracks + 1] = t
      end
    end,
  })
  for i = 1, #parts do
    E:act({
      name = "a synth for voice " .. i,
      keys = { "<Esc>", i .. "G", "a", "synth<CR>" },
      apply = function(m) m.tracks[i].devices = { "synth" } end,
    })
  end
  local last = #E.model.tracks
  E:act({
    name = "add the track Flute",
    keys = { "<Esc>", last .. "G", "o", "grn", "<C-u>Flute<CR>", "a", "synth<CR>" },
    apply = function(m)
      local t = M.new_track("Flute")
      t.devices = { "synth" }
      m.tracks[#m.tracks + 1] = t
    end,
  })
  local flute = last + 1
  -- A sketch: four quarters from C4 in the piano roll.
  local keys, sketch = E.draw({ { 60, 4 }, { 62, 4 }, { 64, 4 }, { 65, 4 } })
  local all = { "<Esc>", flute .. "G", "1|" }
  for _, k in ipairs(keys) do
    all[#all + 1] = k
  end
  all[#all + 1] = "<C-w>p"
  E:act({
    name = "sketch a bar for the flute",
    keys = all,
    focus = "arrange",
    apply = function(m)
      local t = m.tracks[flute]
      t.clips = { { kind = "midi", start = 0, length = 4, notes = sketch } }
      M.renote(t)
    end,
  })
  load_notation(E)
  E:act({
    name = "open the bar as a score",
    keys = { "<Esc>", flute .. "G", "1|", ":notation<CR>" },
    focus = "notation",
  })
  -- The melody, by letter over the sketch: quarters replace the quarters.
  -- The melody stays from C4 up: a note under the treble staff makes the
  -- clip a grand staff, and the later letters then go beside the sketch's
  -- notes on the other staff, not over them (a finding of the first run).
  local letters, last = {}, 60
  while #letters < 4 do
    local letter = r.pick({ "c", "d", "e", "g", "a" })
    if nearest(letter, last) >= 60 then
      letters[#letters + 1] = letter
      last = nearest(letter, last)
    end
  end
  E:act({
    name = "write the melody " .. table.concat(letters),
    keys = { "0", "g5", "i" .. table.concat(letters), "<Esc>" },
    focus = "notation",
    apply = function(m)
      local c = m.tracks[flute].clips[1]
      local before = 60
      for k, letter in ipairs(letters) do
        before = nearest(letter, before)
        c.notes[k] = { pitch = before, start = k - 1, length = 1, velocity = M.ANY }
      end
      M.renote(m.tracks[flute])
    end,
  })
  E:act({
    name = "sharpen the second note and lift the third an octave",
    keys = { "0", "w", "+", "w", "}" },
    focus = "notation",
    apply = function(m)
      local c = m.tracks[flute].clips[1]
      c.notes[2].pitch = c.notes[2].pitch + 1
      c.notes[3].pitch = c.notes[3].pitch + 12
      M.renote(m.tracks[flute])
    end,
  })
  E:act({
    name = "delete the last note",
    keys = { "w", "x" },
    focus = "notation",
    apply = function(m)
      local c = m.tracks[flute].clips[1]
      c.notes[4] = nil
      M.renote(m.tracks[flute])
    end,
  })
  E:act({ name = "back to the arrange view", keys = { "<Esc>", "\\n" }, focus = "arrange" })
end

-- Day 2: the score goes out. The flute's bar as MusicXML and LilyPond, and
-- the whole score as MusicXML. The flute's file, imported again, gives its
-- notes back (then the person takes the import back).
days[2] = function(E)
  M = E.Model
  load_notation(E)
  local flute = #E.model.tracks
  local xml = E.workdir .. "/flute.musicxml"
  E:act({
    name = "write the flute as MusicXML",
    keys = { "<Esc>", flute .. "G", "1|", ":notation.export " .. xml .. "<CR>" },
    slow = true,
    check = function(self)
      local got = read_musicxml(xml)
      local want = pitches(self.model.tracks[flute])
      local seen = {}
      for k, n in ipairs(got) do
        seen[k] = n.pitch
      end
      if table.concat(seen, " ") ~= table.concat(want, " ") then
        self:fail(
          "MusicXML",
          "the file has the pitches " .. table.concat(seen, " ") .. ", the model " .. table.concat(want, " ")
        )
      end
    end,
  })
  local ly = E.workdir .. "/flute.ly"
  E:act({
    name = "write the flute as LilyPond",
    keys = { ":notation.export " .. ly .. "<CR>" },
    slow = true,
    check = function(self)
      local f = io.open(ly, "rb")
      local text = f and f:read("*a") or ""
      if f then f:close() end
      if not text:find("\\version", 1, true) then self:fail("LilyPond", "no LilyPond source in " .. ly) end
    end,
  })
  local score = E.workdir .. "/score.musicxml"
  E:act({
    name = "write the whole score as MusicXML",
    keys = { ":notation.export " .. score .. " all<CR>" },
    slow = true,
    check = function(self)
      local got, parts = read_musicxml(score)
      local want = 0
      for _, t in ipairs(self.model.tracks) do
        want = want + #t.notes
      end
      if parts ~= #self.model.tracks or #got ~= want then
        self:fail(
          "MusicXML of the score",
          string.format("%d parts and %d notes, the model %d and %d", parts, #got, #self.model.tracks, want)
        )
      end
    end,
  })
  -- The import and its undo are one action: the model does not change.
  E:act({
    name = "import the flute's MusicXML again at bar 3, compare, and undo",
    slow = true,
    run = function(self)
      self:type({ "<Esc>", flute .. "G", "3|", ":import " .. xml .. "<CR>" })
      local t = paw.tracks()[flute + 1]
      local got = {}
      for _, c in ipairs(t and t:clips() or {}) do
        for _, n in ipairs(c:notes()) do
          got[#got + 1] = { pitch = n.pitch, start = c.start + n.start - 8, length = n.length }
        end
      end
      M.sort_notes(got)
      local want = {}
      for _, n in ipairs(self.model.tracks[flute].notes) do
        want[#want + 1] = { pitch = n.pitch, start = n.start, length = n.length }
      end
      local diffs = M.diff(want, got, "the flute again")
      if #diffs > 0 then self:fail("MusicXML again", table.concat(diffs, "\n", 1, math.min(6, #diffs))) end
      self:type({ "<Esc>", "u" })
    end,
  })
end

-- Day 3: the chorale's soprano, corrected in the score: its first note an
-- octave down.
days[3] = function(E)
  M = E.Model
  load_notation(E)
  local first = E.model.tracks[1].notes[1]
  E:act({
    name = "the soprano's first note an octave down, in the score",
    keys = { "<Esc>", "1G", "1|", ":notation<CR>", "0", "{", "<Esc>" },
    focus = "notation",
    apply = function(m)
      m.tracks[1].notes[1].pitch = first.pitch - 12
      M.sort_notes(m.tracks[1].notes)
    end,
  })
  E:act({ name = "back to the arrange view", keys = { "\\n" }, focus = "arrange" })
end

return { days = days }
