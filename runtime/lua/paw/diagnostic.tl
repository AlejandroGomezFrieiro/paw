-- Diagnostics, as `vim.diagnostic`: what is wrong (or worth knowing) about
-- anything with an address (paw/address.tl): notes of a clip, a part, a
-- device or one of its parameters, a stretch of time, the project, a
-- rendered file. Anyone publishes them (a language server through
-- `paw.lsp`, a lint written in Lua) under a namespace of their own, for a
-- document of theirs; each view shows those it can place (`paw.ui.locator`).
--
-- A diagnostic is a table:
--   { location = { uri = "paw://part/3", selector = { time = { 8, 16 } } },
--     severity,              -- 1 error, 2 warning, 3 info, 4 hint; or those words
--     message, rule, source,
--     fixes = { { title, edit = { workspace changes } },     -- see paw.address.edit
--               { title, apply = function(d) ... end } } }
--
-- About notes, the location is the clip with `selector = { notes = { ids } }`
-- (the notes' own ids, which stay with them through every edit). The older
-- form for a clip is still taken: `set(namespace, clip, { { notes = { places },
-- at, length, ..., fixes = { { title, edits = { { note = place, pitch = 73 } } } } } })`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local util = require("paw.util")
local A = require("paw.address")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type UiModule = require("paw.ui")
local type objects = require("paw.objects")
local type DrawModule = require("paw.draw")
local type PartColumnModule = require("paw.partcolumn")
local type Roll = require("paw.views.pianoroll")

--- A severity: 1 (error) to 4 (hint), or one of the words `error`,
--- `warning` (`warn`), `info` (`information`) and `hint`.
local type Level = number | string

--- A change of a fix in the older form, about a note of a clip by its
--- place: a new pitch, start, length or velocity, or `delete`.
local record OldEdit
  note: integer
  delete: boolean
  pitch: integer
  start: number
  length: number
  velocity: integer
end

--- What the one who publishes a diagnostic keeps in it (`data`): paw does
--- not read it.
local record Data
end

--- A fix of a diagnostic: changes of a workspace edit (`edit`, see
--- `paw.address.edit`), or a function (`apply`). `edits` is the older form.
local record Fix
  title: string
  edit: {A.Change}
  apply: function(d: Diagnostic)
  edits: {OldEdit}
end

--- A diagnostic as it is published (`paw.diagnostic.set`). The older form
--- for a clip gives the places of its notes (`notes`), `at` and `length`
--- in the clip's beats.
local record Published
  location: string | contracts.Location
  severity: Level
  message: string
  rule: string
  code: string
  source: string
  fixes: {Fix}
  data: Data
  notes: {number}
  at: number
  length: number
end

--- What a diagnostic is about in its namespace: a clip id, or a text
--- (the document URI of a server).
local type Document = integer | string

--- A diagnostic as paw keeps it: the severity a number, the location a
--- table. About a clip: the clip, the places of its notes (from 1), and
--- `at` and `length` in the clip's beats.
local record Diagnostic
  namespace: string
  document: Document
  location: contracts.Location
  severity: integer
  message: string
  rule: string
  source: string
  fixes: {Fix}
  data: Data
  clip: integer
  notes: {integer}
  at: number
  length: number
end

--- What `get` asks about: a clip id, an address, or an object of the Lua
--- interface (`paw.clip(7)`, `paw.part(3)`).
local type Target = integer | string | A.Thing

--- The least and most severe of `Filter.severity`.
local record Range
  min: Level
  max: Level
end

--- What `get` keeps: a namespace, a severity (one, or a range), a note's
--- place in the clip, a kind (as `kind` gives it) and a document.
local record Filter
  namespace: string
  severity: Level | Range
  note: integer
  kind: string
  document: Document
end

--- How paw shows diagnostics (`paw.diagnostic.config`).
local record Config
  virtual_text: boolean
  signs: boolean
  underline: boolean
  severity_sort: boolean
end

--- The severities by name and by number, as `vim.diagnostic.severity`.
local record Severity is {string}
  ERROR: integer
  WARN: integer
  INFO: integer
  HINT: integer
end

--- How many diagnostics there are of each severity.
local record Count
  error: integer
  warning: integer
  info: integer
  hint: integer
  total: integer
end

--- A fix of the diagnostics about a place (`paw.diagnostic.actions`).
local record Action
  title: string
  diagnostic: Diagnostic
  fix: Fix
  run: function(): boolean
end

--- What `setqflist` and `setloclist` take (`paw.qf.diagnostics`): the
--- target and the least severity, as `get` takes them, the title of the
--- list, `win` for a location list (true: the current window's) and
--- `open` to open its window.
local record ListOptions
  target: Target
  severity: Level
  title: string
  win: integer | boolean
  open: boolean
end

--- A note that a diagnostic is about, in the piano roll of the window.
local record RollMark
  index: integer
  pitch: integer
  start: number
  length: number
  severity: integer
  message: string
  actions: {string}
end

--- The worst diagnostic about a part, in the window.
local record PartMark
  part: integer
  severity: integer
  message: string
end

--- A stretch of time with a diagnostic, in the window.
local record TimeMark
  from: number
  to: number
  severity: integer
  message: string
end

--- The marks of the window in the views other than the piano roll.
local record Marks
  parts: {PartMark}
  times: {TimeMark}
end

--- The payload of `diagnostic.changed`: the namespace and the document
--- (nil: all of them), and the clip when the document is one.
local record Changed
  namespace: string
  document: Document
  clip: integer
end

--- An item of the picker of `paw.diagnostic.list`.
local record ListItem
  text: string
  diagnostic: Diagnostic
end

-- What this module reads of the modules that are still in Lua.

--- What a layer of the piano roll gets, and the roll (paw/views/pianoroll.tl).
local type RollLayer = Roll.Layer
local type PianoRoll = Roll.PianoRoll

--- What a layer of a view's part gets (`paw.ui.layer`): its cells, where
--- the part is and what it shows.
local record ClipOfLayer
  id: integer
end
local record PartLayer
  buf: contracts.Buf
  x: integer
  y: integer
  width: integer
  clip: ClipOfLayer
  part: integer
  device: integer
  param: string
end

--- The gestures of the window (paw/frontend.tl) that this module adds.
local record Acts
  note_action: function(clip: integer, place: integer, n: integer)
end
local record Frontend
  act: Acts
end

--- `paw.qf` (paw/qf.tl), as far as this module calls it. qf.tl names the
--- types of this module, and two modules cannot name each other's types.
local record QfList
  title: string
end
local record Qf
  diagnostics: function(opts: ListOptions): QfList
end

--- `paw.pick` (paw/pick.tl), the part of it that this module calls: opening
--- a picker.
local record Pick
  metamethod __call: function<T>(self: Pick, spec: contracts.PickSource<T>)
end

local record Paw is partial.Paw
  ui: UiModule
  pick: Pick
  frontend: Frontend
  draw: DrawModule
  partcolumn: PartColumnModule
  qf: Qf
  time: objects.Time
  Clip: objects.Clip
end
local paw = (_G as {string: Paw}).paw

local record M
  type Level = Level
  type OldEdit = OldEdit
  type Data = Data
  type Fix = Fix
  type Published = Published
  type Document = Document
  type Diagnostic = Diagnostic
  type Target = Target
  type Filter = Filter
  type Config = Config
  type Count = Count
  type Action = Action
  type ListOptions = ListOptions
  type RollMark = RollMark
  type Marks = Marks
  type Changed = Changed
  --- Severities by name and number, as `vim.diagnostic.severity`.
  severity: Severity
  --- Moves on every change, for whoever caches what is drawn.
  revision: integer
  severity_of: function(value: Level): integer
  --- The event `diagnostic.changed`: the diagnostics of a document changed.
  changed: events.Event<Changed>
end

M.severity = {ERROR = 1, WARN = 2, INFO = 3, HINT = 4, "error", "warning", "info", "hint"}
M.changed = events.event("diagnostic.changed")
local by_word: {string: integer} = {error = 1, warning = 2, warn = 2, info = 3, information = 3, hint = 4}
local groups = {"Error", "Warn", "Info", "Hint"}

local options: Config = {virtual_text = true, signs = true, underline = true, severity_sort = true}

local store: {string: {Document: {Diagnostic}}} = {

} -- store[namespace][document] = list; a document is a clip id or any string
M.revision = 0 -- moves on every change, for whoever caches what is drawn

--- A severity from 1 (error) to 4 (hint), from a number or a word.
local function severity_of(value: Level): integer
  if value is number then
    return math.max(1, math.min(4, math.floor(value)))
  end
  return by_word[tostring(value or ""):lower()] or 2
end
M.severity_of = severity_of

--- The highlight group for a severity with a prefix: `Diagnostic` gives
--- `DiagnosticWarn`.
function M.group(prefix: string, severity: Level): string
  return prefix .. groups[severity_of(severity)]
end

--- What a document is: a clip id or a text, or the id or the address of
--- an object.
local function document_of(doc: Document | A.Thing): Document
  if doc is A.Thing then
    return (doc as ClipOfLayer).id or A.of(doc)
  end
  return doc
end

-- A clip's notes, all of them.
local clip_notes = api.clip_notes as function(id: integer): {types.Note}

-- A diagnostic about the notes of a clip in the older form: places now,
-- named by the notes' ids from here on.
local function from_places(id: integer, d: Published): contracts.Location, {Fix}, {integer}
  local notes: {integer} = {}
  local ok, list = pcall(clip_notes, id)
  local ids: {integer} = {}
  local first, last = math.huge, -math.huge
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
  local fixes: {Fix} = {}
  for _, fix in ipairs(d.fixes or {}) do
    if fix.edits then
      local changes: {A.Change} = {}
      for _, e in ipairs(fix.edits) do
        local n = ok and list[e.note]
        local uri = n and n.id and A.note(id, n.id) or ("paw://clip/" .. id .. "/note/gone")
        if e.delete then
          changes[#changes + 1] = {uri = uri, delete = true}
        else
          local set: {string: number} = {pitch = e.pitch, start = e.start, length = e.length, velocity = e.velocity}
          local change = {uri = uri, set = set}
          changes[#changes + 1] = change as A.Change
        end
      end
      fixes[#fixes + 1] = {title = fix.title, edit = changes}
    else
      fixes[#fixes + 1] = fix
    end
  end
  local selector: contracts.Selector = {time = {at, at + math.max(0, length)}}
  if #ids > 0 then
    selector.notes = ids
  end
  return {uri = A.clip(id), selector = selector}, fixes, notes
end

local function normalize(ns: string, doc: Document, d: Published): Diagnostic
  local given = d.location
  local location: contracts.Location
  local fixes, places = d.fixes or {}, nil as {integer}
  if not given and doc is integer then
    location, fixes, places = from_places(doc, d)
  elseif given is string then
    location = {uri = given}
  else
    location = given
  end
  location = location or {uri = A.project()}
  local p = A.parse(location.uri) or {}
  local out: Diagnostic = {
    namespace = ns,
    document = doc,
    location = location,
    severity = severity_of(d.severity),
    message = tostring(d.message or ""),
    rule = d.rule or d.code,
    source = d.source or ns,
    fixes = fixes,
    data = d.data,
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
      out.notes = {place}
      if n and not t then
        out.at, out.length = n.start, n.length
      end
    end
  end
  return out
end

local function changed(ns: string, doc: Document)
  M.revision = M.revision + 1
  events.emit(M.changed, {namespace = ns, document = doc, clip = doc is integer and doc or nil})
  api.ui_redraw()
end

--- Publish the diagnostics of `namespace` about a document (a clip, or a
--- string: the document URI of a server). They replace its old diagnostics
--- of that document. An empty list clears them.
function M.set(namespace: string, doc: Document | A.Thing, list: {Published})
  assert(namespace is string, "usage: paw.diagnostic.set(namespace, document, { diagnostic, ... })")
  local document = document_of(doc)
  local out: {Diagnostic} = {}
  for _, d in ipairs(list or {}) do
    out[#out + 1] = normalize(namespace, document, d)
  end
  store[namespace] = store[namespace] or {}
  store[namespace][document] = #out > 0 and out or nil
  changed(namespace, document)
end

--- Forget the diagnostics of `namespace` about one document, or all of
--- them. With a clip id, forget all its diagnostics about that clip. With
--- no namespace, forget the diagnostics of all namespaces about that
--- document, or all diagnostics.
function M.reset(namespace?: string, doc?: Document | A.Thing)
  local document = doc and document_of(doc)
  for ns, docs in pairs(store) do
    if not namespace or ns == namespace then
      if document == nil then
        store[ns] = nil
      else
        docs[document] = nil
        if document is integer then
          for key, list in pairs(docs) do
            local kept: {Diagnostic} = {}
            for _, d in ipairs(list) do
              if d.clip ~= document then
                kept[#kept + 1] = d
              end
            end
            docs[key] = #kept > 0 and kept or nil
          end
        end
      end
    end
  end
  changed(namespace, document)
end

--- The namespaces that published diagnostics.
function M.namespaces(): {string}
  local out: {string} = {}
  for ns, docs in pairs(store) do
    if next(docs) then
      out[#out + 1] = ns
    end
  end
  table.sort(out)
  return out
end

--- The current places of the notes of a diagnostic (from 1). The list does
--- not contain a note that does not exist now.
function M.places(d: Diagnostic): {integer}
  local out: {integer} = {}
  local sel = d.location and d.location.selector
  local p = d.location and A.parse(d.location.uri)
  if p and p.kind == "note" then
    local _, place = A.find_note(p.clip, p.note)
    out[#out + 1] = place
  elseif p and sel and sel.notes then
    for _, id in ipairs(sel.notes) do
      local _, place = A.find_note(p.clip, id)
      if place then
        out[#out + 1] = place
      end
    end
  end
  return out
end

--- The notes of a diagnostic as they are now.
function M.notes_of(d: Diagnostic): {types.Note}
  local out: {types.Note} = {}
  local p = d.location and A.parse(d.location.uri)
  if not p or not p.clip then
    return out
  end
  local ok, list = pcall(clip_notes, p.clip)
  if not ok then
    return out
  end
  for _, place in ipairs(M.places(d)) do
    out[#out + 1] = list[place]
  end
  return out
end

--- The kind of item that a diagnostic is about, to make groups: clip,
--- part, device, time, project, render, or the kind of an extension.
function M.kind(d: Diagnostic): string
  local p = A.parse(d.location.uri)
  if not p then
    return "other"
  end
  if p.kind == "note" or p.kind == "control" then
    return "clip"
  end
  if p.kind == "param" then
    return "device"
  end
  if p.kind == "send" then
    return "part"
  end
  if (p.kind == "project" or p.kind == "part") and d.location.selector and d.location.selector.time then
    return p.kind == "project" and "time" or "part"
  end
  return p.kind
end

--- True if a diagnostic is about an address or an item in it. A note
--- counts when a diagnostic of its clip names the note in its notes.
function M.about(d: Diagnostic, uri: string): boolean
  if A.within(d.location.uri, uri) then
    return true
  end
  local p = A.parse(uri)
  local sel = d.location.selector
  if p and p.kind == "note" and d.clip == p.clip and sel and sel.notes then
    for _, id in ipairs(sel.notes) do
      if id == p.note then
        return true
      end
    end
  end
  return false
end

local KIND_ORDER: {string: integer} = {clip = 1, part = 2, device = 3, time = 4, project = 5, render = 6}

local function sorted(list: {Diagnostic}): {Diagnostic}
  table.sort(
    list,
    function(a: Diagnostic, b: Diagnostic): boolean
      local ka, kb = KIND_ORDER[M.kind(a)] or 9, KIND_ORDER[M.kind(b)] or 9
      if ka ~= kb then
        return ka < kb
      end
      if a.location.uri ~= b.location.uri then
        return a.location.uri < b.location.uri
      end
      if math.abs((a.at or 0) - (b.at or 0)) > 1e-9 then
        return (a.at or 0) < (b.at or 0)
      end
      if options.severity_sort and a.severity ~= b.severity then
        return a.severity < b.severity
      end
      return a.message < b.message
    end
  )
  return list
end

-- A diagnostic is gone with what it is about.
local function alive(d: Diagnostic): boolean
  local p = A.parse(d.location.uri)
  if not p then
    return true
  end
  if p.kind == "clip" or p.kind == "note" or p.kind == "control" then
    return (pcall(api.clip_get, p.clip))
  end
  if p.kind == "part" or p.kind == "send" then
    return (pcall(api.part_get, p.part))
  end
  if p.kind == "device" or p.kind == "param" then
    return (pcall(api.device_get, p.device))
  end
  return true
end

--- Diagnostics, sorted by kind and then by where they are. `target`: a clip
--- id (those about it and its notes), an address (those about it or what
--- it holds), or nil for all. `filter`: `namespace`, `severity` (a severity
--- or `{ min, max }`, min the least severe), `note` (a place in the clip),
--- `kind` (as `paw.diagnostic.kind`), `document`.
function M.get(target?: Target, filter?: Filter): {Diagnostic}
  filter = filter or {}
  local within: string = nil
  local clip: integer = nil
  if target is string then
    within = target
  elseif target is integer then
    clip = target
  elseif target is A.Thing then
    within = A.of(target)
    if getmetatable(target as {string: Data}) == paw.Clip as metatable<{string: Data}> then
      clip = (target as ClipOfLayer).id
    end
  end
  if clip then
    within = nil
  end
  local min, max = 1, 4
  local severity = filter.severity
  if severity is Range then
    min, max = severity_of(severity.max or 1), severity_of(severity.min or 4)
  elseif severity then
    min = severity_of(severity)
    max = min
  end
  local out: {Diagnostic} = {}
  for ns, docs in pairs(store) do
    if not filter.namespace or filter.namespace == ns then
      for doc, list in pairs(docs) do
        if not filter.document or filter.document == doc then
          local kept: {Diagnostic} = {}
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
    local kept: {Diagnostic} = {}
    for _, d in ipairs(out) do
      for _, place in ipairs(M.places(d)) do
        if place == filter.note then
          kept[#kept + 1] = d
          break
        end
      end
    end
    out = kept
  end
  return sorted(out)
end

--- How many diagnostics of each severity (as `get` takes its target):
--- `{ error = 1, warning = 2, info = 0, hint = 0, total = 3 }`.
function M.count(target?: Target, filter?: Filter): Count
  local out: Count = {error = 0, warning = 0, info = 0, hint = 0, total = 0}
  local by: {string: integer} = out as {string: integer}
  for _, d in ipairs(M.get(target, filter)) do
    local word = M.severity[d.severity]
    by[word], out.total = by[word] + 1, out.total + 1
  end
  return out
end

--- The worst severity said about an address or what it holds, or nil.
function M.worst(uri: Target, filter?: Filter): integer
  local worst: integer
  for _, d in ipairs(M.get(uri, filter)) do
    worst = math.min(worst or 4, d.severity)
  end
  return worst
end

--- Change how paw shows diagnostics. Returns the options in use.
---   paw.diagnostic.config({ virtual_text = false })
function M.config(opts?: Config): Config
  local all = options as {string: boolean}
  for k, v in pairs((opts or {}) as {string: boolean}) do
    all[k] = v
  end
  if opts then
    api.ui_redraw()
  end
  return util.merge(all, {}) as Config
end

-- Fixes ----------------------------------------------------------------------

--- Do a fix of a diagnostic as one undo step. Returns true if it did the fix.
function M.apply(d: Diagnostic, fix?: Fix): boolean
  fix = fix or d.fixes[1]
  if not fix then
    return false
  end
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
function M.actions(target?: Target, place?: integer | Filter): {Action}
  local out: {Action} = {}
  local filter: Filter
  if place is integer then
    filter = {note = place}
  else
    filter = place
  end
  for _, d in ipairs(M.get(target, filter)) do
    for _, fix in ipairs(d.fixes) do
      out[#out + 1] = {
        title = fix.title or "Fix", diagnostic = d, fix = fix, run = function(): boolean return M.apply(d, fix) end
      }
    end
  end
  table.sort(out, function(a: Action, b: Action): boolean return a.diagnostic.severity < b.diagnostic.severity end)
  return out
end

-- Where a diagnostic is, in words -------------------------------------------

local function part_name(id: integer): string
  local ok, t = pcall(api.part_get, id)
  return ok and t.name or ("part " .. id)
end

--- Where a diagnostic is about, in a few words: `Lead › Synth · cutoff`,
--- `chords 2.1.00`, `5.1.00–9.1.00`, `mix.wav`.
function M.where(d: Diagnostic): string
  local loc = d.location
  local p = A.parse(loc.uri)
  local t = loc.selector and loc.selector.time
  if not p then
    return loc.uri
  end
  if p.kind == "clip" or p.kind == "note" or p.kind == "control" then
    local ok, c = pcall(api.clip_get, p.clip)
    return ok and string.format("%s %s", c.name, paw.time.format(c.start + (d.at or 0))) or "a clip"
  end
  if p.kind == "part" or p.kind == "send" then
    return part_name(p.part) .. (t and (" " .. paw.time.format(t[1])) or "")
  end
  if p.kind == "device" or p.kind == "param" then
    local ok, dev = pcall(api.device_get, p.device)
    local name = part_name(p.part) .. " › " .. (ok and dev.name or "a device")
    if p.kind == "param" then
      for _, info in ipairs(ok and dev.param_info or {}) do
        if info.key == p.param then
          return name .. " · " .. (info.name or p.param)
        end
      end
      return name .. " · " .. p.param
    end
    return name
  end
  if p.kind == "render" then
    return (p.path:match("([^/]+)$") or p.path) .. (t and string.format(" %.1f s", t[1]) or "")
  end
  if t then
    return paw.time.format(t[1]) .. "–" .. paw.time.format(t[2])
  end
  return p.kind
end

--- A diagnostic in one line: `warning parallel-perfect: Parallel fifths … [midi-lsp]`.
function M.format(d: Diagnostic): string
  return string.format("%s%s: %s [%s]", M.severity[d.severity], d.rule and (" " .. d.rule) or "", d.message, d.source)
end

-- Going from one to the next --------------------------------------------------

--- Put the cursor of the view that shows it best on a diagnostic, and say it.
function M.show(d: Diagnostic)
  paw.ui.go(d.location)
  paw.notify(M.format(d), d.severity == 1 and "error" or d.severity == 2 and "warn" or "info")
end

--- Where the last jump went, and where it left the cursor: a view that
--- cannot put its cursor exactly there (a finding about the master, in the
--- arrange view) goes on from the diagnostic, not from the cursor.
local record Jump
  view: string
  at: {number}
  landed: {number}
end
local last_jump: Jump

--- A diagnostic and where the focused view places it.
local record Placed
  d: Diagnostic
  at: {number}
end

--- The next (`dir` 1) or previous (-1) diagnostic that the focused view can
--- show, from its cursor, `count` times, round the ends. The cursor goes
--- there. Returns the diagnostic, or nil when the view has none.
function M.jump(dir: integer, count?: integer): Diagnostic
  local view = paw.ui.focused
  local loc = paw.ui.locators[view]
  local found: Diagnostic
  if loc then
    local placed: {Placed} = {}
    for _, d in ipairs(M.get()) do
      local at = loc.place(d.location)
      if at then
        placed[#placed + 1] = {d = d, at = at}
      end
    end
    local function before(a: {number}, b: {number}): boolean
      for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if math.abs(x - y) > 1e-6 then
          return x < y
        end
      end
      return false
    end
    table.sort(placed, function(a: Placed, b: Placed): boolean return before(a.at, b.at) end)
    if #placed > 0 then
      local here = loc.position()
      if
        last_jump
        and last_jump.view == view
        and not before(here, last_jump.landed)
        and not before(last_jump.landed, here)
      then
        here = last_jump.at
      end
      for _ = 1, count or 1 do
        local pick: Placed
        if dir > 0 then
          for _, e in ipairs(placed) do
            if before(here, e.at) then
              pick = e
              break
            end
          end
          pick = pick or placed[1]
        else
          for i = #placed, 1, -1 do
            if before(placed[i].at, here) then
              pick = placed[i]
              break
            end
          end
          pick = pick or placed[#placed]
        end
        found, here = pick.d, pick.at
      end
    end
  end
  if not found then
    paw.notify("no diagnostics here")
    return nil
  end
  loc.go(found.location)
  last_jump = {view = view, at = loc.place(found.location), landed = loc.position()}
  paw.notify(M.format(found), found.severity == 1 and "error" or found.severity == 2 and "warn" or "info")
  return found
end

--- What `goto_next` and `goto_prev` take: how many to go.
local record GotoOptions
  count: integer
end

--- Go to the next diagnostic, or `opts.count` on (`]d`).
function M.goto_next(opts?: GotoOptions): Diagnostic
  return M.jump(1, opts and opts.count)
end
--- Go to the diagnostic before, or `opts.count` back (`[d`).
function M.goto_prev(opts?: GotoOptions): Diagnostic
  return M.jump(-1, opts and opts.count)
end

local KIND_TITLE: {string: string} = {
  clip = "Notes", part = "Parts", device = "Devices", time = "Time", project = "Project", render = "Renders"
}

--- Every diagnostic (of `target`, as `get` takes it) in a picker, as the
--- quickfix list, grouped by what they are about: Enter goes to one.
function M.list(target?: Target)
  local items: {ListItem} = {}
  local last: string
  for _, d in ipairs(M.get(target)) do
    local kind = M.kind(d)
    if kind ~= last then
      items[#items + 1] = {text = "── " .. (KIND_TITLE[kind] or kind)}
      last = kind
    end
    local said = M.format(d):gsub("^%a+ ", "")
    items[#items + 1] = {
      text = string.format("  %-7s %-24s %s", M.severity[d.severity], util.fit(M.where(d), 24), said), diagnostic = d
    }
  end
  if #items == 0 then
    paw.notify("no diagnostics")
    return
  end
  local source: contracts.PickSource<ListItem> = {
    title = "Diagnostics",
    items = items,
    on_choose = function(item: ListItem)
      if item and item.diagnostic then
        M.show(item.diagnostic)
      end
    end,
  }
  paw.pick(source)
end

--- Put the diagnostics in the quickfix list, as `vim.diagnostic.setqflist`:
--- `opts` has `target`, `severity` (the least severe), `title`, `open`.
--- `setloclist` puts them in the current window's location list.
function M.setqflist(opts?: ListOptions): QfList
  return paw.qf.diagnostics(opts)
end
--- The diagnostics in the current window's location list.
function M.setloclist(opts?: ListOptions): QfList
  local given = opts or {}
  local with: ListOptions = {}
  for k, v in pairs(given as {string: Data}) do
    (with as {string: Data})[k] = v
  end
  with.win = given.win or true
  return paw.qf.diagnostics(with)
end

-- Drawing ----------------------------------------------------------------------

local g = function(): contracts.Glyphs return paw.draw.g end

--- One clip's, `offset` beats from the roll's own.
function M.paint_portion(p: RollLayer, id: integer, offset: number)
  local list = M.get(id)
  if #list == 0 then
    return
  end
  local notes = clip_notes(id)
  local worst: {integer: integer} = {}
  for _, d in ipairs(list) do
    for _, place in ipairs(M.places(d)) do
      if not worst[place] or d.severity < worst[place] then
        worst[place] = d.severity
      end
    end
  end
  if options.underline then
    for place, severity in pairs(worst) do
      local n = notes[place]
      local x0, x1, row = p.x(n.start + offset), p.x(n.start + n.length + offset), p.row(n.pitch)
      if row then
        p.roll:fill(x0, row, math.max(1, x1 - x0), 1, nil, M.group("DiagnosticUnderline", severity))
      end
    end
  end
  for _, d in ipairs(list) do
    -- On the cell's left edge, where the diagnostic starts.
    if options.signs then
      p.ruler:text(p.x((d.at or 0) + offset), 0, g().mark, M.group("Diagnostic", d.severity))
    end
    if options.virtual_text then
      local last: types.Note
      for _, place in ipairs(M.places(d)) do
        local n = notes[place]
        if not last or n.start + n.length > last.start + last.length then
          last = n
        end
      end
      local row = last and p.row(last.pitch)
      if row then
        local x = p.x(last.start + last.length + offset) + 1
        local room = p.roll.width - x
        if room >= 8 then
          local text = api.str_width(d.message) > room and util.fit(d.message, room) or d.message
          p.roll:text(x, row, text, M.group("DiagnosticVirtualText", d.severity))
        end
      end
    end
  end
end

--- Mark the diagnostics of each clip that the piano roll edits, as one of
--- its layers. Each note has a line below it in the color of its severity.
--- The message comes after the last note while there is space, and a mark
--- on the ruler shows where it starts.
function M.paint_roll(p: RollLayer)
  for _, portion in ipairs(p.portions or {{id = p.clip.id, offset = 0}}) do
    M.paint_portion(p, portion.id, portion.offset or 0)
  end
end

-- A sign with its colour, and the message after it while there is room.
local function sign(buf: contracts.Buf, x: integer, y: integer, room: integer, severity: integer, message: string)
  buf:text(x, y, severity == 1 and g().error or g().warn, M.group("Diagnostic", severity))
  if options.virtual_text and message and room > 4 then
    local text = api.str_width(message) > room - 2 and util.fit(message, room - 2) or message
    buf:text(x + 2, y, text, M.group("DiagnosticVirtualText", severity))
  end
end

-- What the arrange view, the mixer and the device panel show, as layers of
-- theirs (`paw.ui.layer`), so that other modules' marks go beside them.
paw.ui.layer(
  "arrange",
  "clip",
  "diagnostics",
  30,
  function(c: PartLayer)
    if c.width < 3 or not next(store) then
      return
    end
    local worst = M.worst(A.clip(c.clip.id))
    if worst then
      c.buf:text(c.width - 1, 0, worst == 1 and g().error or g().warn, M.group("Diagnostic", worst))
    end
  end
)
-- A sign in the part column (paw/partcolumn.tl), as in Neovim's sign
-- column: the worst said of the part, its devices, its sends or its clips.
-- Its glyphs (`error`, `warn`) and styles (`error`, `warn`) can be set
-- with `paw.partcolumn.set_sign("diagnostics", ...)`.
paw.partcolumn.sign(
  "diagnostics",
  {
    priority = 30,
    glyphs = {},
    styles = {},
    render = function(part: integer, ctx: contracts.PartColumnContext): contracts.ColumnCells
      if not (options.signs and next(store)) then
        return nil
      end
      local worst = M.worst(A.part(part))
      if not worst then
        return nil
      end
      local which = worst == 1 and "error" or "warn"
      return {
        {ctx.glyphs[which] or (worst == 1 and g().error or g().warn), ctx.styles[which] or M.group("Diagnostic", worst)}
      }
    end,
    describe = function(part: integer): string
      if not next(store) then
        return nil
      end
      local n = M.count(A.part(part))
      if n.total == 0 then
        return nil
      end
      return string.format("diagnostics: %d errors, %d warnings", n.error, n.warning)
    end,
  }
)
-- Stretches of time on the arrange view's ruler (one of its layers).
local arrange = paw.ui.views:get("arrange") as contracts.ArrangeView
arrange.layers.diagnostics = function(_: contracts.ArrangeView, c: contracts.ArrangeLayer)
  if not next(store) then
    return
  end
  for _, d in ipairs(M.get(nil, {kind = "time"})) do
    local t = d.location.selector.time
    local x0, x1 = c.x(t[1]), c.x(t[2])
    if x1 > 0 and x0 < c.ruler.width then
      -- The stretch it is about, from the cell its start is in (marks sit on the left edge).
      local from = math.max(0, x0)
      c.ruler:fill(
        from, 0, math.max(1, math.min(c.ruler.width, x1) - from), 1, nil, M.group("DiagnosticUnderline", d.severity)
      )
      if x0 >= 0 then
        c.ruler:text(x0, 0, g().mark, M.group("Diagnostic", d.severity))
      end
    end
  end
end
-- A strip: a sign at the right end of its name plate.
paw.ui.layer(
  "mixer",
  "strip",
  "diagnostics",
  30,
  function(c: PartLayer)
    if not next(store) then
      return
    end
    local worst = M.worst(A.part(c.part))
    if worst then
      c.buf:text(c.x + c.width - 1, c.y, worst == 1 and g().error or g().warn, M.group("Diagnostic", worst))
    end
  end
)
-- A device: a sign after its name and what is said of it; a parameter: a sign before its name.
paw.ui.layer(
  "devices",
  "device",
  "diagnostics",
  30,
  function(c: PartLayer)
    if not next(store) then
      return
    end
    local list = M.get(A.device(c.device))
    if #list == 0 then
      return
    end
    local worst: integer = 4
    local own: Diagnostic
    for _, d in ipairs(list) do
      worst = math.min(worst, d.severity)
      if not own and d.location.uri == A.device(c.device) then
        own = d
      end
    end
    -- What is said of the device itself; its parameters have marks of their own.
    sign(c.buf, c.x, c.y, c.width, worst, own and own.message or (#list .. " diagnostics"))
  end
)
paw.ui.layer(
  "devices",
  "param",
  "diagnostics",
  30,
  function(c: PartLayer)
    if not next(store) then
      return
    end
    local worst = M.worst(A.param(c.device, c.param))
    if worst then
      c.buf:text(c.x, c.y, worst == 1 and g().error or g().warn, M.group("Diagnostic", worst))
    end
  end
)

--- The status line's piece: `E1 W2` for the clip in the piano roll, or the
--- whole project when none is open. Nil when there is nothing to say.
function M.status(): {contracts.Piece}
  if not next(store) then
    return nil
  end
  local view = paw.ui.views:get("pianoroll") as PianoRoll
  local n = M.count(paw.ui.visible("pianoroll") and view.clip_id or nil)
  if n.total == 0 then
    return nil
  end
  local by = n as {string: integer}
  local pieces: {contracts.Piece} = {}
  for i, word in ipairs({"error", "warning", "info", "hint"}) do
    if by[word] > 0 then
      if #pieces > 0 then
        pieces[#pieces + 1] = {" ", "StatusLine"}
      end
      pieces[#pieces + 1] = {
        ("EWIH"):sub(i, i) .. by[word], i == 1 and "StatusError" or i == 2 and "StatusWarn" or "StatusDim"
      }
    end
  end
  return pieces
end

--- The marks of the window in its piano roll for a clip. These are the
--- notes that diagnostics are about, by place from 0. Each has its worst
--- severity, the messages about it and the titles of its fixes.
function M.roll_marks(id: integer): {RollMark}
  local out: {RollMark} = {}
  local by_place: {integer: RollMark} = {}
  local list = M.get(id)
  local notes = #list > 0 and clip_notes(id) or {}
  for _, d in ipairs(list) do
    for _, place in ipairs(M.places(d)) do
      local mark = by_place[place]
      local n = notes[place]
      if not mark then
        mark = {
          index = place - 1,
          pitch = n.pitch,
          start = n.start,
          length = n.length,
          severity = d.severity,
          message = M.format(d),
          actions = {},
        }
        by_place[place], out[#out + 1] = mark, mark
      elseif d.severity < mark.severity then
        mark.severity, mark.message = d.severity, M.format(d) .. "\n" .. mark.message
      else
        mark.message = mark.message .. "\n" .. M.format(d)
      end
    end
  end
  for place, mark in pairs(by_place) do
    for _, action in ipairs(M.actions(id, place)) do
      mark.actions[#mark.actions + 1] = action.title
    end
  end
  return out
end

--- The marks of the window in other views. Each part (by id) has the worst
--- severity about it, its devices or its sends, and the first message.
--- The ranges of time are also marks.
function M.marks(): Marks
  local parts: {integer: PartMark} = {}
  local times: {TimeMark} = {}
  for _, d in ipairs(M.get()) do
    local kind = M.kind(d)
    local part = A.part_of(d.location.uri)
    if part and kind ~= "clip" then
      local t = parts[part]
      if not t or d.severity < t.severity then
        parts[part] = {part = part, severity = d.severity, message = M.format(d)}
      end
    elseif kind == "time" then
      local t = d.location.selector.time
      times[#times + 1] = {from = t[1], to = t[2], severity = d.severity, message = M.format(d)}
    end
  end
  local list: {PartMark} = {}
  for _, t in pairs(parts) do
    list[#list + 1] = t
  end
  table.sort(list, function(a: PartMark, b: PartMark): boolean return a.part < b.part end)
  return {parts = list, times = times}
end

local roll = paw.ui.views:get("pianoroll") as PianoRoll
roll.layer("diagnostics", 30, function(p: RollLayer) M.paint_roll(p) end)

-- The window's menu on a note: the `n`th of its fixes, as `actions` lists them.
local frontend = paw.frontend
frontend.act.note_action = function(clip: integer, place: integer, n: integer)
  local action = M.actions(clip, place)[n]
  if action then
    action.run()
  end
end

events.on(
  kernel.project_loaded,
  function()
    if next(store) then
      M.reset()
    end
  end
)

return M
