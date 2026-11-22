-- Sine: a small instrument, eight voices of sine with an attack and a
-- release. Shows how an instrument reads notes and adds its sound.
local dsp = require("paw.dsp")

local dev = dsp.device {
  name = "Sine (Lua)",
  category = "instrument",
  params = {
    { key = "attack", name = "Attack", min = 0.001, max = 2, default = 0.005, unit = "s" },
    { key = "release", name = "Release", min = 0.005, max = 4, default = 0.2, unit = "s" },
    { key = "level", name = "Level", min = -48, max = 0, default = -12, unit = "dB" },
  },
}

local voices = {}
for i = 1, 8 do
  voices[i] = { key = -1, phase = 0, step = 0, level = 0, target = 0, velocity = 0 }
end

local function start(key, velocity, sample_rate)
  -- The quietest voice makes way.
  local chosen = voices[1]
  for _, v in ipairs(voices) do
    if v.level < chosen.level then chosen = v end
  end
  chosen.key, chosen.velocity, chosen.target = key, velocity, 1
  chosen.step = 2 * math.pi * dsp.mtof(key) / sample_rate
end

local function stop(key)
  for _, v in ipairs(voices) do
    if v.key == key then v.target = 0 end
  end
end

local function render(b, from, to, up, down, gain)
  local left, right = b.left, b.right
  for _, v in ipairs(voices) do
    if v.level > 0 or v.target > 0 then
      local phase, step, level, target = v.phase, v.step, v.level, v.target
      local amp = gain * v.velocity
      for i = from, to - 1 do
        if level < target then
          level = math.min(target, level + up)
        else
          level = math.max(target, level - down)
        end
        local s = math.sin(phase) * level * amp
        left[i] = left[i] + s
        right[i] = right[i] + s
        phase = phase + step
      end
      v.phase, v.level = phase % (2 * math.pi), level
    end
  end
end

function dev.process(b)
  local p = b.params
  local up = 1 / (p.attack * b.sample_rate)
  local down = 1 / (p.release * b.sample_rate)
  local gain = dsp.gain(p.level)
  -- Sound up to each event, then the event, so that notes start where they fall.
  local at = 0
  for i = 0, b.nevents - 1 do
    local e = b.events[i]
    render(b, at, e.frame, up, down, gain)
    at = e.frame
    if e.type == dsp.NOTE_ON then
      start(e.key, e.value, b.sample_rate)
    elseif e.type == dsp.NOTE_OFF then
      stop(e.key)
    elseif e.type == dsp.ALL_NOTES_OFF then
      for _, v in ipairs(voices) do
        v.target = 0
      end
    end
  end
  render(b, at, b.frames, up, down, gain)
end

return dev
