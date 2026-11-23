-- The piano roll over several tracks, as REAPER's editable and visible
-- tracks: the other tracks' notes behind in their colours, `]t` `[t` and
-- `Tab` making another shown track the one edited, a click on a note
-- behind doing the same, and edits going to the active track's clip.
-- Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local keymap = paw.keymap

local keys = T.keys

local function three()
  fresh()
  local clips = {}
  for i, name in ipairs({ "Violin", "Viola", "Cello" }) do
    local t = paw.add_track({ name = name })
    clips[i] = t:add_clip({
      start = 0,
      length = 8,
      name = name,
      notes = { { pitch = 76 - 7 * i, start = 0, length = 1, velocity = 90 } },
    })
  end
  paw.flush()
  api.undo_checkpoint()
  keymap.set_mode("n")
  paw.ui.views:get("pianoroll"):edit(clips[2])
  paw.ui.focus("pianoroll")
  return paw.ui.views:get("pianoroll"), clips
end

local function track_of(roll) return api.track_get(roll:clip():get().track).name end

test("the piano roll: ]t [t and Tab make the next shown track the one edited, its notes then edited", function()
  local roll, clips = three()
  eq(track_of(roll), "Viola", "the clip opened is edited")
  eq(#paw.roll_clips.context(), 2, "the other two tracks' notes behind")
  keys("]t")
  eq(track_of(roll), "Cello", "]t: the next track")
  eq(#paw.roll_clips.context(), 2, "the viola's notes behind now")
  keys("2[t")
  eq(track_of(roll), "Violin", "2[t: two before")
  keys("<Tab>")
  eq(track_of(roll), "Viola", "Tab: the next")
  keys("<Tab><Tab>")
  eq(track_of(roll), "Violin", "and round")
  -- An edit goes to the active track's clip alone.
  roll:set(62, 2)
  keys("<CR>")
  eq(
    #clips[1]:notes() .. " " .. #clips[2]:notes() .. " " .. #clips[3]:notes(),
    "2 1 1",
    "a note entered into the violin's clip"
  )
  -- A click on a note behind makes its clip the one edited.
  paw.frontend.act.add_note(clips[1].id, 55, 0)
  eq(track_of(roll), "Cello", "a click on the cello's note behind")
  -- With nothing shown behind, Tab is the next view as everywhere.
  paw.opt.roll_context = "none"
  keys("<Tab>")
  eq(paw.ui.focused ~= "pianoroll", true, "Tab goes to the next view")
  paw.opt.roll_context = "all"
end)

test(":roll.tracks: Enter on a track or a clip shows its new state on its line", function()
  three()
  keys(":roll.tracks<CR>")
  local function line(n) return paw.pick.state().matches[n] end
  eq(line(3), "[x] Violin", "the violin's notes show behind")
  eq(line(4), "      [    ] Violin", "the violin's clip is not edited")
  keys("<Down><Down><CR>")
  eq(line(3), "[ ] Violin", "Enter hides the violin's notes, and its line says so")
  eq(paw.pick.state().selected, 3, "the selection stays on the line")
  keys("<Down><CR>")
  eq(line(4), "      [edit] Violin", "Enter edits the violin's clip, and its line says so")
  keys("<Up><CR>")
  eq(line(3), "[x] Violin", "a second Enter shows the notes again")
  keys("<Esc>")
end)
