-- Mix diagnostics: measure the mix and report what is wrong with it the way a
-- language server reports problems in code, as findings that each point at a
-- place. See README.md beside this extension.
local api = paw.api

local M = {
  --- The latest measurement, as `paw.api.measure` returned it, and its findings.
  result = nil,
  findings = {},
  --- The measurement running now: { id, range, timer, progress }.
  job = nil,
  severities = { "error", "warn", "info", "hint" },
  rank = { error = 1, warn = 2, info = 3, hint = 4 },
}

--- The event `mixdiag.done`: the findings of a measurement are ready.
M.done = paw.events.event("mixdiag.done")

--- Delivery targets. `kind` says how a target treats loudness:
--- "normalize" (a service turns every part to `integrated`; louder or quieter
--- is a consequence to report, not an error), "deliver" (the programme must
--- be within `tolerance` of `integrated`), or nil (no loudness verdict).
--- Add your own: `require("mixdiag").targets.mine = { ... }`.
M.targets = {
  streaming = {
    name = "streaming (Spotify)",
    kind = "normalize",
    integrated = -14,
    true_peak = -1,
    -- Spotify's advice: under -2 dBTP when the master is louder than -14 LUFS.
    true_peak_loud = -2,
    source = "Spotify for Artists, Loudness normalization (undated page, read 2026-11-06)",
  },
  ebu = {
    name = "EBU R 128",
    kind = "deliver",
    integrated = -23,
    tolerance = 1,
    true_peak = -1,
    source = "EBU R 128 v5 (Nov 2023)",
  },
  none = { name = "no target" },
}

--- The rules, by name. Each is `{ desc, check = function(ctx, add) end }`,
--- with optional thresholds of its own; see rules.lua. Other extensions add
--- theirs here, and `paw.opt.mixdiag_ignore` turns rules off by name.
M.rules = {}

function M.target()
  local name = paw.opt.mixdiag_target
  return M.targets[name] or M.targets.none, name
end

local function project_length() return api.project_get().length end

--- The stretch of the project a scope means: "song", "loop", "selection",
--- "part" (the cursor part's contribution to the song), a table
--- `{ start, ["end"], part }` in beats, or `{ file = path }`.
function M.range(scope)
  scope = scope or "song"
  if type(scope) == "table" then
    local range = paw.util.merge({ label = scope.file and scope.file:match("[^/]+$") or "stretch" }, scope)
    range.kind = range.file and "file" or range.part and "part" or "mix"
    return range
  end
  local length = project_length()
  if scope == "song" then
    if length <= 0 then error("the project has no clips to measure", 0) end
    return { start = 0, ["end"] = length, label = "song", kind = "mix", whole = true }
  elseif scope == "loop" then
    local t = api.transport_get()
    if t.loop_end <= t.loop_start then error("the loop is empty", 0) end
    return { start = t.loop_start, ["end"] = t.loop_end, label = "loop", kind = "mix" }
  elseif scope == "selection" then
    local sel = paw.keymap.selection()
    if not sel then
      local last = paw.keymap.last_visual
      if last and last.view == "arrange" then
        sel = { c0 = math.min(last.col, last.cursor_col), c1 = math.max(last.col, last.cursor_col), kind = last.kind }
        if sel.c1 - sel.c0 < 1e-9 then sel.c1 = sel.c0 + paw.timegrid.step() end
      end
    end
    if not sel then error("nothing selected: select a stretch with `v` first", 0) end
    if sel.kind == "line" or sel.kind == "V" then
      return { start = 0, ["end"] = length, label = "song", kind = "mix", whole = true }
    end
    return { start = sel.c0, ["end"] = sel.c1, label = "selection", kind = "mix" }
  elseif scope == "part" then
    local id = paw.cursor.part_id()
    if not id then error("no part under the cursor", 0) end
    if length <= 0 then error("the project has no clips to measure", 0) end
    return { start = 0, ["end"] = length, part = id, label = api.part_get(id, "name"), kind = "part", whole = true }
  end
  error("unknown scope `" .. tostring(scope) .. "`: song, loop, selection or part", 0)
end

local function measure_args(range)
  if range.file then return { file = range.file } end
  return { start = range.start, ["end"] = range["end"], tail = range.tail or paw.opt.mixdiag_tail, part = range.part }
end

--- Measure and diagnose. Without `opts.wait` the measurement runs on a
--- worker thread and `opts.done(findings)` is called when it is finished;
--- with it, this waits and returns the findings.
function M.analyze(scope, opts)
  opts = opts or {}
  local range = M.range(scope)
  if not range.file then
    -- Extensions that make audio of their own finish it first, as for a render.
    paw.emit("render.before", { path = nil, opts = measure_args(range), measure = true })
    paw.flush()
  end
  if opts.wait then
    local result = api.measure(measure_args(range))
    return M.finish(result, range, opts.quiet)
  end
  M.cancel()
  local id = api.measure_start(measure_args(range))
  M.job = { id = id, range = range, progress = 0, started = api.now(), done = opts.done, quiet = opts.quiet }
  M.job.timer = paw.every(50, function() M.poll() end)
  if not opts.quiet then paw.notify("mix: measuring the " .. range.label .. "…") end
  M.show_strip()
  return id
end

--- Check on a running measurement; called by a timer.
function M.poll()
  local job = M.job
  if not job then return end
  local status = api.measure_poll(job.id)
  if not status.done then
    job.progress = status.progress
    api.ui_redraw()
    return
  end
  paw.cancel(job.timer)
  M.job = nil
  if status.error then
    paw.notify("mix: " .. status.error, "error")
    api.ui_redraw()
    return
  end
  local findings = M.finish(status.result, job.range, job.quiet)
  if job.done then job.done(findings) end
end

function M.cancel()
  local job = M.job
  if not job then return false end
  paw.cancel(job.timer)
  api.measure_cancel(job.id)
  M.job = nil
  api.ui_redraw()
  return true
end

local function ignored()
  local out = {}
  for name in tostring(paw.opt.mixdiag_ignore or ""):gmatch("[%w_]+") do
    out[name] = true
  end
  return out
end

--- What a rule's `check` gets.
function M.context(result, range)
  local target, target_name = M.target()
  paw.time.bar()
  local ctx = {
    result = result,
    range = range,
    kind = range.kind,
    -- The measurement covers the whole song, not a stretch of it.
    whole = range.whole or range.kind == "file",
    target = target,
    target_name = target_name,
    project = api.project_get(),
  }
  --- Beat for a time in seconds from the start of the measurement; nil for a file.
  function ctx.beat(seconds)
    if not result.tempo or not seconds then return nil end
    return paw.tempo.seconds_to_beats(paw.tempo.beats_to_seconds(result.start) + seconds)
  end
  --- "bar 12" for a beat, or "1:23.4" for a time in a file.
  function ctx.where(beat, seconds)
    if beat then return "bar " .. paw.time.bar_of(beat + 1e-9) end
    if seconds then return string.format("%d:%04.1f", math.floor(seconds / 60), seconds % 60) end
    return ""
  end
  function ctx.part_name(id)
    if id == 0 then return "the master" end
    local ok, part = pcall(api.part_get, id)
    return ok and part.name ~= "" and part.name or ("part " .. tostring(id))
  end
  return ctx
end

local function sort_findings(list)
  local order = {}
  for i, id in ipairs(api.part_list()) do
    order[id] = i
  end
  table.sort(list, function(a, b)
    local ab, bb = a.beat or math.huge, b.beat or math.huge
    if ab ~= bb then return ab < bb end
    local at, bt = order[a.part] or 0, order[b.part] or 0
    if at ~= bt then return at < bt end
    return M.rank[a.severity] < M.rank[b.severity]
  end)
  return list
end

--- Run every rule over a measurement.
function M.diagnose(result, range)
  local ctx = M.context(result, range)
  local off, list = ignored(), {}
  local names = {}
  for name in pairs(M.rules) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local rule = M.rules[name]
    if not off[name] and rule.enabled ~= false then
      local function add(f)
        assert(M.rank[f.severity], "a finding needs a severity: error, warn, info or hint")
        f.rule = name
        list[#list + 1] = f
      end
      local ok, err = pcall(rule.check, ctx, add, rule)
      if not ok then paw.notify("mix: rule " .. name .. " failed: " .. tostring(err), "error") end
    end
  end
  return sort_findings(list)
end

--- One line for a finding, as lists show it.
function M.format(f)
  local text = f.message
  if f.fix and f.fix ~= "" then text = text .. "; " .. f.fix end
  return text
end

--- "LUFS -14.2  TP -1.3 dBTP  LRA 6.1 LU" for a measurement.
function M.summary(result)
  result = result or M.result
  if not result then return "no measurement yet" end
  local function num(v, fmt) return v and string.format(fmt, v) or "–" end
  local parts = {
    "LUFS " .. num(result.integrated, "%.1f"),
    "TP " .. num(result.true_peak, "%.1f") .. " dBTP",
    "LRA " .. num(result.lra, "%.1f") .. " LU",
    "S max " .. num(result.short_term_max, "%.1f"),
  }
  if result.mono_loss then parts[#parts + 1] = string.format("mono loss %.1f dB", result.mono_loss) end
  return table.concat(parts, "  ")
end

function M.finish(result, range, quiet)
  M.result, M.range_measured = result, range
  M.measured_at = api.now()
  M.findings = M.diagnose(result, range)
  local counts = {}
  for _, f in ipairs(M.findings) do
    counts[f.severity] = (counts[f.severity] or 0) + 1
  end
  local tally = {}
  for _, s in ipairs(M.severities) do
    if counts[s] then tally[#tally + 1] = counts[s] .. " " .. s end
  end
  M.line = string.format(
    "mix (%s): %s  │ %s  │ %.1f s",
    range.label,
    M.summary(result),
    #tally > 0 and table.concat(tally, ", ") or "no findings",
    result.elapsed or 0
  )
  if not quiet then
    local worst = M.findings[1] and "info"
    for _, f in ipairs(M.findings) do
      if f.severity == "error" then
        worst = "error"
      elseif f.severity == "warn" and worst ~= "error" then
        worst = "warn"
      end
    end
    paw.notify(M.line, worst == "error" and "warn" or "info")
  end
  paw.emit(M.done, { count = #M.findings })
  require("mixdiag.lens").publish()
  M.show_strip()
  api.ui_redraw()
  return M.findings
end

--- Whether the project changed since the measurement.
function M.stale() return M.result and M.result.edits ~= nil and api.project_get("edits") ~= M.result.edits end

function M.clear()
  M.cancel()
  M.result, M.findings, M.line = nil, {}, nil
  require("mixdiag.lens").publish()
  M.hide_strip()
  -- The findings' band in the graphical frontend goes too.
  paw.frontend.refresh()
end

--- Findings that have a place on the timeline, for a ruler: { beat, severity, text }.
function M.marks()
  local out = {}
  for _, f in ipairs(M.findings) do
    if f.beat then out[#out + 1] = { beat = f.beat, severity = f.severity, text = M.format(f), part = f.part } end
  end
  return out
end

-- Moving between findings ------------------------------------------------------

local function placed()
  local out = {}
  for _, f in ipairs(M.findings) do
    if f.beat then out[#out + 1] = f end
  end
  return out
end

--- Row of a finding's part in the arrange view, or nil for the master and
--- findings about the whole mix.
local function row_of(f)
  if not f.part or f.part == 0 then return nil end
  for i, id in ipairs(api.part_list()) do
    if id == f.part then return i end
  end
end

--- Put the cursor on a finding and show its message.
function M.jump(f)
  if f.part and f.part ~= 0 and pcall(api.part_get, f.part) then paw.cursor.set_part(f.part) end
  if f.beat then paw.cursor.set_beat(math.max(0, f.beat)) end
  M.current = f
  paw.notify(
    string.format("%s: %s", f.severity, M.format(f)),
    f.severity == "error" and "error" or f.severity == "warn" and "warn" or "info"
  )
end

--- The next (`dir` 1) or previous (-1) finding from the cursor, `count` times,
--- wrapping around the ends.
function M.step(dir, count)
  local list = placed()
  if #list == 0 then
    paw.notify(M.result and "mix: no findings with a place" or "mix: nothing measured yet: <leader>ma", "warn")
    return nil
  end
  local beat = paw.cursor.beat
  local row = paw.cursor.index() or 0
  -- On a finding about the master, the cursor's part says nothing about
  -- where in the list we are: the finding last jumped to does.
  local current = M.current
  if current and current.beat and math.abs(current.beat - beat) <= 1e-6 then row = row_of(current) or 0 end
  local found
  for _ = 1, count or 1 do
    found = nil
    local function key(f) return f.beat, row_of(f) or 0 end
    if dir > 0 then
      for _, f in ipairs(list) do
        local b, r = key(f)
        if b > beat + 1e-6 or (math.abs(b - beat) <= 1e-6 and r > row) then
          found = f
          break
        end
      end
      found = found or list[1]
    else
      for i = #list, 1, -1 do
        local b, r = key(list[i])
        if b < beat - 1e-6 or (math.abs(b - beat) <= 1e-6 and r < row) then
          found = list[i]
          break
        end
      end
      found = found or list[#list]
    end
    beat, row = key(found)
  end
  M.jump(found)
  return found
end

-- The list -------------------------------------------------------------------

--- Items for a list of findings: { text, beat, part, finding }.
function M.items()
  local ctx = M.result and M.context(M.result, M.range_measured or { kind = "mix" })
  local items = {}
  for _, f in ipairs(M.findings) do
    local where = ctx and ctx.where(f.beat, f.seconds) or ""
    local part = f.part and f.part ~= 0 and ctx and ctx.part_name(f.part) or ""
    local text = string.format(
      "%-5s  %-9s %-10s %s",
      f.severity,
      where,
      paw.util.fit and paw.util.fit(part, 10) or part,
      M.format(f)
    )
    items[#items + 1] = { text = text, beat = f.beat, part = f.part, finding = f, severity = f.severity }
  end
  return items
end

--- Show the findings: in the picker when there is one, else in a list of our own.
function M.list()
  if not M.result then return paw.notify("mix: nothing measured yet: <leader>ma", "warn") end
  if paw.pick then
    return paw.pick({
      title = "Mix",
      items = M.items(),
      on_choose = function(item)
        if item and item.finding then M.jump(item.finding) end
      end,
    })
  end
  require("mixdiag.view").open()
end

--- The report: what was measured, the numbers and the findings, with keys
--- to measure again. Floating in the terminal; in a window of its own in
--- the graphical frontend.
function M.report() require("mixdiag.view").open() end

-- The strip of marks above the arrange view ----------------------------------

function M.show_strip()
  if not paw.opt.mixdiag_strip then return end
  require("mixdiag.view").strip(true)
end

function M.hide_strip() require("mixdiag.view").strip(false) end

return M
