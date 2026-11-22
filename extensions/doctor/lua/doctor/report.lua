-- The report: what is known of the machine, what each check found, and what
-- changed since the report before. Written as Markdown, with the same in
-- JSON beside it for the next report to compare with.
local api = paw.api

local MARKS = { ok = "ok", warn = "WARN", fail = "FAIL", skip = "skipped" }

local function read(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

local function cell(text) return (tostring(text or ""):gsub("|", "\\|"):gsub("\n", " ")) end

local function seconds(s)
  if s < 90 then return string.format("%.0f s", s) end
  return string.format("%d min %02d s", math.floor(s / 60), math.floor(s % 60))
end

return function(M, util)
  --- What is known of the machine, as `{ label, value }` in order.
  function M.machine()
    local e = api.engine_get()
    local env = api.env()
    local out = {}
    local function add(label, value)
      if value and value ~= "" then out[#out + 1] = { label, tostring(value) } end
    end
    local function line(path) return (read(path) or ""):match("^[^\n]*") end
    add("Program", "paw " .. tostring(paw.version))
    add("Kernel", line("/proc/sys/kernel/osrelease"))
    add("System", (read("/etc/os-release") or ""):match('PRETTY_NAME="?([^"\n]*)"?'))
    add("Host", line("/proc/sys/kernel/hostname"))
    local cpu = read("/proc/cpuinfo") or ""
    local _, cores = cpu:gsub("\nprocessor", "")
    add(
      "Processor",
      string.format(
        "%s, %d threads",
        cpu:match("model name%s*:%s*([^\n]*)") or "unknown",
        cores + (cpu:match("^processor") and 1 or 0)
      )
    )
    local memory = tonumber((read("/proc/meminfo") or ""):match("MemTotal:%s*(%d+)"))
    add("Memory", memory and string.format("%.1f GB", memory / 1048576))
    add("Sound system", e.backend)
    add("Output", e.device)
    add("Input", e.input_device)
    add("Sample rate", string.format("%d Hz", e.sample_rate))
    add("Block", e.block > 0 and (e.block .. " frames") or "not known yet")
    add(
      "Display",
      string.format(
        "DISPLAY=%s WAYLAND_DISPLAY=%s",
        os.getenv("DISPLAY") or "unset",
        os.getenv("WAYLAND_DISPLAY") or "unset"
      )
    )
    add("Configuration", env.clean and "none (--clean)" or env.config_dir)
    add("State directory", env.state_dir)
    return out
  end

  local function summary_of(run)
    local checks = {}
    for _, r in ipairs(run.done) do
      checks[#checks + 1] = { id = r.id, name = r.name, status = r.status, summary = r.summary, facts = r.facts }
    end
    local machine = {}
    for _, m in ipairs(run.machine) do
      machine[m[1]] = m[2]
    end
    return { version = 1, time = os.time(), attended = run.attended, machine = machine, checks = checks }
  end

  --- The report before this one: its JSON, and its name.
  local function previous(run)
    local newest
    for _, entry in ipairs(api.read_dir(M.dir())) do
      local name = entry.name:match("^(%d%d%d%d%-.+)%.json$")
      if name and (not newest or name > newest) then newest = name end
    end
    if not newest then return nil end
    local decoded = paw.json.decode(read(M.dir() .. "/" .. newest .. ".json") or "")
    return decoded, newest
  end

  --- What changed from `old` to `new` (both as `summary_of` makes them), as lines.
  function M.changes(old, new)
    local out = {}
    local labels = {}
    for label in pairs(old.machine or {}) do
      labels[label] = true
    end
    for label in pairs(new.machine or {}) do
      labels[label] = true
    end
    local names = {}
    for label in pairs(labels) do
      names[#names + 1] = label
    end
    table.sort(names)
    for _, label in ipairs(names) do
      local a, b = (old.machine or {})[label], (new.machine or {})[label]
      if a ~= b then out[#out + 1] = string.format("- %s: %s → %s", label, a or "not known", b or "not known") end
    end
    local was = {}
    for _, c in ipairs(old.checks or {}) do
      was[c.id] = c
    end
    for _, c in ipairs(new.checks or {}) do
      local p = was[c.id]
      if not p then
        out[#out + 1] = string.format("- %s: new, %s", c.name, MARKS[c.status] or c.status)
      elseif p.status ~= c.status and p.status ~= "skip" and c.status ~= "skip" then
        out[#out + 1] = string.format(
          "- %s: %s → %s (%s)",
          c.name,
          MARKS[p.status] or p.status,
          MARKS[c.status] or c.status,
          c.summary
        )
      end
      if p and p.status ~= "skip" and c.status ~= "skip" then
        local keys = {}
        for key in pairs(c.facts or {}) do
          keys[#keys + 1] = key
        end
        for key in pairs(p.facts or {}) do
          if (c.facts or {})[key] == nil then keys[#keys + 1] = key end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
          local a, b = (p.facts or {})[key], (c.facts or {})[key]
          if tostring(a) ~= tostring(b) then
            out[#out + 1] = string.format(
              "- %s, %s: %s → %s",
              c.name,
              key,
              a == nil and "not there" or tostring(a),
              b == nil and "not there" or tostring(b)
            )
          end
        end
      end
    end
    return out
  end

  --- The report as Markdown.
  function M.markdown(run)
    run.machine = run.machine or M.machine()
    local lines = {}
    local function add(text) lines[#lines + 1] = text or "" end
    add("# paw doctor, " .. os.date("%Y-%m-%d %H:%M", math.floor(run.started_at or os.time())))
    add()
    add(
      string.format(
        "%s run, %s. Written by `:doctor` or `paw doctor`.",
        run.attended and "An attended" or "An unattended",
        seconds(((run.finished or api.now()) - run.started) / 1000)
      )
    )
    add()
    add("## This machine")
    add()
    add("| | |")
    add("| --- | --- |")
    for _, m in ipairs(run.machine) do
      add("| " .. cell(m[1]) .. " | " .. cell(m[2]) .. " |")
    end
    add()
    add("## Result")
    add()
    add("| Check | Result | What was found |")
    add("| --- | --- | --- |")
    for _, r in ipairs(run.done) do
      add(string.format("| %s | %s | %s |", cell(r.name), MARKS[r.status] or r.status, cell(r.summary)))
    end
    add()
    local now = summary_of(run)
    if run.before then
      add("## Changed since the report of " .. run.before_name)
      add()
      local changes = M.changes(run.before, now)
      if #changes == 0 then add("Nothing that is compared has changed.") end
      for _, change in ipairs(changes) do
        add(change)
      end
      add()
    end
    for index, r in ipairs(run.done) do
      add(string.format("## %d. %s: %s", index, r.name, MARKS[r.status] or r.status))
      add()
      if r.summary ~= "" then
        add(r.summary)
        add()
      end
      for _, text in ipairs(r.lines) do
        add("- " .. text:gsub("\n", "\n  "))
      end
      if #r.lines > 0 then add() end
      if #r.fact_order > 0 or #r.measure_order > 0 then
        for _, key in ipairs(r.fact_order) do
          add(string.format("- `%s`: %s", key, tostring(r.facts[key])))
        end
        for _, key in ipairs(r.measure_order) do
          add(string.format("- `%s`: %s (measured)", key, tostring(r.measures[key])))
        end
        add()
      end
      if r.seconds then
        add(string.format("Took %s.", seconds(r.seconds)))
        add()
      end
    end
    if run.problem then
      add("## Problem")
      add()
      add(run.problem)
      add()
    end
    return table.concat(lines, "\n")
  end

  --- Write the report (and its JSON) into the doctor's directory. Returns the path.
  function M.write_report(run)
    run.started_at = os.time() - math.floor((api.now() - run.started) / 1000)
    run.machine = M.machine()
    run.before, run.before_name = previous(run)
    util.mkdir(M.dir())
    local base = util.stamp()
    local file = assert(io.open(base .. ".md", "w"))
    file:write(M.markdown(run), "\n")
    file:close()
    local json = assert(io.open(base .. ".json", "w"))
    json:write(paw.json.encode(summary_of(run)))
    json:close()
    return base .. ".md"
  end
end
