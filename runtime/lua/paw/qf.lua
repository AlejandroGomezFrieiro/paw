-- The quickfix list, as Neovim's: one shared place for what is wrong (or
-- found) anywhere in the project, each entry with an address (paw/address.tl)
-- to go to, and maybe a fix. docs/reference/quickfix.md says how it is used,
-- docs/reference/lua-addresses.md how to fill it.
--
-- An entry is `{ address, selector?, text, level?, source, fix? }`:
-- `address` a `paw://` address (or a location, `{ uri, selector }`),
-- `level` "error", "warning", "info" or "hint" (or 1 to 4; none for a
-- plain match), `fix` `{ title, edit = { workspace changes } }`,
-- `{ title, apply = function(entry) end }` or a command line run with the
-- cursor on the entry.
--
-- Lists are kept in a history of ten (`:colder`, `:cnewer`); each has a
-- title. The quickfix lists are shared; every window has location lists of
-- its own (`:lopen`, `:lnext`). One quickfix list, "Problems", is kept by
-- the program: each source (`paw.qf.feed`) owns its entries in it, and the
-- program feeds it the diagnostics, renders that clipped, were too loud or
-- failed, missing sound files, plugins that stopped or are not installed,
-- and plugin files that could not be looked into.
local api = paw.api
local A = paw.address

local M = {}

paw.option.define("qf_height", 10)            -- rows of the window `:copen` opens
paw.option.define("qf_diagnostics", "warning") -- diagnostics this severe and worse go into Problems; "hint" for all, "off" for none
paw.option.define("render_loudest", -9)       -- LUFS: a render louder than this is listed as too loud

M.HISTORY = 10
M.PROBLEMS = "Problems"

local LEVELS = { "error", "warning", "info", "hint" }
local by_word = { error = 1, e = 1, warning = 2, warn = 2, w = 2, info = 3, information = 3, i = 3, hint = 4, h = 4 }

--- A severity from 1 (error) to 4 (hint) from a number or a word. Nil for none.
local function severity_of(level)
  if level == nil or level == false then return nil end
  if type(level) == "number" then return math.max(1, math.min(4, math.floor(level))) end
  return by_word[tostring(level):lower()]
end
M.severity_of = severity_of

-- Stacks of lists: the quickfix one, and each window's location lists.
local next_id = 0
local function new_stack() return { lists = {}, at = 0 } end
local quickfix = new_stack()
local locations = {}   -- window number -> stack

--- The quickfix lists.
function M.stack() return quickfix end

--- The location lists of a window (of the current window without `win`),
--- made when you ask with `make`. A window that shows a location list uses
--- the list that it shows, as in Neovim.
function M.loc_stack(win, make)
  if not win then
    local cur = paw.layout.current()
    local buf = cur and cur.view == "qflist" and paw.layout.buf_of(cur)
    win = buf and type(buf.target) == "number" and buf.target or (cur and cur.id)
  end
  if not win then return nil end
  if not locations[win] and make then locations[win] = new_stack() end
  return locations[win], win
end

-- Entries ------------------------------------------------------------------------

--- An entry as the list keeps it: `{ address, location, text, level,
--- severity, source, fix, data }`.
function M.entry(e, source)
  local loc = e.location
  if not loc and type(e.address) == "table" then loc = e.address end
  if not loc and e.address then loc = { uri = e.address, selector = e.selector } end
  local severity = severity_of(e.level or e.severity)
  local fix = e.fix
  if fix == nil and type(e.fixes) == "table" then fix = e.fixes[1] end
  return {
    address = loc and loc.uri, location = loc, text = tostring(e.text or e.message or ""),
    severity = severity, level = severity and LEVELS[severity] or nil,
    source = e.source or source, fix = fix, data = e.data,
  }
end

local function key_of(e) return tostring(e.address) .. "\0" .. e.text end

local function make_list(title, entries)
  next_id = next_id + 1
  return { id = next_id, title = title or "", entries = entries or {}, idx = 0 }
end

-- Put new entries in a list, keeping the entry that was current where it is.
local function replace(list, entries)
  local was = list.entries[list.idx]
  list.entries = entries
  list.idx = 0
  if was then
    for i, e in ipairs(entries) do
      if key_of(e) == key_of(was) then list.idx = i break end
    end
  end
end

local function find(stack, title)
  for i, list in ipairs(stack.lists) do
    if list.title == title then return list, i end
  end
end

-- Add a list after the current one, dropping the newer, as Neovim does;
-- the oldest goes past ten.
local function push(stack, list, current)
  if current ~= false then
    for i = #stack.lists, stack.at + 1, -1 do stack.lists[i] = nil end
  end
  stack.lists[#stack.lists + 1] = list
  while #stack.lists > M.HISTORY do
    table.remove(stack.lists, 1)
    stack.at = stack.at - 1
  end
  if current ~= false or stack.at < 1 then stack.at = #stack.lists end
end

local refresh

--- The current list of a stack (the quickfix lists by default), or nil.
function M.current(stack)
  refresh()
  stack = stack or quickfix
  return stack.lists[stack.at]
end

--- Put a list of entries in the quickfix lists (the location lists of a
--- window with `opts.win`, of the current window with `opts.win = true`),
--- with the title `opts.title`, and make it current. A list with the same
--- title in the history is replaced at its place. Its current entry stays.
--- `opts.current = false` keeps a different list current. Returns the list.
---   paw.qf.set({ { address = "paw://track/3", text = "too quiet", level = "warning" } }, { title = "Levels" })
function M.set(entries, opts)
  opts = opts or {}
  local stack = quickfix
  if opts.win then stack = M.loc_stack(opts.win ~= true and opts.win or nil, true) end
  assert(stack, "no window for a location list")
  local list_entries = {}
  for i, e in ipairs(entries or {}) do list_entries[i] = M.entry(e, opts.source or opts.title) end
  local title = opts.title or ""
  local list, at = find(stack, title)
  if list then
    replace(list, list_entries)
    if opts.current ~= false then stack.at = at end
  else
    list = make_list(title, list_entries)
    push(stack, list, opts.current)
  end
  api.ui_redraw()
  paw.emit("qf.changed", { title = title, win = opts.win })
  return list
end

-- Problems: what each source says, kept by source ---------------------------------

local feeds = {}       -- source -> entries
local pulls = {}       -- source -> function giving its entries
local dirty = {}       -- sources to ask again
local ORDER = { "diagnostic", "render", "media", "plugins", "plugin scan" }

local function problems_entries()
  local names = {}
  for name in pairs(feeds) do names[#names + 1] = name end
  local rank = {}
  for i, name in ipairs(ORDER) do rank[name] = i end
  table.sort(names, function(a, b)
    local ra, rb = rank[a] or 99, rank[b] or 99
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  local out = {}
  for _, name in ipairs(names) do
    for _, e in ipairs(feeds[name]) do out[#out + 1] = e end
  end
  -- The worst first, each source's own order kept within a level.
  local order = {}
  for i, e in ipairs(out) do order[e] = i end
  table.sort(out, function(a, b)
    local sa, sb = a.severity or 5, b.severity or 5
    if sa ~= sb then return sa < sb end
    return order[a] < order[b]
  end)
  return out
end

local function store_problems()
  local entries = problems_entries()
  local list = find(quickfix, M.PROBLEMS)
  if list then
    replace(list, entries)
  elseif #entries > 0 then
    -- Made by the program, it does not take the place of the list being
    -- worked through.
    local current = quickfix.lists[quickfix.at]
    push(quickfix, make_list(M.PROBLEMS, entries), not (current and #current.entries > 0) and true or false)
  end
  api.ui_redraw()
  paw.emit("qf.changed", { title = M.PROBLEMS })
end

--- The current entries of a source, in the Problems list. These entries
--- replace the old entries of the source (none removes them). Each
--- extension can feed it.
---   paw.qf.feed("tuning", { { address = "paw://clip/4", text = "out of tune", level = "warning" } })
function M.feed(source, entries)
  local list = {}
  for i, e in ipairs(entries or {}) do list[i] = M.entry(e, source) end
  feeds[source] = #list > 0 and list or nil
  store_problems()
end

--- A source that paw asks for its entries when they can change. `fn()`
--- returns them. paw calls it again after `paw.qf.changed(source)`, one
--- time, when a user next looks at the list.
function M.source(source, fn)
  pulls[source] = fn
  dirty[source] = true
  api.ui_redraw()
end

--- Tell paw that the entries of a source can be different now.
function M.changed(source)
  if pulls[source] then
    dirty[source] = true
    api.ui_redraw()
  end
end

local refreshing = false
refresh = function()
  if refreshing or not next(dirty) then return end
  refreshing = true
  local ok, err = pcall(function()
    local any = false
    for source in pairs(dirty) do
      dirty[source] = nil
      local fn = pulls[source]
      local okf, entries = pcall(fn)
      if not okf then
        paw.api.log("qf: " .. source .. ": " .. tostring(entries))
        entries = {}
      end
      local list = {}
      for i, e in ipairs(entries or {}) do list[i] = M.entry(e, source) end
      local before = feeds[source]
      feeds[source] = #list > 0 and list or nil
      any = any or before ~= nil or #list > 0
    end
    if any then store_problems() end
  end)
  refreshing = false
  if not ok then error(err, 0) end
end
--- Read every source of the Problems list again.
M.refresh = function() refresh() end

--- What a source has in the Problems list now.
function M.fed(source)
  refresh()
  return feeds[source] or {}
end

-- Where an entry is, in words ------------------------------------------------------

--- The subject of an entry, in a few words: `Bass 3.1.00`, `Lead › Synth`,
--- `mix.wav`. Empty without an address.
function M.where(e)
  local loc = e.location
  if not loc then return "" end
  local p = A.parse(loc.uri)
  local t = loc.selector and loc.selector.time
  local scheme = p and A.schemes[p.kind]
  if scheme and scheme.where then return scheme.where(loc, p) end
  if p and p.kind == "lane" then
    local ok, lane = pcall(api.lane_get, p.lane)
    return (ok and paw.lanes.name(lane) or "a lane") .. (t and (" " .. paw.time.format(t[1])) or "")
  end
  if p and p.kind == "marker" then
    local m = A.resolve(loc.uri)
    return m and (m.name or "marker") .. " " .. paw.time.format(m.beat or m.start or 0) or "a marker"
  end
  return paw.diagnostic.where({ location = loc, at = t and t[1] or 0 })
end

--- An entry in one line, as said when going to it: `(2 of 7) error: …`.
function M.format(e, list)
  local at = ""
  if list then
    for i, x in ipairs(list.entries) do
      if x == e then at = string.format("(%d of %d) ", i, #list.entries) end
    end
  end
  return string.format("%s%s%s%s", at, e.level and (e.level .. ": ") or "", e.text, e.source and (" [" .. e.source .. "]") or "")
end

-- Going to an entry ------------------------------------------------------------------

local GONE = { clip = true, note = true, control = true, track = true, device = true, param = true, send = true, lane = true }

--- Put the cursor on the address of an entry, in the view that shows it
--- best, and focus that view. A note goes to the piano roll, and a device
--- or a parameter to the device panel. A clip, a track, a lane or a range
--- of time goes to the arrange view. Returns true if there was a place to go.
function M.go(e)
  local loc = e.location
  if not loc then return false end
  local p = A.parse(loc.uri)
  if not p then return false end
  if GONE[p.kind] and not A.resolve(loc.uri) then
    paw.notify("what this entry is about is gone", "warn")
    return false
  end
  -- An address of an extension's own kind goes where the kind says.
  local scheme = A.schemes[p.kind]
  if scheme and scheme.go then return scheme.go(loc, p) ~= false end
  if p.kind == "lane" then
    local lane = api.lane_get(p.lane)
    local arrange = paw.ui.locators.arrange
    paw.ui.focus("arrange")
    arrange.go(loc)
    if lane.track then
      paw.lanes.open(lane.track, true)
      paw.cursor.set_track(lane.track, p.lane)
    end
    return true
  end
  -- A clip of audio, or one named as a whole, is gone to in the arrange view.
  if p.kind == "clip" and not (loc.selector and loc.selector.notes) then
    local c = api.clip_get(p.clip)
    if c.kind == "audio" or not loc.selector then
      paw.ui.focus("arrange")
      paw.ui.locators.arrange.go(loc)
      return true
    end
  end
  for _, name in ipairs({ "pianoroll", "devices", "arrange", "mixer" }) do
    local locator = paw.ui.locators[name]
    if locator and locator.place(loc, true) then
      paw.ui.go(loc)
      return true
    end
  end
  return false
end

local function say(e, list)
  paw.notify(M.format(e, list), e.severity == 1 and "error" or e.severity == 2 and "warn" or "info")
end

--- Make entry `n` of a stack's current list the current entry and go to it.
function M.jump(n, stack)
  local list = M.current(stack)
  if not list or #list.entries == 0 then return paw.notify("no entries" .. (list and " in " .. list.title or ""), "warn") end
  n = math.max(1, math.min(#list.entries, n))
  list.idx = n
  local e = list.entries[n]
  M.go(e)
  say(e, list)
  api.ui_redraw()
  return e
end

--- Go `count` entries forward (back, when negative) from the current entry.
--- The first `]q` goes to the first entry. It stops at the ends, as Neovim does.
function M.step(count, stack)
  local list = M.current(stack)
  if not list or #list.entries == 0 then return paw.notify("no entries" .. (list and " in " .. list.title or ""), "warn") end
  local at = list.idx
  if at == 0 then at = count > 0 and 0 or #list.entries + 1 end
  local to = at + count
  if (count > 0 and at >= #list.entries) or (count < 0 and at <= 1) then
    return paw.notify(count > 0 and "no more entries: this is the last" or "no more entries: this is the first", "warn")
  end
  return M.jump(to, stack)
end

--- Go to the list's first entry, or its last.
function M.first(stack) return M.jump(1, stack) end
--- Go to the list's last entry.
function M.last(stack) return M.jump(math.huge, stack) end

--- Go to an older list in the history (`count` back), or a newer one.
function M.older(count, stack)
  stack = stack or quickfix
  refresh()
  if #stack.lists == 0 then return paw.notify("no lists", "warn") end
  local to = stack.at - (count or 1)
  if to < 1 or to > #stack.lists then
    return paw.notify((count or 1) > 0 and "no older list" or "no newer list", "warn")
  end
  stack.at = to
  local list = stack.lists[to]
  paw.notify(string.format("list %d of %d: %s, %d entr%s", to, #stack.lists, list.title, #list.entries, #list.entries == 1 and "y" or "ies"))
  api.ui_redraw()
  return list
end

--- Go to a newer list in the history (`count` on).
function M.newer(count, stack) return M.older(-(count or 1), stack) end

-- Counts and the status line ----------------------------------------------------------

--- How many entries of each level a list has: `{ error, warning, info, hint, total }`.
function M.count(list)
  local out = { error = 0, warning = 0, info = 0, hint = 0, total = 0 }
  for _, e in ipairs(list and list.entries or {}) do
    if e.level then out[e.level] = out[e.level] + 1 end
    out.total = out.total + 1
  end
  return out
end

--- The part of the status line while the quickfix list has entries:
--- `qf 2/7 E2 W5`, with the position after you go to an entry. Nil when the
--- list is empty.
function M.status()
  local list = M.current()
  if not list or #list.entries == 0 then return nil end
  local n = M.count(list)
  local pieces = { { "qf", "StatusDim" } }
  if list.idx > 0 then pieces[#pieces + 1] = { string.format(" %d/%d", list.idx, n.total), "StatusLine" } end
  local any = false
  for i, word in ipairs(LEVELS) do
    if n[word] > 0 then
      any = true
      pieces[#pieces + 1] = { " " .. ("EWIH"):sub(i, i) .. n[word], i == 1 and "StatusError" or i == 2 and "StatusWarn" or "StatusDim" }
    end
  end
  if not any and list.idx == 0 then pieces[#pieces + 1] = { " " .. n.total, "StatusLine" } end
  return pieces
end

-- Doing things over the entries ------------------------------------------------------------

--- Run a command line on each entry of the current list of a stack (`:cdo`),
--- all as one undo step. For each entry, the cursor goes to the entry
--- first. The command gets the address as `ctx.target`, and the whole
--- location as `ctx.location`. With `per_track`, it runs one time for each
--- track of the entries (`:cfdo`). Returns how many times it ran.
function M.cdo(line, opts)
  opts = opts or {}
  line = tostring(line or ""):match("^%s*:?(.-)%s*$")
  if line == "" then return paw.notify("usage: cdo <command>, run on every entry", "warn") end
  local list = M.current(opts.stack)
  if not list or #list.entries == 0 then return paw.notify("no entries", "warn") end
  local targets, seen = {}, {}
  for i, e in ipairs(list.entries) do
    if opts.per_track then
      local key = e.address and (A.track_of(e.address) or e.address) or ""
      if not seen[key] then
        seen[key] = true
        targets[#targets + 1] = i
      end
    else
      targets[#targets + 1] = i
    end
  end
  local done, failed = 0, nil
  for _, i in ipairs(targets) do
    local e = list.entries[i]
    list.idx = i
    M.go(e)
    local ok, err = pcall(paw.commands.exec, line, { target = e.address, location = e.location, entry = e })
    if ok then done = done + 1 else failed = failed or tostring(err) end
  end
  api.ui_redraw()
  if failed then paw.notify(string.format("ran on %d of %d: %s", done, #targets, failed), "error") end
  return done
end

--- Do the fixes of entries as one undo step: each entry with a fix in the
--- current list of a stack, or the given entries. Returns how many.
function M.fix(entries, opts)
  opts = opts or {}
  if not entries then
    local list = M.current(opts.stack)
    entries = list and list.entries or {}
  end
  local edits, rest = {}, {}
  for _, e in ipairs(entries) do
    local fix = e.fix
    if type(fix) == "table" and fix.edit then
      for _, change in ipairs(fix.edit) do edits[#edits + 1] = change end
      if #fix.edit > 0 then edits[#edits].entry = e end
    elseif fix then
      rest[#rest + 1] = e
    end
  end
  local n = 0
  api.undo_label(opts.label or "Fix")
  if #edits > 0 then
    local ok = A.edit(edits)
    if ok then
      for _, change in ipairs(edits) do
        if change.entry then n = n + 1 end
      end
    else
      -- One that cannot be made does not hold the others back.
      for _, e in ipairs(entries) do
        if type(e.fix) == "table" and e.fix.edit then
          local made, why = A.edit(e.fix.edit)
          if made then n = n + 1 else paw.notify("a fix cannot be made: " .. tostring(why), "warn") end
        end
      end
    end
  end
  for _, e in ipairs(rest) do
    local ok, err = pcall(function()
      if type(e.fix) == "string" then
        M.go(e)
        paw.commands.exec(e.fix, { target = e.address, location = e.location, entry = e })
      else
        e.fix.apply(e)
      end
    end)
    if ok then n = n + 1 else paw.notify("a fix failed: " .. tostring(err), "warn") end
  end
  for _, e in ipairs(entries) do
    if e.fix then e.fixed = true end
  end
  api.ui_redraw()
  return n
end

--- The title of an entry's fix, or nil.
function M.fix_title(e)
  local fix = e.fix
  if type(fix) == "string" then return ":" .. fix end
  return fix and (fix.title or "Fix") or nil
end

-- Diagnostics -------------------------------------------------------------------------------

--- Diagnostics as entries (as `paw.diagnostic.get` takes `target` and `filter`).
function M.from_diagnostics(target, filter)
  local out = {}
  for _, d in ipairs(paw.diagnostic.get(target, filter)) do
    out[#out + 1] = {
      location = d.location, level = d.severity, source = d.source,
      text = (d.rule and (d.rule .. ": ") or "") .. d.message, fix = d.fixes[1], data = { diagnostic = d },
    }
  end
  return out
end

--- Put diagnostics in a list, as `vim.diagnostic.setqflist`: `opts` has
--- `target` and `severity` (as `paw.diagnostic.get` takes them), `title`
--- ("Diagnostics"), `win` for a location list, `open` to open its window.
function M.diagnostics(opts)
  opts = opts or {}
  local filter = opts.severity and { severity = { min = opts.severity } } or nil
  local list = M.set(M.from_diagnostics(opts.target, filter), { title = opts.title or "Diagnostics", win = opts.win })
  if opts.open then M.open({ loc = opts.win ~= nil, win = type(opts.win) == "number" and opts.win or nil }) end
  return list
end

M.source("diagnostic", function()
  local least = paw.opt.qf_diagnostics
  if least == false or least == "off" then return {} end
  return M.from_diagnostics(nil, { severity = { min = severity_of(least) or 2 } })
end)
paw.on("diagnostic.changed", function() M.changed("diagnostic") end)
paw.on("option.changed", function(e) if e.name == "qf_diagnostics" then M.changed("diagnostic") end end)
-- A diagnostic goes with what it is about.
paw.on("changed", function() if feeds.diagnostic then M.changed("diagnostic") end end)

-- Renders --------------------------------------------------------------------------------

local render_opts, renders = {}, {}   -- by path: the options asked for, the entries
local function db(x) return 20 * math.log10(math.max(x, 1e-9)) end
local function file_name(path) return tostring(path):match("([^/]+)$") or tostring(path) end

local function render_again(path, set)
  return { title = "Render " .. file_name(path) .. " again" .. (set.loudness and string.format(" at %g LUFS", set.loudness) or set.normalize and string.format(" peaking at %g dB", set.normalize) or ""),
    edit = { { uri = A.render(path), set = set } } }
end

local function render_problems(info)
  local path = info.path
  local out = {}
  local uri = A.render(path)
  local peak = info.peak or 0
  if peak > 1 then
    local float = info.bits == 32
    out[#out + 1] = { address = uri, level = float and "warning" or "error",
      text = string.format("%s goes over full scale (peak %+.1f dB)%s", file_name(path), db(peak),
        float and ": a 32-bit float file holds it, but it clips once converted" or ": it clips"),
      fix = render_again(path, { normalize = -1 }) }
  end
  if info.loudness and info.loudness > paw.opt.render_loudest then
    out[#out + 1] = { address = uri, level = "warning",
      text = string.format("%s is too loud: %.1f LUFS integrated, over %g", file_name(path), info.loudness, paw.opt.render_loudest),
      fix = render_again(path, { loudness = -14, normalize = -1 }) }
  end
  for _, why in ipairs(info.left_out or {}) do
    out[#out + 1] = { address = uri, level = "warning", text = file_name(path) .. ": " .. why }
  end
  return out
end

local function render_feed()
  local all = {}
  local paths = {}
  for path in pairs(renders) do paths[#paths + 1] = path end
  table.sort(paths)
  for _, path in ipairs(paths) do
    for _, e in ipairs(renders[path]) do all[#all + 1] = e end
  end
  M.feed("render", all)
end

paw.on("render.before", function(e) if e.path then render_opts[e.path] = e.opts end end)
local function rendered(info)
  if type(info) ~= "table" or not info.path then return end
  renders[info.path] = render_problems(info)
  render_feed()
end
paw.on("render.done", rendered)
paw.on("render.finished", rendered)
paw.on("render.failed", function(e)
  if not e.path then return end
  local path, opts = e.path, render_opts[e.path] or {}
  renders[path] = { {
    address = A.render(path), level = "error", text = "render of " .. file_name(path) .. " failed: " .. tostring(e.error),
    fix = { title = "Render " .. file_name(path) .. " again", apply = function()
      paw.render(path, paw.util.merge(opts, { background = true }))
    end },
  } }
  render_feed()
end)

-- Missing sound files ----------------------------------------------------------------------

local function project_dir()
  local path = api.project_get("path")
  return path and tostring(path):match("^(.*)/[^/]+$")
end

M.source("media", function()
  local missing = api.media_missing()
  if #missing == 0 then return {} end
  local wanted = {}
  for _, path in ipairs(missing) do wanted[tostring(path)] = true end
  local dir = project_dir()
  local fix = dir and { title = "Look for the missing files under the project's folder", apply = function() api.media_search(dir) end }
  local out, found = {}, {}
  for _, id in ipairs(api.track_list()) do
    for _, c in ipairs(api.clip_list(id)) do
      if c.file and wanted[tostring(c.file)] then
        found[tostring(c.file)] = true
        out[#out + 1] = { address = A.clip(c.id), level = "error", fix = fix,
          text = string.format("%s plays %s, which is not there", c.name, file_name(c.file)) }
      end
    end
  end
  for _, path in ipairs(missing) do
    if not found[tostring(path)] then
      out[#out + 1] = { address = A.project(), level = "error", fix = fix, text = tostring(path) .. " is not there" }
    end
  end
  return out
end)
paw.on("project.loaded", function() M.changed("media") end)
paw.on("clip.added", function() M.changed("media") end)
paw.on("changed", function() if feeds.media then M.changed("media") end end)

-- Plugins ------------------------------------------------------------------------------------

local invalid = {}   -- devices that put out NaN or infinity, by id

M.source("plugins", function()
  local out = {}
  local tracks = api.track_list()
  tracks[#tracks + 1] = 0
  for _, track in ipairs(tracks) do
    local ok, t = pcall(api.track_get, track)
    for _, id in ipairs(ok and t.devices or {}) do
      local okd, d = pcall(api.device_get, id)
      if okd then
        local uri = "paw://track/" .. track .. "/device/" .. id
        local restart = { title = "Start " .. d.name .. " again", apply = function() api.device_restart(id) end }
        if d.missing or d.status == "missing" then
          out[#out + 1] = { address = uri, level = "error", text = d.name .. " on " .. t.name .. " is not installed or did not load" }
        elseif d.stopped or d.status == "stopped" then
          out[#out + 1] = { address = uri, level = "error", fix = restart,
            text = string.format("%s on %s stopped: %s", d.name, t.name, tostring(d.stopped or "it stopped answering")) }
        elseif invalid[id] then
          out[#out + 1] = { address = uri, level = "warning", fix = restart,
            text = string.format("%s on %s put out invalid numbers (NaN or infinity) and is silenced", d.name, t.name) }
        end
      end
    end
  end
  return out
end)
paw.on("device.invalid", function(e)
  invalid[e.device] = true
  M.changed("plugins")
end)
for _, name in ipairs({ "device.stopped", "device.added", "device.removed", "project.loaded" }) do
  paw.on(name, function() M.changed("plugins") end)
end
paw.on("device.ready", function(e)
  invalid[e.id] = nil
  M.changed("plugins")
end)
paw.on("device.changed", function() if feeds.plugins then M.changed("plugins") end end)

-- Plugin files that could not be looked into: what a scan notes, at start
-- and after `:plugins.rescan` (the `plugins.scanned` event, `{ notes, name }`).
local scans = {}
paw.on("plugins.scanned", function(e)
  local name = e.name and tostring(e.name):lower()
  local kept = {}
  for _, entry in ipairs(name and scans or {}) do
    if not entry.text:lower():find(name, 1, true) then kept[#kept + 1] = entry end
  end
  for _, note in ipairs(e.notes or {}) do
    local path = note:match("^(/[^:]+): ")
    local stem = path and file_name(path):gsub("%.[^.]+$", "")
    kept[#kept + 1] = { level = "warning", text = note, fix = stem and ("plugins.rescan " .. stem) or "plugins.rescan" }
  end
  scans = kept
  M.feed("plugin scan", scans)
end)

-- Another project: what was said of the last one's renders goes.
paw.on("project.loaded", function()
  renders, render_opts, invalid = {}, {}, {}
  render_feed()
end)

-- The window ------------------------------------------------------------------------------

--- Open the window of the list and give it the keyboard. The quickfix list
--- opens along the bottom of the tab, the whole width (`opts.height` rows,
--- or `paw.opt.qf_height`). A location list opens below its window
--- (`opts.loc`, with `opts.win` the window, the current one by default). If
--- a window of the tab shows the list already, paw goes to it. Returns the window.
function M.open(opts)
  opts = opts or {}
  local L = paw.layout
  local target, from = "quickfix", nil
  if opts.loc then
    local stack, win = M.loc_stack(opts.win, true)
    if not stack then return nil end
    target, from = win, L.get(win)
  end
  local buf = L.buf_create("qflist", target)
  for _, w in ipairs(L.windows()) do
    if w.view == "qflist" and w.buf == buf.id then
      L.enter(w)
      return w
    end
  end
  local height = tonumber(opts.height) or paw.opt.qf_height
  local win
  if from and from.view ~= "qflist" then
    local made = L.split({ win = from, view = "qflist", buf = buf.id })
    if not made then return nil end
    win = made
    win.size, win.weight = height, nil
  else
    win = L.leaf("qflist", { buf = buf.id, size = height })
    local root = paw.ui.layout
    root[#root + 1] = win
    L.tidy(root)
  end
  L.enter(win)
  api.ui_redraw()
  return win
end

--- Close the windows of the tab that show the quickfix list (`loc`: the
--- location list of the current window). Returns true if one closed.
function M.close(loc)
  local L = paw.layout
  local target = "quickfix"
  if loc then
    local _, win = M.loc_stack(nil)
    target = win
  end
  local closed = false
  for _, w in ipairs(L.windows()) do
    local buf = w.view == "qflist" and L.buf_of(w)
    if buf and (buf.target or "quickfix") == target then closed = L.close(w) or closed end
  end
  return closed
end

-- Commands and keys -------------------------------------------------------------------------

local command, map = paw.command, paw.keymap.set

-- The stack a command works on: the quickfix lists, or the current
-- window's location lists.
local function stack_for(loc, make)
  if not loc then return quickfix end
  local stack = M.loc_stack(nil, make)
  if not stack then paw.notify("no location list for this window: `:ldiag` makes one", "warn") end
  return stack
end

-- A command for the quickfix lists (`c<name>`) and one for the window's
-- location lists (`l<name>`); `%s` in the description names which.
local function both(name, fn, desc, opts)
  for _, loc in ipairs({ false, true }) do
    local spec = paw.util.merge(opts or {}, { desc = (desc:gsub("%%s", loc and "the window's location list" or "the quickfix list")) })
    command((loc and "l" or "c") .. name, function(ctx)
      local stack = stack_for(loc, spec.make)
      if stack then return fn(stack, ctx, loc) end
    end, spec)
  end
end

local function count(ctx) return tonumber(ctx.args[1]) or ctx.count or 1 end

both("next", function(s, ctx) M.step(count(ctx), s) end, "Go to the next entry of %s (`]q`)")
both("previous", function(s, ctx) M.step(-count(ctx), s) end, "Go to the entry before in %s (`[q`)")
both("first", function(s, ctx) M.jump(tonumber(ctx.args[1]) or ctx.count or 1, s) end, "Go to the first entry of %s (`[Q`)")
both("last", function(s) M.last(s) end, "Go to the last entry of %s (`]Q`)")
command.alias("cn", "cnext")
command.alias("cprev", "cprevious")
command.alias("cp", "cprevious")
command.alias("cN", "cprevious")
command.alias("lprev", "lprevious")
for _, loc in ipairs({ false, true }) do
  command(loc and "ll" or "cc", function(ctx)
    local stack = stack_for(loc)
    if not stack then return end
    local list = M.current(stack)
    M.jump(tonumber(ctx.args[1]) or ctx.count or (list and list.idx > 0 and list.idx) or 1, stack)
  end, { desc = "Go to entry n of " .. (loc and "the window's location list: `ll 3`" or "the quickfix list: `cc 3`; the current one without") })
end

both("open", function(_, ctx, loc)
  M.open({ loc = loc, height = tonumber(ctx.args[1]) or ctx.count })
end, "Open a window showing %s and go to it: `copen 15` rows high", { make = true })
both("close", function(_, _, loc) M.close(loc) end, "Close the window showing %s")
both("window", function(s, ctx, loc)
  local list = M.current(s)
  if list and #list.entries > 0 then return M.open({ loc = loc, height = tonumber(ctx.args[1]) or ctx.count }) end
  M.close(loc)
end, "Open the window of %s when it has entries, close it when it has none")
both("older", function(s, ctx) M.older(count(ctx), s) end, "Go to the list before in the history of %s")
both("newer", function(s, ctx) M.newer(count(ctx), s) end, "Go to the next list in the history of %s")
both("history", function(s)
  refresh()
  if #s.lists == 0 then return paw.notify("no lists", "warn") end
  local lines = {}
  for i, list in ipairs(s.lists) do
    local n = M.count(list)
    lines[#lines + 1] = string.format("%s list %d of %d: %-20s %d entr%s%s", i == s.at and ">" or " ", i, #s.lists, list.title,
      n.total, n.total == 1 and "y" or "ies", (n.error + n.warning > 0) and string.format(" (E%d W%d)", n.error, n.warning) or "")
  end
  lines[#lines + 1] = { text = "> the current one; `:colder` and `:cnewer` go between them", style = "Dim" }
  paw.ui.page("Lists", lines)
end, "List the lists in the history of %s")
both("do", function(s, ctx) M.cdo(ctx.args[1], { stack = s }) end,
  "Run a command on every entry of %s, the cursor on each, as one undo step: `cdo track.mute`", { raw = true, label = "Run a command on every entry" })
both("fdo", function(s, ctx) M.cdo(ctx.args[1], { stack = s, per_track = true }) end,
  "Run a command once for every track the entries of %s are on, as one undo step: `cfdo track.solo`", { raw = true, label = "Run a command on every track of the entries" })
both("fix", function(s, ctx)
  local list = M.current(s)
  if not list or #list.entries == 0 then return paw.notify("no entries", "warn") end
  local entries = nil
  if ctx.args[1] == "." then entries = { list.entries[math.max(1, list.idx)] } end
  local n = M.fix(entries, { stack = s })
  paw.notify(n == 0 and "no entry has a fix" or string.format("%d fix%s made", n, n == 1 and "" or "es"))
end, "Make the fixes the entries of %s have, as one undo step; `cfix .` the current entry's", { label = "Fix the entries" })

-- What the window shows: the piano roll its clip, the mixer and the device
-- panel the cursor's track, the arrange view everything.
local function shown_target()
  local view = paw.ui.focused
  if view == "pianoroll" then return paw.ui.views.pianoroll.clip_id end
  if view == "mixer" or view == "devices" then
    local id = paw.cursor.track_id()
    return id and A.track(id) or nil
  end
  return nil
end
both("diag", function(_, ctx, loc)
  local severity = ctx.args[1] and severity_of(ctx.args[1]) or nil
  local list = M.diagnostics({ target = loc and shown_target() or nil, severity = severity, win = loc or nil })
  paw.notify(string.format("%d diagnostic%s in the list", #list.entries, #list.entries == 1 and "" or "s"))
end, "Put the diagnostics in %s (the location list: those of what the window shows); `cdiag warning` only warnings and worse",
  { make = true, complete = function() return LEVELS end })

map("]q", function(ctx) M.step(ctx.count or 1) end, { desc = "Next entry of the quickfix list", jump = true })
map("[q", function(ctx) M.step(-(ctx.count or 1)) end, { desc = "Entry before in the quickfix list", jump = true })
map("]Q", function() M.last() end, { desc = "Last entry of the quickfix list", jump = true })
map("[Q", function() M.first() end, { desc = "First entry of the quickfix list", jump = true })
map("]l", "lnext", { desc = "Next entry of the window's location list", jump = true })
map("[l", "lprevious", { desc = "Entry before in the window's location list", jump = true })

return M
