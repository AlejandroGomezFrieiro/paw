-- Tests of the starting set of snippets, loaded by tests/suite.lua with its
-- helpers. The first is the owner's example: before a C major chord,
-- `dominant` writes G7 up to it.
local T = ...
local api = paw.api
local eq, test = T.eq, T.test
local H = paw.harmony
local music = paw.music

local function load()
  if not paw.ext.loaded.snippets then
    paw.ext.load("extensions/snippets")
    assert(paw.ext.loaded.snippets.ok, paw.ext.loaded.snippets.error)
  end
end

local keys = T.keys

local function notes_of(list)
  local out = {}
  for word in list:gmatch("%S+") do
    out[#out + 1] = music.pitch(word)
  end
  return out
end

--- A track with one clip of chords: `{ "C4 E4 G4", at, length }` each.
local function track(name, chords, length)
  local t = paw.add_track({ name = name })
  local notes = {}
  for _, c in ipairs(chords) do
    for _, p in ipairs(notes_of(c[1])) do
      notes[#notes + 1] = { pitch = p, start = c[2], length = c[3], velocity = 90 }
    end
  end
  return t, t:add_clip({ start = 0, length = length or 16, notes = notes })
end

--- The notes of a clip starting at `at`: their pitches, and the pitch
--- classes as a sorted set ("2 5 7 11"), and the length of the first.
local function at(clip, beat)
  local pitches, pcs, seen, length = {}, {}, {}, nil
  for _, n in ipairs(clip:notes()) do
    if math.abs(n.start - beat) < 1e-6 then
      pitches[#pitches + 1] = n.pitch
      length = length or n.length
      if not seen[n.pitch % 12] then
        seen[n.pitch % 12] = true
        pcs[#pcs + 1] = n.pitch % 12
      end
    end
  end
  table.sort(pitches)
  table.sort(pcs)
  return pitches, table.concat(pcs, " "), length
end

local function start()
  load()
  T.fresh()
  api.engine_restart({ backend = "null" })
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  -- Panels other tests left open (the mixer, a drum grid) would leave the
  -- piano roll too few rows to show what these tests look for.
  for _, name in ipairs({
    "mixer",
    "devices",
    "drums",
    "notation",
    "utau",
    "session",
    "undotree",
    "eventlist",
    "mixdiag",
    "sections",
    "vinput",
    "tutor",
  }) do
    if paw.ui.views[name] and paw.ui.visible(name) then pcall(paw.ui.hide, name) end
  end
end

local function open(clip, pitch, beat)
  paw.flush()
  api.undo_checkpoint()
  local roll = paw.ui.views.pianoroll
  roll:edit(clip)
  roll:set(pitch, beat)
  paw.ui.focus("pianoroll")
  return roll
end

test(
  "snippets: dominant before a C major chord on another track writes G7 up to it, led from what came before",
  function()
    start()
    -- This clip plays D minor seventh; the strings bring C major at beat 4.
    local _, keys_clip = track("Keys", { { "D3 F3 A3 C4", 0, 2 } })
    track("Strings", { { "C3 G3 C4 E4", 4, 4 } })
    open(keys_clip, 60, 2)
    keys(":snippet dominant<CR>")
    local pitches, pcs, length = at(keys_clip, 2)
    eq(pcs, "2 5 7 11", "G B D F: G7, " .. table.concat(pitches, " "))
    eq(length, 2, "from the cursor up to the C")
    for _, p in ipairs(pitches) do
      eq(p >= 48 and p <= 84, true, "within the keys' range")
    end
    local moved = H.voice.distance(notes_of("D3 F3 A3 C4"), pitches)
    eq(moved <= 6, true, "smoothly from the D minor seventh: moved " .. moved)
    local before = table.concat(pitches, " ")
    -- Tab to the choices, C-n to the next voicing.
    keys("<Tab>")
    eq(paw.snippet.active().choices[paw.snippet.active().current].name, "voicing", "the first choice is the voicing")
    keys("<C-n>")
    local other, pcs2, length2 = at(keys_clip, 2)
    eq(pcs2, "2 5 7 11", "still G7")
    eq(length2, 2, "still up to the C")
    eq(table.concat(other, " ") ~= before, true, "voiced otherwise: " .. table.concat(other, " "))
    -- One undo takes it all away.
    keys("u")
    eq(#keys_clip:notes(), 4, "u: only the D minor seventh is left")
    eq(select(2, at(keys_clip, 2)), "", "nothing at the cursor")
  end
)

test(
  "snippets: the owner's example as the terminal shows it: chords over the ruler, ghosts, marks, the choice",
  function()
    start()
    local _, clip = track("Piano", { { "D3 F3 A3 C4", 0, 2 } }, 8)
    track("Strings", { { "C3 G3 C4 E4", 4, 4 } }, 8)
    open(clip, 60, 2)
    paw.opt.note_zoom = 8
    local function screen() return table.concat(api.ui_snapshot(140, 48), "\n") end
    local function has(text) return screen():find(text, 1, true) ~= nil end
    eq(has("▏Dm7") and has("▏C"), true, "the chord row: D minor seventh, then C")
    eq(has("▏B3") or has("▏G3"), false, "no B or G in the clip yet")
    keys("<C-s>")
    keys("dom")
    eq(has("D3 F3 G3 B3"), true, "the picker's pane names what it would write")
    eq(has("▏B3") and has("▏G3"), true, "and the roll shows it as ghosts:\n" .. screen())
    eq(#clip:notes(), 4, "nothing written yet")
    keys("<CR>")
    eq(has("▏G7/D"), true, "the chord row reads the new chord")
    eq(has("dominant · Tab: voicing"), true, "the snippet's span says what Tab does")
    keys("<Tab>")
    eq(has("dominant · voicing: smooth (1/5)"), true, "Tab: the voicing")
    local before = screen()
    keys("<C-n>")
    eq(
      has("dominant · voicing: drop2 (3/5)"),
      true,
      "C-n: the next voicing that sounds otherwise (close is the smooth one here)"
    )
    eq(screen() ~= before, true, "drawn anew")
    keys("<C-y>")
    eq(paw.snippet.marks(clip.id), nil, "C-y: done, the marks are gone")
    eq(has("▏G7"), true, "the notes stay")
    keys("u")
    eq(has("▏G7"), false, "u: the whole snippet undone")
    paw.ui.focus("arrange")
  end
)

test("snippets: with two clips edited, dominant writes into the active one, in its own beats", function()
  start()
  local _, piano = track("Piano", { { "D3 F3 A3 C4", 0, 2 } }, 8)
  -- The strings' clip starts at beat 2, so its C major at its own beat 2 is
  -- the song's beat 4.
  local strings = paw.add_track({ name = "Strings" })
  local other = strings:add_clip({
    start = 2,
    length = 6,
    notes = {
      { pitch = 48, start = 2, length = 4 },
      { pitch = 55, start = 2, length = 4 },
      { pitch = 60, start = 2, length = 4 },
      { pitch = 64, start = 2, length = 4 },
    },
  })
  paw.flush()
  api.undo_checkpoint()
  paw.roll_clips.open({ piano.id, other.id }, piano.id)
  paw.ui.views.pianoroll:set(60, 2)
  paw.ui.focus("pianoroll")
  keys(":snippet dominant<CR>")
  local pitches, pcs, length = at(piano, 2)
  eq(pcs .. " " .. length, "2 5 7 11 2", "G7 in the active clip, up to the C: " .. table.concat(pitches, " "))
  eq(#other:notes(), 4, "the other clip edited is left alone")
  keys("u")
  eq(#piano:notes(), 4, "one undo")
  paw.roll_clips.only()
end)

test("snippets: dominant before a C major chord in this clip, through the picker, leads into it", function()
  start()
  local _, clip = track("Piano", { { "E4 G4 C5", 4, 4 } })
  open(clip, 60, 0)
  keys("<C-s>")
  keys("dom")
  eq(paw.pick.state().item.name, "dominant", "typing finds it")
  keys("<CR>")
  local pitches, pcs, length = at(clip, 0)
  eq(pcs, "2 5 7 11", "G7: " .. table.concat(pitches, " "))
  eq(length, 4, "up to the C")
  local moved = H.voice.distance(pitches, notes_of("E4 G4 C5"))
  eq(moved <= 6, true, "into the C, moving little: " .. moved)
  keys("u")
  eq(#clip:notes(), 3, "undone")
end)

test("snippets: dominant's choices: the kind of chord, and a count chains dominants back", function()
  start()
  local _, clip = track("Piano", {})
  track("Pad", { { "C3 E3 G3", 8, 4 } })
  open(clip, 60, 0)
  keys(":snippet dominant<CR><Tab><Tab><C-n>")
  eq(
    select(2, at(clip, 0)),
    "5 7 9 11",
    "the kind's next value: G9, its fifth left out for four voices (" .. table.concat(at(clip, 0), " ") .. ")"
  )
  keys("u")
  keys(":2snippet dominant<CR>")
  eq(select(2, at(clip, 0)), "0 2 6 9", "first D7, the dominant of the dominant")
  eq(select(2, at(clip, 4)), "2 5 7 11", "then G7")
end)

test("snippets: the dominant family and its approaches", function()
  start()
  local _, clip = track("Piano", {})
  track("Pad", { { "C3 E3 G3", 4, 4 } })
  open(clip, 60, 0)
  local function expand(name, want, beat)
    keys(":snippet " .. name .. "<CR>")
    local pitches, pcs = at(clip, beat or 0)
    eq(pcs, want, name .. ": " .. table.concat(pitches, " "))
  end
  expand("tritone", "1 5 8 11") -- Db7
  keys("u")
  expand("passing-dim", "2 5 8 11") -- Bdim7, the leading note's
  keys("u")
  expand("secondary", "2 5 7 11") -- V7 of the next chord: G7
  keys("<Tab><Tab><C-n>") -- of ii: A7
  eq(select(2, at(clip, 0)), "1 4 7 9", "secondary of ii: A7")
  keys("u")
  expand("two-five", "0 2 5 9") -- Dm7
  eq(select(2, at(clip, 2)), "2 5 7 11", "then G7")
  keys("u")
  expand("sus", "0 5 7") -- Csus4 up to the C
  eq(select(2, at(clip, 4)), "0 4 7", "resolving into C")
  keys("u")
  eq(#clip:notes(), 0, "all undone")
end)

test("snippets: cadence goes to the key's tonic", function()
  start()
  local _, clip = track("Piano", {})
  H.set_key("F major")
  open(clip, 60, 0)
  keys(":snippet cadence<CR>")
  eq(select(2, at(clip, 0)), "0 4 7 10", "C7")
  eq(select(2, at(clip, 4)), "0 5 9", "then F")
  keys("<Tab><Tab><C-n>")
  eq(select(2, at(clip, 0)), "2 5 10", "IV-V-I: first Bb")
end)

test("snippets: pedal, arp and bass are made of the chords there", function()
  start()
  track("Pad", { { "A2 C3 E3", 0, 4 }, { "F2 A2 C3", 4, 4 } })
  local _, clip = track("Bass", {})
  open(clip, 40, 0)
  keys(":snippet bass<CR>")
  local list = {}
  for _, n in ipairs(clip:notes()) do
    list[#list + 1] = music.name(n.pitch) .. "@" .. n.start
  end
  eq(table.concat(list, " "), "A1@0 E2@1 A1@2 E2@3", "root and fifth of A minor for a bar, in the bass's range")
  keys("u")
  keys(":snippet bass<CR><Tab><Tab><C-n>")
  eq(#clip:notes(), 4 + 4, "two bars: A minor's, then F's")
  keys("u")
  keys(":snippet pedal<CR>")
  local n = clip:notes()[1]
  eq(n.pitch % 12 .. " " .. n.length, "9 4", "a held tonic for a bar (A minor)")
  keys("u")
  paw.opt.note_grid = 0.5
  keys(":snippet arp<CR>")
  local arp = {}
  for _, x in ipairs(clip:notes()) do
    arp[#arp + 1] = x.pitch
  end
  eq(#arp, 8, "eighths over the A minor chord's four beats")
  eq(arp[1] < arp[2] and arp[2] < arp[3], true, "upwards")
  local pcs = {}
  for i = 1, 3 do
    pcs[i] = arp[i] % 12
  end
  table.sort(pcs)
  eq(table.concat(pcs, " "), "0 4 9", "through A C E")
  paw.opt.note_grid = 0.25
end)

test("snippets: harmonize and voice-lead work on the selection", function()
  start()
  local _, clip = track("Lead", { { "C5", 0, 1 }, { "D5", 1, 1 }, { "E5", 2, 1 } })
  open(clip, 72, 0)
  keys(":snippet harmonize<CR>")
  eq(paw.ui.message.text, "select the notes to harmonize first", "without a selection it says so")
  keys("v$")
  keys("<C-s>harm<CR>")
  local pcs = {}
  for _, n in ipairs(clip:notes()) do
    pcs[#pcs + 1] = music.name(n.pitch)
  end
  table.sort(pcs)
  eq(table.concat(pcs, " "), "A4 B4 C5 C5 D5 E5", "a third below each note, in C major")
  keys("<Tab><C-n>")
  pcs = {}
  for _, n in ipairs(clip:notes()) do
    pcs[#pcs + 1] = music.name(n.pitch)
  end
  table.sort(pcs)
  eq(table.concat(pcs, " "), "C5 D5 E4 E5 F4 G4", "a sixth below")
  keys("u")
  eq(#clip:notes(), 3, "undone")

  start()
  local _, chords = track("Keys", { { "C4 E4 G4", 0, 2 }, { "B4 D5 G5", 2, 2 }, { "C4 E4 G4", 4, 2 } })
  local roll = open(chords, 60, 0)
  roll:set(60, 0)
  keys("v$")
  keys(":snippet voice-lead<CR>")
  local second = at(chords, 2)
  eq(table.concat(second, " "), "59 62 67", "the G moved next to the C: B3 D4 G4")
  eq(#chords:notes(), 9, "as many notes as before")
end)

test("snippets: Ctrl-Space offers the snippets that fit as suggestions, and Tab writes one", function()
  start()
  local _, clip = track("Piano", {}, 8)
  track("Strings", { { "C3 G3 C4 E4", 4, 4 } }, 8)
  open(clip, 60, 0)
  paw.opt.complete_auto = false
  keys("<C-Space>")
  local shown
  for _ = 1, 300 do
    shown = paw.complete.current()
    if shown then break end
    paw.wait(10)
  end
  eq(shown ~= nil, true, "suggestions show")
  local labels, which = {}, nil
  for i, item in ipairs(shown.items) do
    labels[#labels + 1] = item.label
    if item.label == "dominant" then which = i end
  end
  eq(which ~= nil, true, "dominant among them: " .. table.concat(labels, " "))
  for _ = 2, which do
    keys("<C-n>")
  end
  eq(paw.complete.current().item.label, "dominant", "chosen")
  eq(#clip:notes(), 0, "a ghost, not written yet")
  keys("<Tab>")
  eq(select(2, at(clip, 0)), "2 5 7 11", "Tab writes the G7")
  keys("u")
  eq(#clip:notes(), 0, "one undo")
  paw.opt.complete_auto = true
end)
