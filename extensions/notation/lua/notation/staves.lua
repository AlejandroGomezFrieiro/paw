-- The score as lines to edit. The full score, a group's score or a
-- selection's tracks (`:score`) are shown as staves, and each staff is a
-- line: the staff the cursor is on is the active track, its clip the view's
-- open clip, and every key, operator, popover and command edits it as the
-- view edits a clip alone (`notation.parts` lays the score out, `view:frame`
-- says where the clip is in it). There is no other state to keep: moving
-- between staves is moving the cursor.
--
--   Ctrl-j Ctrl-k   a staff down, up (a grand staff's two, then the next instrument's)
--   ]] [[           the next, previous instrument (a grand staff is one)
--   ]s [s           the next, previous instrument in the same group
--   [{ ]}           the first, last instrument of the group (Strings, Woodwinds)
--
-- A selection spans staves (`Ctrl-v` then `Ctrl-j`, `V` over staves
-- takes them whole) and an operator acts on each staff's clip, one undo
-- step; Ex reads staves as tracks (`:5,8 s4 >`, `:5,8 Strings art pizz`).
-- A condensed staff is two players: the cursor's voice says whose clip
-- is edited, and an edit where they play `a2` is made for both.
local api = paw.api
local util = paw.util
local keymap = paw.keymap
local view = require("notation")
local model = require("notation.model")
local P = require("notation.parts")

local S = {}
local EPS = 1e-6
local ROWS = 128 -- rows of the grid an instrument takes: its pitches

paw.option.define("score_dim", false) -- the staves not under the cursor drawn dimmer
paw.option.define("score_colors", false) -- the staves not under the cursor in their tracks' colours

-- Staves and instruments ---------------------------------------------------------------------------

--- The instrument (`layout.units`) a staff of the score belongs to: its
--- place and itself.
function S.unit_of(layout, staff)
  for k, u in ipairs(layout.units or {}) do
    if staff >= u.first and staff <= u.last then return k, u end
  end
end

--- The runs of instruments of one family (one group): `{ first, last }`
--- places in `layout.units` each, in order.
function S.runs(layout)
  local out = {}
  for k, u in ipairs(layout.units or {}) do
    local run = out[#out]
    if run and layout.units[run.last].family == u.family then
      run.last = k
    else
      out[#out + 1] = { first = k, last = k }
    end
  end
  return out
end

--- The group the song is narrowed to (`paw.scope`), or nil.
local function scope_group()
  local scope = rawget(paw, "scope")
  return scope and scope.group()
end

--- What the view shows, in words: "the full score", "the score of Strings".
function view.score_name()
  local shown = view.parts
  if not shown then return "the clip" end
  if shown.kind == "part" then return "the part" end
  local group = shown.scope and scope_group()
  if group then return "the score of " .. api.track_get(group, "name") end
  return shown.label or "the full score"
end

--- The middle line of a staff of the open clip, or the note sounding at the
--- cursor there nearest it: where the cursor lands on coming to a staff.
local function landing(self, staff)
  local layout = self:layout()
  if not layout then return 35 end
  local si = util.clamp(staff or 1, 1, #layout.staves)
  local m = self:measure_at(self.beat, layout)
  local clef = m and m.clefs and m.clefs[si] or layout.staves[si]
  local middle = model.CLEF_BOTTOM[clef] + 4
  local best
  for _, ev in ipairs(m and m.staves[si] or {}) do
    if self.beat >= ev.start - EPS and self.beat < ev.start + ev.length - EPS then
      for _, n in ipairs(ev.notes or {}) do
        if not best or math.abs(n.step - middle) < math.abs(best - middle) then best = n.step end
      end
    end
  end
  return best or middle
end

--- Make another clip the open one, the active staff, keeping the cursor
--- where it is in the song. The cursor goes onto `opts.step`, else onto
--- the note there nearest the middle of `opts.staff` (the clip's first
--- staff, or "last"), else onto its middle line.
function view:activate(id, opts)
  opts = opts or {}
  local old, new = self:clip(), paw.clip(id)
  if not (old and new) then return end
  if old.id ~= id then
    local song = old:get().start + self.beat
    local c = new:get()
    self.clip_id, self.cache, self.chord, self.last, self.voice = id, nil, nil, nil, 1
    self.beat = util.clamp(song - c.start, 0, c.length)
  end
  local layout = self:layout()
  local staff = opts.staff == "last" and layout and #layout.staves or tonumber(opts.staff) or 1
  self.step = opts.step or landing(self, staff)
  api.ui_redraw()
end

--- The song's beat at the cursor.
function S.song()
  local clip = view:clip()
  return clip and clip:get().start + view.beat or 0
end

--- A player's clip at a beat of the song, of a staff's (`u`, of
--- `layout.units`): the one playing then, else the last before it (where
--- what is entered in a gap goes, the clip growing to hold it), else the
--- first.
function S.clip_at(u, player, song)
  local ids = u.players[player] or u.players[1]
  local best
  for _, id in ipairs(ids) do
    if api.clip_get(id).start <= song + EPS then best = id end
  end
  return best or ids[1]
end

--- Onto a staff of the score (and a condensed staff's player) at a beat of
--- the score (else the cursor's), or onto `clip` of it: true when the clip
--- there is the open one, or was made so with `activate`.
function view:onto_staff(F, staff, player, activate, beat, clip)
  if not F.multi then return true end
  local k, u = S.unit_of(F.layout, staff)
  if not u then return false end
  local id = clip or S.clip_at(u, player or (k == F.unit and F.player) or 1, beat and F.start + beat or S.song())
  if id == self.clip_id then return true end
  if not activate then return false end
  self:activate(id, { staff = staff - u.first + 1 })
  return true
end

--- Make a staff of the score active, by its place among the staves.
function S.go_staff(staff)
  local F = view:frame()
  if not (F and F.multi) then return end
  local k, u = S.unit_of(F.layout, staff)
  if not u then return end
  local within = staff - u.first + 1
  if k == F.unit then
    -- Within the instrument: its other staff (a grand staff's hands).
    if within ~= view:cursor_staff() then view:set(landing(view, within), nil) end
    return
  end
  view:activate(S.clip_at(u, 1, S.song()), { staff = within })
end

-- Moving between staves -------------------------------------------------------------------------

--- On a condensed staff, the other player (or the next with `dir` 1, the
--- one before with -1): voice 1 is the first's clip, voice 2 the
--- second's. True when it moved.
function S.player(dir)
  local F = view:frame()
  local u = F and F.multi and F.layout.units[F.unit]
  if not (u and u.condensed) then return false end
  local to = dir == 1 and 2 or dir == -1 and 1 or 3 - F.player
  if to == F.player then return false end
  local step = view.step
  view:activate(S.clip_at(u, to, S.song()), { step = step })
  paw.notify("voice " .. to .. ": " .. api.track_get(u.tracks[to], "name"))
  return true
end

local function alone() paw.notify("the clip alone: :score shows every track's staff", "warn") end

--- A staff down (1) or up (-1), `count` times: through a grand staff's two,
--- then into the next instrument.
function S.staff(dir, count)
  local F = view:frame()
  if not (F and F.multi) then return false end
  local here = F.base + view:cursor_staff()
  local to = util.clamp(here + dir * (count or 1), 1, #F.layout.staves)
  if to ~= here then S.go_staff(to) end
  return true
end

--- The next (1) or previous (-1) instrument, `count` of them on.
function S.unit(dir, count)
  local F = view:frame()
  if not (F and F.multi) then return alone() end
  local units = F.layout.units
  local k = util.clamp(F.unit + dir * (count or 1), 1, #units)
  if k == F.unit then
    return paw.notify(dir > 0 and "the last instrument of the score" or "the first instrument of the score", "warn")
  end
  view:activate(S.clip_at(units[k], 1, S.song()))
end

--- The run of instruments (a group) the active one is in.
local function run_of(F)
  for _, run in ipairs(S.runs(F.layout)) do
    if F.unit >= run.first and F.unit <= run.last then return run end
  end
end

--- The next (1) or previous (-1) instrument in the same group.
function S.sibling(dir, count)
  local F = view:frame()
  if not (F and F.multi) then return alone() end
  local run = run_of(F)
  local k = F.unit + dir * (count or 1)
  if not run or k < run.first or k > run.last then
    return paw.notify(dir > 0 and "the last instrument of its group" or "the first instrument of its group", "warn")
  end
  view:activate(S.clip_at(F.layout.units[k], 1, S.song()))
end

--- The first (-1) or last (1) instrument of the group; there already, of
--- the group before or after. A count goes as many groups out.
function S.edge(dir, count)
  local F = view:frame()
  if not (F and F.multi) then return alone() end
  local runs = S.runs(F.layout)
  local at
  for i, run in ipairs(runs) do
    if F.unit >= run.first and F.unit <= run.last then at = i end
  end
  local k = F.unit
  for _ = 1, count or 1 do
    local run = runs[at]
    local target = dir < 0 and run.first or run.last
    if k == target and runs[at + dir] then
      at = at + dir
      target = dir < 0 and runs[at].first or runs[at].last
    end
    k = target
  end
  if k ~= F.unit then view:activate(S.clip_at(F.layout.units[k], 1, S.song())) end
end

-- The grid: rows are an instrument's pitches, instrument under instrument --------------------
--
-- In a score the keymap's rows and columns are the score's: an
-- instrument's 128 pitches above the next one's, and beats from the
-- score's start, so that a selection reaches across staves and clips that
-- start apart. A region is turned back into each clip's own before an
-- operator or a command sees it.

--- The grid row of a pitch of an instrument.
local function row_of(F, unit, pitch) return (#(F.layout.units or { 1 }) - unit) * ROWS + pitch end

--- The instrument and pitch of a grid row.
local function unit_of_row(F, row)
  local count = #(F.layout.units or { 1 })
  local k = util.clamp(count - math.floor(row / ROWS), 1, count)
  return k, util.clamp(row - (count - k) * ROWS, 0, 127)
end

--- Each instrument a region reaches, with the region as its clip has it:
--- `{ unit, clips, region }` each, the active instrument last. Within one
--- instrument a region is as it was; across several, each instrument's
--- staves whole over its stretch (all of them for whole rows).
function S.split(F, region)
  if not F.multi then return { { unit = 1, clips = { view.clip_id }, region = region } } end
  local top = unit_of_row(F, region.r1)
  local bottom = unit_of_row(F, region.r0)
  if region.unit then
    top, bottom = region.unit, region.unit
  end
  local out, mine = {}, nil
  for k = top, bottom do
    local u = F.layout.units[k]
    local _, low = unit_of_row(F, region.r0)
    local _, high = unit_of_row(F, region.r1)
    if top ~= bottom then
      low, high = 0, 127
    end
    -- A condensed staff: the player under the cursor's, or both where
    -- they play the same (`a2`) or the region takes the staff whole.
    local players = { k == F.unit and F.player or 1 }
    if u.condensed and (top ~= bottom or region.kind == "line" or S.a2(F.layout, u, region.c0, region.c1)) then
      players = { 3 - players[1], players[1] }
    end
    -- Each player's clips the stretch reaches; in a gap, the clip before.
    local clips = {}
    for _, p in ipairs(players) do
      local found = false
      for _, id in ipairs(u.players[p] or {}) do
        local c = api.clip_get(id)
        local a = c.start - F.start
        if region.kind == "line" or (a < region.c1 - EPS and a + c.length > region.c0 + EPS) then
          clips[#clips + 1] = id
          found = true
        end
      end
      if not found then clips[#clips + 1] = S.clip_at(u, p, F.start + region.c0) end
    end

    local part = {
      unit = k,
      clips = clips,
      region = util.merge(
        region,
        { r0 = low, r1 = high, kind = top ~= bottom and region.kind ~= "line" and "block" or region.kind, unit = false }
      ),
    }
    if k == F.unit then
      mine = part
    else
      out[#out + 1] = part
    end
  end
  out[#out + 1] = mine
  return out
end

--- Whether every bar of a condensed staff (`u`) a stretch of the score
--- touches is written `a2`.
function S.a2(layout, u, from, to)
  local any = false
  for mi, m in ipairs(layout.measures) do
    if m.start < to - EPS and m.start + m.length > from + EPS then
      if u.condensed[mi] ~= "a2" then return false end
      any = true
    end
  end
  return any
end

--- Run `fn()` with another clip open, the cursor at the same place of the
--- song; then the view as it was.
function S.within(id, fn)
  if id == view.clip_id then return fn() end
  local kept = { view.clip_id, view.beat, view.step, view.voice, view.cache, view.last, view.chord }
  local from = view:clip()
  local song = from and (from:get().start + view.beat) or 0
  view.clip_id, view.cache = id, nil
  local c = view:clip():get()
  view.beat = util.clamp(song - c.start, 0, c.length)
  local ok, err = pcall(fn)
  view.clip_id, view.beat, view.step, view.voice, view.cache, view.last, view.chord = unpack(kept)
  if not ok then error(err, 0) end
end

--- A region of the score in a clip's own beats.
local function into_clip(F, region, id)
  local c = api.clip_get(id)
  local shift = c.start - F.start
  return util.merge(region, { c0 = math.max(0, region.c0 - shift), c1 = math.max(0, region.c1 - shift) })
end

--- Run an operator on a region of the score: on each instrument's clip.
--- What a text object found (`region.score`, the selection it made) names
--- the open clip's score; another clip's is read from the region's stretch.
function S.operate(fn, region, ctx)
  local F = view:frame()
  if not (F and F.multi) then return fn(region, ctx) end
  local O = require("notation.objects")
  local result
  for _, part in ipairs(S.split(F, region)) do
    for _, id in ipairs(part.clips) do
      local r = into_clip(F, part.region, id)
      if id == view.clip_id then
        result = fn(r, ctx)
      else
        r.score = nil
        local found = O.visual
        O.visual = nil
        local ok, err = pcall(S.within, id, function() fn(r, ctx) end)
        O.visual = found
        if not ok then error(err, 0) end
      end
    end
  end
  return result
end

--- The selection as the open clip has it (its beats and pitches), or nil
--- when there is none or it leaves out the active staff. What every
--- command and drawing of the view reads.
function view:selection()
  local region = keymap.selection()
  if not region or region.view ~= "notation" then return nil end
  local F = self:frame()
  if not (F and F.multi) then return region end
  for _, part in ipairs(S.split(F, region)) do
    for _, id in ipairs(part.clips) do
      if id == self.clip_id then return into_clip(F, part.region, id) end
    end
  end
end

--- The pitches a selection takes on a staff of the score, `{ low, high }`,
--- or nil when it leaves the staff out.
function view:selected_staff(region, F, staff)
  if not F.multi then return { region.r0, region.r1 } end
  local k = S.unit_of(F.layout, staff)
  for _, part in ipairs(S.split(F, region)) do
    if part.unit == k then return { part.region.r0, part.region.r1 } end
  end
end

do
  local grid = view.grid
  local plain = { get = grid.get, set = grid.set, extent = grid.extent, search = grid.search }
  grid.get = function()
    local row, col = plain.get()
    local F = view:frame()
    if not (F and F.multi) then return row, col end
    return row_of(F, F.unit, row), col + F.off
  end
  grid.set = function(row, col)
    local F = view:frame()
    if not (F and F.multi) then return plain.set(row, col) end
    local k, pitch = unit_of_row(F, row)
    if k ~= F.unit then
      view:activate(S.clip_at(F.layout.units[k], 1, F.start + (col or view.beat + F.off)))
      F = view:frame()
    end
    plain.set(pitch, col and col - F.off)
  end
  grid.extent = function(row, col)
    local F = view:frame()
    if not (F and F.multi) then return plain.extent(row, col) end
    local k, pitch = unit_of_row(F, row)
    if k ~= F.unit then return nil end
    local finish = plain.extent(pitch, col - F.off)
    return finish and finish + F.off
  end
  grid.search = function(text)
    local hits = plain.search(text)
    local F = view:frame()
    if not (F and F.multi) then return hits end
    for _, hit in ipairs(hits) do
      hit.row, hit.col = row_of(F, F.unit, hit.row), hit.col + F.off
    end
    return hits
  end
end

--- The view's operators and text objects work on the score's grid: each
--- text object's region is put in the score's rows and beats, and each
--- operator is run on every clip its region reaches.
function S.wrap_maps()
  for _, map in ipairs(keymap.every()) do
    if map.scope == "notation" and not map.score_wrapped then
      if map.operator then
        local fn = map.operator
        map.operator = function(region, ctx) return S.operate(fn, region, ctx) end
        map.score_wrapped = true
      elseif map.object then
        local fn = map.object
        map.object = function(ctx)
          local region = fn(ctx)
          local F = view:frame()
          if not (region and F and F.multi) then return region end
          return util.merge(region, {
            c0 = region.c0 + F.off,
            c1 = region.c1 + F.off,
            r0 = row_of(F, F.unit, region.r0),
            r1 = row_of(F, F.unit, region.r1),
            unit = F.unit,
          })
        end
        map.score_wrapped = true
      end
    end
  end
end

-- Across a track's clips --------------------------------------------------------------------
--
-- In a score a staff is every clip of its track on the song's timeline:
-- the cursor going past the open clip's ends goes on into the clip there,
-- which becomes the open one. Past the last clip's end it stays at the
-- end, where a note entered makes the clip longer.

do
  local set, move, to_event, to_bar = view.set, view.move, view.to_event, view.to_bar
  function view:move(dbeat, dstep)
    if not (self.parts and self.beat + dbeat < -EPS) then return move(self, dbeat, dstep) end
    -- Back past the clip's start, into the clip before.
    local was = self.step
    self:set(self.step + dstep, self.beat + dbeat)
    if self.step ~= was then self:audition() end
  end
  function view:set(step, beat)
    local F = beat and self.parts and self:frame()
    local clip = self:clip()
    if F and F.multi and clip then
      local c = clip:get()
      if beat < -EPS or beat > c.length - EPS then
        local id = S.clip_at(F.layout.units[F.unit], F.player, c.start + beat)
        if id ~= c.id then
          local start = api.clip_get(id).start
          self.clip_id, self.cache, self.chord, self.last = id, nil, nil, nil
          return set(self, step, c.start + beat - start)
        end
      end
    end
    return set(self, step, beat)
  end

  --- On from a clip's last note (back from its first) into the next
  --- (previous) clip of the track.
  local function onward(self, dir, before, at, again)
    if not self.parts or self.clip_id ~= before or math.abs(self.beat - at) > EPS then return end
    local c = self:clip():get()
    self:set(nil, dir > 0 and c.length or -0.001)
    if self.clip_id ~= before and dir < 0 then again() end
  end
  function view:to_event(dir, count)
    for _ = 1, count or 1 do
      local before, at = self.clip_id, self.beat
      to_event(self, dir, 1)
      onward(self, dir, before, at, function() to_event(self, dir, 1) end)
    end
  end
  function view:to_bar(n)
    local before, at = self.clip_id, self.beat
    to_bar(self, n)
    if n < 0 then onward(self, -1, before, at, function() to_bar(self, -1) end) end
  end
end

-- An edit where two players play the same ----------------------------------------------------

do
  local write = view.write
  --- On a condensed staff, an edit where the two players play the same
  --- (`a2`) is made for both: the other player's clip first, then the
  --- one under the cursor.
  function view:write(fn)
    local F = self.parts and self:frame()
    local u = F and F.multi and F.layout.units[F.unit]
    if u and u.condensed and not self.mirroring then
      local _, mi = self:measure_at(self.beat + F.off, F.layout)
      if mi and u.condensed[mi] == "a2" then
        local other = S.clip_at(u, 3 - F.player, S.song())
        self.mirroring = true
        local ok, err = pcall(S.within, other, function() write(self, fn) end)
        self.mirroring = nil
        if not ok then error(err, 0) end
      end
    end
    return write(self, fn)
  end
end

-- Showing a score -------------------------------------------------------------------------------

--- Show a score of `tracks` (all of them when nil) in the view, named
--- `label`. The cursor's track stays the active staff when it is shown.
function S.show(tracks, label, opts)
  opts = opts or {}
  local clip = view:clip() or view.target()
  if not clip then
    local list = P.instruments({ tracks = tracks })
    clip = list[1] and list[1].clip
  end
  if not clip then return paw.notify(tracks and "none of those tracks has MIDI" or "no track has MIDI", "warn") end
  if not view:clip() or view:clip().id ~= clip.id then view:edit(clip) end
  view.parts = {
    kind = "score",
    condensed = view.parts and view.parts.condensed or opts.condensed,
    tracks = tracks,
    label = label,
    from = opts.from,
    to = opts.to,
    check = opts.check,
    scope = opts.scope,
  }
  view.cache = nil
  local F = view:frame()
  if not (F and F.multi) then return end
  paw.ui.focus("notation")
  if paw.canvas and not paw.canvas.open_views.notation then
    paw.canvas.open("notation", { title = "Notation", width = 1100, height = 560 })
  end
  api.ui_redraw()
  return F
end

--- The tracks of the arrange view's selection, or nil.
local function selected_tracks()
  local region = keymap.visual and keymap.visual.view == "arrange" and keymap.selection() or nil
  if not region then
    local last = keymap.last_visual
    if not (last and last.view == "arrange") then return nil end
    region =
      { r0 = math.min(last.row, last.cursor_row or last.row), r1 = math.max(last.row, last.cursor_row or last.row) }
  end
  local rows, out = paw.groups.rows(), {}
  for r = math.max(1, region.r0), region.r1 do
    if rows[r] then out[#out + 1] = rows[r] end
  end
  return #out > 0 and out or nil
end

local function shown_message(F)
  local count = #F.layout.units
  paw.notify(
    view.score_name()
      .. ": "
      .. count
      .. (count == 1 and " instrument" or " instruments")
      .. ", editing "
      .. api.track_get(api.clip_get(view.clip_id).track).name
      .. "; Ctrl-j Ctrl-k ]] [[ move between staves"
  )
end

paw.command("score", function(ctx)
  local words = tostring(ctx.args[1] or ""):match("^%s*(.-)%s*$")
  if words == "off" then
    view.parts, view.cache = nil, nil
    api.ui_redraw()
    return paw.notify("notation: the clip alone")
  end
  local tracks, label
  if ctx.range and ctx.range.tracks then
    tracks, label = ctx.range.tracks, "the score of " .. #ctx.range.tracks .. " tracks"
  elseif words == "all" then
    tracks = nil
  elseif words == "selection" then
    tracks = selected_tracks()
    if not tracks then return paw.notify("select tracks in the arrange view first (V)", "warn") end
    label = "the score of " .. #tracks .. " tracks"
  elseif words ~= "" then
    local scope = paw.scope
    local group = scope.find(words)
    if not group then
      return paw.notify("no group '" .. words .. "': `:score` alone, `all`, `selection`, or a group's name", "warn")
    end
    tracks, label = scope.tracks(group), "the score of " .. api.track_get(group, "name")
  end
  -- Alone: the tracks the tab is narrowed to, whichever they are then.
  local F = S.show(tracks, label, { scope = words == "" and not tracks })
  if F then shown_message(F) end
end, {
  raw = true,
  range = true,
  desc = "Show a score to edit, a staff for each track with MIDI: alone the scope's (or every track), `all`, a group's name (`score Strings`), `selection` (the arrange view's tracks), `off` the clip alone",
  complete = function()
    local out = { "all", "selection", "off" }
    for _, id in ipairs(api.track_list()) do
      if paw.groups.is_group(id) then out[#out + 1] = api.track_get(id, "name") end
    end
    return out
  end,
})

paw.command("score.check", function()
  if view.parts and view.parts.check then
    view.parts.check, view.page = nil, false
    api.ui_redraw()
    return paw.notify("the score to edit again")
  end
  if not (view.parts and view:frame() and view:frame().multi) then
    if not S.show(nil, nil, { scope = true }) then return end
  end
  view.parts.check, view.page, view.galley = true, true, false
  api.ui_redraw()
  paw.notify("the pages as they will be exported, to read: :score.check again (or zp) to edit")
end, { desc = "Show the score's pages as they will be exported, to check them (read only); again, back to editing" })

paw.command("score.split", function(ctx)
  local F = view:frame()
  local u = F and F.multi and F.layout.units[F.unit]
  if not (u and u.condensed) then return paw.notify("not on a condensed staff (`:part.condense`)", "warn") end
  local bars = {}
  local from, to
  if ctx.range and ctx.range.from then
    from, to = ctx.range.from - F.start, ctx.range.to - F.start
  else
    local sel = keymap.selection()
    if sel and sel.view == "notation" then
      from, to = sel.c0, sel.c1
    else
      local m = view:measure_at(view.beat + F.off, F.layout)
      from, to = m.start, m.start + m.length
    end
  end
  for _, m in ipairs(F.layout.measures) do
    if m.start < to - EPS and m.start + m.length > from + EPS then bars[#bars + 1] = m.number end
  end
  local joined
  P.keep(u.tracks[1], function(part)
    local set, kept = {}, {}
    for _, n in ipairs(part.split or {}) do
      set[n] = true
    end
    joined = #bars > 0 and set[bars[1]] or false
    for _, n in ipairs(bars) do
      set[n] = not joined or nil
    end
    for n in pairs(set) do
      kept[#kept + 1] = n
    end
    table.sort(kept)
    part.split = #kept > 0 and kept or nil
  end)
  view.cache = nil
  api.ui_redraw()
  paw.notify(
    joined and "written a2 again where the players play the same; an edit there is made for both"
      or "the two players written apart there: an edit is the cursor's player's alone"
  )
end, {
  range = true,
  desc = "On a condensed staff: write the two players apart in the cursor's bar (or the range, or selection) though they play the same, so that an edit there is one player's; again, together (a2)",
})

-- Ex over staves -------------------------------------------------------------------------------------
--
-- In a score a staff is a clip to Ex: `s4` the fourth staff's, `s2,s5`
-- the second's to the fifth's, `s.` the cursor's, `s$` the last's, and a
-- group's or a family's name (`Strings`, `Woodwinds`) its instruments';
-- before or after the bars (`:s4 5,8>`, `:5,8 s4 >`, `:5,8 Strings
-- notation.dyn p`). Ex's own commands work on their notes; a command of
-- the view runs on each staff's clip in turn, as if the cursor were there.

local A = paw.ex.views.notation

--- The clips of the staves `a` to `b` of the score.
local function staff_clips(layout, a, b)
  local out, seen = {}, {}
  for staff = a, b do
    local _, u = S.unit_of(layout, staff)
    for _, id in ipairs(u and u.clips or {}) do
      if not seen[id] then
        seen[id], out[#out + 1] = true, id
      end
    end
  end
  return out
end

A.clips_at = function(s, i)
  local F = view:frame()
  if not (F and F.multi) then return nil, i end
  local layout = F.layout
  local function staff_at(j)
    local ch = s:sub(j, j)
    if ch == "." then return F.base + view:cursor_staff(), j + 1 end
    if ch == "$" then return #layout.staves, j + 1 end
    local n, e = s:match("^(%d+)()", j)
    if not n then return nil end
    n = tonumber(n)
    if n < 1 or n > #layout.staves then error(string.format("`s%d`: the score has %d staves", n, #layout.staves), 0) end
    return n, e
  end
  if s:sub(i, i) == "s" then
    local a, j = staff_at(i + 1)
    if a then
      local b = a
      local more = s:match("^,s?()", j)
      local b2, k = nil, nil
      if more then
        b2, k = staff_at(more)
      end
      if b2 then
        b, j = b2, k
      end
      if b < a then error("`" .. s:sub(i, j - 1) .. "`: a range of staves goes from the first to the last", 0) end
      return staff_clips(layout, a, b), j
    end
  end
  -- A group or a family by its name, followed by a command.
  local word, e = s:match("^(%a[%w_]*)()", i)
  if word and s:match("^%s", e) and not paw.commands.get(word) then
    local low, out = word:lower(), {}
    for _, u in ipairs(layout.units) do
      local group = u.group and api.track_get(u.group, "name"):lower()
      if group == low or P.FAMILIES[u.family] == low then
        for _, id in ipairs(u.clips) do
          out[#out + 1] = id
        end
      end
    end
    if #out > 0 then return out, e end
  end
  return nil, i
end

A.selection = function(region, r)
  local F = view:frame()
  if not (F and F.multi) then return end
  local parts = S.split(F, region)
  if #parts > 1 then
    r.clips, r.pitches = {}, nil
    for _, part in ipairs(parts) do
      for _, id in ipairs(part.clips) do
        r.clips[#r.clips + 1] = id
      end
    end
  elseif region.kind ~= "char" then
    r.pitches = { parts[1].region.r0, parts[1].region.r1 }
  end
end

A.each_clip = function(range, run)
  local mine
  for _, id in ipairs(range.clips) do
    local one = util.merge(range, { clips = { id } })
    if id == view.clip_id then
      mine = one
    else
      S.within(id, function() run(one) end)
    end
  end
  if mine then return run(mine) end
end

-- Keys ---------------------------------------------------------------------------------------------

local motion = { motion = true, linewise = true }
local function smap(lhs, fn, desc, opts)
  keymap.set(lhs, fn, util.merge({ view = "notation", desc = desc }, opts or motion))
end
smap(
  "]]",
  function(ctx) S.unit(1, ctx.count) end,
  "The next instrument's staff (a grand staff is one)",
  util.merge(motion, { jump = true })
)
smap(
  "[[",
  function(ctx) S.unit(-1, ctx.count) end,
  "The previous instrument's staff",
  util.merge(motion, { jump = true })
)
smap("]s", function(ctx) S.sibling(1, ctx.count) end, "The next instrument in the same group")
smap("[s", function(ctx) S.sibling(-1, ctx.count) end, "The previous instrument in the same group")
smap(
  "[{",
  function(ctx) S.edge(-1, ctx.count) end,
  "The first instrument of the group (again: of the group before)",
  util.merge(motion, { jump = true })
)
smap(
  "]}",
  function(ctx) S.edge(1, ctx.count) end,
  "The last instrument of the group (again: of the group after)",
  util.merge(motion, { jump = true })
)

S.wrap_maps()
view.staves = S
return S
