-- The vocal editor: a piano roll for one clip of a vocal track that shows
-- each note's lyric, the phonemes the engine made of it, which phrases are
-- rendered, and the pitch that is actually sung; plus the lyric sheet and the
-- singer picker. Keys are in utau.commands.
local api = paw.api
local util = paw.util
local music = paw.music
local utau = require("utau")
local notes = require("utau.notes")
local lyrics = require("utau.lyrics")
local proto = require("utau.proto")
local shapes = require("utau.shapes")
local strips = require("utau.strips")

local KEYS = 5 -- columns for note names
local TICKS = proto.TICKS

local c = require("paw.theme").palette
paw.ui.theme({
  UtauHeader = { fg = c.fg, bg = c.bg_alt },
  UtauSinger = { fg = c.bright, bg = c.bg_alt, bold = true },
  UtauNote = { fg = c.bg, bg = c.cyan },
  UtauNoteCursor = { fg = c.bg, bg = c.bright, bold = true },
  UtauNoteRest = { fg = c.dim, bg = c.bg_hl },
  UtauNoteError = { fg = c.bg, bg = c.red },
  UtauEntry = { fg = c.bg, bg = c.yellow, bold = true },
  UtauPitch = { fg = "#ffffff", bold = true },
  UtauPitd = { fg = c.orange, bold = true },
  UtauPhoneme = { fg = c.cyan, bg = c.bg_dark },
  UtauPhonemeError = { fg = c.red, bg = c.bg_dark, bold = true },
  UtauPending = { fg = c.dim, bg = c.bg_hl },
  UtauRendering = { fg = c.bg, bg = c.yellow },
  UtauDraft = { fg = c.bg, bg = "#5f8fbf" },
  UtauFinal = { fg = c.bg, bg = c.green },
  UtauError = { fg = c.bg, bg = c.red },
  UtauSheetCurrent = { fg = c.yellow, bold = true },
  UtauNoteSelected = { fg = c.bg, bg = c.yellow },
  UtauPhonemeChanged = { fg = c.orange, bg = c.bg_dark, bold = true },
  UtauPhonemeCursor = { fg = c.bg, bg = c.cyan, bold = true },
  UtauCurveBg = { bg = c.bg_dark },
  UtauCurve = { fg = c.green, bg = c.bg_dark },
  UtauCurveBase = { fg = c.line, bg = c.bg_dark },
  UtauCurveName = { fg = c.green, bg = c.bg_dark, bold = true },
})

local STATE_STYLE = {
  [proto.state.pending] = "UtauPending", [proto.state.rendering] = "UtauRendering",
  [proto.state.draft] = "UtauDraft", [proto.state.final] = "UtauFinal", [proto.state.error] = "UtauError",
}

local view = {
  clip_id = nil,
  pitch = 60,   -- cursor row
  beat = 0,     -- cursor column, in beats from the start of the clip
  top = nil,    -- pitch of the first row
  scroll = 0,   -- beat at the left edge
  entry = nil,  -- text being typed: { kind, index, chars, commit }
  sel = {},     -- notes chosen with the pointer, by `key_of`
  curve = "pitd", -- the curve shown under the notes
  ph = nil,     -- the phoneme the keys work on: { note = index, k = place in the note }
}

-- Selection ---------------------------------------------------------------------------

--- What names a note in a selection while other notes come and go.
local function key_of(note) return string.format("%d@%.6f", note.pitch, note.start) end
view.key_of = key_of

--- The visual mode selection in this editor, if there is one.
function view:visual_region()
  local region = paw.keymap.selection()
  if region and region.view == "utau" then return region end
end

--- The places of the selected notes in the clip, in order: the notes in the
--- visual mode selection while there is one, else the notes chosen with the
--- pointer. `list` is the clip's notes when the caller has them already.
function view:selected(list)
  if not self.clip_id then return {} end
  list = list or notes.list(self.clip_id)
  local out = {}
  local region = self:visual_region()
  if region then
    for i, n in ipairs(list) do
      if paw.edit.roll.inside(n, region) then out[#out + 1] = i end
    end
  elseif next(self.sel) then
    for i, n in ipairs(list) do
      if self.sel[key_of(n)] then out[#out + 1] = i end
    end
  end
  return out
end

--- The notes an edit works on: the selection, else the note under the cursor.
function view:targets(list)
  list = list or (self.clip_id and notes.list(self.clip_id)) or {}
  local out = self:selected(list)
  if #out == 0 then
    local _, index = self:note()
    if index then out[1] = index end
  end
  return out, list
end

--- Choose the notes at these places; `add` keeps what was chosen, and
--- `toggle` takes a chosen note out again.
function view:select(indices, add, toggle)
  local list = notes.list(self.clip_id)
  if not add then self.sel = {} end
  for _, i in ipairs(indices) do
    local n = list[i]
    if n then
      local k = key_of(n)
      if toggle and self.sel[k] then self.sel[k] = nil else self.sel[k] = true end
    end
  end
  api.ui_redraw()
end

function view:clear_selection()
  if next(self.sel) then
    self.sel = {}
    api.ui_redraw()
  end
end

--- The phrases of the clip as runs of note places: notes that follow each
--- other with no rest and no gap between them.
function view:phrases(list)
  list = list or notes.list(self.clip_id)
  local out, run, last_end = {}, nil, nil
  for i, n in ipairs(list) do
    local rest = notes.is_rest(notes.lyric(n) or "")
    if rest or not run or n.start > last_end + 1e-6 then
      run = nil
      if not rest then
        run = { first = i, last = i }
        out[#out + 1] = run
      end
    else
      run.last = i
    end
    if not rest then last_end = math.max(last_end or 0, n.start + n.length) end
    if rest then last_end = nil end
  end
  return out
end

--- The phrase around a beat, as `{ first, last }` places, or nil.
function view:phrase_at(beat, list)
  list = list or notes.list(self.clip_id)
  local best
  for _, p in ipairs(self:phrases(list)) do
    local a, b = list[p.first], list[p.last]
    if beat >= a.start - 1e-9 and beat < b.start + b.length then return p end
    if a.start <= beat then best = p end
  end
  return best
end

--- Change the target notes with `fn(note)`, as one edit; the selection and
--- the cursor go with the notes. Returns how many there were.
function view:change_targets(fn)
  local indices, list = self:targets()
  if #indices == 0 then return 0 end
  local under = select(2, self:note())
  local changed = {}
  for _, i in ipairs(indices) do
    local n = list[i]
    local was = key_of(n)
    fn(n)
    changed[#changed + 1] = { was = was, now = key_of(n) }
    if i == under then self.pitch, self.beat = n.pitch, n.start end
  end
  local sel = {}
  for k in pairs(self.sel) do sel[k] = true end
  for _, c in ipairs(changed) do
    if self.sel[c.was] then sel[c.was] = nil end
  end
  for _, c in ipairs(changed) do
    if self.sel[c.was] then sel[c.now] = true end
  end
  self.sel = sel
  api.clip_set_notes(self.clip_id, list)
  return #indices
end

function view:clip()
  if self.clip_id and pcall(api.clip_get, self.clip_id) then return api.clip_get(self.clip_id) end
  self.clip_id = nil
end

--- The vocal device of the clip's track.
function view:device()
  local clip = self:clip()
  return clip and utau.device_of(clip.track)
end

--- Open a MIDI clip of a vocal track in the editor.
function view:edit(clip_id)
  local clip = api.clip_get(clip_id)
  if clip.kind ~= "midi" then return paw.notify("only MIDI clips can be sung", "warn") end
  if not utau.device_of(clip.track) then
    return paw.notify("not a vocal track: `:utau.track` makes it one", "warn")
  end
  if self.clip_id ~= clip_id then self.sel, self.ph = {}, nil end
  self.clip_id, self.beat, self.scroll, self.top = clip_id, 0, 0, nil
  local first = notes.list(clip_id)[1]
  self.pitch = first and first.pitch or 60
  paw.ui.focus("utau")
end

--- The note under the cursor and its index.
function view:note()
  if not self.clip_id then return end
  return notes.at(self.clip_id, self.pitch, self.beat)
end

--- Move the cursor onto the note at `index` of the clip.
function view:go_to(index)
  local note = notes.list(self.clip_id)[index]
  if not note then return false end
  self.pitch, self.beat = note.pitch, note.start
  api.ui_redraw()
  return true
end

function view:move(dbeat, dpitch)
  local clip = self:clip()
  if not clip then return end
  -- One step past the last is allowed, so that a selection can reach the end.
  self.beat = util.clamp(self.beat + dbeat, 0, clip.length)
  self.pitch = util.clamp(self.pitch + dpitch, 0, 127)
  api.ui_redraw()
end

-- What modal editing works on, as in the piano roll: rows are pitches.
view.grid = {
  down = -1,
  get = function() return view.pitch, view.beat end,
  set = function(row, col)
    local clip = view:clip()
    if not clip then return end
    view.pitch, view.beat = util.clamp(row, 0, 127), util.clamp(col, 0, clip.length)
    api.ui_redraw()
  end,
  step = function() return paw.opt.note_grid end,
  -- Notes by what they sing: `/ka` finds the next note with "ka" in its lyric.
  search = function(text)
    local wanted, hits = text:lower(), {}
    for _, n in ipairs(view.clip_id and notes.list(view.clip_id) or {}) do
      if tostring(notes.lyric(n) or ""):lower():find(wanted, 1, true) then hits[#hits + 1] = { row = n.pitch, col = n.start } end
    end
    return hits
  end,
}

--- Jump to the next (or with -1 the previous) note in time.
function view:step_note(dir)
  if not self.clip_id then return end
  local list = notes.list(self.clip_id)
  local _, index = self:note()
  if index then return self:go_to(index + dir) end
  for i = dir > 0 and 1 or #list, dir > 0 and #list or 1, dir do
    local n = list[i]
    if (dir > 0 and n.start > self.beat + 1e-9) or (dir < 0 and n.start < self.beat - 1e-9) then
      return self:go_to(i)
    end
  end
end

--- Add a note at the cursor, or remove the one that is there.
function view:toggle_note()
  local clip = self:clip()
  if not clip then return end
  local note, index = self:note()
  local list = notes.list(clip.id)
  if note then
    table.remove(list, index)
    api.clip_set_notes(clip.id, list)
  else
    api.clip_add_notes(clip.id, { {
      pitch = self.pitch, start = self.beat, length = paw.opt.note_grid * 2, velocity = paw.opt.velocity,
    } })
  end
end

--- Change the note under the cursor with `fn(note)`.
function view:change(fn)
  local _, index = self:note()
  if not index then return false end
  local list = notes.list(self.clip_id)
  fn(list[index])
  api.clip_set_notes(self.clip_id, list)
  return true
end

-- Typing a lyric in place ----------------------------------------------------------

local function chars_of(text)
  local out = {}
  for ch in (text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
  return out
end

function view:entry_text()
  return self.entry and table.concat(self.entry.chars) or nil
end

--- Type the lyric of the note under the cursor. The first key replaces the
--- lyric (Right keeps it to type after it), Tab keeps what was typed and
--- moves on to the next note, Shift-Tab to the previous one, Enter keeps it,
--- Esc does not.
function view:edit_lyric()
  local note, index = self:note()
  if not note then return paw.notify("no note under the cursor", "warn") end
  self.entry = { kind = "lyric", index = index, chars = chars_of(notes.lyric(note) or ""), replace = true }
  paw.ui.grabber = function(key, pasted) self:entry_key(key, pasted) end
  paw.keymap.set_mode("i")
  api.ui_redraw()
end

--- Type some other text in place: `commit(text)` takes it when Enter or Tab
--- is pressed. `opts.kind` says what is typed, for the views to show it
--- where it belongs; the rest of `opts` stays in the entry for them.
function view:type_text(text, commit, opts)
  if self.entry then self:close_entry() end
  self.entry = paw.util.merge(opts or {}, { chars = chars_of(text or ""), replace = true, commit = commit })
  paw.ui.grabber = function(key, pasted) self:entry_key(key, pasted) end
  paw.keymap.set_mode("i")
  api.ui_redraw()
end

function view:close_entry()
  self.entry = nil
  paw.ui.grabber = nil
  paw.keymap.set_mode("n")
  api.ui_redraw()
end

function view:commit_entry()
  if not self.entry then return end
  if self.entry.commit then return self.entry.commit(self:entry_text()) end
  notes.set_lyric(self.clip_id, self.entry.index, self:entry_text())
end

function view:entry_key(key, pasted)
  local e = self.entry
  if not e then return end
  if e.commit and (key == "<Tab>" or key == "<S-Tab>") and not pasted then key = "<CR>" end
  if pasted and e.commit then
    for _, ch in ipairs(chars_of(key:gsub("[\r\n]", ""))) do e.chars[#e.chars + 1] = ch end
  elseif pasted then
    -- Several words fill the notes from this one on, as the lyric sheet does.
    local words = lyrics.tokens(key)
    if #words > 1 then
      lyrics.apply(self.clip_id, key, { first = e.index })
      self:go_to(math.min(#notes.list(self.clip_id), e.index + #words))
      return self:close_entry()
    end
    for _, ch in ipairs(chars_of(key:gsub("[\r\n]", ""))) do e.chars[#e.chars + 1] = ch end
  elseif key == "<Tab>" or key == "<S-Tab>" then
    self:commit_entry()
    local index = e.index + (key == "<Tab>" and 1 or -1)
    if self:go_to(index) then
      self.entry = { kind = "lyric", index = index, chars = chars_of(notes.lyric(notes.list(self.clip_id)[index]) or ""), replace = true }
    else
      return self:close_entry()
    end
  elseif key == "<CR>" then
    self:commit_entry()
    return self:close_entry()
  elseif key == "<Esc>" or key == "<C-c>" then
    return self:close_entry()
  elseif key == "<BS>" then
    if e.replace then e.chars = {} else table.remove(e.chars) end
  elseif key == "<C-u>" then
    e.chars = {}
  elseif key == "<Right>" or key == "<End>" then
    -- Keep the lyric and type after it.
  else
    local ch = key == "<Space>" and " " or key == "<lt>" and "<" or key
    if ch:match("^<.+>$") then return end
    -- The lyric shown when typing starts is replaced by the first key.
    if e.replace then e.chars = {} end
    e.chars[#e.chars + 1] = ch
  end
  e.replace = false
  api.ui_redraw()
end

-- Pitch -----------------------------------------------------------------------------

--- Bend the sung pitch at the cursor by `cents`, as a peak one grid step wide.
function view:bend(cents)
  return self:raise_curve(cents, "pitd")
end

--- The curves the editor can show: the parameters of the vocal device, as
--- `{ key, name, min, max, default, step }`.
function view:curves()
  local device = self:device()
  local out = {}
  for _, info in ipairs(device and api.device_get(device).param_info or {}) do
    if info.key ~= "voice" then
      local range = info.max - info.min
      local step = (info.key == "pitd" or info.key == "shfc") and 10 or range > 200 and 6 or 5
      out[#out + 1] = { key = info.key, name = info.name, min = info.min, max = info.max, default = info.default, step = step }
    end
  end
  return out
end

--- The curve shown under the notes, as `curves` gives it.
function view:curve_info(abbr)
  abbr = abbr or self.curve
  for _, c in ipairs(self:curves()) do
    if c.key == abbr then return c end
  end
end

--- Show the next (or with -1 the previous) curve under the notes.
function view:next_curve(dir)
  local list = self:curves()
  if #list == 0 then return end
  local at = 1
  for i, c in ipairs(list) do
    if c.key == self.curve then at = i end
  end
  self.curve = list[(at - 1 + dir) % #list + 1].key
  paw.notify("curve: " .. list[(at - 1 + dir) % #list + 1].name)
  api.ui_redraw()
end

--- Raise the chosen curve (or `abbr`) at the cursor by `steps` of its step,
--- or for the pitch by that many cents, as a peak one grid step wide.
function view:raise_curve(amount, abbr)
  local clip, device = self:clip(), self:device()
  if not clip or not device then return end
  abbr = abbr or self.curve
  local at = clip.start + self.beat
  local value = notes.bend(clip.track, device, abbr, at, amount, paw.opt.note_grid)
  local info = self:curve_info(abbr)
  paw.notify(string.format("%s %+g at %s", info and info.name:lower() or abbr, math.floor(value * 10 + 0.5) / 10, paw.time.format(at)))
end

--- Put the chosen curve (or `abbr`) back to its default under the note at
--- the cursor, or the whole clip.
function view:flatten(whole, abbr)
  local clip, device = self:clip(), self:device()
  if not clip or not device then return end
  abbr = abbr or self.curve
  local note = self:note()
  if whole or not note then
    notes.reset(clip.track, device, abbr, clip.start, clip.start + clip.length)
  else
    notes.reset(clip.track, device, abbr, clip.start + note.start, clip.start + note.start + note.length)
  end
end

-- Phonemes ----------------------------------------------------------------------------

--- The phonemes the engine made of the note at `index`, or an empty list.
function view:phonemes_of(index)
  local got = self.clip_id and utau.phonemes[self.clip_id]
  return got and got.notes[index] or {}
end

--- The phoneme the keys work on, with its note's place and its own (from 1):
--- the one chosen with `(` and `)` while its note is under the cursor, else
--- the first of the note under the cursor.
function view:phoneme()
  local _, index = self:note()
  if not index then return end
  local list = self:phonemes_of(index)
  if #list == 0 then return end
  local k = (self.ph and self.ph.note == index) and math.min(self.ph.k, #list) or 1
  return list[k], index, k
end

--- Go to the next (or with -1 the previous) phoneme, on to the next note's.
function view:step_phoneme(dir)
  local _, index, k = self:phoneme()
  if not index then
    local _, at = self:note()
    if not at then self:step_note(dir) end
    _, index, k = self:phoneme()
    if not index then return end
    self.ph = { note = index, k = k }
    return api.ui_redraw()
  end
  local list = self:phonemes_of(index)
  if list[k + dir] then
    self.ph = { note = index, k = k + dir }
  else
    local all = notes.list(self.clip_id)
    local i = index + dir
    while all[i] and #self:phonemes_of(i) == 0 do i = i + dir end
    if not all[i] then return end
    self:go_to(i)
    self.ph = { note = i, k = dir > 0 and 1 or #self:phonemes_of(i) }
  end
  api.ui_redraw()
end

--- Change one field of a phoneme's override (`phoneme` or `offset`, or
--- `nil` to clear all of them) on the note at `index`, phoneme `k` (from 1).
function view:set_phoneme(index, k, field, value)
  return notes.change_props(self.clip_id, function(p)
    local list = type(p.ph) == "table" and p.ph or {}
    local entry
    for _, o in ipairs(list) do
      if o.index == k - 1 then entry = o end
    end
    if field == nil then
      if not entry then return false end
      for i, o in ipairs(list) do
        if o == entry then table.remove(list, i) break end
      end
    else
      if not entry then
        entry = { index = k - 1 }
        list[#list + 1] = entry
      end
      if value == "" or value == 0 then value = nil end
      if entry[field] == value then return false end
      entry[field] = value
      local empty = true
      for key in pairs(entry) do
        if key ~= "index" then empty = false end
      end
      if empty then
        for i, o in ipairs(list) do
          if o == entry then table.remove(list, i) break end
        end
      end
    end
    table.sort(list, function(a, b) return a.index < b.index end)
    p.ph = #list > 0 and list or nil
    return true
  end, { [index] = true }) > 0
end

--- The override a phoneme has, or an empty table.
function view:phoneme_override(index, k)
  local note = notes.list(self.clip_id)[index]
  local props = note and note.meta and note.meta.utau or {}
  for _, o in ipairs(type(props.ph) == "table" and props.ph or {}) do
    if o.index == k - 1 then return o end
  end
  return {}
end

--- Move the start of the chosen phoneme by `ticks`.
function view:shift_phoneme(ticks)
  local _, index, k = self:phoneme()
  if not index then return paw.notify("no phoneme here: the engine has not sung this note yet", "warn") end
  self.ph = { note = index, k = k }
  local offset = (self:phoneme_override(index, k).offset or 0) + ticks
  self:set_phoneme(index, k, "offset", offset)
  paw.notify(string.format("phoneme %d starts %+d ticks from where the voicebank puts it", k, offset))
end

--- Type the phoneme to sing in place of the chosen one; empty sings its own.
function view:replace_phoneme()
  local p, index, k = self:phoneme()
  if not index then return paw.notify("no phoneme here: the engine has not sung this note yet", "warn") end
  self.ph = { note = index, k = k }
  local current = self:phoneme_override(index, k).phoneme or (p.phoneme ~= "" and p.phoneme or p.alias)
  self:type_text(current, function(text)
    self:set_phoneme(index, k, "phoneme", text)
  end, { kind = "phoneme", note = index, k = k })
end

--- Forget what was changed of the chosen phoneme.
function view:reset_phoneme()
  local _, index, k = self:phoneme()
  if index then self:set_phoneme(index, k, nil) end
end

-- Hearing -----------------------------------------------------------------------------

--- Play from the cursor, or stop.
function view:play_from_cursor()
  local clip = self:clip()
  if not clip then return end
  if paw.transport.playing then return paw.transport.stop() end
  paw.transport.seek(clip.start + self.beat)
  paw.transport.play()
end

--- Keep the playhead in sight while it plays: a page on when it leaves the
--- right edge, `span` beats being what shows. Returns the new scroll.
function view.follow(scroll, span, clip)
  local t = api.transport_get()
  if not t.playing then return scroll end
  local at = t.position - clip.start
  if at < 0 or at > clip.length then return scroll end
  if at >= scroll + span * 0.95 or at < scroll then
    return math.max(0, at - span * 0.05)
  end
  return scroll
end

-- Drawing ----------------------------------------------------------------------------

local function x_of(self, beat, zoom) return math.floor((beat - self.scroll) * zoom + 0.5) end

function view:render(buf, ctx)
  local w, h = buf.width, buf.height
  buf:fill(0, 0, w, h, " ", "Normal")
  local clip = self:clip()
  if not clip then
    paw.ui.titlebar(buf, { name = "Vocal", focused = ctx.focused })
    buf:text(2, 2, "No vocal clip open. Put the cursor on a clip of a vocal track and press", "Empty")
    buf:text(74, 2, "Enter", "EmptyKey")
    return
  end
  local device = utau.device_of(clip.track)
  local zoom, grid = paw.opt.note_zoom, paw.opt.note_grid
  -- The chosen curve gets a few rows under the notes when there is room.
  local curve_rows = (device and h >= 16) and 4 or 0
  local rows, tw = math.max(1, h - 4 - curve_rows), w - KEYS
  local span = tw / zoom
  local list = notes.list(clip.id)

  -- Keep the cursor on screen, or while playing the playhead.
  if not self.top then self.top = self.pitch + math.floor(rows / 2) end
  if self.pitch > self.top then self.top = self.pitch end
  if self.pitch <= self.top - rows then self.top = self.pitch + rows - 1 end
  self.top = util.clamp(self.top, rows - 1, 127)
  if api.transport_get().playing then
    self.scroll = view.follow(self.scroll, span, clip)
  else
    if self.beat < self.scroll then self.scroll = math.floor(self.beat) end
    if self.beat >= self.scroll + span - grid then self.scroll = math.ceil(self.beat - span + 1) end
  end
  self.scroll = math.max(0, self.scroll)
  self.geometry = { rows = rows, zoom = zoom }
  local chosen = {}
  for _, i in ipairs(self:selected(list)) do chosen[i] = true end

  -- Header: track, singer, render state, the cursor.
  local track = api.track_get(clip.track)
  local config = utau.config(clip.track)
  local singer = config.singer or "no singer (S to choose)"
  for _, s in ipairs(utau.singers) do
    if s.id == config.singer then singer = s.name end
  end
  local state, counts = utau.status(clip.track)
  local parts = {}
  for _, name in ipairs({ "final", "draft", "rendering", "pending", "error" }) do
    if counts[name] then parts[#parts + 1] = counts[name] .. " " .. name end
  end
  local detail = #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""
  -- The clip on its track's colour, as in the piano roll, then who sings
  -- it and how far the engine has got.
  local hue = paw.draw.track_hue(track)
  paw.ui.titlebar(buf, {
    pill = { (paw.opt.ascii and "" or "♪ ") .. clip.name, hue.pill }, name = track.name, focused = ctx.focused,
    context = singer .. "  " .. state .. detail,
    right = string.format("%s %s", music.name(self.pitch), paw.time.format(clip.start + self.beat)),
  })

  -- Ruler, coloured by the state of the phrase under each column.
  local ruler = buf:sub(KEYS, 1, tw, 1)
  buf:fill(0, 1, w, 1, " ", "Ruler")
  local beat_of = paw.tempo.seconds_to_beats
  local layout = utau.layouts[tostring(clip.track)]
  for _, p in ipairs(layout and layout.phrases or {}) do
    local x0 = x_of(self, beat_of(p.start) - clip.start, zoom)
    local x1 = x_of(self, beat_of(p.stop) - clip.start, zoom)
    ruler:fill(x0, 0, math.max(1, x1 - x0), 1, nil, STATE_STYLE[p.state] or "Ruler")
  end
  local lines = paw.draw.beats(ruler, self.scroll, span, zoom, clip.start)

  local roll = buf:sub(KEYS, 2, tw, rows)
  local end_x = x_of(self, clip.length, zoom)
  for row = 0, rows - 1 do
    local pitch = self.top - row
    paw.draw.piano_key(buf, row + 2, pitch, pitch == self.pitch, KEYS)
    roll:fill(0, row, tw, 1, " ", music.is_black(pitch) and "RollRowBlack" or "RollRow")
    for _, line in ipairs(lines) do roll:text(line.x, row, "│", line.bar and "RollBar" or nil) end
    if end_x < tw then roll:fill(math.max(0, end_x), row, tw, 1, " ", "RollOutside") end
  end

  local _, under = self:note()
  local phonemes = utau.phonemes[clip.id]
  local boxes = {}
  for index, note in ipairs(list) do
    local row = self.top - note.pitch
    local x0 = x_of(self, note.start, zoom)
    local nw = math.max(1, x_of(self, note.start + note.length, zoom) - x0)
    local lyric = notes.lyric(note) or paw.opt.utau_default_lyric
    local bad = false
    for _, p in ipairs(phonemes and phonemes.notes[index] or {}) do
      bad = bad or p.flags % 2 == 1
    end
    local style = index == under and "UtauNoteCursor" or chosen[index] and "UtauNoteSelected"
      or notes.is_rest(lyric) and "UtauNoteRest" or bad and "UtauNoteError" or hue.note
    if self.entry and self.entry.kind == "lyric" and self.entry.index == index then
      style, lyric = "UtauEntry", self:entry_text() .. "▏"
    end
    if row >= 0 and row < rows then
      roll:fill(x0, row, nw, 1, " ", style)
      boxes[#boxes + 1] = { x = x0, row = row, w = nw, text = lyric, style = style }
    end
  end

  -- Where the terminal shows pictures, the pitch each note is sung on and
  -- the pitch the engine sang are lines in pixels under the notes.
  local win_id = ctx.win and ctx.win.id or "float"
  local pitd_lane = device and notes.lane(clip.track, device, "pitd")
  local scroll, top = self.scroll, self.top
  local pictured = roll:strip(0, 0, tw, rows, {
    key = "utau:roll#" .. win_id, under = true,
    draw = function(g, px)
      strips.roll(g, px, { list = list, clip = clip, scroll = scroll, zoom = zoom, top = top,
        pitd = pitd_lane and api.lane_points(pitd_lane), sung = utau.pitch[clip.id] })
    end,
  })

  -- The pitch the user drew, as dots, and the pitch that is sung, as a line.
  if device and not pictured then
    local lane = notes.lane(clip.track, device, "pitd")
    local points = lane and api.lane_points(lane) or {}
    if #points > 0 then
      local over = notes.walker(list)
      local value = notes.sampler(points, 0)
      for col = 0, tw - 1 do
        local beat = self.scroll + (col + 0.5) / zoom
        local note = beat < clip.length and over(beat)
        local cents = value(clip.start + beat)
        if note and beat < note.start + note.length then
          if math.abs(cents) >= 5 then
            local row = self.top - math.floor(note.pitch + cents / 100 + 0.5)
            if row >= 0 and row < rows then roll:text(col, row, "·", "UtauPitd") end
          end
        end
      end
    end
  end
  local sung = not pictured and utau.pitch[clip.id]
  if sung then
    local columns = {}
    for tick, cents in pairs(sung.ticks) do
      local col = math.floor((tick / TICKS - self.scroll) * zoom)
      if col >= 0 and col < tw then
        local c = columns[col] or { 0, 0 }
        c[1], c[2] = c[1] + cents, c[2] + 1
        columns[col] = c
      end
    end
    for col, sum in pairs(columns) do
      local semis = sum[1] / sum[2] / 100
      local nearest = math.floor(semis + 0.5)
      local frac = semis - nearest
      local row = self.top - nearest
      if row >= 0 and row < rows then
        roll:text(col, row, frac > 0.17 and "▔" or frac < -0.17 and "▁" or "─", "UtauPitch")
      end
    end
  end
  -- Lyrics last, so the pitch line does not hide them.
  for _, box in ipairs(boxes) do
    roll:sub(box.x, box.row, box.w, 1):text(0, 0, box.text, box.style)
    if self.entry and box.style == "UtauEntry" then
      api.ui_cursor(ctx.x + KEYS + box.x + math.min(box.w - 1, api.str_width(box.text) - 1), ctx.y + 2 + box.row)
    end
  end

  if not under and not self.entry then
    roll:fill(x_of(self, self.beat, zoom), self.top - self.pitch, math.max(1, math.floor(grid * zoom)), 1, nil, "RollCursor")
  end
  -- The selection of visual mode: a stretch of time, a block, or whole pitches.
  local selection = ctx.focused and paw.keymap.selection()
  if selection then
    local x0, x1 = math.max(0, x_of(self, selection.c0, zoom)), math.min(tw, x_of(self, selection.c1, zoom))
    local y0, y1 = math.max(0, self.top - selection.r1), math.min(rows - 1, self.top - selection.r0)
    if selection.kind == "line" then
      x0, x1 = 0, tw
    elseif selection.kind == "char" then
      y0, y1 = 0, rows - 1
    end
    if x1 > x0 and y1 >= y0 then roll:fill(x0, y0, x1 - x0, y1 - y0 + 1, nil, "Visual") end
  end
  local t = api.transport_get()
  local px = x_of(self, t.position - clip.start, zoom)
  if px >= 0 and px < tw and t.position >= clip.start and t.position <= clip.start + clip.length then
    roll:fill(px, 0, 1, rows, nil, "Playhead")
  end

  -- The chosen curve, under the notes: its name and value at the cursor on
  -- the left, a line (`paw.draw.curve`) from its lowest to its highest value.
  if curve_rows > 0 then
    local info = self:curve_info() or self:curves()[1]
    local cy = 2 + rows
    buf:fill(0, cy, w, curve_rows, " ", "UtauCurveBg")
    if info then
      self.curve = info.key
      local lane = notes.lane(clip.track, device, info.key)
      local points = lane and api.lane_points(lane) or {}
      local constant = api.device_get(device).params[info.key] or info.default
      local value = #points > 0 and notes.sampler(points, info.default) or function() return constant end
      local range = math.max(1e-9, info.max - info.min)
      local area = buf:sub(KEYS, cy, tw, curve_rows)
      local drawn = area:strip(0, 0, tw, curve_rows, {
        key = "utau:curve#" .. win_id, under = true,
        draw = function(g, px)
          strips.curve(g, px, { info = info, points = points, constant = constant, clip = clip, scroll = scroll, zoom = zoom })
        end,
      })
      if not drawn then
        local level = math.min(curve_rows * 4 - 1, math.floor((info.default - info.min) / range * curve_rows * 4))
        local base_row = curve_rows - 1 - math.floor(level / 4)
        area:fill(0, base_row, tw, 1, "┄", "UtauCurveBase")
        paw.draw.curve(area, 0, curve_rows, function(i)
          local beat = self.scroll + (i + 0.5) / (zoom * 2)
          if beat > clip.length then return nil end
          return (value(clip.start + beat) - info.min) / range
        end, "UtauCurve")
      end
      if drawn then
        -- Over the picture, a line on the cell's left edge rather than a
        -- block, so that moving it changes no pixels where blocks are painted in.
        area:fill(x_of(self, self.beat, zoom), 0, 1, curve_rows, paw.draw.g.playhead, { fg = c.normal })
      else
        area:fill(x_of(self, self.beat, zoom), 0, 1, curve_rows, nil, "RollCursor")
      end
      local here = value(clip.start + self.beat)
      buf:text(0, cy, util.fit(info.key, KEYS), "UtauCurveName")
      buf:text(0, cy + 1, util.fit(string.format("%g", math.floor(here * 10 + 0.5) / 10), KEYS), "UtauCurveName")
    end
  end

  -- Phonemes, under the notes they belong to; the one the keys work on is
  -- marked, and what is being typed for one is shown in its place.
  local strip = buf:sub(KEYS, h - 2, tw, 1)
  buf:fill(0, h - 2, w, 1, " ", "UtauPhoneme")
  buf:text(0, h - 2, "phon", "UtauPhoneme")
  local _, ph_note, ph_k = self:phoneme()
  local marked = self.ph and ph_note == self.ph.note
  for note_index, list_of in pairs(phonemes and phonemes.notes or {}) do
    for k, p in ipairs(list_of) do
      local name = p.phoneme ~= "" and p.phoneme or p.alias
      local style = p.flags % 2 == 1 and "UtauPhonemeError" or math.floor(p.flags / 2) % 2 == 1 and "UtauPhonemeChanged" or "UtauPhoneme"
      local e = self.entry
      if e and e.kind == "phoneme" and e.note == note_index and e.k == k then
        name, style = self:entry_text() .. "▏", "UtauEntry"
      elseif marked and note_index == ph_note and k == ph_k then
        style = "UtauPhonemeCursor"
      end
      strip:text(x_of(self, p.start / TICKS, zoom), 0, name, style)
    end
  end

  -- What is under the cursor.
  local info
  if self.entry then
    info = self.entry.kind == "lyric" and " lyric: Tab next note, Shift-Tab previous, Enter done, Esc cancel"
      or " " .. (self.entry.label or self.entry.kind or "text") .. ": Enter keeps it, Esc drops it, empty puts it back"
  else
    local note, index = self:note()
    if note then
      local props = note.meta and note.meta.utau or {}
      local names = {}
      for k, p in ipairs(phonemes and phonemes.notes[index] or {}) do
        local name = (p.flags % 2 == 1 and "!" or "") .. (p.phoneme ~= "" and p.phoneme or p.alias)
        if marked and index == ph_note and k == ph_k then name = "(" .. name .. ")" end
        names[#names + 1] = name
      end
      local vb = shapes.vb(note)
      info = string.format(" %s %s  len %g  lyric %q  [%s]%s%s", music.name(note.pitch),
        paw.time.format(clip.start + note.start), note.length, notes.lyric(note) or paw.opt.utau_default_lyric,
        table.concat(names, " "),
        vb and string.format("  vibrato %g%% %gms %gc", vb[1], vb[2], vb[3]) or "",
        props.tu and ("  tuning " .. props.tu) or "")
      local n = #self:selected(list)
      if n > 1 then info = info .. string.format("  (%d selected)", n) end
    else
      info = " "
    end
    if device then
      local pitd = notes.curve_at(clip.track, device, "pitd", clip.start + self.beat)
      if math.abs(pitd) >= 0.5 then info = info .. string.format("  pitch %+dc", math.floor(pitd + 0.5)) end
    end
  end
  buf:fill(0, h - 1, w, 1, " ", "UtauHeader")
  buf:text(0, h - 1, info, "UtauHeader")
end

function view:on_mouse(event)
  local g = self.geometry
  if not g or not self:clip() then return end
  if event.kind == "scroll_up" then self.top = math.min(127, self.top + 2) end
  if event.kind == "scroll_down" then self.top = math.max(g.rows - 1, self.top - 2) end
  if event.kind == "down" and event.y >= 2 and event.y < 2 + g.rows and event.x >= KEYS then
    local grid = paw.opt.note_grid
    self.pitch = self.top - (event.y - 2)
    self.beat = math.max(0, math.floor((self.scroll + (event.x - KEYS) / g.zoom) / grid) * grid)
    if event.button == "right" then self:edit_lyric() end
  end
  self.pitch = util.clamp(self.pitch, self.top - g.rows + 1, self.top)
  api.ui_redraw()
end

paw.ui.view("utau", view)
paw.ui.dock("utau", { side = "bottom", hidden = true })
-- The keys worth knowing first, for the line at the bottom of the screen.
if paw.ui.keybar then
  paw.ui.keybar.set("utau", "n", {
    { "i", "note" }, { "c", "lyric" }, { "<Tab>", "next note" }, { "<A-l>", "longer" }, { "<A-h>", "shorter" },
    { "}", "raise curve" }, { "]c", "curve" }, { "]p", "phoneme" }, { "~", "vibrato" }, { "<Space>", "play" },
    { "S", "singer" }, { "<C-w>p", "back" },
  })
end
-- In its window Ctrl-A chooses every note, as in other programs; in the
-- terminal it raises the pitch, as in every view.
view.window_keys = { ["<C-a>"] = "gA" }

-- The lyric sheet ---------------------------------------------------------------------

local sheet = { line = 1, per_kana = false }

--- The clip the sheet shows: the editor's, else the one under the cursor.
function sheet:clip()
  local clip = view:clip()
  if clip then return clip end
  local at = paw.cursor.clip()
  local found = at and api.clip_get(at.id)
  if found and found.kind == "midi" and utau.device_of(found.track) then return found end
end

--- The line holding the note being sung, or under the editor's cursor.
function sheet:current(lines, list, clip)
  local t = api.transport_get()
  local beat = t.playing and t.position - clip.start or view.beat
  local current
  for i, n in ipairs(list) do
    if n.start <= beat + 1e-9 then current = i end
  end
  for i, line in ipairs(lines) do
    if current and current >= line.first and current <= line.last then return i, current end
  end
end

function sheet:render(buf, ctx)
  local w, h = buf.width, buf.height
  buf:fill(0, 0, w, h, " ", "Normal")
  local clip = self:clip()
  paw.ui.titlebar(buf, { name = "Lyrics", context = clip and clip.name or nil, focused = ctx.focused })
  if not clip then
    buf:text(1, 2, "No vocal clip.", "Dim")
    return
  end
  local _, lines, list = lyrics.sheet(clip.id, paw.opt.utau_default_lyric)
  self.lines = lines
  self.line = util.clamp(self.line, 1, math.max(1, #lines))
  local current, note = self:current(lines, list, clip)
  local row = 1
  for i, line in ipairs(lines) do
    if row >= h - 1 then break end
    local x = 1
    buf:text(0, row, i == self.line and "▸" or " ", "Accent")
    for index = line.first, line.last do
      local word = notes.lyric(list[index]) or paw.opt.utau_default_lyric
      local width = api.str_width(word)
      if x + width >= w and x > 1 then
        row, x = row + 1, 1
        if row >= h - 1 then break end
      end
      local style = index == note and "UtauSheetCurrent" or i == current and "Normal" or "Dim"
      buf:text(x, row, word, style)
      x = x + width + 1
    end
    row = row + 1
  end
  buf:text(1, h - 1, string.format("%d notes, %d lines%s   c edit line", #list, #lines,
    self.per_kana and ", kana per note" or ""), "Dim")
end

--- Retype the selected line; its words go to its notes in order.
function sheet:edit_line()
  local clip = self:clip()
  local line = clip and self.lines and self.lines[self.line]
  if not line then return end
  local list = notes.list(clip.id)
  local words = {}
  for i = line.first, line.last do words[#words + 1] = notes.lyric(list[i]) or paw.opt.utau_default_lyric end
  paw.ui.input({ prompt = "Line " .. self.line .. ": ", text = table.concat(words, " "), history = "utau.sheet" },
    function(text)
      local count = lyrics.apply(clip.id, text, { first = line.first, last = line.last, per_kana = self.per_kana })
      paw.notify(string.format("%d lyrics changed", count))
    end)
end

paw.ui.view("utau_lyrics", sheet)
paw.ui.dock("utau_lyrics", { side = "right", size = 34, hidden = true })

-- The singer picker ---------------------------------------------------------------------

local picker = { row = 1, filter = "", modal = true }

function picker:matches()
  local out = {}
  local filter = self.filter:lower()
  for _, s in ipairs(utau.singers) do
    local text = (s.name .. " " .. s.id .. " " .. s.type):lower()
    if filter == "" or text:find(filter, 1, true) then out[#out + 1] = s end
  end
  return out
end

function picker:open(track_id)
  self.track, self.filter, self.row = track_id, "", 1
  if #utau.singers == 0 then
    return paw.notify("no singers yet: " .. (utau.engine.reason or ("the engine is " .. utau.engine.state)), "warn")
  end
  paw.ui.open("utau_singers", { title = "Singer", width = 72, height = 20 })
end

function picker:render(buf)
  local list = self:matches()
  self.row = util.clamp(self.row, 1, math.max(1, #list))
  local current = self.track and utau.config(self.track).singer
  buf:text(0, 0, "/" .. self.filter, "Accent")
  local rows = buf.height - 2
  local first = math.max(1, self.row - rows + 1)
  for i = first, math.min(#list, first + rows - 1) do
    local s = list[i]
    local y = i - first + 1
    if i == self.row then buf:fill(0, y, buf.width, 1, " ", "Selected") end
    buf:text(1, y, (s.id == current and "● " or "  ") .. s.name, i == self.row and "Title" or "Normal")
    buf:text(buf.width - 12, y, s.type, "Dim")
  end
  buf:text(0, buf.height - 1, "type to filter  ↑↓ choose  Enter sets the singer  Esc closes", "Dim")
end

function picker:on_key(key)
  local list = self:matches()
  if key == "<Esc>" then return paw.ui.close() end
  if key == "<Down>" or key == "<C-n>" then
    self.row = self.row + 1
  elseif key == "<Up>" or key == "<C-p>" then
    self.row = self.row - 1
  elseif key == "<CR>" then
    local s = list[self.row]
    paw.ui.close()
    if s and self.track then
      utau.configure(self.track, { singer = s.id })
      paw.notify("singer: " .. s.name)
    end
  elseif key == "<BS>" then
    self.filter = self.filter:sub(1, -2)
  elseif not key:match("^<.+>$") or key == "<Space>" then
    self.filter = self.filter .. (key == "<Space>" and " " or key)
    self.row = 1
  end
  api.ui_redraw()
end

paw.ui.view("utau_singers", picker)

return { editor = view, sheet = sheet, picker = picker }
