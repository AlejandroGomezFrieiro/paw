-- Freezing a vocal part: its singing rendered to audio, so the engine can
-- stop working on it.
--
-- Freezing is the core's bounce (`paw.bounce`): the part is rendered with
-- its devices, after the engine has sung every phrase at final quality, onto
-- an audio part right below it, "<name> (frozen)", and the vocal part is
-- muted. The vocal part keeps its notes, lyrics, curves and voice, and is
-- marked frozen (`device.meta.utau.frozen` holds the audio part's id): the
-- engine no longer sings it. Unfreezing removes the audio part, unmutes the
-- vocal part and lets the engine sing it again, from its render cache.
local api = paw.api
local utau = require("utau")

local M = {}

local function exists(id) return id and pcall(api.part_get, id) end

--- Freeze a vocal part. Returns the audio part.
function M.freeze(part_id)
  if not utau.device_of(part_id) then error("not a vocal part", 0) end
  if utau.frozen(part_id) then error("the part is frozen already", 0) end
  local part = paw.part(part_id)
  local was_muted = part.mute
  -- Muted, the part would render silent: it plays for the bounce.
  part.mute = false
  paw.flush()
  local ok, why = utau.finish(paw.opt.utau_render_timeout)
  if not ok then
    part.mute = was_muted
    error("the singing is not finished: " .. tostring(why), 0)
  end
  local bounced = paw.bounce(part, { name = part.name .. " (frozen)" })
  if not bounced then
    part.mute = was_muted
    error("nothing on the part to freeze", 0)
  end
  utau.configure(part_id, { frozen = { part = bounced.id, muted = was_muted or nil } })
  utau.voices.clear(utau.device_of(part_id))
  utau.received[tostring(part_id)] = nil
  utau.layouts[tostring(part_id)] = nil
  -- The engine forgets the part now, and sings it whole when it is back.
  utau.sync()
  return bounced
end

--- Unfreeze a vocal part: the audio part goes, and the engine sings it again.
function M.unfreeze(part_id)
  local frozen = utau.config(part_id).frozen
  if not frozen then error("the part is not frozen", 0) end
  if type(frozen) == "table" and exists(frozen.part) then api.part_remove(frozen.part) end
  utau.configure(part_id, { frozen = false })
  paw.part(part_id).mute = type(frozen) == "table" and frozen.muted or false
  utau.sync()
end

--- The audio part a frozen vocal part was rendered to, if it is still there.
function M.audio(part_id)
  local frozen = utau.config(part_id).frozen
  if type(frozen) == "table" and exists(frozen.part) then return frozen.part end
end

return M
