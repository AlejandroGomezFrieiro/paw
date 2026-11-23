-- Hearing a note as it is placed or clicked in the vocal editor.
--
-- When the engine is up and the track has a singer, the engine sings the
-- note by itself with the track's voice (the `Audition` message), and
-- the track's `utau` device plays that at once (a classic voicebank answers
-- in a fraction of a second). Without the engine or a singer, a soft tone at
-- the note's pitch stands in. `paw.opt.utau_audition` turns it off.
local api = paw.api
local ffi = require("ffi")
local utau = require("utau")
local proto = require("utau.proto")

paw.option.define("utau_audition", true) -- hear notes as they are placed or clicked in the vocal editor

local M = { request = 0, pending = {}, last = 0, heard = {} }

local RATE = 44100

--- A soft tone at `pitch` for `ms` milliseconds: its sample rate, its
--- channels, and its samples as 32-bit floats.
function M.tone(pitch, ms)
  local frames = math.floor(RATE * ms / 1000)
  local buf = ffi.new("float[?]", frames)
  local hz = 440 * 2 ^ ((pitch - 69) / 12)
  local fade = math.floor(RATE * 0.01)
  for i = 0, frames - 1 do
    local env = math.min(1, i / fade, (frames - i) / fade)
    -- A little of the octave above, so that low notes are heard on small speakers.
    local t = 2 * math.pi * hz * i / RATE
    buf[i] = env * 0.12 * (math.sin(t) + 0.3 * math.sin(2 * t))
  end
  return RATE, 1, ffi.string(buf, frames * 4)
end

local function play(device, rate, channels, raw)
  local ok, err = pcall(utau.voices.audition, device, rate, channels, raw)
  if not ok then M.error = tostring(err) end
  return ok
end

--- Hear a note of a vocal track: `pitch`, `lyric`, for `ms` (at most a
--- second). Returns how it is heard: "engine", "tone", or nil.
function M.play(track_id, pitch, lyric, ms)
  if not paw.opt.utau_audition then return nil end
  local device = utau.device_of(track_id)
  if not device then return nil end
  -- Not more than one a twentieth of a second, as a drag goes across rows.
  -- The clock gives milliseconds as a float: 50 ms later can read 49.999...
  local now = api.now()
  if now - M.last < 50 - 1e-6 then return nil end
  M.last = now
  ms = math.max(120, math.min(1000, ms or 400))
  local config = utau.config(track_id)
  if utau.engine.state == "ready" and utau.engine.connected() and config.singer then
    M.request = M.request + 1
    -- Only the latest click is worth hearing.
    M.pending = { [M.request] = { device = device, at = now } }
    utau.engine.send(proto.encode.audition(M.request, tostring(track_id), pitch, lyric or "a", ms))
    M.heard[#M.heard + 1] = "engine"
    return "engine"
  end
  play(device, M.tone(pitch, ms))
  M.heard[#M.heard + 1] = "tone"
  return "tone"
end

--- Hear the note at `index` of a clip.
function M.note(clip_id, index)
  local clip = api.clip_get(clip_id)
  local note = api.clip_notes(clip_id)[index]
  if not note then return end
  local lyric = note.meta and note.meta.lyric or paw.opt.utau_default_lyric
  if lyric == "R" or lyric == "r" then return end
  local ms = paw.time.seconds(note.length, clip.start + note.start) * 1000
  return M.play(clip.track, note.pitch, lyric, ms)
end

-- What the engine sang comes back as audio with the request's number.
utau.on_audition = function(m, raw)
  local wanted = M.pending[tonumber(m.hash)]
  if not wanted then return end
  M.pending = {}
  -- Too late to belong to the click any more.
  if api.now() - wanted.at > 3000 then return end
  play(wanted.device, m.rate, m.channels, raw)
end

return M
