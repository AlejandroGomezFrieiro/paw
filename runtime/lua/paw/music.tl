-- Note names and a few scales, for scripts that would rather say "C4" than 60.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.

--- A pitch as typed in a query or a range: one pitch, or a pitch class.
local record PitchWord
  pitch: integer
  class: integer
end

local record M
  type PitchWord = PitchWord
  scales: {string: {integer}}
end

local names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local offsets: {string: integer} = {C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11}

--- MIDI note number for a name such as "C4", "f#3" or "Bb2". Numbers pass through.
function M.pitch(note: number | string): integer
  -- A number passes as it is, as the Lua did: a pitch is a whole number.
  if note is number then
    return note as integer
  end
  local letter, accidental, octave = tostring(note):match("^([A-Ga-g])([#b]?)(-?%d+)$")
  if not letter then
    error("not a note name: " .. tostring(note), 2)
  end
  local semitone = offsets[letter:upper()] + (accidental == "#" and 1 or accidental == "b" and -1 or 0)
  return ((tonumber(octave) as integer) + 1) * 12 + semitone
end

--- Name of a MIDI note number: 60 -> "C4".
function M.name(pitch: integer): string
  return names[pitch % 12 + 1] .. (math.floor(pitch / 12) - 1)
end

--- True if a MIDI pitch is a black key.
function M.is_black(pitch: integer): boolean
  return #names[pitch % 12 + 1] == 2
end

M.scales = {
  major = {0, 2, 4, 5, 7, 9, 11},
  minor = {0, 2, 3, 5, 7, 8, 10},
  dorian = {0, 2, 3, 5, 7, 9, 10},
  pentatonic = {0, 2, 4, 7, 9},
  minor_pentatonic = {0, 3, 5, 7, 10},
  blues = {0, 3, 5, 6, 7, 10},
  chromatic = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11},
}

--- Pitch of scale degree `degree` (1 is the root, 8 the octave above).
function M.degree(root: number | string, scale: string | {integer}, degree: integer): integer
  local steps: {integer}
  if scale is {integer} then
    steps = scale
  else
    steps = M.scales[scale]
  end
  if not steps then
    error("unknown scale " .. tostring(scale), 2)
  end
  local index = degree - 1
  return M.pitch(root) + steps[index % #steps + 1] + 12 * math.floor(index / #steps)
end

local NOTE: {string: integer} = {c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11}

--- A pitch as typed in a query or an Ex range: `{ pitch = 61 }` for `c#4`
--- or `61`, `{ class = 1 }` for `c#` in any octave; nil when it is not one.
function M.pitch_word(text: string): PitchWord
  local n = text:match("^%d+$")
  if n then
    local number = tonumber(n) as integer
    return number <= 127 and {pitch = number} or nil
  end
  local letter, acc, octave = text:match("^([A-Ga-g])([#b]?)(%-?%d*)$")
  if not letter or octave == "-" then
    return nil
  end
  local semitone = NOTE[letter:lower()] + (acc == "#" and 1 or acc == "b" and -1 or 0)
  if octave == "" then
    return {class = semitone % 12}
  end
  local pitch = ((tonumber(octave) as integer) + 1) * 12 + semitone
  if pitch < 0 or pitch > 127 then
    return nil
  end
  return {pitch = pitch}
end

return M
