-- The musical objects of a clip's notes, for the text objects of the piano
-- roll (`in` `ic` `ip` `iv` `i=` and their `a` forms): the note, the chord,
-- the phrase, the voice and the pitch. Each function takes the notes in
-- the order the roll keeps them (by start, lower pitches first) and gives
-- the notes of the object. `region` makes a region of `paw.keymap` that
-- names those notes alone, so that every operator acts on them and on
-- nothing else in their stretch.
--
--   local objects = require("paw.note_objects")
--   objects.voice(notes, notes[3])      --> the notes of the line that note 3 is in
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local type edit = require("paw.edit")

local EPS = 1e-9
-- A note that started before another and goes on sounding less than this
-- (beats) after it starts is legato, not a second voice under it.
local LEGATO = 0.125

--- A note of the roll: its start in the roll's beats, its id and the id of
--- its clip (`paw.roll_clips.notes` gives these).
local record Note
  start: number
  length: number
  pitch: integer
  id: integer
  clip: integer
end

--- A phrase: notes with no rest longer than the limit between them.
local record Phrase
  start: number
  finish: number
  notes: {Note}
end

--- Where a note is in the texture: `rank` from the top (1 the highest of
--- the notes that sound when it starts), whether it is the lowest of two
--- or more (`bass`), and whether it sounds alone.
local record Place
  rank: integer
  bass: boolean
  alone: boolean
end

local record M
  type Note = Note
  type Phrase = Phrase
end

local function finish(n: Note): number return n.start + n.length end

--- The phrases of `notes`: a rest longer than `rest` beats ends one.
function M.phrases(notes: {Note}, rest: number): {Phrase}
  local out: {Phrase} = {}
  local current: Phrase
  for _, n in ipairs(notes) do
    if not current or n.start - current.finish > rest + EPS then
      current = { start = n.start, finish = finish(n), notes = {} }
      out[#out + 1] = current
    end
    current.notes[#current.notes + 1] = n
    current.finish = math.max(current.finish, finish(n))
  end
  return out
end

--- The place of the phrase at `beat` in `list`, or of the next one from a
--- rest, or of the last one after them all. Nil if there is none.
function M.phrase_at(list: {Phrase}, beat: number): integer
  for i, p in ipairs(list) do
    if beat < p.finish - EPS then return i end
  end
  if #list > 0 then return #list end
end

--- The notes that start at `start`.
function M.onset(notes: {Note}, start: number): {Note}
  local out: {Note} = {}
  for _, n in ipairs(notes) do
    if math.abs(n.start - start) < EPS then out[#out + 1] = n end
  end
  return out
end

--- The notes that sound at `beat`: started at or before it, not yet ended.
function M.sounding(notes: {Note}, beat: number): {Note}
  local out: {Note} = {}
  for _, n in ipairs(notes) do
    if n.start <= beat + EPS and finish(n) > beat + EPS then out[#out + 1] = n end
  end
  return out
end

--- The chord at the cursor and `count - 1` chords after it. The chord of a
--- note is the notes that start with it; away from notes, the notes that
--- sound at `beat`. The chords after it are the next places where two or
--- more notes start together.
function M.chords(notes: {Note}, at: Note, beat: number, count: integer): {Note}
  local out = at and M.onset(notes, at.start) or M.sounding(notes, beat)
  if #out == 0 then return out end
  local last = -math.huge
  for _, n in ipairs(out) do last = math.max(last, n.start) end
  local more = (count or 1) - 1
  local i = 1
  while more > 0 and i <= #notes do
    local n = notes[i]
    if n.start > last + EPS then
      -- The notes are in the order they start: those of one start follow.
      local j = i
      while j < #notes and math.abs(notes[j + 1].start - n.start) < EPS do j = j + 1 end
      if j > i then
        for k = i, j do out[#out + 1] = notes[k] end
        more = more - 1
      end
      last = n.start
      i = j + 1
    else
      i = i + 1
    end
  end
  return out
end

--- Where each note is in the texture, by its place in `notes`.
local function places(notes: {Note}): {Place}
  local longest = 0.0
  for _, n in ipairs(notes) do longest = math.max(longest, n.length) end
  local out: {Place} = {}
  local first = 1
  for i, n in ipairs(notes) do
    while first < i and notes[first].start + longest < n.start - EPS do first = first + 1 end
    local above, below = 0, 0
    local j = first
    while j <= #notes and notes[j].start <= n.start + EPS do
      local m = notes[j]
      local with = math.abs(m.start - n.start) < EPS or finish(m) > n.start + LEGATO
      if j ~= i and with then
        if m.pitch > n.pitch then above = above + 1 elseif m.pitch < n.pitch then below = below + 1 end
      end
      j = j + 1
    end
    out[i] = { rank = above + 1, bass = below == 0 and above > 0, alone = above == 0 and below == 0 }
  end
  return out
end

--- The voice that `of` is in: the line of notes at its place in the
--- texture. The lowest of the notes that sound together is the bass;
--- else the n-th from the top is voice n, the top voice first. A note that
--- sounds alone is in the top voice and in the bass.
function M.voice(notes: {Note}, of: Note): {Note}
  local where = places(notes)
  local mine: Place
  for i, n in ipairs(notes) do
    if n == of then mine = where[i] end
  end
  if not mine then return {} end
  local out: {Note} = {}
  for i, n in ipairs(notes) do
    local p = where[i]
    local yes: boolean
    if mine.bass then yes = p.bass or p.alone else yes = p.rank == mine.rank and not p.bass end
    if yes then out[#out + 1] = n end
  end
  return out
end

--- The notes of `voice` and the notes that double them an octave or more
--- away: notes that start with one of them on the same pitch class.
function M.doublings(notes: {Note}, voice: {Note}): {Note}
  local inside: {Note:boolean} = {}
  for _, n in ipairs(voice) do inside[n] = true end
  local out: {Note} = {}
  for _, n in ipairs(notes) do
    local yes = inside[n]
    if not yes then
      for _, v in ipairs(voice) do
        if math.abs(v.start - n.start) < EPS and v.pitch % 12 == n.pitch % 12 then
          yes = true
          break
        end
      end
    end
    if yes then out[#out + 1] = n end
  end
  return out
end

--- The notes of `pitch`, or with `class` of its pitch class in every octave.
function M.pitch(notes: {Note}, pitch: integer, class: boolean): {Note}
  local out: {Note} = {}
  for _, n in ipairs(notes) do
    if n.pitch == pitch or (class and n.pitch % 12 == pitch % 12) then out[#out + 1] = n end
  end
  return out
end

--- A region of the piano roll that names `notes` alone: the block they
--- span, its end moved on to `to` when that is later. Nil for no notes.
function M.region(notes: {Note}, to?: number): edit.Region
  if #notes == 0 then return nil end
  local r0, r1, c0, c1 = 127, 0, math.huge, -math.huge
  local named: {integer:{integer:boolean}} = {}
  for _, n in ipairs(notes) do
    r0, r1 = math.min(r0, n.pitch), math.max(r1, n.pitch)
    c0, c1 = math.min(c0, n.start), math.max(c1, finish(n))
    named[n.clip] = named[n.clip] or {}
    named[n.clip][n.id] = true
  end
  return { view = "pianoroll", kind = "block", r0 = r0, r1 = r1, c0 = c0, c1 = math.max(c1, to or c1), notes = named }
end

return M
