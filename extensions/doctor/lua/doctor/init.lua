-- A guided check of the real hardware: a registry of checks, a runner that
-- gives each one a context to wait, ask and measure with, and the report.
--
-- A check is a table in `doctor.checks`:
--
--   table.insert(require("doctor").checks, {
--     name = "My interface",                  -- shown in the list and the report
--     id = "mine",                            -- optional; the name in lower case by default
--     help = "What it needs from the person", -- optional
--     unattended = true,                      -- can run with nobody there (`paw doctor`)
--     limit = 60,                             -- seconds before it is stopped; 120 by default
--     run = function(ctx)
--       ctx:say("looking")
--       ctx:sleep(500)
--       ctx:fact("channels", 2)
--       return "ok", "two channels"           -- "ok", "warn", "fail" or "skip", and a sentence
--     end,
--   })
--
-- Every check runs in a coroutine that the runner wakes from a timer, so
-- that waiting never holds the program up; `ctx` has what a check needs and
-- takes back everything it added.
local api = paw.api
local M = { checks = {}, results = {}, order = {} }

-- What a check is stopped with: all the user pressed Esc, one the user skipped,
-- one that took longer than it may.
local CANCEL, SKIP, TIMEOUT = { "cancelled" }, { "skipped" }, { "too slow" }

local S -- the run in progress, or the last one

--- The settings, from the options and what a run was started with.
function M.settings(opts)
  local o = opts or {}
  return {
    seconds = o.seconds or tonumber(paw.opt.doctor_seconds) or 20,
    tone = o.tone or 1,
    input_seconds = o.input_seconds or 10,
    record_seconds = o.record_seconds or 4,
    wait_seconds = o.wait_seconds or 20,
    plugin_seconds = o.plugin_seconds or 1.5,
    plugins = o.plugins or paw.opt.doctor_plugins or {},
    round_trips = o.round_trips or 3,
    voices = o.voices or 8,
  }
end

--- The directory reports are written to.
function M.dir()
  local dir = paw.opt.doctor_dir
  if type(dir) ~= "string" or dir == "" then dir = api.env().state_dir .. "/doctor" end
  return dir
end

local function mkdir(path) api.fs_mkdir(path) end

local function id_of(check) return check.id or tostring(check.name):lower():gsub("[^%w]+", "-") end

local function find(id)
  for _, check in ipairs(M.checks) do
    if id_of(check) == id then return check end
  end
end

-- The context a check runs with -------------------------------------------------

local Ctx = {}
Ctx.__index = Ctx

--- Hand control back until `ready()` says so, then go on. A run that was
--- cancelled, a check that was skipped or one that is out of time raise
--- there, so that the check ends and what it added is taken away.
local function pause(run, ready)
  run.waiter = function() return run.cancelled or run.skipping or api.now() > run.deadline or ready() end
  coroutine.yield()
  run.waiter = nil
  if run.waiter_error then
    local err = run.waiter_error
    run.waiter_error = nil
    error(err, 0)
  end
  if run.cancelled then error(CANCEL, 0) end
  if run.skipping then
    run.skipping = false
    error(SKIP, 0)
  end
  if api.now() > run.deadline then error(TIMEOUT, 0) end
end

--- A line shown while the check works.
function Ctx:say(text)
  self.run.say = text
  api.ui_redraw()
end

--- A line for the report, under this check.
function Ctx:log(text) self.result.lines[#self.result.lines + 1] = tostring(text) end

--- Something that was found and is worth comparing with the next time:
--- the report says when it changes.
function Ctx:fact(key, value)
  self.result.facts[key] = value
  self.result.fact_order[#self.result.fact_order + 1] = key
end

--- A measurement: reported, but too restless to compare.
function Ctx:measure(key, value)
  self.result.measures[key] = value
  self.result.measure_order[#self.result.measure_order + 1] = key
end

--- Something to be told, which makes an "ok" a "warn".
function Ctx:warn(text)
  self.result.warnings[#self.result.warnings + 1] = text
  self:log("warning: " .. text)
end

--- Whether a person is there to look, listen and answer.
function Ctx:attended() return self.run.attended end

--- Let `ms` milliseconds pass.
function Ctx:sleep(ms)
  local at = api.now() + ms
  pause(self.run, function() return api.now() >= at end)
end

--- Let time pass until `ready()` is true, for at most `ms`. Says which.
function Ctx:wait_for(ready, ms)
  local at, found = api.now() + ms, false
  pause(self.run, function()
    found = ready() and true or false
    return found or api.now() >= at
  end)
  return found
end

--- Ask the person something and wait for a key: `choices` is a list of
--- `{ key, label }` (yes, no and skip by default); the key pressed comes
--- back, and "skip" when nobody is there. Without an answer in `opts.timeout`
--- seconds, `opts.default` comes back (or "skip"). `opts.each()` is called
--- a few times a second while waiting, and when `opts.done()` is true the
--- waiting ends and "done" comes back.
function Ctx:ask(question, choices, opts)
  local run = self.run
  opts = opts or {}
  choices = choices or { { "y", "yes" }, { "n", "no" }, { "s", "skip" } }
  if not run.attended then return "skip" end
  local prompt = { question = question, choices = choices, id = self.check.id }
  run.prompt = prompt
  api.ui_redraw()
  local at, finished = api.now() + (opts.timeout or 60) * 1000, false
  pause(run, function()
    if opts.each then opts.each() end
    if opts.done and opts.done() then finished = true end
    return finished or prompt.answer ~= nil or api.now() >= at
  end)
  run.prompt = nil
  if prompt.answer ~= nil then return prompt.answer end
  if finished then return "done" end
  if not opts.default then self:log("no answer in " .. (opts.timeout or 60) .. " s") end
  return opts.default or "skip"
end

--- Put what the check needs in a scratch project, and the person's own away
--- until the run is over (see `open_scratch`).
function Ctx:scratch()
  if not self.run.shelved then M.open_scratch(self.run) end
end

--- Run `fn` when the check is over, however it ends.
function Ctx:cleanup(fn) table.insert(self.cleanups, fn) end

--- A part that is taken away when the check is over.
function Ctx:part(opts)
  self:scratch()
  local part = paw.add_part(opts)
  self:cleanup(function()
    if part:exists() then part:remove() end
  end)
  return part
end

--- A file that is deleted when the check is over.
function Ctx:file(path)
  self:cleanup(function() os.remove(path) end)
  return path
end

--- A directory of the run's own to put files in, taken away at its end.
function Ctx:dir()
  local run = self.run
  if not run.tmp then
    run.tmp = M.dir() .. "/tmp-" .. api.env().pid
    mkdir(run.tmp)
  end
  return run.tmp
end

--- Stop the transport, and what it was recording or playing.
function Ctx:stop()
  paw.transport.recording = false
  paw.transport.stop()
end

--- Play the scratch project from `beat` for `seconds`, then stop it.
function Ctx:play(beat, seconds, each)
  self:scratch()
  self:cleanup(function() self:stop() end)
  paw.transport.seek(beat or 0)
  paw.transport.play()
  local to = api.now() + seconds * 1000
  pause(self.run, function()
    if each then each() end
    return api.now() >= to
  end)
  paw.transport.stop()
end

-- The scratch project ---------------------------------------------------------

--- Put the person's project away, with its undo history, and open an empty
--- one to work in. The project is only ever put away, never changed: the
--- checks add and remove parts in the scratch project, and `finish` brings
--- the person's back exactly as it was. A copy of it is written to the
--- doctor's directory meanwhile, in case the program dies in between.
function M.open_scratch(run)
  if run.shelved then return end
  mkdir(M.dir())
  run.copy = M.dir() .. "/open-project.json"
  api.project_backup(run.copy, { doctor = "the project that was open while :doctor ran" })
  api.project_shelve()
  run.shelved = true
end

local function close_scratch(run)
  if not run.shelved then return end
  api.project_unshelve()
  run.shelved = false
  if run.copy then os.remove(run.copy) end
end

-- Running ---------------------------------------------------------------------

local function new_result(check)
  return {
    id = id_of(check),
    name = check.name,
    status = "skip",
    summary = "",
    lines = {},
    warnings = {},
    facts = {},
    fact_order = {},
    measures = {},
    measure_order = {},
  }
end

local function run_cleanups(list, result)
  for i = #list, 1, -1 do
    local ok, err = pcall(list[i])
    if not ok then result.lines[#result.lines + 1] = "cleanup failed: " .. tostring(err) end
  end
end

--- Run one check to its end. Never raises.
local function run_check(run, check)
  local result = new_result(check)
  M.results[result.id] = result
  run.current, run.say, run.prompt = check, nil, nil
  local limit = type(check.limit) == "function" and check.limit(run.settings) or check.limit or 120
  run.deadline = api.now() + limit * 1000
  local started = api.real_ms()
  local ctx = setmetatable({ run = run, check = check, result = result, cleanups = {}, settings = run.settings }, Ctx)
  local ok, status, summary = xpcall(check.run, function(err)
    if type(err) == "table" then return err end
    return debug.traceback(tostring(err), 2)
  end, ctx)
  -- Whatever the check added goes, whatever happened.
  run.say = "tidying up"
  run_cleanups(ctx.cleanups, result)
  if ok then
    result.status = status or "ok"
    result.summary = summary or ""
    if result.status == "ok" and #result.warnings > 0 then result.status = "warn" end
  elseif status == CANCEL then
    result.status, result.summary = "skip", "cancelled"
  elseif status == SKIP then
    result.status, result.summary = "skip", "skipped"
  elseif status == TIMEOUT then
    result.status, result.summary = "fail", string.format("did not finish in %g s, and was stopped", limit)
  else
    result.status, result.summary = "fail", "raised an error: " .. tostring(status):match("^[^\n]*")
    result.lines[#result.lines + 1] = tostring(status)
  end
  result.seconds = (api.real_ms() - started) / 1000
  run.current, run.say, run.prompt = nil, nil, nil
  return result
end

local function stamp()
  local dir, name = M.dir(), os.date("%Y-%m-%d-%H%M%S")
  local path, n = dir .. "/" .. name, 1
  local function taken(p)
    local file = io.open(p .. ".md", "r")
    if file then
      file:close()
      return true
    end
  end
  while taken(path) do
    n = n + 1
    path = dir .. "/" .. name .. "-" .. n
  end
  return path
end

--- The end of a run, reached however it ends: the person's project comes
--- back, what the run added is gone, the report is written.
local function finish(run)
  local ok, err = pcall(close_scratch, run)
  if not ok then run.problem = "the project that was open could not be put back: " .. tostring(err) end
  -- The run's own temporary folder, made by `ctx:dir()`: removed, not trashed.
  if run.tmp then pcall(api.fs_remove, run.tmp) end
  paw.opt.autosave = run.autosave
  if run.timer then paw.cancel(run.timer) end
  run.timer = nil
  run.running = false
  run.finished = api.real_ms()
  local wrote, path = pcall(M.write_report, run)
  if wrote then
    run.report = path
  else
    run.problem = (run.problem and run.problem .. "; " or "") .. "no report: " .. tostring(path)
  end
  paw.emit("doctor.done", { report = run.report, problem = run.problem })
  if run.on_done then paw.try(run.on_done, run) end
end

local function body(run)
  for _, check in ipairs(run.list) do
    if run.cancelled then
      local result = new_result(check)
      result.summary = "cancelled"
      M.results[result.id] = result
      run.done[#run.done + 1] = result
    else
      run.done[#run.done + 1] = run_check(run, check)
    end
  end
end

local function tick()
  local run = S
  if not (run and run.running and run.co) then return end
  if run.prompt and run.prompt.answer == nil and run.opts.auto then
    local key = run.opts.auto(run.prompt, run.current)
    if key then M.answer(key) end
  end
  if run.waiter then
    -- A check's own waiting code that fails ends that check, not the doctor.
    local fine, ready = pcall(run.waiter)
    if not fine then
      run.waiter_error, ready = ready, true
    end
    if not ready then return end
  end
  local ok, err = coroutine.resume(run.co)
  if not ok then
    run.problem = "the doctor itself failed: " .. tostring(err)
    finish(run)
  elseif coroutine.status(run.co) == "dead" then
    run.co = nil
    finish(run)
  end
end

--- The checks that a run takes: every one, those named (by id or position),
--- or with `unattended` only the ones that need nobody.
local function select_checks(opts)
  local list = {}
  for index, check in ipairs(M.checks) do
    local wanted = not opts.only
    for _, which in ipairs(opts.only or {}) do
      if which == index or which == id_of(check) then wanted = true end
    end
    if wanted and (not opts.unattended or check.unattended) then list[#list + 1] = check end
  end
  return list
end

--- Start a run. `opts`: `only` (a list of ids or positions), `unattended`
--- (nobody is there: only the checks that can do without), `on_done(run)`,
--- `auto(prompt, check)` (answers a question: its key, or nil to leave it to
--- the person), and the settings of `M.settings`. Returns the run.
function M.start(opts)
  opts = opts or {}
  if S and S.running then error("the doctor is running already", 2) end
  local run = {
    running = true,
    attended = not opts.unattended,
    opts = opts,
    settings = M.settings(opts),
    list = select_checks(opts),
    done = {},
    started = api.real_ms(),
    autosave = paw.opt.autosave,
  }
  if #run.list == 0 then error("no check to run", 2) end
  S = run
  -- A safety copy of the scratch project would replace the person's own.
  paw.opt.autosave = 0
  run.co = coroutine.create(function()
    local ok, err = xpcall(body, debug.traceback, run)
    if not ok then run.problem = tostring(err) end
  end)
  run.timer = paw.every(25, tick)
  api.ui_redraw()
  return run
end

--- The run in progress, or the last one.
function M.run() return S end

--- Whether a run is in progress.
function M.running() return S ~= nil and S.running end

--- Answer the question being asked, by its key. False if there is none, or
--- the key is not one of its answers.
function M.answer(key)
  local prompt = S and S.running and S.prompt
  if not prompt or prompt.answer ~= nil then return false end
  for _, choice in ipairs(prompt.choices) do
    if choice[1] == key then
      prompt.answer = key
      api.ui_redraw()
      return true
    end
  end
  return false
end

--- Stop the run: the check going on ends, the rest are not run, what was
--- added is taken away, and the report is written.
function M.cancel()
  if not (S and S.running) then return false end
  S.cancelled = true
  return true
end

--- Skip the check going on.
function M.skip()
  if not (S and S.running and S.current) then return false end
  if S.prompt and S.prompt.answer == nil then
    -- A question skipped is a question not answered.
    for _, choice in ipairs(S.prompt.choices) do
      if choice[1] == "s" then
        S.prompt.answer = "s"
        return true
      end
    end
  end
  S.skipping = true
  return true
end

--- Run, and wait for the end. For scripts, tests and the shell. Returns the run.
function M.run_to_end(opts, limit)
  local run = M.start(opts)
  local at = api.now() + (limit or 3600) * 1000
  while run.running and api.now() < at do
    paw.wait(20)
  end
  if run.running then
    M.cancel()
    while run.running do
      paw.wait(20)
    end
  end
  return run
end

--- What `paw doctor` runs: the checks that need nobody, and the report on
--- the standard output. Returns the exit code: 1 if a check failed.
function M.unattended(opts)
  opts = opts or {}
  opts.unattended = true
  local run = M.run_to_end(opts)
  local text = M.markdown(run)
  io.stdout:write(text, "\n")
  io.stdout:flush()
  if run.report then io.stderr:write("report written to " .. run.report .. "\n") end
  for _, result in ipairs(run.done) do
    if result.status == "fail" then return 1 end
  end
  return 0
end

require("doctor.report")(M, { stamp = stamp, mkdir = mkdir, id_of = id_of })
require("doctor.checks")(M)

M.find, M.id_of = find, id_of
return M
