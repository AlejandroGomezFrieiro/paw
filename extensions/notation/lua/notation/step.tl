-- Step input in notation: the notes of a MIDI controller enter at the
-- caret in every insert mode (`i` `a` `I` `R`), at the pitch played and
-- spelled by the key of the music. The core keeps the keys held and the
-- controls (paw/step.tl); this file only says what each of them does here.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.

local type StepNote = paw.contracts.StepNote
local type StepAction = paw.contracts.StepAction

--- The part of the notation view that step input calls.
local record View
  value: number
  dot: boolean
  triplets: boolean
  tuplet: {integer}
  grace: string
  repitch: boolean
  quiet: boolean
  clip: function(self: View): paw.Clip
  editable: function(self: View): paw.Clip
  choose: function(self: View, beats: number)
  enter_pitch: function(self: View, pitch: integer, advance: boolean)
  enter_rest: function(self: View)
  tie_last: function(self: View)
  backspace: function(self: View)
  step_on: function(self: View, n: integer)
  octave_last: function(self: View, dir: integer)
  repeat_chord: function(self: View)
  repitch_pitch: function(self: View, pitch: integer, add: boolean)
  grace_pitch: function(self: View, pitch: integer)
end
local view = package.loaded["notation"] as View

-- The undo state when this insert began: what the controller enters joins
-- the step that the first note made, as the computer keys do.
local began: integer
-- The last key entered a note that the release steps past.
local stepping = false
-- The pedal tied the chord: the release does not step on again.
local tied = false

local function listening(): boolean
  return paw.keymap.mode == "i" and (paw.ui as {string: string}).focused == "notation" and view:editable() ~= nil
end

local function track(): integer
  return listening() and view:clip():track().id or nil
end

-- One undo step for the whole insert.
local function join()
  local now = paw.api.undo_current()
  if began and now ~= began then
    paw.api.undo_join(now)
  end
end

-- Run `fn` with no sound of the view: the controller plays its own.
local function quietly(fn: function())
  view.quiet = true
  local ok, err = pcall(fn) as (boolean, string)
  view.quiet = false
  if not ok then
    error(err, 0)
  end
end

local function note(e: StepNote)
  join()
  tied = false
  stepping = false
  quietly(
    function()
      if view.grace then
        view:grace_pitch(e.pitch)
      elseif view.repitch then
        view:repitch_pitch(e.pitch, e.chord)
      else
        -- The caret stays for a chord: the release of the last key steps on.
        view:enter_pitch(e.pitch, false)
        stepping = true
      end
    end
  )
end

local function release()
  join()
  if stepping and not tied then
    view:step_on(1)
  end
  stepping = false
end

local function times(fn: function()): StepAction
  return function(count: integer)
    join()
    for _ = 1, math.max(1, count or 1) do
      fn()
    end
  end
end

local actions: {string: StepAction} = {
  rest = times(function() view:enter_rest() end),
  tie = function(count: integer)
    join()
    for _ = 1, math.max(1, count or 1) do
      view:tie_last()
    end
    -- With keys held, the release does not step on after the tie.
    tied = #paw.step.held() > 0
  end,
  back = times(function() view:backspace() end),
  again = times(function() view:repeat_chord() end),
  dot = function() view.dot = not view.dot; paw.api.ui_redraw() end,
  triplet = function()
    view.triplets, view.tuplet = not (view.triplets or view.tuplet ~= nil), nil
    paw.api.ui_redraw()
  end,
  ["octave.up"] = times(function() quietly(function() view:octave_last(1) end) end),
  ["octave.down"] = times(function() quietly(function() view:octave_last(-1) end) end),
  finish = function() paw.keymap.set_mode("n") end,
}
for _, whole in ipairs({1, 2, 4, 8, 16, 32}) do
  actions["dur." .. whole] = function() view:choose(4 / whole) end
end

paw.step.target(
  "notation",
  {
    active = listening,
    track = track,
    note = note,
    release = release,
    status = function(): string return listening() and "STEP" or nil end,
    actions = actions,
  }
)

-- The insert modes start and stop listening: its track plays the controller.
paw.on(
  paw.keymap.mode_changed,
  function(e: paw.keymap.ModeChanged)
    if e.mode == "i" and e.old ~= "i" then
      began = paw.api.undo_current()
    end
    paw.step.refresh()
  end
)
