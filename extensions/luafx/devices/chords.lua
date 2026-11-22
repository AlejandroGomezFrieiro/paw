-- Chords: every note played becomes a chord built on it. A MIDI effect:
-- put it before an instrument. Everything else that comes in (pedals,
-- bends) is passed on as it is.
local dsp = require("paw.dsp")

local shapes = {
  { "Major", { 0, 4, 7 } },
  { "Minor", { 0, 3, 7 } },
  { "Power", { 0, 7, 12 } },
  { "Sus4", { 0, 5, 7 } },
  { "Major 7", { 0, 4, 7, 11 } },
  { "Minor 7", { 0, 3, 7, 10 } },
}
local names = {}
for i, s in ipairs(shapes) do
  names[i] = s[1]
end

local dev = dsp.device {
  name = "Chords (Lua)",
  midi_effect = true,
  params = {
    { key = "chord", name = "Chord", choices = names, default = "Major" },
    { key = "octave", name = "Octave", min = -2, max = 2, default = 0 },
    { key = "spread", name = "Velocity spread", min = 0, max = 1, default = 0.1 },
  },
}

-- The notes each held key sounds, so that letting go ends the same ones
-- even when the chord was changed meanwhile.
local held = {}

function dev.process(b)
  local p = b.params
  local shape = shapes[p.chord + 1][2]
  local shift = math.floor(p.octave + 0.5) * 12
  local events = b.events
  for i = 0, b.nevents - 1 do
    local e = events[i]
    local id = e.channel * 128 + e.key
    if e.type == dsp.NOTE_ON then
      local keys = {}
      for n, interval in ipairs(shape) do
        local key = e.key + interval + shift
        if key >= 0 and key <= 127 then
          keys[#keys + 1] = key
          b:note_on(e.frame, key, e.value * (1 - p.spread * (n - 1) / #shape), e.channel)
        end
      end
      held[id] = keys
    elseif e.type == dsp.NOTE_OFF then
      for _, key in ipairs(held[id] or {}) do
        b:note_off(e.frame, key, e.channel)
      end
      held[id] = nil
    else
      b:pass(e)
    end
  end
end

return dev
