-- The tutor: lessons that open a practice project, say what to do next,
-- notice when it is done, and keep the learner's place between sessions.
--
-- A lesson is a table (see README.md beside the extension):
--
--   { id, title, intro, idea, vim, setup = function(look) end, at = function(look) end,
--     steps = { { say, keys, check = function(ctx, look) end, done, hint, unchecked, sim } },
--     outro }
--
-- Lessons are registered in order with `tutor.register(lesson)`; the built-in
-- ones are in `tutor.lessons.*`.
local api = paw.api
local store = require("tutor.store")
local look = require("tutor.look")

local M = { lessons = {}, by_id = {} }

paw.option.define("tutor_dir", "")   -- where progress and practice projects go; "" for $XDG_STATE_HOME/paw/tutor

-- What the tutor is doing now. Kept in `paw.state` too, so that `:reload`
-- (which runs the extension again) does not lose the learner's place.
local S = paw.state.tutor or { active = false }
local ctx                        -- the current step's record of what happened since it began
local progress                   -- the progress file, read when first needed

local function remember()
  paw.state.tutor = S
end

local function data()
  progress = progress or store.load()
  return progress
end

local function write()
  store.save(data())
end

--- Forget what is in memory, as if the program had been started again.
--- For tests.
function M._forget()
  S, ctx, progress = { active = false }, nil, nil
  remember()
end

-- Lessons ---------------------------------------------------------------------

local function check_lesson(lesson)
  assert(type(lesson) == "table", "a lesson is a table")
  assert(type(lesson.id) == "string" and lesson.id:match("^[%w%-_]+$"), "a lesson needs an `id` of letters, digits and dashes")
  assert(type(lesson.title) == "string", "lesson " .. lesson.id .. " needs a `title`")
  assert(type(lesson.steps) == "table" and #lesson.steps > 0, "lesson " .. lesson.id .. " needs `steps`")
  for i, step in ipairs(lesson.steps) do
    local where = lesson.id .. " step " .. i
    assert(type(step.say) == "string", where .. " needs `say`")
    assert(type(step.keys) == "table", where .. " needs `keys`, the keys it asks for, for the tests")
    assert(step.check or step.unchecked or step.on_quit, where .. " needs `check`, or `unchecked` with the reason")
  end
end

--- Add a lesson, at the end or `after` the lesson with that id. An
--- extension can add lessons about itself the same way.
function M.register(lesson, opts)
  check_lesson(lesson)
  if M.by_id[lesson.id] then
    for i, other in ipairs(M.lessons) do
      if other.id == lesson.id then table.remove(M.lessons, i) end
    end
  end
  local at = #M.lessons + 1
  if opts and opts.after then
    for i, other in ipairs(M.lessons) do
      if other.id == opts.after then at = i + 1 end
    end
  end
  table.insert(M.lessons, at, lesson)
  M.by_id[lesson.id] = lesson
  return lesson
end

--- A lesson by number (1-based), id, or the start of its id or title.
function M.find(which)
  if which == nil then return nil end
  local n = tonumber(which)
  if n then return M.lessons[n], n end
  which = tostring(which):lower()
  for i, lesson in ipairs(M.lessons) do
    if lesson.id == which then return lesson, i end
  end
  for i, lesson in ipairs(M.lessons) do
    if lesson.id:sub(1, #which) == which or lesson.title:lower():find(which, 1, true) then return lesson, i end
  end
end

function M.number(lesson)
  for i, other in ipairs(M.lessons) do
    if other == lesson or other.id == lesson then return i end
  end
end

--- The lesson and step the tutor is on, if it is running.
function M.current()
  if not S.active then return nil end
  local lesson = M.by_id[S.lesson]
  return lesson, lesson and lesson.steps[S.step], S.step
end

function M.state() return S end

--- What the progress file says about a lesson: { done = bool, steps = { [i] = "done"|"skipped" } }.
function M.record(id)
  local lessons = data().lessons
  lessons[id] = lessons[id] or { steps = {} }
  lessons[id].steps = lessons[id].steps or {}
  return lessons[id]
end

--- How far the learner got: "done", "3/8", or "".
function M.progress_of(lesson)
  local rec = data().lessons[lesson.id]
  if not rec then return "" end
  if rec.done then return "done" end
  local n = 0
  for _ in pairs(rec.steps or {}) do n = n + 1 end
  return n > 0 and string.format("%d/%d", n, #lesson.steps) or ""
end

-- Keeping the learner's own project safe -----------------------------------------

--- The options lessons set, so they can be put back afterwards.
local OPTIONS = { "grid", "note_grid", "octave", "velocity", "ripple", "clip_length" }

local function in_practice()
  return S.active and S.practice ~= nil and paw.project.path == S.practice
end
M.in_practice = in_practice

--- Whether opening a practice project now would lose unsaved work.
local function unsaved_work()
  if in_practice() then return false end
  return paw.project.unsaved()
end

local function tidy_screen()
  if paw.ui.float then paw.ui.close() end
  for _, name in ipairs({ "pianoroll", "mixer", "devices" }) do paw.ui.hide(name) end
  -- The note length chosen in insert mode lasts the session, and the device
  -- panel keeps its row from track to track: lessons start from the top.
  paw.ui.views.pianoroll:set_step(nil)
  paw.ui.views.devices.row = 1
  paw.ui.focus("arrange")
  if paw.keymap.mode ~= "n" then paw.keymap.set_mode("n") end
end

--- Save the practice project, and remember which step it was saved at, so
--- that coming back resumes where the project and the step agree.
local function save_practice()
  if not in_practice() then return end
  local ok = pcall(paw.project.save)
  if ok and S.lesson then
    local rec = M.record(S.lesson)
    rec.saved_step = S.step
    rec.cursor = { track = paw.cursor.index(), beat = paw.cursor.beat }
  end
end

-- Steps -------------------------------------------------------------------------

local function new_ctx()
  -- The last message so far: the history keeps only so many, so a count
  -- of them stops moving once it is full.
  return { commands = {}, events = {}, messages = paw.ui.messages[#paw.ui.messages] }
end

local function begin_step()
  local _, step = M.current()
  ctx = new_ctx()
  S.hint, S.error = false, nil
  remember()
  if step and step.start then paw.try(step.start, ctx, look) end
  api.ui_redraw()
end

local function finish_lesson(lesson)
  local rec = M.record(lesson.id)
  rec.done = true
  local n = M.number(lesson)
  local next_lesson = M.lessons[n + 1]
  data().current = next_lesson and { lesson = next_lesson.id, step = 1 } or nil
  S.finished = true
  write()
end

--- Mark the current step done (or skipped) and move on.
local function advance(how)
  local lesson, step, index = M.current()
  if not step then return end
  local rec = M.record(lesson.id)
  rec.steps[index] = how
  S.just_done = how == "done" and (step.done or "Done.") or "Skipped."
  if index >= #lesson.steps then
    S.step = #lesson.steps + 1
    finish_lesson(lesson)
  else
    S.step = index + 1
    data().current = { lesson = lesson.id, step = S.step }
    write()
  end
  begin_step()
end

--- Look at the project, the cursor and the mode and move on if the step is
--- done. Run after every event, and on a timer for what makes no event
--- (a window closing, a list of hints appearing).
local checking = false
function M.poll()
  if checking or not S.active or S.finished then return end
  if not in_practice() then
    if not S.paused then
      S.paused = true
      remember()
      api.ui_redraw()
    end
    return
  end
  if S.paused then
    S.paused = false
    remember()
  end
  local _, step = M.current()
  if not step or not step.check then return end
  -- After `:reload` the record of the step is gone: begin it again.
  if not ctx then begin_step() end
  checking = true
  local ok, result = pcall(step.check, ctx, look)
  checking = false
  if not ok then
    S.error = tostring(result)
    remember()
    return
  end
  if result then advance("done") end
end

-- What steps record about what happened since they began.
--- The command an alias stands for: `q` is `quit`, `w` is `write`.
local function command_name(name)
  local spec = name and paw.commands.get(name)
  return spec and spec.alias_of or name
end

paw.on("*", function(payload, name)
  if not S.active then return end
  local command = (name == "command.pre" or name == "command.post") and command_name(payload.name)
  if ctx then
    if name == "command.post" and command then
      ctx.commands[command] = (ctx.commands[command] or 0) + 1
    end
    ctx.events[name] = (ctx.events[name] or 0) + 1
  end
  if name == "project.saved" and in_practice() and S.lesson then
    local rec = M.record(S.lesson)
    rec.saved_step = S.step
    rec.cursor = { track = paw.cursor.index(), beat = paw.cursor.beat }
  end
  if name == "command.pre" and (command == "quit" or command == "wq") then
    M.leaving()
  end
  M.poll()
end)

-- Starting and leaving ------------------------------------------------------------

local function show_panel()
  require("tutor.panel").show()
end

local function hide_panel()
  require("tutor.panel").hide()
end

--- Build a lesson's practice project and save it in the tutor's directory.
local function build(lesson)
  paw.project.new()
  paw.flush()
  paw.transport.loop_enabled = false
  if lesson.setup then lesson.setup(look) end
  paw.project.name = "tutor " .. lesson.id
  local path = store.practice(lesson.id)
  paw.project.save(path)
  -- Opening the file starts the undo history at the practice project, so
  -- `u` cannot take the lesson's own building apart.
  paw.project.load(path)
  paw.flush()
  return path
end

local function place_cursor(lesson)
  local first = api.track_list()[1]
  if first then paw.cursor.set_track(first) end
  paw.cursor.set_beat(0)
  paw.transport.seek(0)
  if lesson.at then lesson.at(look) end
end

--- Start a lesson (a number, an id, or nil for where the learner left off).
--- `opts.force` starts even when the open project has unsaved changes,
--- which are then lost. `opts.fresh` builds the practice project again
--- instead of reopening the one that was being practised on.
function M.start(which, opts)
  opts = opts or {}
  local lesson, n
  local resume
  if which == nil then
    local cur = data().current
    lesson = cur and M.by_id[cur.lesson]
    if lesson then resume = cur.step else lesson = M.lessons[1] end
  else
    lesson = M.find(which)
    if not lesson then return paw.notify("no lesson `" .. tostring(which) .. "`: `:tutor list` shows them", "warn") end
    local cur = data().current
    if cur and cur.lesson == lesson.id and not opts.fresh then resume = cur.step end
  end
  n = M.number(lesson)

  if unsaved_work() and not opts.force then
    return paw.notify("Your project has changes that are not saved. Save them with `:w` (or `:w name`) "
      .. "and start again, or `:tutor! " .. n .. "` to start anyway and lose them.", "warn")
  end

  local first = not S.active
  if not S.active then
    -- Remember the learner's own project, to reopen it when they leave.
    local p = paw.project.get()
    S.back = { path = p.path }
    S.options = {}
    for _, name in ipairs(OPTIONS) do S.options[name] = paw.opt[name] end
  else
    save_practice()   -- the lesson being left keeps its place
  end

  paw.transport.stop()
  tidy_screen()
  paw.opt.grid, paw.opt.note_grid, paw.opt.octave, paw.opt.velocity, paw.opt.ripple, paw.opt.clip_length = 1, 0.25, 4, 100, false, 4

  local path = store.practice(lesson.id)
  local step = 1
  -- The practice file is as it was when last saved: resume at that step.
  local saved = M.record(lesson.id).saved_step
  if resume and saved then resume = math.min(resume, saved) end
  if resume and resume <= #lesson.steps and store.exists(path) and pcall(paw.project.load, path) then
    paw.flush()
    step = resume
    place_cursor(lesson)
    local where = M.record(lesson.id).cursor
    local list = api.track_list()
    if where and where.track and list[where.track] then
      paw.cursor.set_track(list[where.track])
      paw.cursor.set_beat(where.beat or 0)
    end
  else
    path = build(lesson)
    place_cursor(lesson)
    M.record(lesson.id).steps = {}
    M.record(lesson.id).saved_step = 1
  end

  ctx = nil
  S.active, S.lesson, S.step, S.practice = true, lesson.id, step, path
  S.finished, S.paused, S.just_done, S.error = false, false, nil, nil
  data().current = { lesson = lesson.id, step = step }
  write()
  remember()
  paw.flush()
  begin_step()
  show_panel()
  M.show_intro(lesson)
  local note = string.format("Lesson %d: %s%s.", n, lesson.title, step > 1 and string.format(" (from step %d)", step) or "")
  if first and S.back.path then
    note = note .. " " .. S.back.path .. " is closed while you practise, unchanged; `<leader>hq` reopens it."
  end
  paw.notify(note)
  return lesson
end

--- The lesson's introduction in a window over the screen, closed by any key.
function M.show_intro(lesson)
  local panel = require("tutor.panel")
  local lines = {}
  local function section(title, text)
    if not text then return end
    if title then lines[#lines + 1] = { text = title, style = "Title" } end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = panel.keys(line) end
    lines[#lines + 1] = ""
  end
  section(nil, lesson.intro)
  section("The idea", lesson.idea)
  section("If you know Vim", lesson.vim)
  lines[#lines + 1] = { text = "Press any key to begin. The panel at the bottom says what to do.", style = "TutorHint" }
  paw.ui.page(string.format("Lesson %d: %s", M.number(lesson), lesson.title), lines)
end

--- Save the practice project and the learner's place, for leaving the program.
function M.leaving()
  if not S.active then return end
  save_practice()
  local lesson, step = M.current()
  if lesson and step and step.on_quit then
    -- A step about quitting is done by quitting.
    advance("done")
  end
  write()
end

--- Leave the tutor: save the practice project, put the learner's options and
--- project back.
function M.quit()
  if not S.active then return paw.notify("the tutor is not running") end
  save_practice()
  paw.transport.stop()
  tidy_screen()
  for name, value in pairs(S.options or {}) do paw.opt[name] = value end
  local back = S.back or {}
  S.active, S.finished, S.paused = false, false, false
  remember()
  hide_panel()
  if back.path then
    local ok, err = pcall(paw.project.load, back.path)
    if not ok then paw.notify("could not reopen " .. back.path .. ": " .. tostring(err), "error") end
  else
    paw.project.new()
  end
  paw.flush()
  local first = api.track_list()[1]
  if first then paw.cursor.set_track(first) end
  write()
  paw.notify(back.path and ("Left the tutor; reopened " .. back.path) or "Left the tutor. `:tutor` comes back to where you were.")
end

function M.hint()
  local _, step = M.current()
  if not step then return paw.notify("the tutor is not running: `:tutor`") end
  S.hint = true
  remember()
  api.ui_redraw()
end

function M.skip()
  local _, step = M.current()
  if not step then
    if S.active and S.finished then return M.next_lesson() end
    return paw.notify("the tutor is not running: `:tutor`")
  end
  advance("skipped")
end

function M.restart()
  local lesson = M.current() or (S.active and M.by_id[S.lesson])
  if not lesson then return paw.notify("the tutor is not running: `:tutor`") end
  M.start(lesson.id, { fresh = true, force = true })
end

function M.next_lesson()
  local lesson = S.active and M.by_id[S.lesson]
  local n = lesson and M.number(lesson) or 0
  if not M.lessons[n + 1] then return paw.notify("That was the last lesson.") end
  M.start(n + 1, { fresh = true })
end

--- The lessons, with the learner's progress, to choose one from.
function M.list()
  local items = {}
  for i, lesson in ipairs(M.lessons) do
    local mark = M.progress_of(lesson)
    items[#items + 1] = {
      n = i, lesson = lesson,
      text = string.format("%2d  %-6s %s", i, mark == "done" and "✓" or mark, lesson.title),
    }
  end
  paw.pick({
    title = "Lessons",
    items = items,
    format = function(item) return item.text end,
    preview = function(item)
      local lines = { { text = item.lesson.title, style = "Title" }, "" }
      for line in (item.lesson.intro or ""):gmatch("[^\n]+") do lines[#lines + 1] = line end
      return lines
    end,
    on_choose = function(item) M.start(item.n) end,
  })
end

--- Forget all progress.
function M.reset()
  progress = { version = 1, lessons = {} }
  write()
  paw.notify("tutor progress forgotten")
end

return M
