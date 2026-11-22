-- Codes of the MIDI 2.0 Note-On Orchestral Articulation Profile (M2-123):
-- what a note's attribute means, read and written as short text.
--
-- A note's attribute is `{ type, data }`: the type is the classification
-- (0x10 to 0x1F), and the 16 bits of data are subclass:4, variation:4,
-- direction:2, reserved:2, reset round robin:1, string:3. A code is the
-- classification and the subclass in hex, with the variation after it when
-- it is not 0: `11.A` is pizzicato, `13.2` a whole-step trill, `11.A3` the
-- third variation of pizzicato.
--
--   m2.parse("11.A")              -- { type = 0x11, data = 0xA000 }
--   m2.code({ type = 0x11, data = 0xA000 })   -- "11.A"
--   m2.describe(attr)             -- "pizzicato (11.A)"
--   m2.guess("Spicc short")       -- "11.5", from the words a library uses
local M = {}

local band, rshift, lshift = bit.band, bit.rshift, bit.lshift

--- The classifications, and the subclasses the profile names.
M.classes = {
  [0x10] = {
    "core sustains and strikes",
    {
      [0] = "sustain",
      "sustain",
      "legato",
      "molto legato",
      "glissando",
      "détaché",
      "marcato",
      "martelé",
      "senza vibrato",
      "con vibrato",
      "synchronized vibrato",
    },
  },
  [0x11] = {
    "staccatos and shorts",
    {
      [0] = "staccato",
      "staccato on the string",
      "slurred staccato",
      "accented staccato",
      "staccatissimo",
      "spiccato",
      "sautillé",
      "martellato",
      "louré",
      "portato",
      "pizzicato",
      "Bartók pizzicato",
      "col legno battuto",
      "col legno gestrichen",
      "hand tap",
      "jeté",
    },
  },
  [0x12] = { "same-note trills and repeats", { [0] = "tremolo", "growl" } },
  [0x13] = {
    "intervallic trills",
    { [0] = "trill, half step", "trill, half step", "trill, whole step", "trill, classical" },
  },
  [0x14] = { "additional colours", { [0] = "harmonics", "artificial harmonics", "col legno tratto", "flautando" } },
  [0x15] = { "pitch and dynamic gestures", { [0] = "fall" } },
  [0x16] = { "scales, runs and arpeggios", { [0] = "run" } },
  [0x17] = { "effects and noises", { [0] = "effect" } },
}
for t = 0x1A, 0x1F do
  M.classes[t] = { "the library's own", {} }
end

--- `{ type, data }` for a code (`"11.A"`, `"11.A3"`, `"1A.0"`), or nil and why.
function M.parse(code)
  local text = tostring(code or ""):upper():gsub("^%s+", ""):gsub("%s+$", "")
  local t, sub, var = text:match("^(%x%x)%.(%x)(%x?)$")
  if not t then
    return nil, "`" .. tostring(code) .. "` is not an M2-123 code such as 11.A (classification.subclass)"
  end
  local kind = tonumber(t, 16)
  if kind < 0x10 or kind > 0x1F then return nil, "`" .. tostring(code) .. "`: a classification runs from 10 to 1F" end
  return { type = kind, data = lshift(tonumber(sub, 16), 12) + lshift(tonumber(var ~= "" and var or "0", 16), 8) }
end

--- The parts of an attribute's data.
function M.parts(attr)
  local data = attr.data or 0
  return {
    type = attr.type,
    subclass = band(rshift(data, 12), 15),
    variation = band(rshift(data, 8), 15),
    direction = band(rshift(data, 6), 3),
    rrr = band(rshift(data, 3), 1),
    string = band(data, 7),
  }
end

--- An attribute's code: classification, subclass and variation. Direction,
--- string and round robin are left out: they do not change which
--- articulation it is.
function M.code(attr)
  if not attr or not attr.type or attr.type == 0 then return nil end
  local p = M.parts(attr)
  if p.variation ~= 0 then return string.format("%02X.%X%X", p.type, p.subclass, p.variation) end
  return string.format("%02X.%X", p.type, p.subclass)
end

--- Whether a value is an attribute that says something (type 0 says nothing).
function M.is(attr) return type(attr) == "table" and type(attr.type) == "number" and attr.type ~= 0 end

--- What the profile calls an attribute, in words, with its code.
function M.describe(attr)
  if not M.is(attr) then return "no articulation" end
  local p = M.parts(attr)
  local class = M.classes[p.type]
  local code = M.code(attr)
  if not class then return string.format("attribute 0x%02X 0x%04X", attr.type, attr.data or 0) end
  local name = class[2][p.subclass] or class[1]
  return name .. " (" .. code .. ")"
end

--- The codes to try for an attribute, best first, by the profile's
--- fallback: the exact one, another variation of its subclass, subclass 0
--- of its classification, and the core sustain (10.0).
function M.fallbacks(attr)
  local p = M.parts(attr)
  local out = { M.code(attr) }
  if p.variation ~= 0 then out[#out + 1] = string.format("%02X.%X", p.type, p.subclass) end
  out[#out + 1] = { type = p.type, subclass = p.subclass } -- any variation of this subclass
  if p.subclass ~= 0 then out[#out + 1] = string.format("%02X.0", p.type) end
  if p.type ~= 0x10 or p.subclass ~= 0 then out[#out + 1] = "10.0" end
  return out
end

--- Words that libraries name articulations with, and the codes they mean;
--- the longest match wins. Measured on Reaticulate's factory banks: with
--- icons first, 90 % of their articulations get a code.
M.words = {
  { "legato", "10.2" },
  { "leg", "10.2" },
  { "slur", "10.2" },
  { "portamento", "10.4" },
  { "gliss", "10.4" },
  { "detache", "10.5" },
  { "détaché", "10.5" },
  { "marcato", "10.6" },
  { "marc", "10.6" },
  { "martele", "10.7" },
  { "non vib", "10.8" },
  { "nv", "10.8" },
  { "senza vib", "10.8" },
  { "vib", "10.9" },
  { "sustain", "10.0" },
  { "sus", "10.0" },
  { "sust", "10.0" },
  { "long", "10.0" },
  { "note-whole", "10.0" },
  { "arco", "10.0" },
  { "ord", "10.0" },
  { "ordinario", "10.0" },
  { "staccatissimo", "11.4" },
  { "spiccato", "11.5" },
  { "spicc", "11.5" },
  { "spic", "11.5" },
  { "sautille", "11.6" },
  { "staccato", "11.0" },
  { "stacc", "11.0" },
  { "stac", "11.0" },
  { "stc", "11.0" },
  { "short", "11.0" },
  { "portato", "11.9" },
  { "tenuto", "11.8" },
  { "pizz-bartok", "11.B" },
  { "bartok", "11.B" },
  { "snap", "11.B" },
  { "pizzicato", "11.A" },
  { "pizz", "11.A" },
  { "col legno", "11.C" },
  { "col-legno", "11.C" },
  { "tremolo", "12.0" },
  { "trem", "12.0" },
  { "flutter", "12.0" },
  { "growl", "12.1" },
  { "multitongued", "12.9" },
  { "double tongue", "12.4" },
  { "triple tongue", "12.5" },
  { "trill-min2", "13.0" },
  { "trill-maj2", "13.2" },
  { "trill M2", "13.2" },
  { "trill m2", "13.0" },
  { "trill", "13.0" },
  { "harmonics", "14.0" },
  { "harmonic", "14.0" },
  { "harm", "14.0" },
  { "col legno tratto", "14.2" },
  { "flautando", "14.3" },
  { "flaut", "14.3" },
  { "cuivre", "14.6" },
  { "cuivré", "14.6" },
  { "fall", "15.0" },
  { "rip", "15.3" },
  { "doit", "15.2" },
  { "shake", "15.8" },
  { "cresc", "15.9" },
  { "dim", "15.A" },
  { "decresc", "15.A" },
  { "sfz", "15.D" },
  { "swell", "15.B" },
  { "run", "16.0" },
  { "legato-runs", "16.0" },
  { "fx", "17.0" },
  { "effects", "17.0" },
}
-- Longest first; of two as long, the one listed first (so `trill M2`, with
-- its capital, is tried before its lowercase twin).
for i, w in ipairs(M.words) do
  w.order = i
end
table.sort(M.words, function(a, b)
  if #a[1] ~= #b[1] then return #a[1] > #b[1] end
  return a.order < b.order
end)

--- Modifiers the profile makes controllers, not articulations: a library
--- that names them gets them as modifiers.
M.modifiers = {
  { "con sord", "mute=straight" },
  { "con-sord", "mute=straight" },
  { "sord", "mute=straight" },
  { "sul pont", "position=ponticello" },
  { "sul-pont", "position=ponticello" },
  { "sul tasto", "position=tasto" },
  { "sul-tasto", "position=tasto" },
}

--- Whether `lower` (a text in lowercase) holds `word` as a word of its own;
--- the capitals of `word` must be capitals in `text` there.
local function holds(lower, word, text)
  local wanted = word:lower()
  local at = 1
  while true do
    local i, j = lower:find(wanted, at, true)
    if not i then return false end
    local before, after = lower:sub(i - 1, i - 1), lower:sub(j + 1, j + 1)
    local cased = true
    for k = 1, #word do
      local c = word:sub(k, k)
      if c:match("%u") and text:sub(i + k - 1, i + k - 1) ~= c then cased = false end
    end
    if cased and not before:match("%a") and not after:match("%a") then return true end
    at = i + 1
  end
end

--- The code a name or an icon's name means, or nil. Case is kept for the
--- words that differ only by it (`trill m2`, `trill M2`).
function M.guess(...)
  local texts = {}
  for i = 1, select("#", ...) do
    local t = select(i, ...)
    if t and t ~= "" then texts[#texts + 1] = tostring(t):gsub("_", " ") end
  end
  local text = table.concat(texts, " ")
  local lower = text:lower()
  for _, w in ipairs(M.words) do
    if holds(lower, w[1], text) then return w[2] end
  end
end

--- The modifier a name means (`mute=straight`), or nil.
function M.modifier(name)
  local lower = tostring(name or ""):lower():gsub("_", " ")
  for _, w in ipairs(M.modifiers) do
    if holds(lower, w[1], lower) then return w[2] end
  end
end

return M
