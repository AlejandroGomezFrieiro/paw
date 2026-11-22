-- Run one day of an end-to-end scenario in this paw process:
--
--   paw --clean --no-plugins --audio null --no-listen [PROJECT] \
--     -l tests/e2e/run.lua SCENARIO DAY SEED WORKDIR [approve|check]
--
-- `check` opens what the days before DAY saved and checks it, with no work:
-- the end of a run.
--
-- tests/tools/e2e.sh starts it once for each day, each time in a new
-- process, on the project that the day before saved. Do not run it by hand
-- or from an agent: see tests/tools/e2e.sh.
local paw = require("paw")
local api = paw.api
local E = dofile("tests/e2e/lib.lua")

local scenario_name, day, seed, workdir, mode = ...
day, seed = tonumber(day), tonumber(seed)
local approve, only_check = mode == "approve", mode == "check"
local scenario = dofile("tests/e2e/scenarios/" .. scenario_name .. ".lua")
assert(only_check or scenario.days[day], "the scenario " .. scenario_name .. " has no day " .. tostring(day))

local golden_path = "tests/e2e/golden/" .. scenario_name .. ".json"
local function read_golden()
  local f = io.open(golden_path, "rb")
  if not f then return {} end
  local text = f:read("*a")
  f:close()
  return api.json_decode(text)
end

local function run()
  -- The days before rebuild the model of what the project holds.
  local model = E.Model.new()
  for d = 1, day - 1 do
    local before = E.new({ scenario = scenario_name, day = d, seed = seed, workdir = workdir, model = model })
    scenario.days[d](before)
  end
  local run = E.new({ scenario = scenario_name, day = day, seed = seed, workdir = workdir, model = model, live = true })
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.focus("arrange")
  if scenario.setup then scenario.setup(run) end
  if day > 1 then run:check_opened() end
  if only_check then
    print(string.format("e2e: %s seed %d: the project of day %d opens as the model says", scenario_name, seed, day - 1))
    return
  end
  run.step = 0
  local messages = #paw.ui.messages
  local start_state, start_id = E.snapshot(), api.undo_current()
  scenario.days[day](run)
  -- The checks of the day, before the save that ends it.
  run.step = run.step + 1
  run:check_undo(start_state, start_id)
  run:check_errors(messages)
  local worst = run:check_keys(100)
  run:check_health()
  local golden = read_golden()
  local key = "seed " .. seed
  local mine = golden[key] and golden[key]["day " .. day]
  local print_ = run:check_render(not approve and mine or nil)
  if approve then
    golden[key] = golden[key] or {}
    golden[key]["day " .. day] = print_
    local f = assert(io.open(golden_path, "wb"))
    -- One line for each seed and day, so that a review sees what changed.
    local seeds = {}
    for k in pairs(golden) do
      seeds[#seeds + 1] = k
    end
    table.sort(seeds)
    local lines = {}
    for _, s in ipairs(seeds) do
      local ds = {}
      for k in pairs(golden[s]) do
        ds[#ds + 1] = k
      end
      table.sort(ds, function(a, b) return tonumber(a:match("%d+")) < tonumber(b:match("%d+")) end)
      local inner = {}
      for _, d in ipairs(ds) do
        inner[#inner + 1] = string.format("    %q: %s", d, api.json_encode(golden[s][d]))
      end
      lines[#lines + 1] = string.format("  %q: {\n%s\n  }", s, table.concat(inner, ",\n"))
    end
    f:write("{\n", table.concat(lines, ",\n"), "\n}\n")
    f:close()
  elseif not mine then
    print(
      string.format("e2e: no approved render for %s %s day %d (tests/tools/e2e.sh --approve)", scenario_name, key, day)
    )
  end
  -- Save, as the user ends the session.
  run:type({ "<Esc>", ":w " .. workdir .. "/project<CR>" })
  if not (paw.ui.message and paw.ui.message.text:find("^saved")) then
    run:fail("save", "the save at the end of the day says: " .. tostring(paw.ui.message and paw.ui.message.text))
  end
  print(
    string.format(
      "e2e: %s seed %d day %d: %d steps, the slowest key %.1f ms (%s)",
      scenario_name,
      seed,
      day,
      run.step,
      worst.ms,
      worst.name
    )
  )
end

local ok, err = xpcall(run, function(e)
  if type(e) == "table" and e.e2e then return e end
  return {
    where = string.format("scenario %s, seed %d, day %d", scenario_name, seed, day),
    text = debug.traceback(tostring(e), 2),
  }
end)
if not ok then
  -- Keep what the day made, beside the project of the day before.
  pcall(paw.project.save, workdir .. "/failed-day" .. day)
  print("E2E FAIL " .. err.where .. "\n" .. err.text)
  print(string.format("repeat: tests/tools/e2e.sh %s --seed %d --days %d", scenario_name, seed, day))
  print("kept: " .. workdir .. " (project = the day before, failed-day" .. day .. " = this day at the failure)")
  api.quit(1)
else
  api.quit(0)
end
