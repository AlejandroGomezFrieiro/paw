-- `:profile`: LuaJIT's sampling profiler (`jit.profile`) in the kernel, as
-- Neovim's `:profile`. `:profile start [file]` starts it, `:profile stop`
-- stops it and puts the 30 Lua functions that took the most time in the
-- quickfix list, each with its file and line. With a file, it also writes
-- the folded stacks there, for a flame graph (`inferno-flamegraph`).
-- `:profile` alone says whether it runs.
--
-- The profiler takes a sample each millisecond and counts it for the Lua
-- function that ran then (a function of the C library counts for the Lua
-- function that called it).
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local commands = require("paw.commands")
local A = require("paw.address")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type QfModule = require("paw.qf")

local record Paw is partial.Paw
  qf: QfModule
end
local paw = (_G as {string: Paw}).paw

--- LuaJIT's `jit.profile`, the part of it that this module calls.
local record JitProfile
  start: function(mode: string, callback: function(th: thread, samples: integer, vmstate: string))
  stop: function()
  dumpstack: function(th: thread, format: string, depth: integer): string
end
local record Loader
  require: function(name: string): JitProfile
end

--- A Lua function that samples fell in: its file, the line where it is
--- defined, its name, and its samples.
local record Hot
  file: string
  line: integer
  name: string
  samples: integer
end

--- The profiler that runs: since when, the file of the folded stacks,
--- the samples, the functions by `file:line`, and the folded stacks.
local record Run
  started: number
  file: string
  samples: integer
  hot: {string: Hot}
  folded: {string: integer}
end

--- What `paw.profile.stop` gives: the samples, the seconds, and the
--- functions that took the most time, most first.
local record Report
  samples: integer
  seconds: number
  top: {Hot}
end

local record M
  type Hot = Hot
  type Report = Report
  --- How many functions the quickfix list gets.
  TOP: integer
end
M.TOP = 30

local running: Run

local function profiler(): JitProfile
  return (_G as Loader).require("jit.profile")
end

--- The Lua function that ran in `th` at a sample: the innermost frame
--- that is not a function of C.
local function sampled(th: thread): Hot
  for level = 0, 32 do
    local info = debug.getinfo(th, level, "Sn")
    if not info then
      return nil
    end
    if info.what ~= "C" then
      local file = info.source:gsub("^@", "")
      return {file = file, line = info.linedefined, name = info.name, samples = 0}
    end
  end
end

--- Start `jit.profile`, which takes a sample of the Lua code each
--- millisecond. With `file`, `stop` writes the folded stacks there. Fails
--- when it runs already.
function M.start(file?: string)
  if running then
    error("the profiler runs already: `:profile stop` stops it", 0)
  end
  local run: Run = {started = api.now(), file = file, samples = 0, hot = {}, folded = {}}
  local prof = profiler()
  prof.start(
    "fi1",
    function(th: thread, samples: integer, vmstate: string)
      run.samples = run.samples + samples
      local fn = sampled(th)
      if fn then
        local key = fn.file .. ":" .. fn.line
        local hot = run.hot[key]
        if not hot then
          hot = fn
          run.hot[key] = hot
        end
        hot.name = hot.name or fn.name
        hot.samples = hot.samples + samples
      end
      if run.file then
        local stack = prof.dumpstack(th, "pF;", -48):gsub(";$", ""):gsub("%[builtin#(%d+)%]", "builtin#%1")
        local key = stack .. ";[" .. vmstate .. "]"
        run.folded[key] = (run.folded[key] or 0) + samples
      end
    end
  )
  running = run
end

--- Whether `jit.profile` runs, and the samples it took so far.
function M.running(): boolean, integer
  return running ~= nil, running and running.samples or 0
end

--- Stop `jit.profile`. Returns the samples, the seconds and the functions
--- that took the most time. Writes the folded stacks to the file that
--- `start` was given. Fails when it does not run.
function M.stop(): Report
  if not running then
    error("the profiler does not run: `:profile start` starts it", 0)
  end
  profiler().stop()
  local run = running
  running = nil
  local all: {Hot} = {}
  for _, hot in pairs(run.hot) do
    all[#all + 1] = hot
  end
  table.sort(
    all,
    function(a: Hot, b: Hot): boolean
      if a.samples ~= b.samples then
        return a.samples > b.samples
      end
      return a.file .. a.line < b.file .. b.line
    end
  )
  local top: {Hot} = {}
  for i = 1, math.min(M.TOP, #all) do
    top[i] = all[i]
  end
  if run.file then
    local f, err = io.open(run.file, "w")
    if not f then
      error("cannot write the folded stacks: " .. tostring(err), 0)
    end
    for stack, count in pairs(run.folded) do
      f:write(stack, " ", count, "\n")
    end
    f:close()
  end
  return {samples = run.samples, seconds = (api.now() - run.started) / 1000, top = top}
end

-- The address of a place in a Lua file, for the quickfix list:
-- `paw://lua/<file>#<line>`.
local record Place is A.Thing
  file: string
  line: integer
end

local function place_of(parts: A.Parts): Place
  local file = parts.uri:match("^paw://lua/([^#]*)")
  return file and {file = file, line = tonumber(parts.fragment) as integer} or nil
end

A.scheme(
  "lua",
  {
    resolve = function(_: string, parts: A.Parts): A.Thing return place_of(parts) end,
    where = function(_: contracts.Location, parts: A.Parts): string
      local p = place_of(parts)
      return p and (p.file .. ":" .. tostring(p.line)) or ""
    end,
    -- paw has no editor of Lua files: going to one says where it is.
    go = function(_: contracts.Location, parts: A.Parts): boolean
      local p = place_of(parts)
      if not p then
        return false
      end
      paw.notify(p.file .. ":" .. tostring(p.line))
      return true
    end,
  }
)

local function address(hot: Hot): string
  return "paw://lua/" .. hot.file:gsub("#", "%%23") .. "#" .. tostring(hot.line)
end

--- The functions of a report as entries of the quickfix list: the share
--- of the samples, the name, the file and the line.
function M.entries(report: Report): {QfModule.Item}
  local out: {QfModule.Item} = {}
  for i, hot in ipairs(report.top) do
    out[i] = {
      address = address(hot),
      text = string.format(
        "%5.1f%%  %s  %s:%d",
        100 * hot.samples / math.max(report.samples, 1),
        hot.name or "(function)",
        hot.file,
        hot.line
      ),
      source = "profile",
    }
  end
  return out
end

local type Context = commands.Context
local type Result = commands.Result

commands.define(
  "profile",
  function(ctx: Context): Result
    local what = ctx.args[1] as string
    if what == nil then
      local on, samples = M.running()
      paw.notify(
        on and string.format("the profiler runs: %d samples, `:profile stop` stops it", samples)
          or "the profiler does not run: `:profile start` starts it"
      )
    elseif what == "start" then
      local file = ctx.args[2] as string
      M.start(file)
      paw.notify("the profiler runs" .. (file and (", folded stacks to " .. file) or ""))
    elseif what == "stop" then
      local file = running and running.file
      local report = M.stop()
      paw.qf.set(M.entries(report), {title = "Lua profile", source = "profile"})
      paw.qf.open()
      paw.notify(
        string.format(
          "%d samples in %.1f s: the %d functions that took the most time are in the quickfix list%s",
          report.samples,
          report.seconds,
          #report.top,
          file and (", the folded stacks in " .. file) or ""
        )
      )
    else
      error("`:profile start [file]`, `:profile stop` or `:profile`", 0)
    end
  end,
  {
    complete = function(_: string, info: contracts.CompleteInfo): {string}
      return info.index == 1 and {"start", "stop"} or {}
    end,
    desc = "LuaJIT's sampling profiler: `profile start [file]`, `profile stop` puts the 30 Lua functions that took the most time in the quickfix list (and the folded stacks in the file), `profile` says whether it runs",
  }
)

return M
