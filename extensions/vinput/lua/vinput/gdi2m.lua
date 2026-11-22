-- Guitar to MIDI: the kind of virtual input that runs gdi2m, a small neural
-- network that hears the notes of a guitar, chords included, as they are
-- played (https://github.com/maximmashkov1/gdi2m, with a JACK backend in
-- guitar_tracker).
--
-- The chain, stage by stage:
--
--   source   an audio port of the machine: the guitar, dry, straight in
--   level    a gain ahead of the tracker, which was trained at one level
--   tracker  gdi2m: when a note starts, and when it has ended
--   notes    how hard, on which MIDI channel, split by pitch or not
--   port     the MIDI port of this program's that tracks take
--
-- gdi2m runs as a program of its own, takes the audio from the port itself
-- and sends its notes to the input's MIDI port; nothing of it passes through
-- this program's audio thread.
local music = paw.music
local vinput = require("vinput")

local K = { name = "Guitar", title = "Guitar to MIDI" }

--- `E3:2, E4:3` as the splits gdi2m takes: `52:2,64:3`. Nil and the reason
--- when it does not read as that.
function K.splits(text)
  local out = {}
  for part in tostring(text or ""):gmatch("[^,%s]+") do
    local pitch, channel = part:match("^(.-):(%d+)$")
    local ok, number = pcall(music.pitch, tonumber(pitch) or pitch)
    channel = tonumber(channel)
    if not (pitch and ok and number and channel and channel >= 1 and channel <= 16) then
      return nil, "a split is a pitch and a channel, as `E3:2`; several with commas"
    end
    out[#out + 1] = number .. ":" .. channel
  end
  if #out > 3 then return nil, "at most three splits" end
  return table.concat(out, ",")
end

K.stages = {
  {
    key = "source",
    title = "Source",
    settings = {
      {
        key = "source",
        name = "Source",
        type = "choice",
        default = "",
        empty = "choose the guitar's input",
        help = "the audio port the guitar is plugged into: dry, no effects",
      },
    },
  },
  {
    key = "level",
    title = "Level",
    settings = {
      {
        key = "gain",
        name = "Gain",
        type = "number",
        min = 0.1,
        max = 8,
        step = 0.05,
        default = 1,
        unit = "×",
        help = "level ahead of the tracker; after a few seconds of playing it says what it would rather have",
      },
    },
  },
  {
    key = "tracker",
    title = "gdi2m",
    settings = {
      {
        key = "threshold",
        name = "Threshold",
        type = "number",
        min = 0.5,
        max = 0.99,
        step = 0.01,
        default = 0.85,
        help = "how sure the tracker must be to start a note: lower finds more notes and more wrong ones",
      },
      {
        key = "mute_drop",
        name = "Damping",
        type = "number",
        min = 0,
        max = 40,
        step = 1,
        default = 20,
        unit = "dB",
        digits = 0,
        help = "how far the level must fall for damped strings to end every note; 0 leaves it to the tracker",
      },
      {
        key = "sus_off",
        name = "Ringing",
        type = "number",
        min = 0.05,
        max = 0.9,
        step = 0.05,
        default = 0.35,
        help = "how sure the tracker must stay that a note still rings: lower holds notes longer",
      },
    },
  },
  {
    key = "notes",
    title = "Notes",
    settings = {
      {
        key = "attack_velocity",
        name = "Velocity",
        type = "switch",
        default = false,
        format = function(on) return on and "follows the picking" or "always 100" end,
        help = "how hard notes are: as hard as the string was picked, or all the same",
      },
      {
        key = "channel",
        name = "Channel",
        type = "number",
        min = 1,
        max = 16,
        step = 1,
        default = 1,
        whole = true,
        help = "the MIDI channel the notes are sent on",
      },
      {
        key = "split",
        name = "Split",
        type = "text",
        default = "",
        empty = "none",
        check = function(text) return K.splits(text) ~= nil, select(2, K.splits(text)) end,
        help = "notes from a pitch upward on another channel: `E3:2`, or several, `E3:2, E4:3`",
      },
    },
  },
  { key = "port", title = "MIDI port", settings = {} },
}

function K.defaults()
  local input = {}
  for _, stage in ipairs(K.stages) do
    for _, setting in ipairs(stage.settings) do
      input[setting.key] = setting.default
    end
  end
  return input
end

local exists = paw.api.fs_exists

--- The gdi2m program: `paw.opt.vinput_gdi2m`, `$GDI2M`, `gdi2m` on the
--- PATH, or a guitar_tracker built in the home directory. Nil when none.
function K.program()
  local set = paw.opt.vinput_gdi2m
  if set and set ~= "" then return exists(set) and set or nil end
  local env = os.getenv("GDI2M")
  if env and env ~= "" and exists(env) then return env end
  for dir in (os.getenv("PATH") or ""):gmatch("[^:]+") do
    if exists(dir .. "/gdi2m") then return dir .. "/gdi2m" end
  end
  local home = os.getenv("HOME")
  local built = home and home .. "/guitar_tracker/result/bin/gdi2m"
  return built and exists(built) and built or nil
end

K.missing = "gdi2m was not found: put it on the PATH, or set `paw.opt.vinput_gdi2m` or $GDI2M to it"

--- Why the input cannot run yet, or nil.
function K.blocked(input)
  if input.source == "" then return "choose the guitar's input" end
  if not K.program() then return K.missing end
end

--- The command that runs an input.
function K.argv(input)
  local argv = {
    K.program(),
    "live",
    "--device",
    input.source,
    -- As PipeWire shows this program's port to gdi2m.
    "--port",
    "paw:" .. input.name .. " (playback)",
    "--gain",
    string.format("%g", input.gain),
    "--threshold",
    string.format("%g", input.threshold),
    "--mute-drop-db",
    string.format("%g", input.mute_drop),
    "--sus-off",
    string.format("%g", input.sus_off),
    "--channel",
    tostring(input.channel),
  }
  if input.attack_velocity then argv[#argv + 1] = "--attack-velocity" end
  local splits = K.splits(input.split)
  if splits and splits ~= "" then
    argv[#argv + 1] = "--split"
    argv[#argv + 1] = splits
  end
  return argv
end

--- The command that lists what can be a source.
function K.list_argv()
  local program = K.program()
  return program and { program, "live", "--list" }
end

--- The capture ports in what `gdi2m live --list` prints.
function K.parse_list(text)
  local out, inside = {}, false
  for line in text:gmatch("[^\n]+") do
    if line:match("^capture devices:") then
      inside = true
    elseif line:match("^%S") then
      inside = false
    elseif inside then
      local index, name = line:match("^%s*%[(%d+)%]%s+(.-)%s*$")
      if index and tonumber(index) > 0 then out[#out + 1] = (name:gsub("%s+%(default%)$", "")) end
    end
  end
  return out
end

--- What gdi2m has written so far, read for what it is doing: the line it
--- prints every second while it runs (`level` is what the tracker hears
--- after the gain, `peak` what arrives from the port), the wire to the
--- MIDI port, what it says of the level when it ends, and why it stopped
--- if it failed.
function K.parse_log(text)
  local out = {}
  for line in text:gmatch("[^\n]+") do
    -- `  2.0s  in -47.0 pk / -48.4 rms dBFS  [ch0 -47.0]  act -52.2 dBFS  q 0  notes 0 (0.0/s)  inf 3.39 mean / 4.97 max ms`
    local seconds, level, queue, notes, load =
      line:match("^%s*([%d%.]+)s%s.-act%s+(%-?[%d%.]+) dBFS%s+q (%d+)%s+notes (%d+).-inf ([%d%.]+) mean")
    if seconds then
      out.seconds, out.level, out.queue, out.notes, out.load =
        tonumber(seconds), tonumber(level), tonumber(queue), tonumber(notes), tonumber(load)
      out.peak = tonumber(line:match("in (%-?[%d%.]+) pk"))
    elseif line:match("^midi%s+%[%d+%]") then
      out.wired = true
    elseif line:match("^%s*%-> ") then
      local db, way, gain = line:match("%-> ([%d%.]+) dB (%u+)%. Use %-%-gain ([%d%.]+)")
      -- Only when it heard playing: after silence it asks for the moon.
      if db and tonumber(gain) >= 0.1 and tonumber(gain) <= 8 then
        out.advice = { db = tonumber(db), way = way:lower(), gain = tonumber(gain) }
      end
    elseif line:match("dropped %d+") then
      out.dropped = tonumber(line:match("dropped (%d+)"))
    elseif line:match("^%s*[%d%.]+ s wall") then
      out.notes = tonumber(line:match("(%d+) notes")) or out.notes
    elseif
      line:lower():match("^error")
      or line:match("could not")
      or line:match("no MIDI port matches")
      or line:match("no capture")
      or line:match("more than one")
      or line:match("cannot")
      or line:match("load failed")
    then
      out.error = line:gsub("^%s+", "")
    end
  end
  return out
end

vinput.kinds.gdi2m = K
return K
