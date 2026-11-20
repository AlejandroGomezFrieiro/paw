-- Diagnostics, as `vim.diagnostic`: what is wrong (or worth knowing) about
-- anything with an address (paw/address.lua): notes of a clip, a track, a
-- device or one of its parameters, a stretch of time, the project, a
-- rendered file. Anyone publishes them (a language server through
-- `paw.lsp`, a lint written in Lua) under a namespace of their own, for a
-- document of theirs; each view shows those it can place (`paw.ui.locator`).
--
-- A diagnostic is a table:
--   { location = { uri = "paw://track/3", selector = { time = { 8, 16 } } },
--     severity,              -- 1 error, 2 warning, 3 info, 4 hint; or those words
--     message, rule, source,
--     fixes = { { title, edit = { workspace changes } },     -- see paw.address.edit
--               { title, apply = function(d) ... end } } }
--
-- About notes, the location is the clip with `selector = { notes = { ids } }`
-- (the notes' own ids, which stay with them through every edit). The older
-- form for a clip is still taken: `set(namespace, clip, { { notes = { places },
-- at, length, ..., fixes = { { title, edits = { { note = place, pitch = 73 } } } } } })`.
local api = paw.api
local A = paw.address

local M = {}

--- Severities by name and number, as `vim.diagnostic.severity`.
M.severity = { ERROR = 1, WARN = 2, INFO = 3, HINT = 4, "error", "warning", "info", "hint" }
local by_word = { error = 1, warning = 2, warn = 2, info = 3, information = 3, hint = 4 }
local groups = { "Error", "Warn", "Info", "Hint" }

local options = { virtual_text = true, signs = true, underline = true, severity_sort = true }

local store = {}    -- store[namespace][document] = list; a document is a clip id or any string
M.revision = 0      -- moves on every change, for whoever caches what is drawn

--- A severity from 1 (error) to 4 (hint), from a number or a word.
local function severity_of(value)
  if type(value) == "number" then return math.max(1, math.min(4, math.floor(value))) end
  return by_word[tostring(value or ""):lower()] or 2
end
M.severity_of = severity_of

--- The highlight group for a severity with a prefix: `Diagnostic` gives
--- `DiagnosticWarn`.
function M.group(prefix, severity) return prefix .. groups[severity_of(severity)] end

local function document_of(doc)
  if type(doc) == "table" then return doc.id or A.of(doc) end
  return doc
end

-- A diagnostic about the notes of a clip in the older form: places now,
-- named by the notes' ids from here on.
local function from_places(id, d)
  local notes = {}
  local ok, list = pcall(api.clip_notes, id)
  local ids, first, last = {}, math.huge, -math.huge
  for _, place in ipairs(d.notes or {}) do
    local n = ok and list[math.floor(place)]
    if n then
      ids[#ids + 1] = n.id
      notes[#notes + 1] = math.floor(place)
      first, last = math.min(first, n.start), math.max(last, n.start + n.length)
    end
  end
  local at = tonumber(d.at) or (first < math.huge and first or 0)
  local length = tonumber(d.length) or (last > -math.huge and last - first or 0)
  local fixes = {}
  for _, fix in ipairs(d.fixes or {}) do
    if fix.edits then
      local changes = {}
      for _, e in ipairs(fix.edits) do
        local n = ok and list[e.note]
        local uri = n and n.id and A.note(id, n.id) or ("paw://clip/" .. id .. "/note/gone")
        if e.delete then
          changes[#changes + 1] = { uri = uri, delete = true }
        else
          changes[#changes + 1] = { uri = uri, set = { pitch = e.pitch, start = e.start, length = e.length, velocity = e.velocity } }
        end
      end
      fixes[#fixes + 1] = { title = fix.title, edit = changes }
    else
      fixes[#fixes + 1] = fix
    end
  end
  local selector = { time = { at, at + math.max(0, length) } }
  if #ids > 0 then selector.notes = ids end
  return { uri = A.clip(id), selector = selector }, fixes, notes
end

local function normalize(ns, doc, d)
  local location, fixes, places = d.location, d.fixes or {}, nil
  if not location and type(doc) == "number" then
    location, fixes, places = from_places(doc, d)
  elseif type(location) == "string" then
    location = { uri = location }
  end
  location = location or { uri = A.project() }
  local p = A.parse(location.uri) or {}
  local out = {
    namespace = ns, document = doc, location = location,
    severity = severity_of(d.severity), message = tostring(d.message or ""),
    rule = d.rule or d.code, source = d.source or ns, fixes = fixes, data = d.data,
  }
  -- About a clip: the clip, its notes' places when published, and where in it.
  if p.kind == "clip" or p.kind == "note" then
    out.clip = p.clip
    out.notes = places
    if not places and location.selector and location.selector.notes then
      out.notes = {}
      for _, nid in ipairs(location.selector.notes) do
        local _, place = A.find_note(p.clip, nid)
        out.notes[#out.notes + 1] = place
      end
    end
    local t = location.selector and location.selector.time
    out.at, out.length = t and t[1] or 0, t and (t[2] - t[1]) or 0
    if p.kind == "note" then
      local n, place = A.find_note(p.clip, p.note)
      out.notes = { place }
      if n and not t then out.at, out.length = n.start, n.length end
    end
  end
  return out
end

local function changed(ns, doc)
  M.revision = M.revision + 1
  paw.emit("diagnostic.changed", { namespace = ns, document = doc, clip = type(doc) == "number" and doc or nil })
  api.ui_redraw()
end

--- Publish the diagnostics of `namespace` about a document (a clip, or a
--- string: the document URI of a server). They replace its old diagnostics
--- of that document. An empty list clears them.
function M.set(namespace, doc, list)
  assert(type(namespace) == "string", "usage: paw.diagnostic.set(namespace, document, { diagnostic, ... })")
  doc = document_of(doc)
  local out = {}
  for _, d in ipairs(list or {}) do out[#out + 1] = normalize(namespace, doc, d) end
  store[namespace] = store[namespace] or {}
  store[namespace][doc] = #out > 0 and out or nil
  changed(namespace, doc)
end

--- Forget the diagnostics of `namespace` about one document, or all of
--- them. With a clip id, forget all its diagnostics about that clip. With
--- no namespace, forget the diagnostics of all namespaces about that
--- document, or all diagnostics.
function M.reset(namespace, doc)
  doc = doc and document_of(doc)
  for ns, docs in pairs(store) do
    if not namespace or ns == namespace then
      if doc == nil then
        store[ns] = nil
      else
        docs[doc] = nil
        if type(doc) == "number" then
          for key, list in pairs(docs) do
            local kept = {}
            for _, d in ipairs(list) do if d.clip ~= doc then kept[#kept + 1] = d end end
            docs[key] = #kept > 0 and kept or nil
          end
        end
      end
    end
  end
  changed(namespace, doc)
end

--- The namespaces that published diagnostics.
function M.namespaces()
  local out = {}
  for ns, docs in pairs(store) do
    if next(docs) then out[#out + 1] = ns end
  end
  table.sort(out)
  return out
end

--- The current places of the notes of a diagnostic (from 1). The list does
--- not contain a note that does not exist now.
function M.places(d)
  local out = {}
  local sel = d.location and d.location.selector
  local p = d.location and A.parse(d.location.uri)
  if p and p.kind == "note" then
    local _, place = A.find_note(p.clip, p.note)
    out[#out + 1] = place
  elseif p and sel and sel.notes then
    for _, id in ipairs(sel.notes) do
      local _, place = A.find_note(p.clip, id)
      if place then out[#out + 1] = place end
    end
  end
  return out
end

--- The notes of a diagnostic as they are now.
function M.notes_of(d)
  local out = {}
  local p = d.location and A.parse(d.location.uri)
  if not p or not p.clip then return out end
  local ok, list = pcall(api.clip_notes, p.clip)
  if not ok then return out end
  for _, place in ipairs(M.places(d)) do out[#out + 1] = list[place] end
  return out
end

--- The kind of item that a diagnostic is about, to make groups: clip,
--- track, device, time, project, render, or the kind of an extension.
function M.kind(d)
  local p = A.parse(d.location.uri)
  if not p then return "other" end
  if p.kind == "note" or p.kind == "control" then return "clip" end
  if p.kind == "param" then return "device" end
  if p.kind == "send" then return "track" end
  if (p.kind == "project" or p.kind == "track") and d.location.selector and d.location.selector.time then
    return p.kind == "project" and "time" or "track"
  end
  return p.kind
end

--- True if a diagnostic is about an address or an item in it. A note
--- counts when a diagnostic of its clip names the note in its notes.
function M.about(d, uri)
  if A.within(d.location.uri, uri) then return true end
  local p = A.parse(uri)
  local sel = d.location.selector
  if p and p.kind == "note" and d.clip == p.clip and sel and sel.notes then
    for _, id in ipairs(sel.notes) do
      if id == p.note then return true end
    end
  end
  return false
end

local KIND_ORDER ={ clip = 1, track = 2, device = 3, time = 4, project = 5, render = 6 }

local function sorted(list)
  table.sort(list, function(a, b)
    local ka, kb = KIND_ORDER[M.kind(a)] or 9, KIND_ORDER[M.kind(b)] or 9
    if ka ~= kb then return ka < kb end
    if a.location.uri ~= b.location.uri then return a.location.uri < b.location.uri end
    if math.abs((a.at or 0) - (b.at or 0)) > 1e-9 then return (a.at or 0) < (b.at or 0) end
    if options.severity_sort and a.severity ~= b.severity then return a.severity < b.severity end
    return a.message < b.message
  end)
  return list
end

-- A diagnostic is gone with what it is about.
local function alive(d)
  local p = A.parse(d.location.uri)
  if not p then return true end
  if p.kind == "clip" or p.kind == "note" or p.kind == "control" then return pcall(api.clip_get, p.clip) end
  if p.kind == "track" or p.kind == "send" then return pcall(api.track_get, p.track) end
  if p.kind == "device" or p.kind == "param" then return pcall(api.device_get, p.device) end
  return true
end

--- Diagnostics, sorted by kind and then by where they are. `target`: a clip
--- id (those about it and its notes), an address (those about it or what
--- it holds), or nil for all. `filter`: `namespace`, `severity` (a severity
--- or `{ min, max }`, min the least severe), `note` (a place in the clip),
--- `kind` (as `paw.diagnostic.kind`), `document`.
function M.get(target, filter)
  filter = filter or {}
  local within = type(target) == "string" and target or (type(target) == "table" and A.of(target)) or nil
  local clip = type(target) == "number" and target or (type(target) == "table" and getmetatable(target) == paw.Clip and target.id) or nil
  if clip then within = nil end
  local min, max = 1, 4
  if type(filter.severity) == "table" then
    min, max = severity_of(filter.severity.max or 1), severity_of(filter.severity.min or 4)
  elseif filter.severity then
    min = severity_of(filter.severity)
    max = min
  end
  local out = {}
  for ns, docs in pairs(store) do
    if not filter.namespace or filter.namespace == ns then
      for doc, list in pairs(docs) do
        if not filter.document or filter.document == doc then
          local kept = {}
          for _, d in ipairs(list) do
            if alive(d) then
              kept[#kept + 1] = d
              local here = (not clip or d.clip == clip) and (not within or M.about(d, within))
              if here and d.severity >= min and d.severity <= max and (not filter.kind or M.kind(d) == filter.kind) then
                out[#out + 1] = d
              end
            end
          end
          if #kept ~= #list then
            docs[doc] = #kept > 0 and kept or nil
            M.revision = M.revision + 1
          end
        end
      end
    end
  end
  if filter.note then
    local kept = {}
    for _, d in ipairs(out) do
      for _, place in ipairs(M.places(d)) do
        if place == filter.note then kept[#kept + 1] = d break end
      end
    end
    out = kept
  end
  return sorted(out)
end

--- How many diagnostics of each severity (as `get` takes its target):
--- `{ error = 1, warning = 2, info = 0, hint = 0, total = 3 }`.
function M.count(target, filter)
  local out = { error = 0, warning = 0, info = 0, hint = 0, total = 0 }
  for _, d in ipairs(M.get(target, filter)) do
    local word = M.severity[d.severity]
    out[word], out.total = out[word] + 1, out.total + 1
  end
  return out
end

--- The worst severity said about an address or what it holds, or nil.
function M.worst(uri, filter)
  local worst
  for _, d in ipairs(M.get(uri, filter)) do worst = math.min(worst or 4, d.severity) end
  return worst
end

--- Change how paw shows diagnostics. Returns the options in use.
---   paw.diagnostic.config({ virtual_text = false })
function M.config(opts)
  for k, v in pairs(opts or {}) do options[k] = v end
  if opts then api.ui_redraw() end
  return paw.util.merge(options, {})
end

-- Fixes ----------------------------------------------------------------------

--- Do a fix of a diagnostic as one undo step. Returns true if it did the fix.
function M.apply(d, fix)
  fix = fix or d.fixes[1]
  if not fix then return false end
  if fix.apply then
    api.undo_label(fix.title or "Fix")
    fix.apply(d)
    return true
  end
  local ok, why = A.edit(fix.edit or {}, fix.title or "Fix")
  if not ok then
    paw.notify("the fix cannot be made: " .. tostring(why), "warn")
    return false
  end
  return true
end

--- The fixes of the diagnostics about a place (as `get` takes its target
--- and filter), as `{ title, diagnostic, fix, run }`, the most severe first.
--- `actions(clip, place)` asks about one note of a clip.
function M.actions(target, place)
  local out = {}
  local filter = type(place) == "number" and { note = place } or place
  for _, d in ipairs(M.get(target, filter)) do
    for _, fix in ipairs(d.fixes) do
      out[#out + 1] = { title = fix.title or "Fix", diagnostic = d, fix = fix, run = function() return M.apply(d, fix) end }
    end
  end
  table.sort(out, function(a, b) return a.diagnostic.severity < b.diagnostic.severity end)
  return out
end

-- Where a diagnostic is, in words -------------------------------------------

local function track_name(id)
  local ok, t = pcall(api.track_get, id)
  return ok and t.name or ("track " .. id)
end

--- Where a diagnostic is about, in a few words: `Lead › Synth · cutoff`,
--- `chords 2.1.00`, `5.1.00–9.1.00`, `mix.wav`.
function M.where(d)
  local loc = d.location
  local p = A.parse(loc.uri)
  local t = loc.selector and loc.selector.time
  if not p then return loc.uri end
  if p.kind == "clip" or p.kind == "note" or p.kind == "control" then
    local ok, c = pcall(api.clip_get, p.clip)
    return ok and string.format("%s %s", c.name, paw.time.format(c.start + (d.at or 0))) or "a clip"
  end
  if p.kind == "track" or p.kind == "send" then
    return track_name(p.track) .. (t and (" " .. paw.time.format(t[1])) or "")
  end
  if p.kind == "device" or p.kind == "param" then
    local ok, dev = pcall(api.device_get, p.device)
    local name = track_name(p.track) .. " › " .. (ok and dev.name or "a device")
    if p.kind == "param" then
      for _, info in ipairs(ok and dev.param_info or {}) do
        if info.key == p.param then return name .. " · " .. (info.name or p.param) end
      end
      return name .. " · " .. p.param
    end
    return name
  end
  if p.kind == "render" then return (p.path:match("([^/]+)$") or p.path) .. (t and string.format(" %.1f s", t[1]) or "") end
  if t then return paw.time.format(t[1]) .. "–" .. paw.time.format(t[2]) end
  return p.kind
end

--- A diagnostic in one line: `warning parallel-perfect: Parallel fifths … [midi-lsp]`.
function M.format(d)
  return string.format("%s%s: %s [%s]", M.severity[d.severity], d.rule and (" " .. d.rule) or "", d.message, d.source)
end

-- Going from one to the next --------------------------------------------------

--- Put the cursor of the view that shows it best on a diagnostic, and say it.
function M.show(d)
  paw.ui.go(d.location)
  paw.notify(M.format(d), d.severity == 1 and "error" or d.severity == 2 and "warn" or "info")
end

-- Where the last jump went, and where it left the cursor: a view that cannot
-- put its cursor exactly there (a finding about the master, in the arrange
-- view) goes on from the diagnostic, not from the cursor.
local last_jump

--- The next (`dir` 1) or previous (-1) diagnostic that the focused view can
--- show, from its cursor, `count` times, round the ends. The cursor goes
--- there. Returns the diagnostic, or nil when the view has none.
function M.jump(dir, count)
  local view = paw.ui.focused
  local loc = paw.ui.locators[view]
  local found
  if loc then
    local placed = {}
    for _, d in ipairs(M.get()) do
      local at = loc.place(d.location)
      if at then placed[#placed + 1] = { d = d, at = at } end
    end
    local function before(a, b)
      for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if math.abs(x - y) > 1e-6 then return x < y end
      end
      return false
    end
    table.sort(placed, function(a, b) return before(a.at, b.at) end)
    if #placed > 0 then
      local here = loc.position()
      if last_jump and last_jump.view == view and not before(here, last_jump.landed) and not before(last_jump.landed, here) then
        here = last_jump.at
      end
      for _ = 1, count or 1 do
        local pick
        if dir > 0 then
          for _, e in ipairs(placed) do if before(here, e.at) then pick = e break end end
          pick = pick or placed[1]
        else
          for i = #placed, 1, -1 do if before(placed[i].at, here) then pick = placed[i] break end end
          pick = pick or placed[#placed]
        end
        found, here = pick.d, pick.at
      end
    end
  end
  if not found then return paw.notify("no diagnostics here") end
  loc.go(found.location)
  last_jump = { view = view, at = loc.place(found.location), landed = loc.position() }
  paw.notify(M.format(found), found.severity == 1 and "error" or found.severity == 2 and "warn" or "info")
  return found
end

--- Go to the next diagnostic, or `opts.count` on (`]d`).
function M.goto_next(opts) return M.jump(1, opts and opts.count) end
--- Go to the diagnostic before, or `opts.count` back (`[d`).
function M.goto_prev(opts) return M.jump(-1, opts and opts.count) end

local KIND_TITLE = { clip = "Notes", track = "Tracks", device = "Devices", time = "Time", project = "Project", render = "Renders" }

--- Every diagnostic (of `target`, as `get` takes it) in a picker, as the
--- quickfix list, grouped by what they are about: Enter goes to one.
function M.list(target)
  local items, last = {}, nil
  for _, d in ipairs(M.get(target)) do
    local kind = M.kind(d)
    if kind ~= last then
      items[#items + 1] = { text = "── " .. (KIND_TITLE[kind] or kind) }
      last = kind
    end
    items[#items + 1] = { text = string.format("  %-7s %-24s %s", M.severity[d.severity], paw.util.fit(M.where(d), 24), M.format(d):gsub("^%a+ ", "")), diagnostic = d }
  end
  if #items == 0 then return paw.notify("no diagnostics") end
  paw.pick({
    title = "Diagnostics",
    items = items,
    on_choose = function(item) if item and item.diagnostic then M.show(item.diagnostic) end end,
  })
end

--- Put the diagnostics in the quickfix list, as `vim.diagnostic.setqflist`:
--- `opts` has `target`, `severity` (the least severe), `title`, `open`.
--- `setloclist` puts them in the current window's location list.
function M.setqflist(opts) return paw.qf.diagnostics(opts) end
--- The diagnostics in the current window's location list.
function M.setloclist(opts) return paw.qf.diagnostics(paw.util.merge(opts or {}, { win = (opts and opts.win) or true })) end

-- Drawing ----------------------------------------------------------------------

local g = function() return paw.draw.g end

--- Mark the diagnostics of each clip that the piano roll edits, as one of
--- its layers. Each note has a line below it in the color of its severity.
--- The message comes after the last note while there is space, and a mark
--- on the ruler shows where it starts.
function M.paint_roll(p)
  for _, part in ipairs(p.parts or { { id = p.clip.id, offset = 0 } }) do
    M.paint_part(p, part.id, part.offset or 0)
  end
end

--- One clip's, `offset` beats from the roll's own.
function M.paint_part(p, id, offset)
  local list = M.get(id)
  if #list == 0 then return end
  local notes = api.clip_notes(id)
  local worst = {}
  for _, d in ipairs(list) do
    for _, place in ipairs(M.places(d)) do
      if not worst[place] or d.severity < worst[place] then worst[place] = d.severity end
    end
  end
  if options.underline then
    for place, severity in pairs(worst) do
      local n = notes[place]
      local x0, x1, row = p.x(n.start + offset), p.x(n.start + n.length + offset), p.row(n.pitch)
      if row then p.roll:fill(x0, row, math.max(1, x1 - x0), 1, nil, M.group("DiagnosticUnderline", severity)) end
    end
  end
  for _, d in ipairs(list) do
    -- On the cell's left edge, where the diagnostic starts.
    if options.signs then p.ruler:text(p.x((d.at or 0) + offset), 0, g().mark, M.group("Diagnostic", d.severity)) end
    if options.virtual_text then
      local last
      for _, place in ipairs(M.places(d)) do
        local n = notes[place]
        if not last or n.start + n.length > last.start + last.length then last = n end
      end
      local row = last and p.row(last.pitch)
      if row then
        local x = p.x(last.start + last.length + offset) + 1
        local room = p.roll.width - x
        if room >= 8 then
          local text = api.str_width(d.message) > room and paw.util.fit(d.message, room) or d.message
          p.roll:text(x, row, text, M.group("DiagnosticVirtualText", d.severity))
        end
      end
    end
  end
end

-- A sign with its colour, and the message after it while there is room.
local function sign(buf, x, y, room, severity, message)
  buf:text(x, y, severity == 1 and g().error or g().warn, M.group("Diagnostic", severity))
  if options.virtual_text and message and room > 4 then
    local text = api.str_width(message) > room - 2 and paw.util.fit(message, room - 2) or message
    buf:text(x + 2, y, text, M.group("DiagnosticVirtualText", severity))
  end
end

-- What the arrange view, the mixer and the device panel show, as layers of
-- theirs (`paw.ui.layer`), so that other modules' marks go beside them.
paw.ui.layer("arrange", "clip", "diagnostics", 30, function(c)
  if c.width < 3 or not next(store) then return end
  local worst = M.worst(A.clip(c.clip.id))
  if worst then c.buf:text(c.width - 1, 0, worst == 1 and g().error or g().warn, M.group("Diagnostic", worst)) end
end)
paw.ui.layer("arrange", "header", "diagnostics", 30, function(c)
  if not next(store) then return end
  -- What is said of the track itself, its devices or sends; its clips have marks of their own.
  local worst
  for _, d in ipairs(M.get(A.track(c.track))) do
    if M.kind(d) ~= "clip" then worst = math.min(worst or 4, d.severity) end
  end
  if worst then c.buf:text(c.x, c.y, worst == 1 and g().error or g().warn, M.group("Diagnostic", worst)) end
end)
-- Stretches of time on the arrange view's ruler (one of its layers).
paw.ui.views.arrange.layers.diagnostics = function(_, c)
  if not next(store) then return end
  for _, d in ipairs(M.get(nil, { kind = "time" })) do
    local t = d.location.selector.time
    local x0, x1 = c.x(t[1]), c.x(t[2])
    if x1 > 0 and x0 < c.ruler.width then
      -- The stretch it is about, from the cell its start is in (marks sit on the left edge).
      local from = math.max(0, x0)
      c.ruler:fill(from, 0, math.max(1, math.min(c.ruler.width, x1) - from), 1, nil, M.group("DiagnosticUnderline", d.severity))
      if x0 >= 0 then c.ruler:text(x0, 0, g().mark, M.group("Diagnostic", d.severity)) end
    end
  end
end
-- A strip: a sign at the right end of its name plate.
paw.ui.layer("mixer", "strip", "diagnostics", 30, function(c)
  if not next(store) then return end
  local worst = M.worst(A.track(c.track))
  if worst then c.buf:text(c.x + c.width - 1, c.y, worst == 1 and g().error or g().warn, M.group("Diagnostic", worst)) end
end)
-- A device: a sign after its name and what is said of it; a parameter: a sign before its name.
paw.ui.layer("devices", "device", "diagnostics", 30, function(c)
  if not next(store) then return end
  local list = M.get(A.device(c.device))
  if #list == 0 then return end
  local worst, own = 4, nil
  for _, d in ipairs(list) do
    worst = math.min(worst, d.severity)
    if not own and d.location.uri == A.device(c.device) then own = d end
  end
  -- What is said of the device itself; its parameters have marks of their own.
  sign(c.buf, c.x, c.y, c.width, worst, own and own.message or (#list .. " diagnostics"))
end)
paw.ui.layer("devices", "param", "diagnostics", 30, function(c)
  if not next(store) then return end
  local worst = M.worst(A.param(c.device, c.param))
  if worst then c.buf:text(c.x, c.y, worst == 1 and g().error or g().warn, M.group("Diagnostic", worst)) end
end)

--- The status line's piece: `E1 W2` for the clip in the piano roll, or the
--- whole project when none is open. Nil when there is nothing to say.
function M.status()
  if not next(store) then return nil end
  local view = paw.ui.views.pianoroll
  local n = M.count(paw.ui.visible("pianoroll") and view.clip_id or nil)
  if n.total == 0 then return nil end
  local pieces = {}
  for i, word in ipairs({ "error", "warning", "info", "hint" }) do
    if n[word] > 0 then
      if #pieces > 0 then pieces[#pieces + 1] = { " ", "StatusLine" } end
      pieces[#pieces + 1] = { ("EWIH"):sub(i, i) .. n[word], i == 1 and "StatusError" or i == 2 and "StatusWarn" or "StatusDim" }
    end
  end
  return pieces
end

--- The marks of the window in its piano roll for a clip. These are the
--- notes that diagnostics are about, by place from 0. Each has its worst
--- severity, the messages about it and the titles of its fixes.
function M.roll_marks(id)
  local out, by_place = {}, {}
  local list = M.get(id)
  local notes = #list > 0 and api.clip_notes(id) or {}
  for _, d in ipairs(list) do
    for _, place in ipairs(M.places(d)) do
      local mark = by_place[place]
      local n = notes[place]
      if not mark then
        mark = { index = place - 1, pitch = n.pitch, start = n.start, length = n.length, severity = d.severity,
          message = M.format(d), actions = {} }
        by_place[place], out[#out + 1] = mark, mark
      elseif d.severity < mark.severity then
        mark.severity, mark.message = d.severity, M.format(d) .. "\n" .. mark.message
      else
        mark.message = mark.message .. "\n" .. M.format(d)
      end
    end
  end
  for place, mark in pairs(by_place) do
    for _, action in ipairs(M.actions(id, place)) do mark.actions[#mark.actions + 1] = action.title end
  end
  return out
end

--- The marks of the window in other views. Each track (by id) has the worst
--- severity about it, its devices or its sends, and the first message.
--- The ranges of time are also marks.
function M.marks()
  local tracks, times = {}, {}
  for _, d in ipairs(M.get()) do
    local kind = M.kind(d)
    local track = A.track_of(d.location.uri)
    if track and kind ~= "clip" then
      local t = tracks[track]
      if not t or d.severity < t.severity then tracks[track] = { track = track, severity = d.severity, message = M.format(d) } end
    elseif kind == "time" then
      local t = d.location.selector.time
      times[#times + 1] = { from = t[1], to = t[2], severity = d.severity, message = M.format(d) }
    end
  end
  local list = {}
  for _, t in pairs(tracks) do list[#list + 1] = t end
  table.sort(list, function(a, b) return a.track < b.track end)
  return { tracks = list, times = times }
end

paw.ui.views.pianoroll.layer("diagnostics", 30, function(p) M.paint_roll(p) end)

-- The window's menu on a note: the `n`th of its fixes, as `actions` lists them.
function paw.frontend.act.note_action(clip, place, n)
  local action = M.actions(clip, place)[n]
  if action then action.run() end
end

paw.on("project.loaded", function() if next(store) then M.reset() end end)

return M
