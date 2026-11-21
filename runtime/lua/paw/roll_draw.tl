-- `paw.roll_draw`: the piano roll's insert mode, drawing notes with the
-- cursor. `i` starts a note at the cursor, nothing long yet; `l` and `h`
-- make it a grid step longer and shorter, `j` and `k` move its pitch, and
-- the cursor stays at its end, so what shows is what will be written.
-- `<CR>` keeps it and starts the next where it ends, `<Space>` after a
-- step's rest, `o` at the same place and as long, for a chord. `<Esc>`
-- writes them all and leaves.
--
-- Nothing reaches the project until insert mode ends: then every note drawn
-- is written at once, which makes the whole of it one undo step and lets
-- `.` draw the same shape again at the cursor, as Vim repeats an insert.
--
-- The other way in, `paw.opt.roll_insert = "keys"` or `I`, turns the
-- keyboard into a piano instead (`view:enter`); this module then stays out
-- of the way.
local api = paw.api
local util = paw.util
local music = paw.music
local clips = paw.roll_clips
local M = {}

-- How insert mode in the piano roll enters notes: "draw" with the cursor,
-- or "keys", the keyboard as a piano.
paw.option.define("roll_insert", "draw")

-- Beats here are the project's, so that what is drawn stays put when the
-- active clip changes: `notes` kept so far, as `{ pitch, start, length,
-- velocity }`; the note being drawn, from `start` at `pitch`, `length` long;
-- `count`, digits typed for the next key.
local session
local keys_once   -- `I` asked for the piano keys this time
paw.seats.keep("roll_draw", function() return session, keys_once end,
  function(s, k) session, keys_once = s, k end,
  function() return nil, nil end)

local function roll() return paw.ui.views.pianoroll end

local function changed()
  if paw.frontend then paw.frontend.refresh() else api.ui_redraw() end
end

--- Where the active clip starts in the project, or nil with none open.
local function origin()
  local clip = roll():clip()
  return clip and clip.start
end

--- True if you draw a note now: insert mode in the piano roll, the kind that draws.
function M.active()
  return session ~= nil and paw.keymap.mode == "i"
end

--- Bring the note being drawn to the cursor, if something else moved it
--- (a click, a suggestion accepted): it starts afresh there.
local function sync()
  local at = origin()
  if not session or not at then return end
  local r = roll()
  local beat = r.beat + at
  if r.pitch ~= session.pitch or math.abs(beat - (session.start + session.length)) > 1e-9 then
    session.pitch, session.start, session.length = r.pitch, beat, 0
  end
end

--- The cursor goes to the end of the note being drawn. It may go past the
--- end of the clip, which grows when the note is written.
local function place()
  local r, at = roll(), origin()
  if not at then return end
  r.pitch = session.pitch
  r.beat = session.start + session.length - at
  changed()
end

--- Start drawing at the cursor, `after` steps on.
function M.start(after)
  local at = origin()
  if not at then return end
  local r = roll()
  session = { notes = {}, pitch = r.pitch, start = r.beat + at + (after or 0) * paw.opt.note_grid, length = 0 }
  place()
end

--- The count typed so far, taken: 1 when there is none.
local function take_count()
  local n = session.count or 1
  session.count = nil
  return n
end

--- A digit of the count for the next key.
function M.digit(d)
  if not session then return end
  sync()
  if d == 0 and not session.count then return end
  session.count = (session.count or 0) * 10 + d
  api.ui_redraw()
end

--- Make the note `steps` grid steps longer, or shorter with a negative count.
function M.grow(steps)
  if not session then return end
  sync()
  local n = take_count()
  session.length = math.max(0, session.length + steps * n * paw.opt.note_grid)
  place()
end

--- Move the note by `semitones` (times the count), and hear its new pitch.
--- `step(pitch, n)`, if given, says where `n` such moves go instead: by
--- steps of a scale, say.
function M.pitch(semitones, step)
  if not session then return end
  sync()
  local n = take_count()
  local to = step and step(session.pitch, n) or session.pitch + semitones * n
  session.pitch = util.clamp(to, 0, 127)
  place()
  local at = origin()
  local part = at and clips.target(session.start - at)
  if part then part.clip:track():play_note(session.pitch, paw.opt.velocity, 180) end
end

--- Keep the note being drawn among those to write, replacing one drawn
--- before at the same pitch and start. One of no length is not kept.
local function put()
  if session.length <= 1e-9 then return end
  for i = #session.notes, 1, -1 do
    local n = session.notes[i]
    if n.pitch == session.pitch and math.abs(n.start - session.start) < 1e-9 then table.remove(session.notes, i) end
  end
  session.notes[#session.notes + 1] = {
    pitch = session.pitch, start = session.start, length = session.length, velocity = paw.opt.velocity,
  }
end

--- Keep the note and go to the next note. "legato" starts it at the end,
--- "rest" one step (or count steps) after the end, and "chord" at the same
--- start and with the same length.
function M.next(how)
  if not session then return end
  sync()
  local n = take_count()
  put()
  if how == "chord" then return place() end
  session.start = session.start + session.length + (how == "rest" and n * paw.opt.note_grid or 0)
  session.length = 0
  place()
end

--- Take back the last note kept: it is the one being drawn again.
function M.back()
  if not session then return end
  sync()
  session.count = nil
  local last = table.remove(session.notes)
  if not last then return end
  session.pitch, session.start, session.length = last.pitch, last.start, last.length
  place()
end

--- The notes to write in the clips they go into: `{ part, notes }` in the
--- part's own beats, by clip id. The note being drawn is among them.
local function by_clip(list)
  local at = origin()
  local parts = clips.parts()
  local out = {}
  for _, n in ipairs(list) do
    local part = clips.target(n.start - at, parts)
    local start = n.start - at - part.offset
    if part and start > -1e-9 then
      local entry = out[part.id] or { part = part, notes = {} }
      out[part.id] = entry
      entry.notes[#entry.notes + 1] = {
        pitch = n.pitch, start = math.max(0, start), length = n.length, velocity = n.velocity, pending = n.pending,
      }
    end
  end
  return out
end

--- Every note drawn, the one being drawn last, if it has a length.
local function drawn()
  local list = {}
  local drawing = session.length > 1e-9
  for _, n in ipairs(session.notes) do
    -- The one being drawn takes the place of one kept at its pitch and start.
    if not (drawing and n.pitch == session.pitch and math.abs(n.start - session.start) < 1e-9) then list[#list + 1] = n end
  end
  if drawing then
    list[#list + 1] = { pitch = session.pitch, start = session.start, length = session.length, velocity = paw.opt.velocity, pending = true }
  end
  return list
end

--- Write what was drawn into the clips, all at once: one undo step. A note
--- of the same pitch that starts where one is drawn is replaced, and a clip
--- grows by whole bars to hold what runs past its end.
local function write()
  if not origin() then return end
  local list = drawn()
  if #list == 0 then return end
  api.undo_label("Draw notes")
  for _, entry in pairs(by_clip(list)) do
    local part, clip = entry.part, entry.part.clip
    local finish, add, remove, seen = 0, {}, {}, {}
    for _, n in ipairs(entry.notes) do
      add[#add + 1] = paw.ui.views.pianoroll.new_note(clip, { pitch = n.pitch, start = n.start, length = n.length, velocity = n.velocity })
      finish = math.max(finish, n.start + n.length)
      local found, places = clip:notes({ from = n.start - 1e-9, to = n.start + 2e-9, low = n.pitch, high = n.pitch })
      for i, old in ipairs(found) do
        if math.abs(old.start - n.start) < 1e-9 and not seen[places[i]] then
          seen[places[i]] = true
          remove[#remove + 1] = places[i]
        end
      end
    end
    if finish > part.length + 1e-9 then
      clip.length = paw.time.bar_ceil(part.start + finish - 1e-9) - part.start
    end
    clip:edit_notes({ remove = remove, add = add })
  end
  paw.ui.poke()
end

--- End the drawing: write it, and forget it.
function M.finish()
  if not session then return end
  sync()
  write()
  session = nil
  changed()
end

--- Insert mode the piano keys way this once, whatever `roll_insert` says.
function M.keys_once()
  keys_once = true
end

--- Change from drawing to the piano keys and stay in insert mode. paw
--- writes the drawn notes, and the letters are notes from now on.
function M.to_keys()
  if not session then return end
  M.finish()
  keys_once = true
  paw.notify("typing notes as a piano: a s d f g h j k are a scale, Esc stops")
end

-- Entering insert mode in the piano roll starts a note at the cursor, unless
-- the keys are a piano this time; leaving it writes what was drawn.
local entered   -- { clip, notes it held } when insert mode began
paw.on("mode.changed", function(e)
  if e.old == "i" then
    keys_once = nil
    M.finish()
    -- Whatever was entered, drawn or typed, is said once it is in.
    local from = entered
    entered = nil
    if from then
      local ok, notes = pcall(function() return #from.clip:notes() end)
      local added = ok and notes - from.notes or 0
      if added > 0 then paw.notify(string.format("wrote %d note%s", added, added == 1 and "" or "s")) end
    end
    return
  end
  if e.mode == "i" and paw.ui.focused == "pianoroll" and roll():clip() then
    local clip = roll():clip()
    entered = { clip = clip, notes = #clip:notes() }
    if keys_once or paw.opt.roll_insert == "keys" then return end
    M.start()
  end
end)

-- What shows ------------------------------------------------------------------

--- A length in grid steps and in beats: "2 steps · 0.5 beats".
local function length_text(length)
  local steps = length / paw.opt.note_grid
  return string.format("%g step%s · %g beat%s", steps, steps == 1 and "" or "s", length, length == 1 and "" or "s")
end

--- The note being drawn, in words: "C4 · 2 steps · 0.5 beats", or nil.
function M.describe()
  if not M.active() then return nil end
  sync()
  return music.name(session.pitch) .. " · " .. length_text(session.length)
end

--- What the piano roll's title says in insert mode.
function M.label()
  if not M.active() then
    local r = roll()
    return string.format("INS C%d  step %g  vel %d", paw.opt.octave, r:step_length(), paw.opt.velocity)
  end
  sync()
  return string.format("DRAW %s%s  %s  vel %d", session.count and session.count .. " " or "", music.name(session.pitch),
    length_text(session.length), paw.opt.velocity)
end

--- What the window says while in insert mode.
function M.status()
  if not M.active() then
    return string.format("entering notes · a is C%d · step %g · Esc to stop", paw.opt.octave, roll():step_length())
  end
  return "drawing " .. M.describe() .. " · l h longer, shorter · Enter next · Esc writes"
end

--- The notes that you drew and kept, as "60@1+0.5 64@1+0.5" in the beats of
--- the roll. The second value is the note that you draw now, "67@1.5+0".
function M.text()
  if not session then return "", nil end
  sync()
  local at = origin() or 0
  local out = {}
  for _, n in ipairs(session.notes) do out[#out + 1] = string.format("%d@%g+%g", n.pitch, n.start - at, n.length) end
  return table.concat(out, " "), string.format("%d@%g+%g", session.pitch, session.start - at, session.length)
end

local styles = {}

--- The terminal's look for the note being drawn: the insert mode's colour,
--- faint behind and bright in front, unlike any clip's notes.
local function pending_style()
  local palette = require("paw.theme").palette
  local key = palette.bg .. palette.insert
  if not styles[key] then
    paw.ui.hl("NoteDrawing", { fg = palette.insert, bg = paw.draw.mix(palette.bg, palette.insert, 0.3), bold = true })
    styles[key] = "NoteDrawing"
  end
  return styles[key]
end

-- Above the clips' notes and below a snippet's marks and suggestions: the notes kept, as they
-- will look once written, and the one being drawn in the insert colour.
roll().layer("draw", 35, function(L)
  if not M.active() then return end
  sync()
  local at = L.data.start
  local insert = require("paw.theme").palette.insert
  local colour = paw.draw.track_colour(api.track_get(L.data.track))
  for i, n in ipairs(drawn()) do
    local row = L.row(n.pitch)
    local x0, x1 = L.x(n.start - at), L.x(n.start + n.length - at)
    if row and x1 > 0 and x0 < L.width then
      L.plane:mark("note", n.start - at, n.pitch, n.length, 1, {
        label = music.name(n.pitch), style = n.pending and pending_style() or paw.draw.note_style(L.hue, n.velocity),
        color = n.pending and insert or colour, velocity = n.velocity, pending = n.pending, key = "drawn:" .. i,
      })
    end
  end
end)

return M
