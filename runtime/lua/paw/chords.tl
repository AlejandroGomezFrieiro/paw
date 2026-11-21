-- `paw.chords`: chord symbols read into pitches, for the pencil's `c`
-- (paw/roll_draw.tl) and for anyone who writes chords. One parser reads
-- both kinds of symbol:
--
--   absolute   C  Cm  Cmaj7  C4maj7 (the root's octave)  Csus4  Am7b5
--              F#m9/C# (a bass)  C(add9)  Bb7
--   relative   I  ii  V7  ii7  bVII  V64 = V6/4  I6  viio7  iiø7
--   to the     V/ii  V7/V  viio7/V (applied chords)
--   key        N6  It6  Fr6  Ger6
--
-- The names of qualities are paw.harmony's (what its reading names), so
-- a chord read can be written again by its name; `M.quality` adds more.
-- A relative chord counts its degrees in the key's scale; with `b` or `#`
-- first, from the major scale on the tonic, as paw.harmony's numerals
-- do (`bVII`, `bIII`). Its case gives a triad's quality: upper major,
-- lower minor, `o` diminished, `+` augmented, `ø` half diminished. `7` is
-- the seventh of the scale above the root (V7 a dominant seventh, I7 a
-- major seventh), unless the symbol says (`o7`, `ø7`, `maj7`). Figures
-- invert: 6 and 65 the first inversion, 64 and 43 the second, 42 the third.
--
--   local c = paw.chords.parse("V7/V", paw.harmony.key(), 60)
--   c.pitches   -- { 62, 66, 69, 72 }: D7 in C major
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local type partial = require("paw.partial")
local type HarmonyModule = require("paw.harmony")
local type MusicModule = require("paw.music")

local type Key = HarmonyModule.Key

--- A chord read from its symbol: its pitches from low to high, its name
--- (absolute) and its numeral in the key.
local record Voiced
  symbol: string
  name: string
  roman: string
  root: integer
  quality: string
  pitches: {integer}
end

--- A quality by its suffix: semitones above the root.
local record Quality
  name: string
  suffix: string
  steps: {integer}
end

local record Paw is partial.Paw
  harmony: HarmonyModule
  music: MusicModule
end
local paw = (_G as {string:Paw}).paw

local record M
  type Voiced = Voiced
  type Quality = Quality
  --- Every quality by its suffix, paw.harmony's and those added.
  qualities: {string:Quality}
end

local MAJOR = { 0, 2, 4, 5, 7, 9, 11 }
local NUMERALS: {string:integer} = { i = 1, ii = 2, iii = 3, iv = 4, v = 5, vi = 6, vii = 7 }
local LETTERS: {string:integer} = { c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11 }

-- Other ways to write a suffix.
local ALIASES: {string:string} = {
  maj = "", M = "", major = "", min = "m", minor = "m", ["-"] = "m", ["+"] = "aug", ["°"] = "dim", o = "dim",
  ["ø"] = "m7b5", ["ø7"] = "m7b5", o7 = "dim7", ["°7"] = "dim7", M7 = "maj7", ["Δ"] = "maj7", ["Δ7"] = "maj7",
  sus = "sus4", mM7 = "m(maj7)", mmaj7 = "m(maj7)", ["-7"] = "m7", ["7b5"] = "7b5", ["(add9)"] = "add9",
  add2 = "add9", ["2"] = "sus2", ["4"] = "sus4",
}

M.qualities = {}

--- Add a chord name: its suffix after the root (`"7#9"`) and its tones
--- in semitones above the root. A name the reading does not know is
--- written but not read.
function M.quality(suffix: string, steps: {integer}, name?: string)
  M.qualities[suffix] = { name = name or suffix, suffix = suffix, steps = steps }
end

for _, q in ipairs(paw.harmony.read.qualities) do M.quality(q.suffix, q.steps, q.name) end
M.quality("7b5", { 0, 4, 6, 10 })
M.quality("7#9", { 0, 4, 7, 10, 15 })
M.quality("13", { 0, 4, 7, 10, 14, 21 })
M.quality("m11", { 0, 3, 7, 10, 14, 17 })

local function pc(n: integer): integer return n % 12 end

--- The quality of a suffix, or nil.
local function quality_of(suffix: string): Quality
  return M.qualities[suffix] or M.qualities[ALIASES[suffix] or "\0"]
end

--- The pitch of class `class` nearest `near` (below it on a tie).
local function nearest(class: integer, near: integer): integer
  local up = near + pc(class - near)
  return up - near > 6 and up - 12 or up
end

--- Pitches of a chord on `root` (a pitch) with `steps`, from low to high:
--- with a third, a second or a fourth is a ninth or an eleventh, an octave
--- up; `bass`, a pitch class, goes below; then `inversion` times the
--- lowest note goes up an octave.
local function voice(root: integer, steps: {integer}, bass?: integer, inversion?: integer): {integer}
  local third = false
  for _, s in ipairs(steps) do if s == 3 or s == 4 then third = true end end
  local out: {integer} = {}
  for _, s in ipairs(steps) do
    local up = third and (s == 1 or s == 2 or s == 5)
    out[#out + 1] = root + (up and s + 12 or s)
  end
  table.sort(out)
  for _ = 1, inversion or 0 do
    local low = table.remove(out, 1)
    out[#out + 1] = low + 12
  end
  if bass and pc(bass) ~= pc(out[1]) then
    for i = #out, 1, -1 do if pc(out[i]) == pc(bass) then table.remove(out, i) end end
    table.insert(out, 1, out[1] - pc(out[1] - bass))
  end
  return out
end

--- The quality with these steps (in any order), or nil.
local function quality_with(steps: {integer}): Quality
  local want: {integer:boolean} = {}
  for _, s in ipairs(steps) do want[s % 12] = true end
  for _, q in pairs(M.qualities) do
    if #q.steps == #steps then
      local same = true
      for _, s in ipairs(q.steps) do if not want[s % 12] then same = false end end
      if same and paw.harmony.read.by_quality[q.name] then return q end
    end
  end
end

--- The key's steps if it has seven, else the major scale's.
local function scale_of(key: Key): {integer}
  return key.steps and #key.steps == 7 and key.steps or MAJOR
end

--- A degree's root (a pitch class) in `key`: in its scale, or with an
--- accidental from the major scale on its tonic.
local function degree_root(key: Key, degree: integer, accidental: string): integer
  if accidental == "b" then return pc(key.root + MAJOR[degree] - 1) end
  if accidental == "#" then return pc(key.root + MAJOR[degree] + 1) end
  return pc(key.root + scale_of(key)[degree])
end

--- A numeral: its accidental, degree and case (true for upper), or nil.
local function numeral(text: string): string, integer, boolean, string
  local acc, word, rest = text:match("^([b#]?)([ivIV]+)(.*)$")
  if not word then return nil end
  local degree = NUMERALS[word:lower()]
  if not degree or (word ~= word:upper() and word ~= word:lower()) then return nil end
  return acc, degree, word == word:upper(), rest
end

local FIGURES: {string:integer} = { [""] = 0, ["7"] = 0, ["6"] = 1, ["65"] = 1, ["64"] = 2, ["43"] = 2, ["42"] = 3, ["2"] = 3 }
local SEVENTHS: {string:boolean} = { ["7"] = true, ["65"] = true, ["43"] = true, ["42"] = true, ["2"] = true }

local relative: function(text: string, key: Key, near: integer): Voiced, string

--- The augmented sixths and the Neapolitan, on the key's tonic.
local function special(text: string, key: Key, near: integer): Voiced
  local t = key.root
  local sets: {string:{integer}} = {
    It6 = { 8, 12, 18 }, Fr6 = { 8, 12, 14, 18 }, Ger6 = { 8, 12, 15, 18 },
  }
  if text == "N6" or text == "N" then
    local root = nearest(pc(t + 1), near)
    return { symbol = text, roman = text, root = pc(t + 1), quality = "maj", pitches = voice(root, { 0, 4, 7 }, nil, text == "N6" and 1 or 0) }
  end
  local set = sets[text]
  if not set then return nil end
  local bass = nearest(pc(t + 8), near - 7)
  local out: {integer} = {}
  for i, s in ipairs(set) do out[i] = bass + s - 8 end
  return { symbol = text, roman = text, root = pc(t + 8), quality = text, pitches = out }
end

relative = function(text: string, key: Key, near: integer): Voiced, string
  local sp = special(text, key, near)
  if sp then return sp end
  -- An applied chord: the chord of the key of the degree after the slash.
  local body, target = text:match("^(.-)/([b#]?[ivIV]+)$")
  if body then
    local acc, degree, upper = numeral(target)
    if not degree then return nil, "not a degree: " .. target end
    local tonic = degree_root(key, degree, acc)
    local into = paw.harmony.parse_key(({ "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" })[tonic + 1] .. (upper and " major" or " minor"))
    local v, why = relative(body, into, near)
    if v then v.symbol, v.roman = text, text end
    return v, why
  end
  local acc, degree, upper, rest = numeral(text)
  if not degree then return nil end
  local root = degree_root(key, degree, acc)
  -- The mark of the quality, then the figures.
  local mark, figure = "", rest
  for _, m in ipairs({ "o", "°", "+", "ø" }) do
    if rest:sub(1, #m) == m then mark, figure = m, rest:sub(#m + 1) end
  end
  local maj7 = false
  if figure:match("^maj") or figure:match("^M") then
    maj7 = true
    figure = figure:gsub("^maj", ""):gsub("^M", "")
  end
  local inversion = FIGURES[figure]
  if inversion == nil then
    if figure == "9" then inversion = 0 else return nil, "figures are 7, 6, 64, 65, 43, 42 or 9: not `" .. figure .. "`" end
  end
  local third = upper and 4 or 3
  local fifth = 7
  if mark == "o" or mark == "°" or mark == "ø" then third, fifth = 3, 6 end
  if mark == "+" then third, fifth = 4, 8 end
  local steps = { 0, third, fifth }
  if SEVENTHS[figure] or figure == "9" or maj7 then
    local seventh: integer
    if maj7 then seventh = 11
    elseif mark == "o" or mark == "°" then seventh = 9
    elseif mark == "ø" then seventh = 10
    elseif acc == "" then
      local s = scale_of(key)
      seventh = pc(s[(degree + 5) % 7 + 1] - s[degree])
      if seventh < 9 then seventh = 10 end
    else
      seventh = 10
    end
    steps[#steps + 1] = seventh
    if figure == "9" then steps[#steps + 1] = 14 end
  end
  local pitches = voice(nearest(root, near), steps, nil, inversion)
  -- An inversion stays near: its bass, not its root, is nearest the pitch.
  if pitches[1] - near > 6 then
    for i, p in ipairs(pitches) do pitches[i] = p - 12 end
  end
  local q = quality_with(steps)
  return { symbol = text, roman = text, root = root, quality = q and q.name or "", pitches = pitches }
end

--- An absolute chord: a root, maybe its octave, a quality, maybe a bass.
local function absolute(text: string, near: integer): Voiced, string
  local letter, acc, rest = text:match("^([A-Ga-g])([#b]?)(.*)$")
  if not letter then return nil end
  local class = pc(LETTERS[letter:lower()] + (acc == "#" and 1 or acc == "b" and -1 or 0))
  local bass: integer
  local body, b = rest:match("^(.-)/([A-Ga-g][#b]?)$")
  if body then
    rest = body
    bass = pc(LETTERS[b:sub(1, 1):lower()] + (b:sub(2) == "#" and 1 or b:sub(2) == "b" and -1 or 0))
  end
  -- A suffix first (C7 is a seventh); else an octave then a suffix (C4maj7).
  local q = quality_of(rest)
  local root = nearest(class, near)
  if not q then
    local octave, after = rest:match("^(%-?%d)(.*)$")
    q = octave and quality_of(after)
    if q then root = class + 12 * (math.floor(tonumber(octave)) + 1) end
  end
  if not q then return nil, "no chord `" .. rest .. "` after " .. letter:upper() .. acc end
  local v: Voiced = { symbol = text, root = class, quality = q.name, pitches = voice(root, q.steps, bass) }
  return v
end

--- Read a chord symbol in `key` (paw.harmony's key, C major when nil)
--- with its root nearest the pitch `near` (60 when nil). Returns the chord,
--- or nil and why not.
function M.parse(text: string, key?: Key, near?: integer): Voiced, string
  text = (text or ""):match("^%s*(.-)%s*$")
  key = key or paw.harmony.parse_key("C major")
  near = near or 60
  local figure = text:gsub("6/4", "64"):gsub("6/5", "65"):gsub("4/3", "43"):gsub("4/2", "42")
  local v, why = relative(figure, key, near)
  if not v and not why then v, why = absolute(text, near) end
  if not v then return nil, why or ("not a chord: `" .. text .. "`") end
  local chord: HarmonyModule.Chord = { root = v.root, quality = v.quality, tones = {} }
  if paw.harmony.read.by_quality[v.quality] then
    v.name = v.name or paw.harmony.chord_name(chord, key)
    v.roman = v.roman or paw.harmony.chord_roman(chord, key)
  end
  local names: {string} = {}
  for i, p in ipairs(v.pitches) do names[i] = paw.music.name(p) end
  v.name = v.name or (v.roman and table.concat(names, " ")) or text
  return v
end

--- The chord of `n` notes (3 a triad, 4 a seventh) on `root`, a pitch,
--- stacked in thirds from the scale of `key`: the diatonic chord.
function M.stack(root: integer, n: integer, key?: Key): {integer}
  key = key or paw.harmony.parse_key("C major")
  local out: {integer} = {}
  for i = 0, n - 1 do out[#out + 1] = paw.harmony.step(key, root, 2 * i) end
  return out
end

--- The chords to offer at the pencil, in this order: the diatonic triads
--- and sevenths of `key`, then the common qualities on the pitch `near`.
--- Each with its symbol, name, numeral and pitches.
function M.offer(key: Key, near: integer): {Voiced}
  local out: {Voiced} = {}
  local upper = { "I", "II", "III", "IV", "V", "VI", "VII" }
  local s = scale_of(key)
  for _, seventh in ipairs({ false, true }) do
    for d = 1, 7 do
      local third = pc(s[(d + 1) % 7 + 1] - s[d])
      local fifth = pc(s[(d + 3) % 7 + 1] - s[d])
      local word = third == 4 and upper[d] or upper[d]:lower()
      local mark = fifth == 6 and (seventh and pc(s[(d + 5) % 7 + 1] - s[d]) == 10 and "ø" or "o") or fifth == 8 and "+" or ""
      local v = M.parse(word .. mark .. (seventh and "7" or ""), key, near)
      if v then out[#out + 1] = v end
    end
  end
  local root = paw.music.name(near):gsub("%-?%d+$", "")
  for _, suffix in ipairs({ "", "m", "7", "maj7", "m7", "dim", "aug", "sus2", "sus4", "6", "9", "m7b5", "dim7", "add9" }) do
    local v = M.parse(root .. suffix, key, near)
    if v then out[#out + 1] = v end
  end
  return out
end

return M
