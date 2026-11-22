-- The piano roll: edit the notes of a MIDI clip, or of several at once (see
-- `paw.roll_clips`), with other tracks' notes shown behind them.
local api = paw.api
local util = paw.util
local music = paw.music
local clips = require("paw.roll_clips")
paw.roll_clips = clips

local KEYS = 5 -- columns for the note names on the left

local view = {
  clip_id = nil, -- the active clip: where new notes go
  pitch = 60, -- cursor row
  beat = 0, -- cursor column, in beats from the start of the active clip
  top = 72, -- pitch of the first row
  scroll = 0, -- beat at the left edge
  -- Each window of the roll has its own clip, cursor and scroll: two
  -- windows show two clips, or one clip twice.
  window_state = { "clip_id", "pitch", "beat", "top", "scroll", "seen_jump", "geometry", "length" },
  window_fresh = { "geometry" },
}
paw.seats.fields(
  "pianoroll",
  view,
  { "clip_id", "pitch", "beat", "top", "scroll", "seen_jump", "geometry", "length" },
  { pitch = 60, beat = 0, top = 72, scroll = 0 }
)

function view:clip()
  if self.clip_id and pcall(api.clip_get, self.clip_id) then return paw.clip(self.clip_id) end
  self.clip_id = nil
end

--- Where play starts from this view: the cursor, as a beat of the song.
function view:play_beat()
  local clip = self:clip()
  if clip then return clip.start + self.beat end
end

--- The clips being edited, the active one first: `{ id, clip, offset, ... }`
--- each (see `paw.roll_clips.parts`).
function view:parts() return clips.parts() end

local function open(self, clip)
  self.clip_id, self.beat, self.scroll = clip.id, 0, 0
  -- A fit asked for by the pointer is for the clip it opened, not this one.
  self.fit_next = nil
  clips.only()
  local notes = clip:notes()
  self.pitch = notes[1] and notes[1].pitch or 60
  self.top = nil
end

--- Open a MIDI clip in the piano roll, alone.
function view:edit(clip)
  if clip.kind ~= "midi" then return paw.notify("only MIDI clips open in the piano roll", "warn") end
  open(self, clip)
  paw.ui.focus("pianoroll")
  paw.emit("pianoroll.opened", { clip = clip.id })
end

--- Open the clip a window's name gives (`:e roll://riff`, `:vs roll://7`):
--- by its name, its number or its address.
function view:open_target(target)
  local clip = paw.layout.clip_named(target)
  if not clip then return false, "no clip `" .. tostring(target) .. "`" end
  if clip.kind ~= "midi" then return false, "only MIDI clips open in the piano roll" end
  open(self, clip)
  paw.emit("pianoroll.opened", { clip = clip.id })
end

--- What a saved layout keeps of the window: the number of its clip, if
--- the clip is there (not undone or deleted).
function view:window_target()
  if self.clip_id and pcall(api.clip_get, self.clip_id) then return self.clip_id end
end

--- Shown beside a view that has a clip open (the notation view), the roll
--- takes that clip, as the arrange view's clip is taken: the window that
--- had the keyboard says which.
function view:on_show()
  local other = paw.ui.views[paw.ui.focused]
  if not other or other == self or type(other.clip) ~= "function" then return end
  local clip = other:clip()
  if not clip or clip.kind ~= "midi" or clip.id == self.clip_id then return end
  self.clip_id, self.beat, self.scroll, self.top = clip.id, 0, 0, nil
  local notes = clip:notes()
  self.pitch = notes[1] and notes[1].pitch or 60
  clips.only()
end

--- The time this view shows, for windows bound in time (`timebind`): the
--- project's beat at the left edge, columns per beat, and beats shown.
--- The roll counts beats from the active clip's start.
function view:time_axis()
  local clip = self:clip()
  if not clip then return nil end
  return clip.start + self.scroll, paw.opt.note_zoom, self.geometry and self.geometry.span
end

function view:set_time_axis(left, zoom)
  local clip = self:clip()
  if not clip then return end
  -- As far left as the earliest clip edited starts, as the roll scrolls.
  local lo = clips.span()
  self.scroll = math.max(math.min(0, math.floor(lo or 0)), left - clip.start)
  if zoom and paw.opt.note_zoom ~= zoom then paw.opt.note_zoom = zoom end
end

--- The note under the cursor in any of the clips edited, the active one's
--- first: the note (its start in the roll's beats), its place among its
--- clip's notes, and its part.
function view:note_at(pitch, beat)
  if not self:clip() or pitch < 0 or pitch > 127 then return end
  return clips.note_at(pitch, beat)
end

--- Whether a panel `h` rows tall has a row of tools under its title.
--- (A panel `w` wide enough has them in its title row instead.)
function view.toolbar_rows(h, w) return not view.tools_in_title(w) and h >= 20 and 1 or 0 end

--- Whether a panel `w` columns wide has its tools in its title row.
function view.tools_in_title(w) return (w or 0) >= 140 end

--- Columns for the keyboard on the left of a panel `w` wide.
function view.keys_width(w) return (w or 0) >= 100 and 8 or KEYS end

--- Rows above the notes on a panel `h` rows tall and `w` wide: the panel's
--- title, the tools when they are not in it and there is room, the chord
--- symbols when `paw.opt.chords` asks for them and there is room, then the
--- ruler.
function view.head_rows(h, w) return 2 + view.toolbar_rows(h, w) + ((paw.opt.chords and h >= 12) and 1 or 0) end
-- Switches a module adds to the piano roll's row of tools: `fn()` returns
-- `{ label, on, tip, act }` (`act` names the `paw.frontend.act` function a
-- click calls, given the clip), or nil to show none for now.
view.tools = {}

function view:tool(name, fn)
  for i = #self.tools, 1, -1 do
    if self.tools[i].name == name then table.remove(self.tools, i) end
  end
  if fn then self.tools[#self.tools + 1] = { name = name, fn = fn } end
end

function view:toolbar()
  local out = {}
  for _, tool in ipairs(self.tools) do
    local ok, t = pcall(tool.fn)
    if ok and type(t) == "table" then out[#out + 1] = t end
  end
  return out
end

-- Keys that hold for a while: a module whose state takes keys of its own
-- (a suggestion showing, a snippet being filled in) names a scope of
-- mappings and says when it is on; while it is, its keys come before the
-- piano roll's, earlier entries first (`paw.keymap` looks here through
-- `subscope`).
--
--   paw.ui.views.pianoroll:key_scope("pianoroll.complete", 50, function() return shown ~= nil end)
view.key_scopes = {}

function view:key_scope(name, order, active)
  for i = #self.key_scopes, 1, -1 do
    if self.key_scopes[i].name == name then table.remove(self.key_scopes, i) end
  end
  if not active then return end
  self.key_scopes[#self.key_scopes + 1] = { name = name, order = order, active = active }
  table.sort(self.key_scopes, function(a, b) return a.order < b.order end)
end

function view:subscope()
  local out = {}
  for _, scope in ipairs(self.key_scopes) do
    local ok, on = pcall(scope.active)
    if ok and on then out[#out + 1] = scope.name end
  end
  return #out > 0 and out or nil
end

-- Layers that modules draw over the roll, from back to front by `order`:
-- other tracks' notes ("context", 10), the notes of the clips edited
-- ("notes", 20), diagnostics 30, the notes insert mode is drawing
-- ("draw", 35), a snippet's marks 40, suggestions 50; the
-- selection and the cursor last of all.
view.layers = {}

--- Draw `paint(p)` as a layer of the roll, replacing one of the same name
--- (nil removes it). `p` holds `roll` and `ruler` (cell buffers), `plane`
--- (the roll as a plane of beats along and pitches up, see `buf:plane`:
--- what is marked there a window paints where it is, between cells),
--- `clip` (the active one), `data` (its fields), `parts` (every clip
--- edited, see `paw.roll_clips`), `x(beat)` (a column of the roll),
--- `row(pitch)` (its first row, nil when off screen), `scroll`, `from`
--- and `to` (the beats that show), `zoom`, `top`, `rows` (the pitches
--- shown), `per` (the rows of a pitch: the window's vertical zoom),
--- `width`, `focused` and `hue`. Beats are the roll's: the active clip's. Both frontends show
--- what a layer draws. A chip that does something is a hit region,
--- `p.roll:hit(x, y, w, 1, { kind = "act", act = name, arg = arg, tip = text })`:
--- a click calls `paw.frontend.act[name](clip, arg)`, and `tip` is what the
--- pointer over it says. A failing layer is skipped.
function view.layer(name, order, paint)
  for i = #view.layers, 1, -1 do
    if view.layers[i].name == name then table.remove(view.layers, i) end
  end
  if paint then view.layers[#view.layers + 1] = { name = name, order = order, paint = paint } end
  table.sort(view.layers, function(a, b) return a.order < b.order end)
  api.ui_redraw()
end

local function paint_layers(p)
  for _, layer in ipairs(view.layers) do
    local ok, err = pcall(layer.paint, p)
    if not ok then api.log("piano roll layer " .. layer.name .. ": " .. tostring(err)) end
  end
end

-- Other tracks' notes, behind the clips' own: each a dashed line on a
-- faint shade of its track's colour, without a name; the clips' own notes
-- are solid and named.
view.layer("context", 10, function(L)
  local glyph = paw.opt.ascii and "-" or "╌"
  for _, n in ipairs(clips.context()) do
    local row = L.row(n.pitch)
    if row and n.start < L.to and n.start + n.length > L.from then
      local x0 = math.floor((n.start - L.from) * L.zoom + 0.5)
      local x1 = math.floor((n.start + n.length - L.from) * L.zoom + 0.5)
      L.roll:fill(x0, row, math.max(1, x1 - x0), L.per, glyph, paw.draw.hue(n.color).body)
    end
  end
end)

-- The notes of the clips being edited: each a note on the roll's plane,
-- and what the pointer finds there.
view.layer("notes", 20, function(L)
  -- A selection that names its notes (`viv`) shows on them.
  local selection = paw.ui.focused == "pianoroll" and paw.keymap.selection()
  local named = selection and selection.notes
  for i, part in ipairs(L.parts) do
    local colour = paw.draw.track_colour(api.track_get(part.track))
    local hue = i == 1 and L.hue or paw.draw.hue(colour)
    local chosen = {}
    for _, place in ipairs(paw.frontend.chosen_notes(part.id)) do
      chosen[place] = true
    end
    local shown, places = part.clip:notes({
      from = L.from - part.offset,
      to = L.to - part.offset,
      low = math.max(0, L.top - L.rows + 1),
      high = L.top,
    })
    -- The notes insert mode's pencil holds show where it has them; each
    -- note's own bend shows on it.
    local held = paw.roll_draw.hidden(part.id) or {}
    local controls = #shown > 0 and paw.roll_draw.controls_of(part.id) or {}
    local ids = named and named[part.id] or {}
    for k, note in ipairs(shown) do
      if not held[note.id] then
        local place, start = places[k], note.start + part.offset
        local at_cursor = L.under_part and L.under_part.id == part.id and place == L.under_place
        if ids[note.id] then chosen[place] = true end
        local style = at_cursor and "NoteCursor"
          or ids[note.id] and "Visual"
          or chosen[place] and hue.title_cur
          or paw.draw.note_style(hue, note.velocity)
        -- Long enough notes say which they are, or the articulation
        -- (MIDI 2.0 attribute) they carry.
        local said = note.attr and paw.attr.describe(note.attr)
        local bend, bend_at = paw.roll_draw.bend_of(controls, note)
        L.plane:mark("note", start, note.pitch, note.length, 1, {
          label = said and said.tag or music.name(note.pitch),
          style = style,
          color = colour,
          velocity = note.velocity,
          selected = chosen[place] or nil,
          cursor = at_cursor or nil,
          key = "note:" .. part.id .. ":" .. place,
          bend = bend,
          bend_at = bend_at,
          hit = {
            kind = "note",
            clip = part.id,
            place = place,
            pitch = note.pitch,
            start = start,
            length = note.length,
          },
        })
      end
    end
  end
end)

-- What modules say about rows and notes, for an instrument whose keys mean
-- more than pitches (keyswitches, a playable range, drum pieces):
--
--   view.rows(name, fn)      fn(pitch, track) -> { label, style, shade } or nil:
--                            `label` (and its `style`) on the keyboard edge
--                            instead of the pitch, `shade` the row's style
--   view.band(name, order, spec)  a row of its own above the ruler while
--                            `spec.active(clip)`: `spec.title` on the
--                            keyboard edge, `spec.paint(buf, L)` in it
--   view.describer(name, fn) fn(note, part) -> lines `K` adds for a note;
--                            with `articulation = true` in the table they
--                            say the note's articulation for the roll
--   view.entering(name, fn)  fn(note, clip) changes a note the roll is
--                            about to enter (keys, insert mode, the mouse)
-- The first provider with something to say about a row wins. nil removes one.
view.row_providers, view.bands, view.describers, view.enterers = {}, {}, {}, {}

local function provide(list, name, entry)
  for i = #list, 1, -1 do
    if list[i].name == name then table.remove(list, i) end
  end
  if entry then
    entry.name = name
    list[#list + 1] = entry
  end
  table.sort(list, function(a, b) return (a.order or 0) < (b.order or 0) end)
  api.ui_redraw()
end

function view.rows(name, fn) provide(view.row_providers, name, fn and { fn = fn }) end

function view.band(name, order, spec) provide(view.bands, name, spec and util.merge(spec, { order = order })) end

function view.describer(name, fn) provide(view.describers, name, fn and { fn = fn }) end

function view.entering(name, fn) provide(view.enterers, name, fn and { fn = fn }) end

--- What the modules say about a row of a track, or nil.
function view.row_look(pitch, track)
  for _, p in ipairs(view.row_providers) do
    local ok, look = pcall(p.fn, pitch, track)
    if ok and look then return look end
  end
end

--- The bands shown over a clip.
function view.active_bands(clip)
  local out = {}
  for _, band in ipairs(view.bands) do
    local ok, on = pcall(band.active, clip)
    if ok and on then out[#out + 1] = band end
  end
  return out
end

--- A note about to be entered in `clip`, as the modules want it.
function view.new_note(clip, note)
  for _, e in ipairs(view.enterers) do
    local ok, err = pcall(e.fn, note, clip)
    if not ok then api.log("piano roll entering " .. e.name .. ": " .. tostring(err)) end
  end
  return note
end

-- The grids the row of tools offers, as `:grid` takes them.
view.grids = {
  { "1/1", 4 },
  { "1/2", 2 },
  { "1/4", 1 },
  { "1/8", 0.5 },
  { "1/16", 0.25 },
  { "1/32", 0.125 },
  { "1/8 triplet", 1 / 3 },
  { "1/16 triplet", 1 / 6 },
}

--- The tools the pointer reaches without keys, in order: `{ name, text,
--- tip, on, menu, act }` each (`menu` for one that opens a menu).
local function tool_list(self, titled)
  local grid_text = paw.ui.views.status.grid_text
  local list = {
    {
      name = "tracks",
      text = "Tracks",
      tip = "the tracks whose notes show behind these, and the clips edited together (also :roll.tracks)",
    },
    {
      name = "grid",
      text = "Grid " .. grid_text(paw.opt.note_grid),
      menu = true,
      tip = "the grid notes snap to and the lines it draws (also :grid)",
    },
    {
      name = "snap",
      text = "Snap",
      on = paw.opt.note_snap,
      tip = "snap to the grid: notes land on it (Shift while dragging leaves it)",
    },
    {
      name = "length",
      text = "Note " .. grid_text(self:step_length()),
      menu = true,
      tip = "the length a click gives a note; drawing a note sets it",
    },
    {
      name = "quantize",
      text = "Quantize",
      tip = "the chosen notes, or all of them, start on the grid (also :notes.quantize)",
    },
    {
      name = "step",
      text = "Step",
      on = paw.roll_draw.stepping(),
      tip = "step input (I): notes played on a MIDI keyboard go in at the cursor, one undo step; Esc writes them",
    },
    {
      name = "list",
      text = "List",
      tip = "the event list: every note and controller move of the clip, a row each (also E)",
    },
  }
  for _, t in ipairs(self:toolbar()) do
    list[#list + 1] = { name = "layer", act = t.act, text = t.label, on = t.on, tip = t.tip }
  end
  list[#list + 1] =
    { name = "zoom_out", text = "-", tip = "zoom out in time (Ctrl and the wheel zoom where the pointer is)" }
  list[#list + 1] = { name = "zoom_in", text = "+", tip = "zoom in in time" }
  if titled then
    list[#list + 1] = {
      name = "window",
      text = "Window",
      tip = "the piano roll in a window of its own, in a graphical frontend (also :view.window)",
    }
    list[#list + 1] = { name = "close", text = "x", tip = "close the piano roll" }
  end
  return list
end

--- The tools as buttons on a row of `buf` from column `x`; each a button
--- whose hit region names it (paw/views/pianoroll_mouse.lua). Returns the
--- columns they take; with `measure`, draws nothing.
local function place_tools(buf, list, x, measure)
  local from = x
  local caret = paw.opt.ascii and "v" or "▾"
  for _, t in ipairs(list) do
    local text = " " .. t.text .. (t.menu and " " .. caret or "") .. " "
    local w = api.str_width(text)
    if x + w > buf.width then break end
    if not measure then
      buf:mark("button", x, 0, w, 1, {
        text = text,
        on = t.on or nil,
        menu = t.menu or nil,
        style = "TrackInfo",
        on_style = "TitleBarFocus",
        label = t.text,
        hit = { kind = "tool", name = t.name, act = t.act, tip = t.tip },
      })
    end
    x = x + w + 1
  end
  return x - from
end

--- The tools under the title, on a row of their own (`buf`), where the
--- panel is not wide enough for them in its title: then what the pointer
--- has chosen, or what insert mode is doing.
function view.draw_tools(self, buf, clip, ctx)
  buf:fill(0, 0, buf.width, 1, " ", "Ruler")
  local x = 1 + place_tools(buf, tool_list(self, false), 1)
  local said = ctx.focused and paw.keymap.mode == "i" and paw.roll_draw.status() or paw.frontend.chosen_text(clip.id)
  if said and said ~= "" and buf.width - x > 6 then
    buf:text(x + 1, 0, util.fit(said, buf.width - x - 2), "RulerChordEdge")
  end
end

--- The tools at the right end of the title row (`buf`, the row): the
--- columns they take, from the right edge; with `measure`, draws nothing.
function view.title_tools(self, buf, measure)
  local list = tool_list(self, true)
  local w = place_tools(buf, list, 0, true)
  local x = math.max(0, buf.width - w)
  if not measure then place_tools(buf, list, x) end
  return w
end

--- Rows for the velocity lane on a panel `h` rows tall.
function view.velocity_rows(h) return h >= 30 and 5 or h >= 16 and 3 or 0 end

function view:render(buf, ctx)
  local g = paw.draw.g
  local w, h = buf.width, buf.height
  local clip = self:clip()
  buf:fill(0, 0, w, h, " ", "Normal")
  if not clip then
    paw.ui.titlebar(buf, { name = "Piano roll", focused = ctx.focused })
    buf:text(2, 2, "No clip open.", "Empty")
    local lead = "Put the cursor on a MIDI clip in the arrange view and press "
    buf:text(2, 3, lead, "Empty")
    buf:text(2 + #lead, 3, "Enter", "EmptyKey")
    return
  end
  local c = clip:get()
  local track = api.track_get(c.track)
  local hue = paw.draw.track_hue(track)
  local parts = clips.parts()
  local lo, hi = clips.span()
  local zoom, grid = paw.opt.note_zoom, paw.opt.note_grid
  -- With room to spare, the notes' velocities get a few rows of their own.
  local vel = view.velocity_rows(h)
  local head = view.head_rows(h, w)
  local tools = view.toolbar_rows(h, w)
  local titled = view.tools_in_title(w)
  local KEYS = view.keys_width(w)
  local chords_row = paw.opt.chords and h >= 12 and 1 + tools or nil
  local bands = h >= 12 and view.active_bands(clip) or {}
  head = head + #bands
  self.head = head
  -- A wide roll has a scroll bar through the pitches in a column of its own.
  local bar = titled and 1 or 0
  -- The grid's lines, and the keys on them: a key is `per` lines tall
  -- with the window's vertical zoom (paw/vzoom.tl).
  local per = paw.vzoom.key_rows()
  local grid_h, tw = h - head - vel, w - KEYS - bar
  local rows = math.max(1, math.floor(grid_h / per))
  -- Opened by the pointer (`fit_next`), zoomed in as far as the clips and
  -- a bar after them fill the width, never out.
  if self.fit_next then
    self.fit_next = nil
    local fit = math.floor(tw / (hi - math.min(0, lo) + paw.time.bar_ceil(c.start + 1) - c.start) * 4) / 4
    if fit > zoom then
      zoom = math.min(64, fit)
      paw.opt.note_zoom = zoom
    end
  end
  local span = tw / zoom

  -- Keep the cursor on screen.
  if not self.top then self.top = self.pitch + math.floor(rows / 2) end
  if self.pitch > self.top then self.top = self.pitch end
  if self.pitch <= self.top - rows then self.top = self.pitch + rows - 1 end
  self.top = util.clamp(self.top, rows - 1, 127)
  -- Unless another window leads this one's time (`timebind`).
  local jumped = paw.keymap.jump_serial ~= self.seen_jump
  self.seen_jump = paw.keymap.jump_serial
  if not ctx.follower then
    local to = paw.draw.jump_scroll(self.beat, self.scroll, span, zoom, jumped)
    if to then
      self.scroll = math.floor(to)
    elseif self.beat < self.scroll then
      self.scroll = math.floor(self.beat)
    elseif self.beat >= self.scroll + span - grid then
      self.scroll = math.ceil(self.beat - span + 1)
    end
  end
  self.scroll = math.max(math.min(0, math.floor(lo)), self.scroll)
  self.geometry =
    { rows = rows, lines = grid_h, per = per, zoom = zoom, keys = KEYS, head = head, vel = vel, span = span }

  -- Title: the active clip in its track's colour, the track and how many
  -- clips are edited, where the cursor is and the chord sounding there; on
  -- the right what the keys will enter.
  local inserting = ctx.focused and paw.keymap.mode == "i"
  local grid_text = paw.ui.views.status.grid_text
  local right =
    string.format("grid %s  len %s  vel %d", grid_text(grid), grid_text(self:step_length()), paw.opt.velocity)
  local sounding, chord = clips.sounding(self.beat)
  local place = music.name(self.pitch) .. "  " .. paw.time.format(c.start + self.beat)
  -- A wide panel has its tools at the right of the title row, and says
  -- there what is chosen or what insert mode is doing, as the row of tools
  -- does where they have a row of their own.
  local title_row = buf:sub(0, 0, w, 1)
  local reserve = titled and view.title_tools(self, title_row, true) or 0
  if titled then
    right = ctx.focused and paw.keymap.mode == "i" and paw.roll_draw.status() or paw.frontend.chosen_text(clip.id)
  end
  paw.ui.titlebar(buf, {
    pill = { c.name, hue.pill },
    focused = ctx.focused,
    name = #parts > 1 and string.format("%s  +%d clip%s", track.name, #parts - 1, #parts == 2 and "" or "s")
      or track.name,
    context = chord and place .. "  " .. chord or place,
    right = (titled or w >= 90) and right ~= "" and right or nil,
    reserve = reserve,
  })
  if inserting and not titled then
    local text = " " .. paw.roll_draw.label() .. " "
    buf:text(math.max(0, w - api.str_width(text) - 1), 0, text, "RulerInsert")
  end
  if titled then view.title_tools(self, title_row) end
  if tools > 0 then view.draw_tools(self, buf:sub(0, 1, w, 1), clip, ctx) end

  -- Ruler: bars as the project counts them, beats in between; above it
  -- the chords that sound, read over every pitched track, and the key.
  buf:fill(0, head - 1, w, 1, " ", "Ruler")
  buf:hit(0, head - 1, w, 1, { kind = "ruler" })
  local roll = buf:sub(KEYS, head, tw, grid_h)
  local ruler = buf:sub(KEYS, head - 1, tw, 1)
  if chords_row then
    buf:fill(0, chords_row, w, 1, " ", "Ruler")
    local key = paw.harmony.key(c.start + self.scroll, true)
    buf:text(0, chords_row, (key.name:gsub(" major", ""):gsub(" minor", "m")):sub(1, KEYS - 1), "RulerChordEdge")
    paw.harmony.draw(buf:sub(KEYS, chords_row, tw, 1), self.scroll, span, zoom, c.start)
  end
  local lines = paw.draw.beats(ruler, self.scroll, span, zoom, c.start)
  for i, band in ipairs(bands) do
    local y = head - 1 - #bands + i - 1
    buf:fill(0, y, w, 1, " ", "Ruler")
    buf:text(0, y, util.fit(band.title or band.name, KEYS - 1), "RulerChordEdge")
    local ok, err = pcall(band.paint, buf:sub(KEYS, y, tw, 1), {
      clip = clip,
      data = c,
      from = self.scroll,
      to = self.scroll + span,
      zoom = zoom,
      width = tw,
      lines = lines,
      x = function(beat) return math.floor((beat - self.scroll) * zoom + 0.5) end,
    })
    if not ok then api.log("piano roll band " .. band.name .. ": " .. tostring(err)) end
  end
  -- Steps between the beats when zoomed in far enough to see them.
  -- They are the same on every row: one line of text, drawn row by row.
  local steps
  if zoom >= 8 and grid < 1 then
    local cells = {}
    for i = 1, tw do
      cells[i] = " "
    end
    for _, line in ipairs(lines) do
      for k = 1, math.floor(1 / grid + 0.5) - 1 do
        local x = line.x + math.floor(k * grid * zoom + 0.5)
        if x >= 0 and x < tw then cells[x + 1] = g.step end
      end
    end
    steps = table.concat(cells)
  end

  -- What the track's instrument calls its keys (a drum, a keyswitch) is
  -- written on them.
  local key_names = paw.plugins.key_names(c.track)
  local start_x = math.floor((lo - self.scroll) * zoom + 0.5)
  local end_x = math.floor((hi - self.scroll) * zoom + 0.5)
  local names, labels = {}, {}
  for row = 0, rows * per - 1 do
    local pitch = self.top - math.floor(row / per)
    local look = view.row_look(pitch, c.track) or {}
    if row % per == 0 and key_names[pitch] then names[#names + 1] = { pitch, key_names[pitch] } end
    if row % per == 0 and look.label then labels[#labels + 1] = { pitch, look.label, look.style } end
    roll:fill(0, row, tw, 1, " ", look.shade or (music.is_black(pitch) and "RollRowBlack" or "RollRow"))
    if steps then roll:text(0, row, steps, music.is_black(pitch) and "RollStepBlack" or "RollStep") end
    for _, line in ipairs(lines) do
      roll:text(line.x, row, line.bar and g.bar or g.beat, line.bar and "RollBar" or "RollBeat")
    end
    -- Before and past the clips, the grid goes on, shaded.
    local outside = music.is_black(pitch) and "RollOutsideBlack" or "RollOutside"
    if start_x > 0 then roll:fill(0, row, math.min(tw, start_x), 1, nil, outside) end
    if end_x < tw then roll:fill(math.max(0, end_x), row, tw, 1, nil, outside) end
  end
  buf:mark("keyboard", 0, head, KEYS, grid_h, {
    top = self.top,
    per = per,
    cursor = self.pitch,
    names = names,
    labels = labels,
    sounding = sounding,
    hit = { kind = "keys" },
  })

  -- The playhead is a thin line on the beat's left edge, under the notes,
  -- with a cap on the ruler: one that starts where it stands is drawn
  -- whole, from where it starts. A window moves it as the song plays.
  local t = api.transport_get()
  buf:mark("playhead", KEYS, head - 1, tw, grid_h + 1, {
    at = t.position,
    from = c.start + self.scroll,
    per = zoom,
    lo = c.start + lo,
    hi = c.start + hi,
    bind = "position",
  })

  -- The grid as a plane: beats along from the left edge, a row a pitch
  -- down from the top. What the layers mark on it a window paints where
  -- it is; a press on its empty part is on the grid.
  local plane = buf:plane(KEYS, head, tw, grid_h, {
    key = "roll",
    hit = { kind = "grid" },
    x = { domain = "beat", from = self.scroll, per = zoom },
    y = { domain = "pitch", from = self.top + 1, per = -per },
  })

  -- The layers, back to front. Only what is on screen crosses over from the core.
  local _, under_place, under_part = self:note_at(self.pitch, self.beat)
  local L = {
    roll = roll,
    ruler = ruler,
    plane = plane,
    clip = clip,
    data = c,
    scroll = self.scroll,
    from = self.scroll,
    to = self.scroll + span,
    top = self.top,
    rows = rows,
    per = per,
    zoom = zoom,
    width = tw,
    focused = ctx.focused,
    parts = parts,
    hue = hue,
    under_place = under_place,
    under_part = under_part,
    x = function(beat) return math.floor((beat - self.scroll) * zoom + 0.5) end,
    row = function(pitch)
      local row = self.top - pitch
      return row >= 0 and row < rows and row * per or nil
    end,
  }
  paint_layers(L)

  -- How hard each note on screen is played, along the bottom.
  if vel > 0 then
    local lane = buf:sub(KEYS, head + grid_h, tw, vel)
    buf:fill(0, head + grid_h, w, vel, " ", "VelocityLane")
    buf:hit(0, head + grid_h, w, vel, { kind = "velocity" })
    -- What it shows, which a click on it chooses.
    local shown = require("paw.views.pianoroll_strip").shown()
    local caret = paw.opt.ascii and "v" or "▾"
    local name = shown.short
    buf:mark("button", 0, head + grid_h + vel - 1, KEYS, 1, {
      text = " " .. name .. " " .. caret,
      menu = true,
      style = "VelocityLane",
      label = shown.label,
      hit = { kind = "velocity" },
    })
    for _, line in ipairs(lines) do
      if line.bar then lane:fill(line.x, 0, 1, vel, g.bar, "RollBar") end
    end
    for i, part in ipairs(parts) do
      local fg = i == 1 and hue.fg or paw.draw.track_hue(api.track_get(part.track)).fg
      local all, places = part.clip:notes({ from = self.scroll - part.offset, to = self.scroll + span - part.offset })
      for k, note in ipairs(all) do
        local x0 = math.floor((note.start + part.offset - self.scroll) * zoom + 0.5)
        local level = note.velocity / 127 * vel * 8
        local at_cursor = under_part and under_part.id == part.id and places[k] == under_place
        for row = 0, vel - 1 do
          local amount = level - (vel - 1 - row) * 8
          if amount >= 1 then
            lane:text(x0, row, g.eighths[math.min(8, math.floor(amount))], at_cursor and "Bright" or fg)
          end
        end
        if at_cursor then
          local text = tostring(note.velocity)
          lane:text(x0 + 1, 0, text, "Bright")
        end
      end
    end
  end

  -- The selection of visual mode: a stretch of time, a block, or whole pitches.
  local selection = ctx.focused and paw.keymap.selection()
  -- One that names its notes shows on the notes themselves.
  if selection and not selection.notes then
    local x0 = math.max(0, math.floor((selection.c0 - self.scroll) * zoom + 0.5))
    local x1 = math.min(tw, math.floor((selection.c1 - self.scroll) * zoom + 0.5))
    local y0, y1 = math.max(0, self.top - selection.r1), math.min(rows - 1, self.top - selection.r0)
    if selection.kind == "line" then
      x0, x1 = 0, tw
    elseif selection.kind == "char" then
      y0, y1 = 0, rows - 1
    end
    if x1 > x0 and y1 >= y0 then roll:fill(x0, y0 * per, x1 - x0, (y1 - y0 + 1) * per, nil, "Visual") end
  end

  local cx = math.floor((self.beat - self.scroll) * zoom + 0.5)
  local cw = math.max(1, math.floor(grid * zoom))
  if not under_place or selection or inserting then
    roll:fill(cx, (self.top - self.pitch) * per, cw, per, nil, inserting and "InsertCursor" or "RollCursor")
  end

  -- Where the view is among the pitches, down its right side.
  if bar > 0 then
    buf:fill(KEYS + tw, head, 1, grid_h, " ", "RollRowBlack")
    buf:mark("scrollbar", KEYS + tw, head, 1, grid_h, {
      axis = "y",
      from = 127 - self.top,
      span = rows,
      total = 128,
      hit = { kind = "scrollbar", axis = "y" },
    })
  end
end

--- What a window of the roll shows besides what events announce (the
--- screen keeps the window while it is the same): its clip, its cursor,
--- its scroll, and whether a jump or another window moves its time.
function view:stamp(ctx)
  return table.concat({
    tostring(self.clip_id),
    self.pitch,
    self.beat,
    tostring(self.top),
    self.scroll,
    tostring(self.length),
    tostring(self.fit_next),
    tostring(self.seen_jump == paw.keymap.jump_serial),
    tostring(ctx.follower),
  }, " ")
end

--- Play the pitch under the cursor on the track of the clip it is in.
function view:audition(pitch)
  local part = clips.target(self.beat)
  if part then part.clip:track():play_note(pitch or self.pitch, paw.opt.velocity, 180) end
end

--- How far the cursor can go: the stretch of the clips edited.
function view:span() return clips.span() end

function view:move(dbeat, dpitch)
  if not self:clip() then return end
  -- One step past the last is allowed, so that a selection can reach the end.
  local lo, hi = self:span()
  self.beat = util.clamp(self.beat + dbeat, lo, hi)
  local pitch = util.clamp(self.pitch + dpitch, 0, 127)
  if pitch ~= self.pitch then
    self.pitch = pitch
    self:audition()
  end
  api.ui_redraw()
end

--- Put the cursor somewhere without sounding the pitch; nil leaves that
--- part of it where it is. Unlike `move` it can sit right at the end of the
--- clip, where a selection or a deletion may need to reach.
function view:set(pitch, beat)
  if not self:clip() then return end
  if pitch then self.pitch = util.clamp(pitch, 0, 127) end
  if beat then self.beat = util.clamp(beat, self:span()) end
  api.ui_redraw()
end

--- The notes of the clips edited in the order they start, lower pitches
--- first within a chord, their starts in the roll's beats.
function view:ordered()
  if not self:clip() then return {} end
  -- One clip's are in the order the core keeps them in.
  return clips.notes()
end

--- Go to the next (`dir` 1) or previous (-1) note, wherever its pitch is.
function view:to_note(dir, count)
  local notes = self:ordered()
  for _ = 1, count or 1 do
    local found
    if dir > 0 then
      for _, n in ipairs(notes) do
        if n.start > self.beat + 1e-9 then
          found = n
          break
        end
      end
    else
      for i = #notes, 1, -1 do
        if notes[i].start < self.beat - 1e-9 then
          found = notes[i]
          break
        end
      end
    end
    if not found then
      -- Past the last note there is the end of the clips; before the first, their start.
      if dir > 0 then
        self:to_edge(-1)
      else
        self:set(nil, (self:span()))
      end
      return
    end
    self:set(found.pitch, found.start)
  end
end

--- Go to where the note under the cursor ends, or else the next one to end.
function view:to_note_end(count)
  for _ = 1, count or 1 do
    local best
    for _, n in ipairs(self:ordered()) do
      local finish = n.start + n.length
      if finish > self.beat + 1e-9 and (not best or finish < best.start + best.length) then best = n end
    end
    if not best then return end
    self:set(best.pitch, best.start + best.length)
  end
end

--- Go `n` bars on, or back with a negative `n`, to where a bar starts.
function view:to_bar(n)
  local clip = self:clip()
  if not clip then return end
  local at = clip.start + self.beat
  local bar = paw.time.bar_of(at)
  local to = n > 0 and bar + n or bar + n + (paw.tempo.is_bar_line(at) and 0 or 1)
  self:set(nil, paw.time.bar_start(math.max(1, to)) - clip.start)
end

--- Go to the first note (`dir` 1) or to the end of the clips (-1).
function view:to_edge(dir)
  if not self:clip() then return end
  local lo, hi = self:span()
  if dir < 0 then return self:set(nil, hi) end
  local first = self:ordered()[1]
  if first then
    self:set(first.pitch, first.start)
  else
    self:set(nil, lo)
  end
end

--- Go to the pitch of the highest (`dir` 1) or lowest (-1) note.
function view:to_extreme(dir)
  local best
  for _, n in ipairs(self:ordered()) do
    if not best or (n.pitch - best) * dir > 0 then best = n.pitch end
  end
  if best then self:set(best, nil) end
end

local last_paste -- where the last paste left the cursor, and where it ended

--- Paste yanked notes `count` times one after another: after the note under
--- the cursor, or right at the cursor with `before`. Notes yanked from
--- clips that are edited now go back into them; the rest go into the clip
--- at the cursor.
function view:paste(value, before, count)
  local clip = self:clip()
  if not clip then return end
  local at = self.beat
  if not before then
    local edits = api.project_get("edits")
    if last_paste and last_paste.clip == clip.id and last_paste.beat == at and last_paste.edits == edits then
      -- Pasting again right after a paste carries on where that one ended.
      at = last_paste.finish
    else
      local note = self:note_at(self.pitch, self.beat)
      if note then at = note.start + note.length end
    end
  end
  local start = at
  for _ = 1, count or 1 do
    start = at
    local parts = clips.parts()
    local finish = paw.edit.roll.paste(#parts > 1 and parts or clip, value, self.pitch, at, clips.target(at, parts))
    if not finish then return end
    at = finish
  end
  self:set(nil, start)
  last_paste = { clip = clip.id, beat = self.beat, finish = at, edits = api.project_get("edits") }
end

-- The note length: what a click gives a note, and the step of step input.

--- How long a new note is: the note length, or a grid step when it is unset.
function view:step_length() return self.length or paw.opt.note_grid end

function view:set_step(length)
  self.length = length
  api.ui_redraw()
end

-- What modal editing works on: rows are pitches, which count upwards.
view.grid = {
  down = -1,
  get = function() return view.pitch, view.beat end,
  set = function(row, col) view:set(row, col) end,
  step = function() return paw.opt.note_grid end,
  -- A selection takes in the note under its far end, as Vim's takes in the
  -- character under the cursor.
  extent = function(row, col)
    local note = view:note_at(row, col)
    if note then return note.start + note.length end
  end,
  -- Notes by the name of their pitch: `c` finds every C and C sharp, `c4` one key.
  search = function(text)
    local wanted, hits = text:lower(), {}
    for _, n in ipairs(view:ordered()) do
      if music.name(n.pitch):lower():find(wanted, 1, true) == 1 then
        hits[#hits + 1] = { row = n.pitch, col = n.start }
      end
    end
    return hits
  end,
}

--- Add a note at the cursor, or remove the one that is there.
function view:toggle_note()
  if not self:clip() then return end
  local _, place, part = self:note_at(self.pitch, self.beat)
  if place then
    part.clip:remove_note(place)
  else
    part = clips.target(self.beat)
    part.clip:add_note(
      view.new_note(
        part.clip,
        { pitch = self.pitch, start = self.beat - part.offset, length = self.length or paw.opt.note_grid }
      )
    )
    self:audition()
  end
end

--- What `K` shows before the track: the note under the cursor.
function view:describe()
  local note, _, part = self:note_at(self.pitch, self.beat)
  if not note then return nil end
  local lines = {
    { text = "Note  " .. music.name(note.pitch), style = "Title" },
    string.format("  from beat %g, %g beats long, velocity %d", note.start, note.length, note.velocity),
  }
  -- A describer that says the articulation (an articulation map's name for
  -- it) says it instead of the attribute's plain words.
  local more, said = {}, false
  for _, d in ipairs(view.describers) do
    local ok, got = pcall(d.fn, note, part)
    if ok and type(got) == "table" then
      said = said or got.articulation == true
      for _, line in ipairs(got) do
        more[#more + 1] = line
      end
    end
  end
  local attr = not said and note.attr and paw.attr.describe(note.attr)
  if attr then lines[#lines + 1] = "  articulation: " .. attr.text end
  local own = note
  if part.offset ~= 0 then own = paw.util.merge(note, { start = note.start - part.offset }) end
  local bend, bend_at = paw.roll_draw.bend_of(paw.roll_draw.controls_of(part.id), own)
  if bend then
    lines[#lines + 1] = string.format(
      "  bends %s %g semitone%s by its end, from %d%% of it (its own pitch bend)",
      bend > 0 and "up" or "down",
      math.abs(bend),
      math.abs(bend) == 1 and "" or "s",
      math.floor(bend_at * 100 + 0.5)
    )
  end
  local key = paw.plugins.key_names(part.track)[note.pitch]
  if key then lines[#lines + 1] = "  the instrument calls this key " .. key end
  -- The chord the note starts in, as paw.harmony reads it. After an edit,
  -- the reading is made again in slices: until then, K says so.
  if not paw.harmony.fresh() then
    lines[#lines + 1] = "  the chord here: reading"
  else
    local chord = paw.harmony.at(part.clip:get().start + own.start, true)
    if chord then lines[#lines + 1] = "  the chord here: " .. chord.name end
  end
  for _, line in ipairs(more) do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = ""
  return lines
end

--- Change the note under the cursor with `fn(note)`, the note's start in
--- its own clip's beats, which it does not leave. Returns whether there was one.
function view:change(fn)
  local _, place, part = self:note_at(self.pitch, self.beat)
  if not place then return false end
  local note = part.clip:notes()[place]
  fn(note)
  part.clip:set_note(place, {
    start = note.start,
    length = note.length,
    pitch = note.pitch,
    velocity = note.velocity,
    meta = note.meta or {},
    attr = note.attr or false,
  })
  return true
end

-- Its title row has buttons of its own (`view.title_tools`): a graphical
-- frontend shows it rather than a title of its own over it (paw/panes.tl).
view.titled = true
-- What moves on its own as the song plays is the playhead: a frontend that
-- paints it with the live values needs no new scene of the roll for it.
view.live_roles = { "playhead" }
paw.ui.view("pianoroll", view)
-- Insert mode's drawing, which draws on the roll as one of its layers.
paw.roll_draw = require("paw.roll_draw")
return view
