-- How long the slices of the help index are: the index that paw makes at
-- idle after it starts (the job `help` of `paw.slices`, paw/help.tl). A key
-- that comes during the build waits for the slice that runs.
--   paw --clean --no-plugins -l bench/profile/help.lua [project dir] [alloc]
-- One run makes the index once, as at the start of a session: every page
-- is read, parsed and rendered. Run it a few times for the spread. Prints
-- one JSON line: the slices, the longest slice, the mean slice and the
-- processor time of the build in ms. With `alloc`, the collector is
-- stopped, and the line also gives the MB that the build allocates.
local paw = require("paw")
local api = paw.api
local dir, alloc = ...
if dir and dir ~= "" then
  paw.open(dir)
  paw.flush()
end
local H = paw.help

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
    '{"slices":%d,"longest_ms":%.1f,"mean_slice_ms":%.2f,"build_ms":%.0f%s}',
    job.slices,
    job.longest,
    job.ms / job.slices,
    job.ms,
    alloc == "alloc" and string.format(',"allocated_mb":%.0f', allocated) or ""
  )
)
api.quit(0)
