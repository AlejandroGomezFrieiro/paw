-- How long the slices of the help index are: the index that paw makes at
-- idle after it starts (the job `help` of `paw.slices`, paw/help.tl). A key
-- that comes during the build waits for the slice that runs.
--   paw --clean --no-plugins -l bench/profile/help.lua [project dir] [alloc]
-- One run makes the index once, as at the start of a session: every page
-- is read, parsed and rendered. Run it a few times for the spread. Prints
-- one JSON line: the slices, the slices over 5 ms (`paw.opt.budget_ms`,
-- the slow-key warnings), the longest slice, the mean slice and the time
-- of the build in ms. With `alloc`, the collector is stopped, and the
-- line also gives the MB that the build allocates.
local paw = require("paw")
local api = paw.api
local dir, alloc = ...
if dir and dir ~= "" then
  paw.open(dir)
  paw.flush()
end
local H = paw.help
local BUDGET_MS = 5
paw.opt.budget_ms = BUDGET_MS

-- The slices of the build that went over the budget: `paw.slices` names
-- each slice "the job help" (paw/limit.tl counts it in `paw.limit.slow`).
local function over_budget()
  for _, s in ipairs(paw.limit.slow) do
    if s.name == "the job help" then return s.times end
  end
  return 0
end

collectgarbage("collect")
local kb = collectgarbage("count")
if alloc == "alloc" then collectgarbage("stop") end
H.dirty = true
local job = H.prepare()
while H.preparing() do
  paw.wait(1)
end
local allocated = (collectgarbage("count") - kb) / 1024
collectgarbage("restart")

print(
  string.format(
    '{"slices":%d,"over_%dms":%d,"longest_ms":%.1f,"mean_slice_ms":%.2f,"build_ms":%.0f%s}',
    job.slices,
    BUDGET_MS,
    over_budget(),
    job.longest,
    job.ms / job.slices,
    job.ms,
    alloc == "alloc" and string.format(',"allocated_mb":%.0f', allocated) or ""
  )
)
api.quit(0)
