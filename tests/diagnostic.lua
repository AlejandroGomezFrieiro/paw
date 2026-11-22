-- Tests of paw.diagnostic, fed by a range lint written in plain Lua: any
-- plugin can say what is wrong with a clip, and it is shown and fixed the
-- same way as a language server's. Loaded by tests/suite.lua with its helpers.
local T = ...
local eq, fresh = T.eq, T.fresh

-- Each test leaves things as the next expects them: no servers, no
-- diagnostics, the piano roll closed, whether it passed or not.
local function test(name, fn)
  T.test(name, function()
    local result = { xpcall(fn, debug.traceback) }
    paw.lsp.stop()
    paw.diagnostic.reset()
    while paw.ui.float do
      paw.ui.close()
    end
    paw.ui.views.pianoroll.clip_id = nil
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
    if not result[1] then error(result[2], 0) end
    return result[2]
  end)
end
local api = paw.api
local diagnostic = paw.diagnostic

local function start()
  fresh()
  diagnostic.reset()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
end

--- A lint of a plugin's own: notes outside `lo`..`hi`, each with a fix
--- that moves it an octave into the range.
local function lint(clip, lo, hi)
  local list = {}
  for place, n in ipairs(clip:notes()) do
    if n.pitch < lo or n.pitch > hi then
      local to = n.pitch < lo and n.pitch + 12 or n.pitch - 12
      list[#list + 1] = {
        notes = { place },
        severity = n.pitch > hi + 12 and "error" or "warning",
        rule = "range",
        message = paw.music.name(n.pitch) .. " is out of range",
        fixes = { { title = "Move to " .. paw.music.name(to), edits = { { note = place, pitch = to } } } },
      }
    end
  end
  diagnostic.set("range", clip, list)
end

local function clip_with(notes)
  local t = paw.add_track({ name = "Oboe" })
  return t:add_clip({ start = 0, length = 4, notes = notes })
end

test("diagnostic: a Lua lint's diagnostics are kept by clip, counted and filtered", function()
  start()
  local clip = clip_with({
    { pitch = 60, start = 0, length = 1 },
    { pitch = 90, start = 1, length = 1 },
    { pitch = 100, start = 2, length = 1 },
  })
  lint(clip, 48, 84)
  local all = diagnostic.get(clip)
  eq(#all, 2, "two notes out of range")
  eq(all[1].at .. "+" .. all[1].length, "1+1", "where the first is, from its note")
  eq(all[1].source, "range", "the namespace is the source")
  local n = diagnostic.count(clip)
  eq(n.error .. " " .. n.warning .. " " .. n.total, "1 1 2", "counted by severity")
  eq(#diagnostic.get(clip, { severity = diagnostic.severity.ERROR }), 1, "filtered by severity")
  eq(#diagnostic.get(clip, { severity = { min = "warning" } }), 2, "or by the least severe")
  eq(#diagnostic.get(clip, { note = 3 }), 1, "or by note")
  eq(#diagnostic.get(clip, { namespace = "other" }), 0, "or by namespace")
  diagnostic.set("other", clip, { { at = 0, length = 4, message = "whole clip", severity = 4 } })
  eq(#diagnostic.get(clip), 3, "namespaces add up")
  eq(table.concat(diagnostic.namespaces(), " "), "other range", "both namespaces")
  diagnostic.reset("other")
  eq(#diagnostic.get(clip), 2, "a namespace is reset alone")
  lint(clip, 0, 127)
  eq(#diagnostic.get(), 0, "an empty list clears the clip")
end)

test("diagnostic: a note keeps its diagnostic when other notes move, and a fix is one undo step", function()
  start()
  local clip = clip_with({ { pitch = 60, start = 1, length = 1 }, { pitch = 96, start = 2, length = 1 } })
  lint(clip, 48, 84)
  api.undo_checkpoint()
  -- A note added before it changes its place.
  clip:add_note({ pitch = 62, start = 0, length = 1 })
  paw.flush()
  api.undo_checkpoint()
  local d = diagnostic.get(clip)[1]
  eq(diagnostic.places(d)[1], 3, "found at its new place")
  eq(#diagnostic.get(clip, { note = 3 }), 1, "and asked about there")
  eq(#diagnostic.actions(clip, 3), 1, "with its fix")
  eq(diagnostic.apply(d), true, "applied")
  paw.flush()
  api.undo_checkpoint()
  eq(clip:notes()[3].pitch, 84, "the fix moved the right note")
  eq(clip:notes()[1].pitch, 62, "and no other")
  paw.undo()
  eq(clip:notes()[3].pitch, 96, "one undo takes the fix back")
  -- A fix whose note has gone is refused.
  clip:remove_note(3)
  paw.flush()
  eq(diagnostic.apply(d), false, "nothing to fix")
end)

test("diagnostic: the piano roll marks them, the status line counts them, the arrange view shows the clip", function()
  start()
  local clip = clip_with({ { pitch = 60, start = 0, length = 1 }, { pitch = 100, start = 1, length = 1 } })
  lint(clip, 48, 84)
  -- The layer paints in the order asked: the note underlined in its colour.
  local painted = {}
  local cells = function(name)
    return {
      width = 80,
      fill = function(_, x, y, w, h, ch, style)
        painted[#painted + 1] = name .. " fill " .. x .. "," .. y .. "," .. w .. " " .. tostring(style)
      end,
      text = function(_, x, y, text, style)
        painted[#painted + 1] = name .. " text " .. x .. "," .. y .. " " .. text .. " " .. tostring(style)
      end,
    }
  end
  diagnostic.paint_roll({
    roll = cells("roll"),
    ruler = cells("ruler"),
    clip = clip,
    x = function(beat) return beat * 4 end,
    row = function(pitch) return 110 - pitch end,
  })
  local text = table.concat(painted, "\n")
  eq(text:find("roll fill 4,10,4 DiagnosticUnderlineError", 1, true) ~= nil, true, "the note underlined\n" .. text)
  eq(
    text:find("ruler text 4,0 " .. paw.draw.g.mark .. " DiagnosticError", 1, true) ~= nil,
    true,
    "a mark on the ruler\n" .. text
  )
  eq(
    text:find("roll text 9,10 E7 is out of range DiagnosticVirtualTextError", 1, true) ~= nil,
    true,
    "the message after it\n" .. text
  )

  paw.ui.views.pianoroll:edit(clip)
  paw.ui.views.pianoroll:set(100, 0)
  local screen = table.concat(api.ui_snapshot(120, 40), "\n")
  eq(screen:find("E7 is out of range", 1, true) ~= nil, true, "the terminal's piano roll shows the message")
  eq(screen:find("E1", 1, true) ~= nil, true, "the status line counts it")
  local marks = diagnostic.roll_marks(clip.id)
  eq(#marks, 1, "the window is told of one note")
  eq(
    string.format(
      "%d %d %g %d %s",
      marks[1].index,
      marks[1].pitch,
      marks[1].start,
      marks[1].severity,
      marks[1].actions[1]
    ),
    "1 100 1 1 Move to E6",
    "by its place from 0, with its fix"
  )
  paw.frontend.act.note_action(clip.id, 2, 1)
  paw.flush()
  eq(clip:notes()[2].pitch, 88, "the window's menu entry applies the fix")
  lint(clip, 48, 84)
  paw.ui.focus("arrange")
  screen = table.concat(api.ui_snapshot(120, 40), "\n")
  eq(screen:find(paw.draw.g.warn, 1, true) ~= nil, true, "the clip is marked in the arrange view")
end)

test("diagnostic: ]d and [d go from one to the next, in the piano roll and between clips", function()
  start()
  local a = clip_with({
    { pitch = 100, start = 0, length = 1 },
    { pitch = 60, start = 1, length = 1 },
    { pitch = 20, start = 3, length = 1 },
  })
  local t2 = paw.add_track({ name = "Horn" })
  local b = t2:add_clip({ start = 8, length = 4, notes = { { pitch = 110, start = 0, length = 1 } } })
  lint(a, 48, 84)
  lint(b, 48, 84)
  local roll = paw.ui.views.pianoroll
  roll:edit(a)
  paw.keymap.feed("]d")
  eq(roll.beat .. " " .. roll.pitch, "3 20", "the next diagnostic's note")
  paw.keymap.feed("]d")
  eq(roll.beat .. " " .. roll.pitch, "0 100", "round to the first")
  paw.keymap.feed("[d")
  eq(roll.beat .. " " .. roll.pitch, "3 20", "and back")
  paw.ui.focus("arrange")
  paw.cursor.set_beat(1)
  paw.keymap.feed("]d")
  eq(
    paw.cursor.beat .. " " .. paw.cursor.track_id(),
    "3 " .. a:get().track,
    "in the arrange view, where the next one is"
  )
  paw.keymap.feed("]d")
  eq(paw.cursor.beat .. " " .. paw.cursor.track_id(), "8 " .. t2.id, "on another track")
  paw.keymap.feed("]d")
  eq(paw.cursor.beat, 0, "round to the first")
  paw.cmd("diagnostics")
  local matches = paw.pick.state().matches
  eq(#matches, 4, ":diagnostics lists them all, under what they are about")
  eq(matches[1], "── Notes", "the heading")
  paw.keymap.feed("<C-n><CR>")
  eq(paw.ui.focused, "pianoroll", "Enter goes to one")
end)

test("diagnostic: a clip that goes takes its diagnostics along", function()
  start()
  local clip = clip_with({ { pitch = 100, start = 0, length = 1 } })
  lint(clip, 48, 84)
  eq(diagnostic.count().total, 1, "one")
  clip:remove()
  paw.flush()
  eq(diagnostic.count().total, 0, "gone with the clip")
end)
