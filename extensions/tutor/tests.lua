-- Tests for the tutor, run by tests/suite.lua:
--
--   paw --clean --no-plugins -l tests/suite.lua tutor
--
-- Every lesson is played from start to finish by typing each step's keys as
-- a person would, and the tutor must notice each step only once it is done.
local T = ...
local paw = require("paw")
local api = paw.api
local test, eq = T.test, T.eq

local function ext()
  -- Progress and practice projects go in the suite's scratch directory,
  -- never in the user's state directory.
  paw.opt.tutor_dir = T.scratch .. "/tutor"
  if not paw.ext.loaded.tutor then paw.ext.load("extensions/tutor") end
  return require("tutor")
end

--- A clean start: no lesson running, no progress, the arrange view.
local function start()
  local tutor = ext()
  -- Some other extensions' tests leave the picker switched off.
  if not paw.pick then paw.pick = require("paw.pick") end
  if tutor.state().active then tutor.quit() end
  tutor._forget()
  os.remove(T.scratch .. "/tutor/progress.lua")
  T.fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.close()
  paw.ui.focus("arrange")
  paw.flush()
  return tutor
end

--- Type keys one at a time as a person does: the kernel closes the undo
--- step after every key, and the tutor's timer looks after every key.
local function type_keys(text)
  local tutor = require("tutor")
  for _, key in ipairs(paw.keymap.parse(text)) do
    paw.keymap.feed(key)
    api.undo_checkpoint()
    paw.flush()
    tutor.poll()
  end
end

--- Do what a step's `keys` say: type them, let time pass, or stand in for what a
--- person does outside the keyboard (a microphone, a MIDI keyboard, quitting).
local function perform(step, lesson, from, to)
  local tutor = require("tutor")
  for index = from or 1, to or #step.keys do
    local item = step.keys[index]
    if type(item) == "string" then
      type_keys(item)
    elseif item.advance then
      -- The time passes: a key that waits for more (`]` before `]d`) runs
      -- when its wait is over, as at the keyboard.
      T.advance(item.advance)
      paw.flush()
      tutor.poll()
    elseif item.sim == "quit" then
      -- Quitting cannot be typed in a test: the suite would end. The tutor
      -- hears of it through `command.pre`, as it would.
      paw.emit("command.pre", { name = "quit", args = {} })
    elseif type(item.sim) == "function" then
      item.sim(lesson, T.advance)
      paw.flush()
      tutor.poll()
    elseif type(item.keys) == "function" then
      type_keys(item.keys())
    end
  end
end

local panel_text = function() return require("tutor.panel").text() end
local function screen() return table.concat(api.ui_snapshot(120, 40), "\n") end

--- Every key string a step asks for appears in its text, in backticks, so
--- what is typed in the test is what the learner is told to type.
local function said(step, key)
  local text = step.say .. " " .. (step.hint or "")
  return text:find("`" .. key .. "`", 1, true) ~= nil
end

local function play_lesson(tutor, n)
  local lesson = tutor.lessons[n]
  if lesson.test and lesson.test.before then lesson.test.before() end
  local ok, err = xpcall(function()
    tutor.start(n, { fresh = true, force = true })
    eq(tutor.state().active, true, lesson.id .. ": started")
    eq(
      paw.ui.float and paw.ui.float.title,
      "Lesson " .. n .. ": " .. lesson.title,
      lesson.id .. ": the introduction is shown"
    )
    type_keys("<Esc>")
    eq(paw.ui.float, nil, lesson.id .. ": any key closes the introduction")
    eq(
      paw.project.path,
      T.scratch .. "/tutor/practice/" .. lesson.id .. "/project.toml",
      lesson.id .. ": the practice project is the tutor's"
    )
    for i, step in ipairs(lesson.steps) do
      local where = lesson.id .. " step " .. i
      eq(tutor.state().step, i, where .. ": the tutor is on it")
      eq(
        panel_text():find(require("tutor.panel").keys(step.say), 1, true) ~= nil,
        true,
        where .. ": the panel says what to do"
      )
      eq(
        screen():find(string.format("step %d of %d", i, #lesson.steps), 1, true) ~= nil,
        true,
        where .. ": the panel is on screen"
      )
      for _, item in ipairs(step.keys) do
        local list = type(item) == "string" and { item } or item.instead or {}
        for _, key in ipairs(list) do
          eq(said(step, key), true, where .. ": the text asks for `" .. key .. "`")
        end
      end
      -- Not done yet, so not noticed.
      tutor.poll()
      eq(tutor.state().step, i, where .. ": not noticed before it is done")
      -- Half done is not done: everything but the last keys is not enough.
      local last = #step.keys
      if last > 1 and not step.early then
        perform(step, lesson, 1, last - 1)
        eq(tutor.state().step, i, where .. ": not noticed before its last keys")
        perform(step, lesson, last, last)
      else
        perform(step, lesson)
      end
      -- A take that the keys stopped becomes clips a moment later.
      T.until_recorded()
      tutor.poll()
      if step.unchecked then
        eq(tutor.state().step, i, where .. ": an unchecked step waits for the learner")
        type_keys("<leader>hn")
      end
      if tutor.state().step ~= i + 1 then
        error(
          string.format(
            "%s: not noticed after typing its keys (%s)\nthe panel says:\n%s",
            where,
            step.say,
            panel_text()
          ),
          0
        )
      end
      local rec = tutor.record(lesson.id).steps[i]
      eq(rec, step.unchecked and "skipped" or "done", where .. ": recorded")
      if not step.unchecked then
        eq(
          panel_text():find("✓ " .. require("tutor.panel").keys(step.done or "Done."), 1, true) ~= nil,
          true,
          where .. ": the panel says it is done"
        )
      end
    end
    eq(tutor.state().finished, true, lesson.id .. ": finished")
    eq(tutor.record(lesson.id).done, true, lesson.id .. ": recorded as done")
  end, debug.traceback)
  if lesson.test and lesson.test.after then lesson.test.after() end
  if not ok then error(err, 0) end
end

-- One test per lesson, so that a failure names the lesson.
do
  local tutor = ext()
  for n, lesson in ipairs(tutor.lessons) do
    test("tutor: lesson " .. n .. " (" .. lesson.id .. ") can be played from start to finish by typing", function()
      local t = start()
      play_lesson(t, n)
      t.quit()
    end)
  end
end

-- Hints, skipping, restarting -----------------------------------------------------

test("tutor: a hint is shown when asked for, and skipping goes on without doing the step", function()
  local tutor = start()
  type_keys(":tutor 1<CR>")
  type_keys("<Esc>")
  local lesson = tutor.by_id["first-steps"]
  eq(tutor.state().step, 1, "on the first step")
  eq(screen():find("Hint:", 1, true), nil, "no hint before it is asked for")
  type_keys("<leader>hh")
  eq(panel_text():find("Hint: " .. lesson.steps[1].hint, 1, true) == nil, false, "the hint is in the panel")
  type_keys("<leader>hn")
  eq(tutor.state().step, 2, "skipped to the second step")
  eq(tutor.record("first-steps").steps[1], "skipped", "recorded as skipped")
  eq(panel_text():find("✓ Skipped.", 1, true) ~= nil, true, "the panel says so")
  eq(panel_text():find("Hint:", 1, true), nil, "the hint goes with its step")
  eq(paw.transport.playing, false, "skipping did not do the step")
  -- A step that is not done is not noticed, even after other keys.
  type_keys("jk")
  eq(tutor.state().step, 2, "other keys do not do the step")
  tutor.quit()
end)

test("tutor: restarting a lesson builds its practice project again", function()
  local tutor = start()
  type_keys(":tutor 5<CR><Esc>")
  type_keys("dw")
  eq(tutor.state().step, 2, "the first step is done")
  eq(require("tutor.look").names("Beat"), "snare fill crash", "kick deleted")
  type_keys("<leader>hr")
  type_keys("<Esc>")
  eq(tutor.state().step, 1, "back at the first step")
  eq(require("tutor.look").names("Beat"), "kick snare fill crash", "a fresh practice project")
  eq(next(tutor.record("grammar").steps), nil, "the lesson's record starts again")
  eq(paw.undo(), false, "the fresh project has nothing to undo: building it is not an edit")
  tutor.quit()
end)

test("tutor: a finished lesson says so, and the next one follows", function()
  local tutor = start()
  type_keys(":tutor 13<CR><Esc>")
  for _ = 1, #tutor.by_id.saving.steps do
    type_keys("<leader>hn")
  end
  eq(tutor.state().finished, true, "finished")
  eq(
    panel_text():find("Lesson done. `<Space>hn` goes on to lesson 14", 1, true) ~= nil,
    true,
    "the panel offers the next lesson"
  )
  type_keys("<leader>hn<Esc>")
  eq(tutor.state().lesson, "finding", "on to lesson 14")
  eq(tutor.state().step, 1, "at its first step")
  tutor.quit()
end)

test("tutor: skipping a step never makes the tutor jump over the next one", function()
  local tutor = start()
  local problems = {}
  for n, lesson in ipairs(tutor.lessons) do
    if lesson.test and lesson.test.before then lesson.test.before() end
    tutor.start(n, { fresh = true, force = true })
    type_keys("<Esc>")
    while not tutor.state().finished do
      local i = tutor.state().step
      type_keys("<leader>hn")
      if not tutor.state().finished and tutor.state().step ~= i + 1 then
        problems[#problems + 1] = string.format("%s: step %d was passed without being done", lesson.id, i + 1)
      end
    end
    if lesson.test and lesson.test.after then lesson.test.after() end
  end
  tutor.quit()
  if #problems > 0 then error(table.concat(problems, "\n"), 0) end
end)

-- The learner's own project ---------------------------------------------------------

local function own_project()
  T.fresh()
  local mine = paw.add_part({ name = "Mine" })
  mine:add_clip({ name = "idea", start = 0, length = 4 })
  paw.opt.grid = 2
  local path = T.scratch .. "/mine.json"
  api.undo_checkpoint()
  paw.project.save(path)
  paw.flush()
  return path, T.read_file(path)
end

test("tutor: the learner's project is never touched, and comes back when they leave", function()
  local tutor = start()
  local path, before = own_project()
  type_keys(":tutor 3<CR>")
  eq(
    paw.ui.messages[#paw.ui.messages].text:find(path .. " is closed while you practise", 1, true) ~= nil,
    true,
    "the tutor says what happens to it"
  )
  type_keys("<Esc>")
  eq(paw.project.path ~= path, true, "a practice project of its own")
  eq(paw.part("Mine"), nil, "the learner's parts are not in it")
  eq(paw.opt.grid, 1, "lessons start from the default grid")
  type_keys("o")
  type_keys("<leader>hq")
  eq(tutor.state().active, false, "left the tutor")
  eq(paw.project.path, path, "the learner's project is open again")
  eq(paw.part("Mine") ~= nil and #paw.parts() == 1, true, "as it was")
  eq(paw.project.modified, false, "with nothing to save")
  eq(T.read_file(path), before, "its file was not written")
  eq(paw.opt.grid, 2, "the learner's grid is back")
  eq(paw.ui.visible("tutor"), false, "the panel is gone")
end)

test("tutor: a project with unsaved changes is not closed without asking", function()
  local tutor = start()
  local path = own_project()
  paw.add_part({ name = "Unsaved" })
  api.undo_checkpoint()
  paw.flush()
  type_keys(":tutor 1<CR>")
  eq(tutor.state().active, false, "the lesson did not start")
  eq(
    paw.ui.messages[#paw.ui.messages].text:find("changes that are not saved", 1, true) ~= nil,
    true,
    "the tutor says why"
  )
  eq(paw.part("Unsaved") ~= nil and paw.project.path == path, true, "the project is still open, changes and all")
  type_keys(":tutor! 1<CR><Esc>")
  eq(tutor.state().active, true, "`:tutor!` starts anyway")
  tutor.quit()
  eq(paw.project.path, path, "and leaving reopens the project as last saved")
  eq(paw.part("Unsaved"), nil, "without the changes that were thrown away")
end)

test("tutor: a project opened from a MIDI file is not replaced without asking", function()
  local tutor = start()
  local t = paw.add_part({ name = "Keys" })
  t:add_clip({ start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1, velocity = 90 } } })
  local path = T.scratch .. "/tutor-import.mid"
  paw.midifile.export(path)
  T.fresh()
  type_keys(":open " .. path .. "<CR>")
  eq(api.project_get("modified"), false, "an imported project is not modified")
  type_keys(":tutor 1<CR>")
  eq(tutor.state().active, false, "yet the lesson did not start")
  eq(paw.part("Keys") ~= nil, true, "and the notes are still there")
  type_keys(":tutor! 1<CR><Esc>")
  eq(tutor.state().active, true, "`:tutor!` starts anyway")
  tutor.quit()
end)

test("tutor: progress survives leaving and coming back, and a restart of the program", function()
  local tutor = start()
  type_keys(":tutor 3<CR><Esc>")
  type_keys("o") -- step 1: a part
  type_keys("grn<C-u>Bass<CR>") -- step 2: its name
  eq(tutor.state().step, 3, "two steps done")
  type_keys("<leader>hq")
  eq(require("tutor.store").exists(T.scratch .. "/tutor/progress.lua"), true, "progress is in the tutor's directory")
  -- As if the program had been closed and started again.
  tutor._forget()
  T.fresh()
  type_keys(":tutor<CR>")
  eq(paw.ui.float and paw.ui.float.title, "Lesson 3: Parts, clips and notes", "back in lesson 3")
  type_keys("<Esc>")
  eq(tutor.state().step, 3, "at the step after the last one done")
  eq(paw.part("Bass") ~= nil, true, "with the practice project as it was left")
  eq(tutor.record("making").steps[2], "done", "and the steps done are remembered")
  type_keys("asynth<CR>")
  eq(tutor.state().step, 4, "and it carries on noticing")
  tutor.quit()
end)

test("tutor: quitting the program in a lesson keeps the place", function()
  local tutor = start()
  type_keys(":tutor 3<CR><Esc>o")
  eq(tutor.state().step, 2, "a step done")
  paw.emit("command.pre", { name = "quit", args = {} }) -- what `:q` in the last window says before the program ends
  tutor._forget()
  T.fresh()
  type_keys(":tutor<CR><Esc>")
  eq(tutor.state().lesson .. " " .. tutor.state().step, "making 2", "back where it was")
  eq(#paw.parts(), 2, "with the part that was added")
  tutor.quit()
end)

test("tutor: in another project the tutor waits, and `:tutor` goes back to the lesson", function()
  local tutor = start()
  local path = own_project()
  type_keys(":tutor 2<CR><Esc>")
  type_keys(":e " .. path .. "<CR>")
  eq(paw.project.path, path, "the learner opened their own project")
  type_keys("lll")
  eq(tutor.state().step, 1, "steps are not checked against it")
  eq(panel_text():find("not the lesson's project", 1, true) ~= nil, true, "the panel says the tutor is waiting")
  type_keys(":tutor<CR><Esc>")
  eq(paw.project.path ~= path and tutor.state().step == 1, true, "back in the lesson")
  type_keys("lll")
  eq(tutor.state().step, 2, "and noticing again")
  tutor.quit()
end)

test("tutor: the lessons are listed with progress, and one is chosen from the list", function()
  local tutor = start()
  type_keys(":tutor 1<CR><Esc>")
  for _ = 1, #tutor.by_id["first-steps"].steps do
    type_keys("<leader>hn")
  end
  type_keys("<leader>hl")
  local state = paw.pick.state()
  eq(state and state.title, "Lessons", "a picker of lessons")
  eq(#state.matches, #tutor.lessons, "every lesson")
  eq(state.matches[1]:find("✓", 1, true) ~= nil, true, "lesson 1 is marked done")
  type_keys("visual<CR><Esc>")
  eq(tutor.state().lesson, "visual", "the chosen lesson starts")
  tutor.quit()
end)

test("tutor: another extension can add a lesson", function()
  local tutor = start()
  local lesson = tutor.register({
    id = "extra",
    title = "An extra lesson",
    setup = function() paw.add_part({ name = "X" }) end,
    steps = { { say = "Press `o`.", keys = { "o" }, check = function() return #paw.parts() == 2 end } },
  }, { after = "first-steps" })
  eq(tutor.number(lesson), 2, "it goes where it was asked")
  type_keys(":tutor extra<CR><Esc>o")
  eq(tutor.state().finished, true, "it runs like the others")
  tutor.quit()
  for i, other in ipairs(tutor.lessons) do
    if other == lesson then table.remove(tutor.lessons, i) end
  end
  tutor.by_id.extra = nil
  T.fails(
    function() tutor.register({ id = "bad", title = "Bad", steps = { { say = "x" } } }) end,
    "keys",
    "a step needs its keys"
  )
end)

-- The course as text -------------------------------------------------------------------

test("tutor: docs/tutorials/course is made from the lessons and agrees with them", function()
  local tutor = ext()
  local files = require("tutor.docs").files(tutor.lessons)
  for name, text in pairs(files) do
    local on_disk = T.read_file("docs/tutorials/course/" .. name)
    if on_disk ~= text then
      error(
        "docs/tutorials/course/"
          .. name
          .. " differs from the lessons: run `paw --clean --no-plugins -l extensions/tutor/make-docs.lua`",
        0
      )
    end
  end
  for _, entry in ipairs(api.read_dir("docs/tutorials/course")) do
    local name = entry.name
    eq(files[name] ~= nil, true, "docs/tutorials/course/" .. name .. " belongs to a lesson")
  end
end)

test(
  "tutor: the page in the browser types what each step asks for, and nothing for a step away from the keyboard",
  function()
    ext()
    local docs = require("tutor.docs")
    local check = function() return true end
    local steps = {
      {
        say = "Play `<leader><Space>`, then stop.",
        keys = { "<leader><Space>", { wait = 300 }, "<leader><Space>" },
        check = check,
      },
      { say = "Quit with `:q`.", keys = { { sim = "quit", instead = { ":q", "<CR>" } } }, check = check },
      {
        say = "Play three notes on a MIDI keyboard.",
        keys = { "R", { sim = function() end, instead = {} } },
        check = check,
      },
      { say = "Open a plugin window.", keys = {}, unchecked = "It needs a desktop." },
      { say = "Find a key.", keys = { "<leader>fk", "loop", "<Esc>" }, check = check },
      { say = "Sing.", keys = { ":tutor.try utau", "<CR>" }, browser_lacks = "utau", check = check },
    }
    local page = docs.page({ { id = "a", title = "A", steps = steps } })
    local function span(n) return page:match("\n" .. n .. "%. [^\n]-(<span [^\n]*></span>)") end
    eq(
      span(1),
      '<span data-paw-keys=\'["&lt;leader&gt;&lt;Space&gt;",2000,"&lt;leader&gt;&lt;Space&gt;"]\''
        .. ' data-paw-state=\'{"lesson":1,"keys":"&lt;Esc&gt;"}\' data-paw-label=\'Type it\'></span>',
      "a wait is long enough to listen"
    )
    eq(span(2):match("data%-paw%-keys='([^']*)'"), '[":q&lt;CR&gt;"]', "quitting types the keys that quit")
    eq(span(3), nil, "a step away from the keyboard has no button")
    eq(span(4):match("data%-paw%-label='([^']*)'"), "Next step", "a step that the tutor cannot check goes on")
    eq(
      span(5):match("data%-paw%-keys='([^']*)'"),
      '["&lt;leader&gt;fk",400,"loop",400,"&lt;Esc&gt;"]',
      "the parts of a step come one at a time"
    )
    eq(
      span(6):match("data%-paw%-keys='([^']*)'"),
      '["&lt;leader&gt;hn"]',
      "a step that the browser cannot do is skipped"
    )
    eq(
      page:find("6. Sing. In the browser, paw has no utau, so skip the step.", 1, true) ~= nil,
      true,
      "and it says why"
    )
    eq(page:find('data-paw-open=\'{"lesson":1,', 1, true) ~= nil, true, "the lesson has a button that opens it")

    local lacking = docs.page({ { id = "b", title = "B", browser_lacks = "sound input", steps = { steps[1] } } })
    eq(lacking:find("<span data-paw", 1, true), nil, "a lesson that the browser cannot do has no buttons")
    eq(
      lacking:find("In the browser, paw has no sound input, so do the lesson in paw on your computer.", 1, true) ~= nil,
      true,
      "it says why"
    )
  end
)

test("tutor: every key in docs/reference/keys.md is a key paw has", function()
  ext()
  -- keys.md also lists the keys of these extensions.
  for _, name in ipairs({ "launcher", "sections" }) do
    if not paw.ext.loaded[name] then
      paw.ext.load("extensions/" .. name)
      T.after(function() paw.ext.unload(name) end)
    end
  end
  local keymap = paw.keymap
  local known, operators, chars = {}, {}, {}
  for _, mode in ipairs({ "n", "x", "o", "i" }) do
    for _, view in ipairs({
      "arrange",
      "pianoroll",
      "pianoroll.complete",
      "mixer",
      "devices",
      "session",
      "textbuf",
    }) do
      for _, map in ipairs(keymap.list(mode, view)) do
        local keys = table.concat(keymap.parse(map.lhs))
        known[keys] = true
        if map.operator and mode == "n" then operators[#operators + 1] = keymap.parse(map.lhs) end
        if map.char then chars[keymap.parse(map.lhs)[1]] = true end
      end
    end
  end
  local function plain(token)
    local keys = keymap.parse(token)
    local text = table.concat(keys)
    if known[text] then return true end
    if #keys == 2 and chars[keys[1]] then return true end -- `ma`, `'a`, `@a`, `qa`
    -- `@19|`: the key after `@` reads a bar, then `|`.
    local bar = text:match("^@%d+(.+)$")
    if bar and known[bar] then return true end
    return false
  end
  local function counted(token)
    if token:match("^%d+$") then return plain(token) end
    return plain(token:gsub("^%d+", ""))
  end
  local function ok(token)
    if token == "<" then token = "<lt>" end
    if token:match("^:.") then
      local name = token:sub(2):match("^%S+")
      return name:match("^%d+$") ~= nil or paw.commands.get(name) ~= nil
    end
    if token:find(" ") then
      for piece in token:gmatch("%S+") do
        if not ok(piece) then return false end
      end
      return true
    end
    token = token:gsub('^"[%w_"]', "")
    if token == "" then return true end
    if counted(token) then return true end
    -- An operator and what follows it.
    local rest = token:gsub("^%d+", "")
    for _, op in ipairs(operators) do
      local lhs = table.concat(op)
      if rest:sub(1, #lhs) == lhs then
        local after = rest:sub(#lhs + 1)
        if after == op[#op] or after:gsub("^%d+", "") == op[#op] or counted(after) then return true end
      end
    end
    return false
  end
  local text = T.read_file("docs/reference/keys.md")
  local checked = 0
  for line in text:gmatch("[^\n]+") do
    local first = line:gsub("\\|", "\1"):match("^| ([^|]*) |")
    if first and first:find("`") then
      first = first:gsub("\1", "|")
      for token in first:gmatch("`([^`]+)`") do
        checked = checked + 1
        if not ok(token) then error("keys.md: `" .. token .. "` is not a key of paw", 0) end
      end
    end
  end
  eq(checked > 150, true, "keys checked: " .. checked)
end)

test("tutor: the keys in a lesson follow the learner's leader and local leader", function()
  local panel = require("tutor.panel")
  local leader, localleader = paw.opt.leader, paw.opt.localleader
  T.after(function()
    paw.opt.leader, paw.opt.localleader = leader, localleader
  end)
  paw.opt.leader, paw.opt.localleader = "-", ";"
  eq(panel.keys("Press `<leader>hh`, then `\\Sa` and `\\`."), "Press `-hh`, then `;Sa` and `\\`.")
  paw.opt.leader, paw.opt.localleader = " ", "\\"
  eq(panel.keys("Press `<leader><Space>`."), "Press `<Space><Space>`.", "the default leader is the space bar")
end)
