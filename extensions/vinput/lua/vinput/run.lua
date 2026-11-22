-- Running the programs behind the virtual inputs, and knowing how they are.
--
-- Each input that is on has one program (its kind's `argv`), started once
-- the input's MIDI port is there, started again when a setting changes, and
-- asked to finish when the input is turned off or removed or paw exits.
-- A program that ends by itself is started again a few times, then left
-- with the reason shown. What a program prints goes to a file per input in
-- the state directory, which is read for the level and the note count.
local api = paw.api
local vinput = require("vinput")

local R = {
  jobs = {}, -- by input name: what runs for it, or why nothing does
  lists = {}, -- by kind: the sources there are, and the listing that is running
  ticker = nil,
  PERIOD = 250, -- ms between looks at the programs
  SETTLE = 700, -- ms a new MIDI port is left to appear to other programs
  GRACE = 1000, -- ms a program is given to finish when asked
  RETRY = 1000, -- ms before a program that ended is started again
  TRIES = 4, -- starts in a row that may fail before giving up
}

--- Whether programs are run at all: not on the null backend, where the
--- MIDI ports are not open for a program to send to (`paw.opt.vinput_run`
--- says otherwise for tests).
function R.enabled()
  local want = paw.opt.vinput_run
  if want == true or want == false then return want end
  return api.engine_get().backend ~= "null"
end

--- Where the programs' output is written: beside the file the inputs are
--- kept in.
function R.dir()
  local path = vinput.path()
  local dir = path and path:match("^(.*)/[^/]*$")
  return (dir or api.env().state_dir) .. "/vinput"
end

function R.log_path(name) return R.dir() .. "/" .. name:gsub("[^%w%-_ ]", "_") .. ".log" end

local function read(path, tail)
  local file = io.open(path, "r")
  if not file then return "" end
  if tail then
    local size = file:seek("end")
    file:seek("set", math.max(0, size - tail))
  end
  local text = file:read("*a") or ""
  file:close()
  return text
end

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

--- The programs that run, kept where `:reload` does not lose them: the
--- new Lua state knows nothing of the jobs, and would start a second
--- program beside each.
function R.remember()
  local procs = {}
  for _, job in pairs(R.jobs) do
    if job.proc then procs[#procs + 1] = job.proc end
  end
  paw.state.vinput_procs = procs
end

for _, proc in ipairs(paw.state.vinput_procs or {}) do
  pcall(api.proc_stop, proc)
  pcall(api.proc_kill, proc)
end
paw.state.vinput_procs = nil

local function job_of(name)
  local job = R.jobs[name]
  if not job then
    job = { state = "off", tries = 0, born = api.now() }
    R.jobs[name] = job
  end
  return job
end

local function start(input, job)
  local kind = vinput.kinds[input.kind]
  local argv = kind.argv(input)
  pcall(paw.api.fs_mkdir, R.dir())
  local log = R.log_path(input.name)
  -- Each run has the file to itself.
  local file = io.open(log, "w")
  if file then file:close() end
  local ok, proc = pcall(api.proc_spawn, argv, { log = log })
  if not ok then
    job.state, job.text = "failed", tostring(proc)
    return
  end
  job.proc, job.argv, job.log, job.started = proc, argv, log, api.now()
  R.remember()
  job.state, job.text, job.seen = "starting", nil, {}
end

--- Ask a job's program to finish; `then_state` is what the job is once it has.
local function finish(job, then_state)
  if job.proc and job.state ~= "stopping" then
    pcall(api.proc_stop, job.proc)
    job.state, job.deadline, job.after = "stopping", api.now() + R.GRACE, then_state
  elseif not job.proc then
    job.state = then_state
  else
    job.after = then_state
  end
end

--- Look at one input and its program, and do what is next.
local function step(input)
  local name = input.name
  local job = job_of(name)
  local kind = vinput.kinds[input.kind]
  local blocked = not input.on and "off" or kind.blocked(input)
  local now = api.now()

  if job.proc then
    local status = api.proc_status(job.proc)
    local seen = kind.parse_log(read(job.log, 8192))
    job.seen = seen
    if job.state == "stopping" then
      if not status.running or now >= job.deadline then
        -- A program that had to be cut off never sent its note-offs: the
        -- port is made again, which releases what was held on it.
        local hard = status.running
        api.proc_kill(job.proc)
        job.proc = nil
        if hard and vinput.get(name) then
          paw.midi.close_port(name)
          paw.midi.open_port(name)
          job.born = now
        end
        job.state = job.after or "off"
        if seen.advice then job.advice = seen.advice end
      end
      return
    end
    if not status.running then
      api.proc_kill(job.proc)
      job.proc = nil
      if seen.advice then job.advice = seen.advice end
      job.tries = job.tries + 1
      local why = seen.error
        or read(job.log, 600):match("([^\n]+)%s*$")
        or ("ended with code " .. tostring(status.code))
      if job.tries >= R.TRIES then
        job.state, job.text = "failed", why
      else
        -- Most often the MIDI port was not there yet: wait and try again.
        job.state, job.text, job.retry = "waiting", why, now + R.RETRY
      end
      return
    end
    if blocked or not R.enabled() then return finish(job, "off") end
    if not same(job.argv, kind.argv(input)) then return finish(job, "restart") end
    if seen.wired or seen.seconds then
      job.state, job.tries = "running", 0
    end
    return
  end

  if blocked == "off" or not R.enabled() then
    job.state, job.text, job.tries = "off", nil, 0
  elseif blocked then
    job.state, job.text, job.tries = "blocked", blocked, 0
  elseif job.state == "failed" then
    -- Stays failed until something is changed (see `sync`) or `restart`.
    return
  elseif now < job.born + R.SETTLE or (job.retry and now < job.retry) then
    if job.state ~= "waiting" then
      job.state, job.text = "waiting", nil
    end
  else
    job.retry = nil
    start(input, job)
  end
end

local function listing()
  for kind, list in pairs(R.lists) do
    if list.proc and not api.proc_status(list.proc).running then
      api.proc_kill(list.proc)
      list.proc = nil
      list.items = vinput.kinds[kind].parse_list(read(list.log))
      list.at = api.now()
      api.ui_redraw()
    end
  end
end

function R.tick()
  for _, input in ipairs(vinput.inputs) do
    step(input)
  end
  -- Programs of inputs that are gone.
  for name, job in pairs(R.jobs) do
    if not vinput.get(name) then
      if job.proc then
        if job.state ~= "stopping" then finish(job, "off") end
        if not api.proc_status(job.proc).running or api.now() >= job.deadline then
          api.proc_kill(job.proc)
          job.proc = nil
        end
      end
      if not job.proc then R.jobs[name] = nil end
    end
  end
  listing()
  local busy = next(R.jobs) ~= nil
  for _, list in pairs(R.lists) do
    busy = busy or list.proc ~= nil
  end
  if not busy and R.ticker then
    paw.cancel(R.ticker)
    R.ticker = nil
  end
  if paw.ui.visible("vinput") then api.ui_redraw() end
end

local function watch()
  if not R.ticker then R.ticker = paw.every(R.PERIOD, R.tick) end
end

--- The inputs or their settings have changed: bring the programs in line.
function R.sync()
  for _, input in ipairs(vinput.inputs) do
    local job = job_of(input.name)
    -- A change is a reason to try again.
    if job.state == "failed" then
      job.state, job.tries = "off", 0
    end
  end
  watch()
  R.tick()
end

--- Stop an input's program now, as when it is renamed or removed.
function R.stop(name)
  local job = R.jobs[name]
  if not (job and job.proc) then
    R.jobs[name] = nil
    return
  end
  pcall(api.proc_stop, job.proc)
  local deadline = api.now() + R.GRACE
  while api.now() < deadline and api.proc_status(job.proc).running do
    api.sleep(10)
  end
  api.proc_kill(job.proc)
  R.jobs[name] = nil
end

--- Start an input's program again, also after it had given up.
function R.restart(name)
  local job = R.jobs[name]
  if not job then return R.sync() end
  job.tries, job.retry = 0, nil
  if job.proc then
    finish(job, "restart")
  else
    job.state = "off"
  end
  watch()
end

local words = {
  off = "off",
  blocked = "not ready",
  waiting = "starting",
  starting = "starting",
  restart = "starting",
  running = "running",
  stopping = "stopping",
  failed = "stopped",
}

--- What an input is doing:
---   state   "off", "blocked", "waiting", "starting", "running", "stopping", "failed"
---   text    the state in words, with the reason when there is one
---   level   the level the tracker hears, in dBFS, while it runs
---   peak    the loudest the source was in the last second, in dBFS
---   notes   how many notes it has sent in this run
---   load    milliseconds the tracker takes for each frame
---   advice  `{ db, way, gain }` from the last run that ended: how far the
---           level was from what the tracker wants, and the gain to use
function R.status(name)
  local input = vinput.get(name)
  local job = R.jobs[name]
  if not input or not job then return { state = "off", text = "off" } end
  local out = { state = job.state == "restart" and "waiting" or job.state, advice = job.advice }
  local seen = job.seen or {}
  if job.state == "running" then
    out.level, out.peak, out.notes, out.load, out.queue = seen.level, seen.peak, seen.notes, seen.load, seen.queue
  end
  out.text = words[job.state] or job.state
  if job.state == "off" and input.on and not R.enabled() then
    out.text = "waits for an audio device"
  elseif job.text and job.state ~= "running" then
    out.text = out.text .. ": " .. job.text
  end
  return out
end

--- The sources a kind can take, as far as they are known; asks for them
--- when they are not, or when `refresh` is set. Nil while the first
--- listing has not come back.
function R.sources(kind, refresh)
  local def = vinput.kinds[kind]
  local list = R.lists[kind]
  if not list then
    list = {}
    R.lists[kind] = list
  end
  if (refresh or not list.items) and not list.proc then
    local argv = def.list_argv and def.list_argv()
    if not argv then
      list.items = list.items or {}
      return list.items
    end
    pcall(paw.api.fs_mkdir, R.dir())
    list.log = R.dir() .. "/" .. kind .. "-list.txt"
    local file = io.open(list.log, "w")
    if file then file:close() end
    local ok, proc = pcall(api.proc_spawn, argv, { log = list.log })
    if ok then
      list.proc = proc
      watch()
    else
      list.items = list.items or {}
    end
  end
  return list.items
end

-- The programs end with paw.
paw.on("exit", function()
  for _, job in pairs(R.jobs) do
    if job.proc then pcall(api.proc_stop, job.proc) end
  end
  local deadline = api.now() + 500
  for _, job in pairs(R.jobs) do
    while job.proc and api.now() < deadline and api.proc_status(job.proc).running do
      api.sleep(10)
    end
    if job.proc then api.proc_kill(job.proc) end
  end
  R.jobs = {}
end)
-- A new audio device, or none: the programs follow.
paw.on("engine.started", function() R.sync() end)

package.loaded["vinput.run"] = R
return R
