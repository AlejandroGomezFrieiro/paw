-- MIDI LSP's dialect, as an adapter for `paw.lsp`: its `initialize` with a
-- protocol version and the configuration, `midi/didOpen|didChange|didClose`
-- with the clip subject's document (MIDI LSP's take snapshot), and its
-- answers (`midi/publishDiagnostics` in ticks and note ids,
-- `midi/publishAnalysis`, `midi/hover`, `midi/completion`, `midi/line`,
-- `midi/velocity`, `midi/cc`) turned into this program's locations and
-- workspace edits. Any server that speaks MIDI LSP's protocol uses it with
-- `adapter = "midi-lsp"`.
local api = paw.api
local A = paw.address

local PPQ = 960
local function beats(ticks) return (tonumber(ticks) or 0) / PPQ end
local function tick(b) return math.floor(b * PPQ + 0.5) end

local function clip_of(doc) return A.parse(doc.address).clip end

local M = { handlers = {} }

-- Protocol version 2; the engine takes its rule configuration at initialize.
function M.initialize(_, offer) return paw.util.merge(offer, { protocolVersion = 2 }) end

-- Version 2's capabilities, or version 1's booleans read as them.
function M.capabilities(_, result)
  local raw = type(result.capabilities) == "table" and result.capabilities or {}
  local caps = { raw = raw, subjects = { "clip" } }
  if (tonumber(result.protocolVersion) or 1) < 2 then
    caps.diagnostics = raw.diagnostics and true or nil
    caps.hover = raw.hover and true or nil
    caps.completion = raw.completion and { lanes = { "notes", "velocity", "cc" } } or nil
    caps.analysis = raw.chords and { "key", "chords" } or nil
    return caps
  end
  caps.diagnostics = raw.diagnosticProvider and true or nil
  caps.hover = raw.hoverProvider and true or nil
  local c = raw.completionProvider
  caps.completion = c and { lanes = type(c) == "table" and c.lanes or { "notes" } } or nil
  caps.analysis = raw.analysisProvider
  return caps
end

function M.initialized(_, result)
  if (tonumber(result.protocolVersion) or 1) >= 2 then return "initialized", require("paw.lsp.rpc").object() end
end

-- Requests: the engine answers them, and refuses a document it cannot read.
function M.open(_, doc) return "midi/didOpen", doc.data, true end
function M.change(_, doc) return "midi/didChange", doc.data, true end
function M.close(_, doc) return "midi/didClose", { uri = doc.uri } end

M.handlers["midi/publishDiagnostics"] = function(client, params, lsp)
  local doc = lsp.document(client, params.uri)
  -- Only about the document as last sent.
  if not doc or (params.hash and params.hash ~= doc.key) then return end
  local id = clip_of(doc)
  local list = {}
  for _, d in ipairs(params.diagnostics or {}) do
    local fixes = {}
    for _, fix in ipairs(d.fixes or {}) do
      local changes = {}
      for _, e in ipairs(fix.edits or {}) do
        local uri = A.note(id, e.note)
        if e.delete then
          changes[#changes + 1] = { uri = uri, delete = true }
        else
          changes[#changes + 1] = {
            uri = uri,
            set = {
              pitch = e.pitch,
              start = e.start and beats(e.start),
              length = e.length and beats(e.length),
              velocity = e.vel,
            },
          }
        end
      end
      fixes[#fixes + 1] = { title = fix.title, edit = changes }
    end
    local selector = { time = { beats(d.start), beats(d["end"] or d.start) } }
    if d.notes and #d.notes > 0 then selector.notes = d.notes end
    list[#list + 1] = {
      location = { uri = A.clip(id), selector = selector },
      severity = d.severity,
      message = d.message,
      rule = d.code or d.rule,
      source = d.source or client.name,
      fixes = fixes,
      data = { related = d.related },
    }
  end
  lsp.publish(client, doc, list)
end

-- Chords and keys in project beats, as `paw.harmony` has them.
M.handlers["midi/publishAnalysis"] = function(client, params, lsp)
  local doc = lsp.document(client, params.uri)
  if not doc or (params.hash and params.hash ~= doc.key) then return end
  local c = api.clip_get(clip_of(doc))
  local chords, keys = {}, {}
  for _, ch in ipairs(params.chords or {}) do
    if ch.start then
      chords[#chords + 1] = {
        at = c.start + beats(ch.start),
        length = beats(ch["end"] - ch.start),
        root = ch.root,
        quality = ch.quality,
        bass = ch.bass or ch.root,
        name = ch.name,
        roman = ch.roman,
        tones = ch.tones,
        ["function"] = ch["function"],
        cadence = ch.cadence,
      }
    end
  end
  local mode = function(k) return tostring(k.scale or k.mode or "major") end
  for _, k in ipairs(params.keys or {}) do
    if k.root then
      local from = k.start and c.start + beats(k.start) or c.start
      local to = k["end"] and c.start + beats(k["end"]) or c.start + c.length
      keys[#keys + 1] = { at = from, length = to - from, tonic = k.root, mode = mode(k), name = k.name }
    end
  end
  local key = params.key
    and params.key.root
    and { tonic = params.key.root, mode = mode(params.key), name = params.key.name }
  lsp.analysis(client, doc, { chords = chords, keys = keys, key = key })
end

-- Hover answers musical facts: the note's name and degree, the chord, the key.
local function hover_lines(result)
  if type(result) ~= "table" then return {} end
  local contents = result.contents
  if type(contents) == "table" and contents.value then contents = contents.value end
  if type(contents) == "string" then
    local out = {}
    for line in (contents .. "\n"):gmatch("([^\n]*)\n") do
      out[#out + 1] = line
    end
    if out[#out] == "" then out[#out] = nil end
    return out
  end
  local out = {}
  local p = result.pitch
  if type(p) == "table" then
    out[#out + 1] = "note   "
      .. tostring(p.name or p.pitch)
      .. (p.degree and ("  (degree " .. p.degree .. " of the key)") or "")
  end
  local ch = result.chord
  if type(ch) == "table" then
    out[#out + 1] = "chord  " .. tostring(ch.name) .. (ch.roman and ch.roman ~= ch.name and ("  " .. ch.roman) or "")
  end
  local key = result.key
  if type(key) == "table" then out[#out + 1] = "key    " .. tostring(key.name or key.root) end
  return out
end
M.hover_lines = hover_lines

function M.hover(_, doc, location)
  local p = A.parse(location.uri)
  local at, pitch = 0, nil
  if p and p.kind == "note" then
    local n = A.resolve(location.uri)
    if n then
      at, pitch = n.start, n.pitch
    end
  elseif location.selector then
    at = location.selector.time and location.selector.time[1] or 0
    pitch = location.selector.pitch and location.selector.pitch[1]
  end
  return "midi/hover", { uri = doc.uri, hash = doc.key, tick = tick(at), pitch = pitch }, hover_lines
end

-- MIDI LSP has no code actions of its own: its fixes come with its diagnostics.
function M.actions() return nil end

-- A server's suggested notes in the clip's beats.
local function ghost_notes(notes)
  local out = {}
  for _, n in ipairs(notes or {}) do
    out[#out + 1] =
      { pitch = n.pitch, start = beats(n.start), length = beats(n["end"] - n.start), velocity = n.vel or 100 }
  end
  return out
end

-- The ids of the notes of a note set in a clip, found by pitch and start.
local function ids_of(id, set)
  local out = {}
  for _, n in ipairs(set or {}) do
    local nid = n.id
    if not nid then
      local found = api.clip_notes(
        id,
        { from = (n.start or n.at) - 1e-6, to = (n.start or n.at) + 1e-6, low = n.pitch, high = n.pitch }
      )
      nid = found[1] and found[1].id
    end
    if nid then out[#out + 1] = nid end
  end
  return out
end

-- Notes after `at`; with a selection, a line under it and velocities for
-- it; with a controller, a curve for it; each as the server's lanes allow.
function M.complete(client, doc, ctx)
  local lsp = paw.lsp
  local base = { uri = doc.uri, hash = doc.key }
  local asks = {}
  if lsp.has(client, "completion", "notes") then
    asks[#asks + 1] = {
      method = "midi/completion",
      params = paw.util.merge(
        base,
        { position = tick(ctx.at or 0), count = ctx.count or 3, mode = ctx.mode or "auto" }
      ),
      translate = function(result)
        local out = {}
        for _, item in ipairs(result.items or {}) do
          out[#out + 1] = {
            label = item.label or item.kind or "notes",
            detail = item.kind and string.format("%s %.2f", item.kind, item.score or 0) or nil,
            notes = ghost_notes(item.notes),
          }
        end
        return out
      end,
    }
  end
  local selected = ctx.selection and ids_of(ctx.clip, ctx.selection)
  if selected and #selected > 0 and lsp.has(client, "completion", "line") then
    asks[#asks + 1] = {
      method = "midi/line",
      params = paw.util.merge(base, { notes = selected }),
      translate = function(result)
        local out = {}
        for _, item in ipairs(result.items or {}) do
          out[#out + 1] = { label = item.label or "line", detail = item.kind, notes = ghost_notes(item.notes) }
        end
        return out
      end,
    }
  end
  if selected and #selected > 0 and lsp.has(client, "completion", "velocity") then
    asks[#asks + 1] = {
      method = "midi/velocity",
      params = paw.util.merge(base, { notes = selected }),
      translate = function(result)
        local out = {}
        for _, item in ipairs(result.items or {}) do
          local velocities = {}
          for _, e in ipairs(item.edits or {}) do
            local _, place = A.find_note(ctx.clip, e.note)
            if place then velocities[place] = e.vel end
          end
          out[#out + 1] =
            { label = item.label or "velocity", detail = "velocities", notes = {}, velocities = velocities }
        end
        return out
      end,
    }
  end
  if ctx.controller and lsp.has(client, "completion", "cc") then
    asks[#asks + 1] = {
      method = "midi/cc",
      params = paw.util.merge(base, { cc = ctx.controller }),
      translate = function(result)
        local out = {}
        for _, item in ipairs(result.items or {}) do
          local controls = {}
          for _, p in ipairs(item.points or {}) do
            controls[#controls + 1] =
              { start = beats(p.tick), type = "cc", number = ctx.controller, value = p.value / 127 }
          end
          out[#out + 1] = {
            label = item.label or ("CC " .. ctx.controller),
            detail = "controller curve",
            notes = {},
            controls = controls,
          }
        end
        return out
      end,
    }
  end
  return asks
end

paw.lsp.adapter("midi-lsp", M)
return M
