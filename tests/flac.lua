-- A FLAC of loud music must be a sensible size. Loaded by tests/suite.lua
-- with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

--- The number of samples per channel in a FLAC file's STREAMINFO.
local function total_samples(data)
  local b = { data:byte(22, 26) }
  return (b[1] % 16) * 2 ^ 32 + b[2] * 2 ^ 24 + b[3] * 2 ^ 16 + b[4] * 2 ^ 8 + b[5]
end

test("the demo song rendered to FLAC is no larger than the same song as a WAV", function()
  fresh()
  api.engine_restart({})
  dofile("tests/fixtures/render-song.lua")
  for _, bits in ipairs({ 16, 24 }) do
    local flac = paw.render(T.scratch .. "/demo" .. bits .. ".flac", { bits = bits, tail = 0, ["end"] = 4 })
    local wav = paw.render(T.scratch .. "/demo" .. bits .. ".wav", { bits = bits, tail = 0, ["end"] = 4 })
    local flac_size, wav_size = #T.read_file(flac.path), #T.read_file(wav.path)
    eq(
      flac_size < wav_size,
      true,
      bits .. " bits: the FLAC (" .. flac_size .. " bytes) is smaller than the WAV (" .. wav_size .. ")"
    )
    eq(total_samples(T.read_file(flac.path)), flac.frames, bits .. " bits: the file says how long it is")
  end
end)
