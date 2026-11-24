-- Step input in the vocal editor: `I` starts it, and each key of a MIDI
-- controller adds one note at the cursor, a step long, with the default
-- lyric. The cursor goes to the end of the note when the key is released.
-- A voice sings one note at a time: a chord enters its highest note.
-- The core knows nothing of this (paw/step.tl): this file only says what
-- the keys and the controls do in the vocal editor.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local type types = require("paw.types")

local type StepNote = paw.contracts.StepNote
local type StepAction = paw.contracts.StepAction

local record Clip
  id: integer
  part: integer
  length: number
end

--- The part of the vocal editor that step input calls.
local record Editor
  clip_id: integer
  pitch: integer
  beat: number
  clip: function(self: Editor): Clip
end

local record Notes
  list: function(clip_id: integer): {types.Note}
  at: function(clip_id: integer, pitch: integer, beat: number): types.Note, integer
end

local record Audition
  note: function(clip_id: integer, index: integer): string
end

local editor = (package.loaded["utau.editor"] as {string: Editor})["editor"]
local notes = package.loaded["utau.notes"] as Notes
local audition = package.loaded["utau.audition"] as Audition
local api = paw.api

local M = {}

-- Whether step input is on, and the state when this insert began: what the
-- controller enters joins the step that the first note made.
local on = false
local began: integer
-- The step in beats: nil is two steps of the grid, as `i` gives. `dur.N` sets it.
local length: number
-- The note that the keys held now entered: its pitch and start.
local pending: {number}
-- A chord was heard in this session, and paw said so.
local told = false

local function step(): number
  return length or paw.timegrid.step("note") * 2
end

local function listening(): boolean
  return on and paw.keymap.mode == "i" and (paw.ui as {string: string}).focused == "utau" and editor:clip() ~= nil
end

local function part(): integer
  return listening() and editor:clip().part or nil
end

local function join()
  local now = api.undo_current()
  if began and now ~= began then
    api.undo_join(now)
  end
end

local function advance(by: number)
  local clip = editor:clip()
  if not clip then
    return
  end
  editor.beat = math.max(0, math.min(clip.length, editor.beat + by))
  api.ui_redraw()
end

local function note(e: StepNote)
  join()
  local clip = editor:clip()
  if not clip then
    return
  end
  if pending and e.chord then
    -- One voice: the highest note of the chord stays.
    if not told then
      told = true
      paw.notify("a vocal part sings one note at a time: a chord enters its highest note")
    end
    if e.pitch <= pending[1] then
      return
    end
    local list = notes.list(clip.id)
    for _, n in ipairs(list) do
      if n.pitch == pending[1] and math.abs(n.start - pending[2]) < 1e-9 then
        n.pitch = e.pitch
      end
    end
    api.clip_set_notes(clip.id, list)
    pending[1] = e.pitch
  else
    api.clip_add_notes(clip.id, {{pitch = e.pitch, start = editor.beat, length = step(), velocity = e.velocity}})
    pending = {e.pitch, editor.beat}
  end
  editor.pitch = e.pitch
  local _, index = notes.at(clip.id, e.pitch, pending[2])
  if index then
    audition.note(clip.id, index)
  end
end

local function release()
  join()
  if pending then
    pending = nil
    advance(step())
  end
end

local function times(fn: function()): StepAction
  return function(count: integer)
    join()
    for _ = 1, math.max(1, count or 1) do
      fn()
    end
  end
end

-- Take back the note that starts a step before the cursor, and the cursor with it.
local function back()
  local clip = editor:clip()
  if not clip or editor.beat <= 0 then
    return
  end
  advance(-step())
  local list = notes.list(clip.id)
  for i = #list, 1, -1 do
    if math.abs(list[i].start - editor.beat) < 1e-6 then
      table.remove(list, i)
    end
  end
  api.clip_set_notes(clip.id, list)
end

local actions: {string: StepAction} = {
  rest = times(function() advance(step()) end),
  back = times(back),
  finish = function() paw.keymap.set_mode("n") end,
}
for _, whole in ipairs({1, 2, 4, 8, 16, 32}) do
  actions["dur." .. whole] = function() length = 4 / whole end
end

--- Start step input at the cursor of the vocal editor (`I`).
function M.start()
  if not editor:clip() then
    return
  end
  on, pending = true, nil
  paw.keymap.set_mode("i")
  paw.step.refresh()
end

--- Move on by one step, leaving what is there (`<Space>` in step input).
function M.rest()
  actions["rest"](1)
end

--- Take back the last note (`<BS>` in step input).
function M.back()
  actions["back"](1)
end

paw.step.target(
  "utau",
  {
    active = listening,
    part = part,
    note = note,
    release = release,
    status = function(): string return listening() and "STEP" or nil end,
    actions = actions,
  }
)

paw.on(
  paw.keymap.mode_changed,
  function(e: paw.keymap.ModeChanged)
    if e.mode == "i" and e.old ~= "i" then
      began = api.undo_current()
    elseif e.old == "i" and e.mode ~= "i" then
      on, pending = false, nil
    end
    paw.step.refresh()
  end
)

return M
