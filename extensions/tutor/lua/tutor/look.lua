-- What lessons look at to see whether a step is done, and build their
-- practice projects with. Plain readings of the public `paw` module.
local api = paw.api
local M = {}

--- A part by name, or nil.
function M.part(name) return paw.part(name) end

--- A part's clips in time order.
function M.clips(part)
  if type(part) == "string" then part = paw.part(part) end
  if not part then return {} end
  local list = part:clips()
  table.sort(list, function(a, b)
    if a.start ~= b.start then return a.start < b.start end
    return a.name < b.name
  end)
  return list
end

--- A part's clip names in time order: "kick snare fill".
function M.names(part)
  local out = {}
  for i, c in ipairs(M.clips(part)) do
    out[i] = c.name
  end
  return table.concat(out, " ")
end

--- Where a part's clips are: "a@0+4 b@4+4", with `m` for a muted one.
function M.layout(part)
  local out = {}
  for i, c in ipairs(M.clips(part)) do
    out[i] = string.format("%s@%g+%g%s", c.name, c.start, c.length, c.muted and "m" or "")
  end
  return table.concat(out, " ")
end

--- A clip's notes in time order (lower pitches first): "60@0+1 62@1+1".
function M.melody(clip)
  if not clip then return "" end
  local notes = clip:notes()
  table.sort(notes, function(a, b)
    if a.start ~= b.start then return a.start < b.start end
    return a.pitch < b.pitch
  end)
  for i, n in ipairs(notes) do
    notes[i] = string.format("%d@%g+%g", n.pitch, n.start, n.length)
  end
  return table.concat(notes, " ")
end

--- The clip on a part whose name is `name` (the first in time).
function M.clip(part, name)
  for _, c in ipairs(M.clips(part)) do
    if not name or c.name == name then return c end
  end
end

--- The name of the part the cursor is on.
function M.cursor_part()
  local t = paw.cursor.part()
  return t and t.name
end

--- The piano roll's view, its clip and cursor.
function M.roll()
  local roll = paw.ui.views:get("pianoroll")
  return roll, roll:clip()
end

function M.focused() return paw.ui.focused end
function M.mode() return paw.keymap.mode end
function M.float() return paw.ui.float and paw.ui.float.name end
function M.float_title() return paw.ui.float and paw.ui.float.title end

--- Whether a view is on screen.
function M.visible(name) return paw.ui.visible(name) end

--- The first device of a kind on a part, or nil.
function M.device(part, kind)
  if type(part) == "string" then part = paw.part(part) end
  if not part then return end
  for _, d in ipairs(part:devices()) do
    if d.kind == kind then return d end
  end
end

-- Steps record what happened since they began: commands run, events seen,
-- messages shown. `ctx` is the step's own table.

--- Whether a command ran since the step began, how many times.
function M.ran(ctx, name) return (ctx.commands[name] or 0) > 0, ctx.commands[name] or 0 end

--- Whether an event was seen since the step began.
function M.saw(ctx, name) return (ctx.events[name] or 0) > 0 end

--- Whether a message containing `text` was shown since the step began.
function M.said(ctx, text)
  -- From the newest back to the last one there was when the step began.
  for i = #paw.ui.messages, 1, -1 do
    local message = paw.ui.messages[i]
    if message == ctx.messages then return false end
    if message.text:find(text, 1, true) then return true end
  end
  return false
end

--- `now`, once it has been false at some time since the step began: for a
--- step whose end state may already hold before it is done.
function M.became(ctx, name, now)
  if not now then ctx["not_" .. name] = true end
  return now and ctx["not_" .. name] == true
end

--- Whether the transport played and then stopped since the step began.
function M.played(ctx) return M.saw(ctx, "transport.play") and not paw.transport.playing end

--- A list of notes from text: "C4:0:1 D4:1:1" is pitch, start, length (and velocity).
function M.notes(text)
  local out = {}
  for item in text:gmatch("%S+") do
    local pitch, start, length, velocity = item:match("^([^:]+):([^:]+):([^:]+):?(%d*)$")
    out[#out + 1] = {
      pitch = tonumber(pitch) or paw.music.pitch(pitch),
      start = tonumber(start),
      length = tonumber(length),
      velocity = tonumber(velocity) or 100,
    }
  end
  return out
end

--- Drum notes from a step pattern, one character per sixteenth: `x` loud,
--- `o` soft, `.` nothing. `rows` maps a General MIDI note to its pattern.
function M.drums(rows, bars)
  local notes = {}
  for pitch, steps in pairs(rows) do
    for bar = 0, (bars or 1) - 1 do
      for i = 1, #steps do
        local ch = steps:sub(i, i)
        if ch ~= "." then
          notes[#notes + 1] =
            { pitch = pitch, start = bar * 4 + (i - 1) * 0.25, length = 0.25, velocity = ch == "x" and 115 or 75 }
        end
      end
    end
  end
  return notes
end

--- A plain rock beat.
M.beat = { [36] = "x.....x.x.......", [38] = "....x.......x...", [42] = "x.o.x.o.x.o.x.o." }

--- Notes repeating a pitch as eighths for `beats`.
function M.pulse(pitch, beats, from)
  local out = {}
  for i = 0, beats * 2 - 1 do
    out[#out + 1] = { pitch = paw.music.pitch(pitch), start = (from or 0) + i * 0.5, length = 0.45, velocity = 100 }
  end
  return out
end

--- A chord held for `beats`.
function M.chord(pitches, beats, from)
  local out = {}
  for _, p in ipairs(pitches) do
    out[#out + 1] = { pitch = paw.music.pitch(p), start = from or 0, length = beats, velocity = 80 }
  end
  return out
end

--- The register's value, or nil.
function M.register(name) return paw.keymap.getreg(name) end

--- The value of a device parameter.
function M.param(device, key) return device and api.device_get(device.id).params[key] end

return M
