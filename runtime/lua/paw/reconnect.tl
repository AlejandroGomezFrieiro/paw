-- The audio device going away and coming back, and MIDI ports likewise:
-- what the session reports (`audio.lost`, `audio.restored`, `midi.lost`,
-- `midi.returned`), told to the user.
--
--   paw.opt.audio_reconnect = false   -- do not reopen a device that comes back
--   :audio.reconnect                  -- try to reopen it now
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local type partial = require("paw.partial")
local type CommandModule = require("paw.command")

local record Paw is partial.Paw
  command: CommandModule
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

local record M
end

options.define("audio_reconnect", true)

local function apply()
  api.audio_watch({auto = opt.audio_reconnect and true or false})
end
apply()
events.on(
  options.changed,
  function(e: options.Changed)
    if e.name == "audio_reconnect" then
      apply()
    end
  end
)

events.on(
  kernel.audio_lost,
  function(e: kernel.AudioLost)
    local took = e.recording and " The take so far is kept." or ""
    local back = e.auto and "it is opened again when it comes back (`:audio.reconnect` tries now)"
      or "`:audio.reconnect` opens it again when it is back"
    paw.notify(
      string.format(
        "The audio device %s was lost (%s): stopped, and running without sound.%s %s.", e.device, e.reason, took, back
      ),
      "error"
    )
  end
)

events.on(
  kernel.audio_restored,
  function(e: kernel.AudioRestored)
    paw.notify(string.format("The audio device %s is back, and open again", e.device))
  end
)

local function parts(list: {string}): string
  if #list == 0 then
    return ""
  end
  return " (" .. table.concat(list, ", ") .. ")"
end

events.on(
  kernel.midi_lost,
  function(e: kernel.MidiPort)
    paw.notify(
      string.format("The MIDI input %s went away%s; it is taken again when it comes back", e.port, parts(e.parts)),
      "warn"
    )
  end
)

events.on(
  kernel.midi_returned,
  function(e: kernel.MidiPort) paw.notify(string.format("The MIDI input %s is back%s", e.port, parts(e.parts))) end
)

--- Try to open again the device that went away. Returns true if it is open.
function M.reconnect(): boolean
  local lost = api.engine_get().lost
  if not lost then
    paw.notify("no audio device has gone away")
    return true
  end
  local open: boolean
  local ok, err = pcall(function() open = api.audio_reconnect() end) as (boolean, string)
  if not ok then
    paw.notify(string.format("could not open %s again: %s", lost.device, tostring(err):match("^[^\n]*")), "error")
    return false
  end
  if not open then
    paw.notify(string.format("%s is not back yet", lost.device), "warn")
  end
  return open
end

paw.command(
  "audio.reconnect", function() M.reconnect() end, {desc = "Open the audio device that went away again, if it is back"}
)

return M
