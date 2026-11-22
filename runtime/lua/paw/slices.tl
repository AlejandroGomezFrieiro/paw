-- Long work in slices between keys: `paw.slices(name, step, opts)` calls
-- `step(ms)` again and again, each time from a timer of its own, until it
-- returns true. A step does at most `ms` milliseconds of work (it looks at
-- `paw.api.now()`), and keeps where it stopped for the next call. The
-- kernel takes the keys that wait before it fires a timer, so a key comes
-- in between two slices and the work does not hold it up.
--
--   paw.slices("count", function(ms)
--     local deadline = paw.api.now() + ms
--     while i <= #list and paw.api.now() < deadline do ... i = i + 1 end
--     return i > #list
--   end)
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local limit = require("paw.limit")

local record M
  --- A job that runs in slices: its name, the slices run, the
  --- milliseconds they took in all, and the longest one.
  record Job
    name: string
    slices: integer
    ms: number
    longest: number
  end
  --- What `paw.slices` takes besides the step: `ms`, the most milliseconds
  --- that one call of the step gets (4), and `after`, the milliseconds
  --- before the first slice (0).
  record Options
    ms: number
    after: number
  end
  --- One slice of a job: work for at most `ms` milliseconds, then return
  --- true when the job is over.
  type Step = function(ms: number): boolean
  metamethod __call: function(M, name: string, step: M.Step, opts?: M.Options): M.Job
end

-- `paw.limit.named` as this module calls it, and `paw.try` of it.
local type Named = function(string, M.Step, number): boolean
local type Try = function(Named, string, M.Step, number): boolean, boolean

-- What this module reads of `paw`, which paw/init.lua makes.
local record Paw
  defer: function(fn: function(), ms?: number): integer
  cancel: function(handle: integer)
  try: Try
end
local paw = (_G as {string: Paw}).paw

--- A job that runs: what it calls, how long a slice is, the timer of its next slice.
local record Running
  job: M.Job
  step: M.Step
  ms: number
  timer: integer
end

local jobs: {string: Running} = {}

local named = limit.named as Named

local function slice(r: Running)
  r.timer = nil
  local job = r.job
  local t0 = api.now()
  local ok, done = paw.try(named, "the job " .. job.name, r.step, r.ms)
  local took = api.now() - t0
  job.slices = job.slices + 1
  job.ms = job.ms + took
  if took > job.longest then
    job.longest = took
  end
  -- Stopped, or started again, by its own step.
  if jobs[job.name] ~= r then
    return
  end
  if not ok or done then
    jobs[job.name] = nil
    return
  end
  r.timer = paw.defer(function() slice(r) end, 0)
end

--- Stop the job `name`. Returns true if it was running.
function M.stop(name: string): boolean
  local r = jobs[name]
  if not r then
    return false
  end
  jobs[name] = nil
  if r.timer then
    paw.cancel(r.timer)
  end
  return true
end

--- Call `step(ms)` again and again, each time from a timer of its own,
--- until it returns true. The step works for at most `ms` milliseconds
--- (`opts.ms`, 4) and keeps its place for the next call. The keys that
--- wait run between two calls. `opts.after` is the time before the first
--- call (0). A job of the same name stops first. An error in the step
--- shows as a message and ends the job. Returns the job.
function M.run(name: string, step: M.Step, opts?: M.Options): M.Job
  M.stop(name)
  opts = opts or {}
  local r: Running = {
    job = {name = name, slices = 0, ms = 0, longest = 0},
    step = step,
    ms = opts.ms or 4,
  }
  jobs[name] = r
  r.timer = paw.defer(function() slice(r) end, opts.after or 0)
  return r.job
end

--- The job `name` while it runs, or nil.
function M.job(name: string): M.Job
  local r = jobs[name]
  return r and r.job
end

--- The jobs that run, by name.
function M.running(): {M.Job}
  local out: {M.Job} = {}
  for _, r in pairs(jobs) do
    out[#out + 1] = r.job
  end
  table.sort(out, function(a: M.Job, b: M.Job): boolean return a.name < b.name end)
  return out
end

return setmetatable(
  M,
  {
    __call = function(_: M, name: string, step: M.Step, opts?: M.Options): M.Job return M.run(name, step, opts) end,
  } as metatable<M>
)
