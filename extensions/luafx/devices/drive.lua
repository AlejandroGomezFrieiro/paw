-- Drive: a soft clipper with a tone filter after it, and a dry/wet mix.
local dsp = require("paw.dsp")

local dev = dsp.device {
  name = "Drive (Lua)",
  params = {
    { key = "drive", name = "Drive", min = 0, max = 36, default = 12, unit = "dB" },
    { key = "tone", name = "Tone", min = 500, max = 16000, default = 6000, unit = "Hz" },
    { key = "output", name = "Output", min = -24, max = 6, default = -6, unit = "dB" },
    { key = "mix", name = "Mix", min = 0, max = 100, default = 100, unit = "%" },
  },
}

local filters, tone

function dev.init(sample_rate)
  filters = { dsp.biquad("lowpass", 6000, 0.707, 0, sample_rate), dsp.biquad("lowpass", 6000, 0.707, 0, sample_rate) }
end

function dev.process(b)
  local p = b.params
  -- The filters are only worked out again when the tone moves.
  if p.tone ~= tone then
    tone = p.tone
    for _, f in ipairs(filters) do
      f:set("lowpass", tone, 0.707, 0, b.sample_rate)
    end
  end
  local drive, out = dsp.gain(p.drive), dsp.gain(p.output)
  local wet = p.mix / 100
  local dry = 1 - wet
  local fl, fr = filters[1], filters[2]
  local left, right = b.left, b.right
  for i = 0, b.frames - 1 do
    local l, r = left[i], right[i]
    left[i] = dry * l + wet * out * fl:process(dsp.saturate(l * drive))
    right[i] = dry * r + wet * out * fr:process(dsp.saturate(r * drive))
  end
end

return dev
