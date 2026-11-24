-- The heads of the arrange view's rows: the cells left of the rule that
-- show a part (later a lane, or a part with its one lane). A head is a
-- record in a registry by name. A kind of part (`head` in
-- `paw.kinds.define("part", ...)`) names one, and paw takes the
-- first name that is registered, the default head last:
--
--   paw.heads.define("vocal", {
--     rows = function(size) return 3 end,
--     render = function(ctx)
--       ctx:line(0, { "badge", "name" }, { "chips" })
--       ctx:text(1, 1, ctx.width - 2, "Kitane", "PartInfo")
--     end,
--     keys = { { lhs = "s", run = "utau.singer", desc = "Choose the singer" } },
--   })
--
-- A head draws with pieces (paw/heads/pieces.tl): the name, the chips,
-- the meter. The default heads are made of them (paw/heads/default.tl).
--
-- The core keeps the frame of each row: the part column, the stripe with
-- the colour and the selection, the rule, and the lit flags (a mute, a
-- solo, an arm or a monitor that is on and that the head does not show).
-- It keeps the keys of the view too: a head adds keys only on
-- `<localleader>`, and only while the cursor is on one of its rows.
--
-- A head that fails, or runs longer than `paw.opt.head_limit`, is out
-- until it is defined again: paw says so once and draws the default head
-- on its rows. A head draws again only when what it shows changes: its
-- cells are kept (`buf:keep`) by a key of all that it reads.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local registry = require("paw.registry")
local options = require("paw.options")
local limit = require("paw.limit")
local events = require("paw.events")
local folds = require("paw.folds")
local kernel = require("paw.events.kernel")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type DrawModule = require("paw.draw")
local type KeymapModule = require("paw.keymap")
local type UiModule = require("paw.ui")
local type UtilModule = require("paw.util")

local type Head = contracts.Head
local type Piece = contracts.HeadPiece
local type Subject = contracts.HeadSubject
local type HeadWidth = contracts.HeadWidth
local type HeadAction = contracts.HeadAction
local type Buf = contracts.Buf

--- paw/cursor.tl, the part of it that this module reads.
local record Cursor
  part_id: function(): integer
  lane_id: function(): integer
end
--- paw/audio.lua, the part of it that this module reads.
local record Audio
  level: function(t: types.Part): number
end
local record Paw is partial.Paw
  util: UtilModule
  audio: Audio
  draw: DrawModule
  keymap: KeymapModule
  ui: UiModule
  cursor: Cursor
  cmd: function(line: string)
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

--- A press of the pointer that a head asked for: the cells in the view's
--- columns and lines, what it does, and a word for it.
local record Hit
  x: integer
  y: integer
  w: integer
  h: integer
  action: HeadAction
  name: string
  subject: Subject
end

--- What the arrange view gives to draw the head of one row: the buffer of
--- the headers (the stripe in its first column), the row's lines, the
--- part, its place among the parts drawn (nil for the master), whether the
--- cursor is on it, its colours, and the first column of `buf` in the view.
local record Row
  buf: Buf
  y: integer
  h: integer
  part: types.Part
  index: integer
  selected: boolean
  hue: DrawModule.Hue
  x: integer
end

--- The gestures of the pointer that the pieces of the core start: the
--- arrange view's mouse code (paw/views/arrange_mouse.tl) sets them.
local record Gestures
  flag: function(s: Subject, e: contracts.MouseEvent, flag: string)
  volume: function(s: Subject, e: contracts.MouseEvent)
  peak: function(s: Subject, e: contracts.MouseEvent)
  pan: function(s: Subject, e: contracts.MouseEvent)
  input: function(s: Subject, e: contracts.MouseEvent)
  fold: function(s: Subject, e: contracts.MouseEvent)
end

local record M
  type Hit = Hit
  type Row = Row
  --- The heads by name, with the extension that defined each one. A new
  --- head of a name hides the old one until it goes.
  heads: registry.Registry<Head>
  --- The pieces by name, with the extension that defined each one.
  pieces: registry.Registry<Piece>
  --- How many heads paw drew since it started: tests count work with it.
  draws: integer
  --- The heads that are out, by name, with the first line of the error.
  out: {string: string}
  --- The gestures that the pieces of the core start.
  gestures: Gestures
  define: function(name: string, spec: Head): Head
  builtin: function(name: string, spec: Head): Head
  remove: function(name: string)
  piece: function(name: string, spec: Piece): Piece
  compose: function(lines: {contracts.HeadLine | string}): function(ctx: contracts.HeadContext)
  subject: function(part: integer): Subject
  of: function(s: Subject): Head
  class_of: function(width: integer): HeadWidth
  begin_layout: function(width: integer)
  wish: function(part: integer): integer
  draw: function(row: Row): {Hit}
  scope: function(part: integer): string
  describe: function(part: integer): {string}
end
M.draws = 0
M.out = {}
M.gestures = {}

local limit_ms = options.define("head_limit", 5, {min = 0})
options.define("head_pictures", true)

-- The registries -------------------------------------------------------------------

--- The scope of the keys of the head `name` (paw/keymap.tl).
local function scope_of(name: string): string
  return "arrange.head." .. name
end

--- The function that a key of a head runs: its `run` on the subject of
--- the cursor's row.
local function key_runner(key: contracts.HeadKey): function()
  return function()
    local run = key.run
    if run is string then
      paw.cmd(run)
    else
      run(M.subject(paw.cursor.part_id()))
    end
  end
end

-- A head that comes maps its keys in its scope, and one that goes takes
-- them away. A new head of a name is not out.
M.heads = registry.new(
  "heads",
  "heads of the arrange view",
  {
    changed = function(name: string, head: Head, old: Head)
      for _, key in ipairs(old and old.keys or {}) do
        paw.keymap.del("<localleader>" .. key.lhs, {view = scope_of(name)})
      end
      for _, key in ipairs(head and head.keys or {}) do
        paw.keymap.set(
          "<localleader>" .. key.lhs, key_runner(key), {view = scope_of(name), desc = key.desc, ext = head.ext}
        )
      end
      M.out[name] = nil
      api.ui_redraw()
    end,
  }
)
M.pieces = registry.new("head_pieces", "pieces of heads", {changed = function() api.ui_redraw() end})

--- The name of the scope where a mapping of `keys` is, and the mapping,
--- when it clashes with `keys`: the same keys, or keys that start with the
--- other's.
local function clash(keys: string): string, KeymapModule.Map
  local scope_found: string
  local found: KeymapModule.Map
  paw.keymap.each(
    function(map: KeymapModule.Map, mode: string, scope: string, joined: string)
      local near = joined:sub(1, #keys) == keys or keys:sub(1, #joined) == joined
      if
        not found and mode == "n" and near and (scope == "arrange" or scope == "arrange.lane" or scope == "global")
      then
        scope_found, found = scope, map
      end
    end
  )
  return scope_found, found
end

--- Refuse a key of the head `name` that a key of the arrange view, or of
--- all views, has: an error that names who uses it.
local function check_key(name: string, key: contracts.HeadKey)
  if type(key) ~= "table" or type(key.lhs) ~= "string" or key.lhs == "" then
    error("a key of the head " .. name .. " needs `lhs`, the keys after <localleader>", 3)
  end
  local keys = table.concat(paw.keymap.parse("<localleader>" .. key.lhs))
  local scope, map = clash(keys)
  if map then
    local groups = paw.keymap.groups()[scope] or {}
    local group = groups[table.concat(paw.keymap.parse("<localleader>" .. key.lhs:sub(1, 1)))]
    local who = map.ext and ("the extension " .. map.ext) or scope == "global" and "paw" or "the arrange view"
    error(
      string.format(
        "the head %s cannot take %s: %s uses it (%s)", name, paw.keymap.human(keys), who, group or map.desc or map.lhs
      ),
      3
    )
  end
end

--- Define a head. `name` is a word, the one that a kind of part names in
--- its `head` field, and `spec` is a `Head` (paw/contracts.tl). A new head
--- with the name of a head that's already defined hides the old one until
--- the new one is removed. Returns the head.
function M.define(name: string, spec: Head): Head
  if type(name) ~= "string" or not name:match("^[%w_.]+$") then
    error("a head is named by a word", 2)
  end
  if type(spec) ~= "table" or type(spec.render) ~= "function" then
    error("paw.heads.define takes a name and a table with `render`", 2)
  end
  for _, key in ipairs(spec.keys or {}) do
    check_key(name, key)
  end
  spec.name = name
  spec.title = spec.title or name
  M.heads:put(name, spec)
  return spec
end

--- The heads of the core (paw/heads/default.tl): they run without the
--- limit of heads.
local core: {Head: boolean} = setmetatable({}, {__mode = "k"})

--- Define a head of the core, the same way as `define`. paw doesn't time
--- the heads of the core.
function M.builtin(name: string, spec: Head): Head
  core[spec] = true
  return M.define(name, spec)
end

--- Remove a head, so that the head it hid, if there's one, comes back.
function M.remove(name: string)
  M.heads:remove(name)
end

--- Define a piece that heads draw with, such as the name or the meter
--- (paw/heads/pieces.tl). Returns the piece.
function M.piece(name: string, spec: Piece): Piece
  if type(name) ~= "string" or not name:match("^[%w_]+$") then
    error("a piece is named by a word", 2)
  end
  if type(spec) ~= "table" or type(spec.draw) ~= "function" then
    error("paw.heads.piece takes a name and a table with `draw`", 2)
  end
  spec.name = name
  spec.keep = spec.keep or 50
  spec.min = spec.min or 1
  M.pieces:put(name, spec)
  return spec
end

-- The choice of a head --------------------------------------------------------------

--- The name of the head that the kind of a part asks for, and the kind.
local function wanted(part: integer): string, string
  if part == 0 then
    return "master", "master"
  end
  local kind = paw.part_kinds.of(part) as string
  local spec = kind and paw.part_kinds.spec(part) as contracts.PartKind
  return spec and spec.head or nil, kind
end

--- What the row of a part shows. Until parts have lanes of their own, the
--- row of a part shows the part and its lane in one head.
function M.subject(part: integer): Subject
  local _, kind = wanted(part)
  return {row = part == 0 and "master" or "merged", part = part, kind = kind or "default"}
end

--- The head that a row uses, which is the first head that the row asks for
--- that's defined and isn't out, or the default head when there's none.
function M.of(s: Subject): Head
  local name = s.row == "master" and "master" or wanted(s.part)
  for _, try in ipairs({name or false, s.row == "master" and "master" or "default"} as {string}) do
    local head = try and not M.out[try] and M.heads:get(try)
    if head then
      return head
    end
  end
  return M.heads:get("default")
end

--- The width class of a head that's `width` columns wide, without the
--- stripe.
function M.class_of(width: integer): HeadWidth
  if width < 15 then
    return "narrow"
  end
  return width >= 23 and "wide" or "default"
end

-- The height ------------------------------------------------------------------------

--- The wishes of the layout that runs, by part: the width they were asked
--- for and the head's stamp, then the rows. A new project clears them.
local wishes: {integer: {string, integer}} = {}
local layout_width = 0
events.on(kernel.project_loaded, function() wishes = {} end)

--- Start a layout of heads that are `width` columns wide. paw asks the
--- heads for their rows again when the width class or the stamp of a head
--- changes.
function M.begin_layout(width: integer)
  layout_width = width
end

--- The rows that the head of a part asks for, from 1 to 6, or nil when the
--- head doesn't ask.
function M.wish(part: integer): integer
  local s = M.subject(part)
  local head = M.of(s)
  if not (head and head.rows) then
    return nil
  end
  local ok_stamp, stamp = true, ""
  if head.stamp then
    ok_stamp, stamp = pcall(head.stamp, s) as (boolean, string)
  end
  local class = M.class_of(layout_width)
  local key = head.name .. "\0" .. class .. "\0" .. tostring(ok_stamp and stamp or "")
  local kept = wishes[part]
  if kept and kept[1] == key then
    return kept[2]
  end
  local ok, rows = pcall(head.rows, {subject = s, width = layout_width, class = class}) as (boolean, integer)
  local n = ok and math.tointeger(tonumber(rows)) or nil
  n = n and math.max(1, math.min(6, n)) or nil
  wishes[part] = {key, n}
  return n
end

-- The context of a head ---------------------------------------------------------------

--- A context as `render` gets it, with what the core reads back: the
--- flags that the pieces drawn show, the hits, and where its cells are
--- in the head (`ox`, `oy`).
local record Ctx is contracts.HeadContext
  ox: integer
  oy: integer
  root: Ctx
  shown: {string: boolean}
  hits: {Hit}
end

local Ctx_mt: metatable<Ctx> = {__index = Ctx}

local function new_ctx(buf: Buf, width: integer, height: integer, from?: Ctx): Ctx
  local ctx: Ctx = setmetatable(
    {buf = buf, width = width, height = height, ox = 0, oy = 0, shown = {}, hits = {}, mark_at = 0} as Ctx, Ctx_mt
  )
  if from then
    ctx.class, ctx.subject, ctx.part, ctx.lane = from.class, from.subject, from.part, from.lane
    ctx.selected, ctx.focused, ctx.g = from.selected, from.focused, from.g
    ctx.root = from.root
  else
    ctx.root = ctx
  end
  return ctx
end

function Ctx:piece(name: string, x: integer, y: integer, w: integer): integer
  local p = M.pieces:get(name)
  if not p or y < 0 or y >= self.height or w < (p.min or 1) then
    return 0
  end
  if p.has and not p.has(self) then
    return 0
  end
  for _, flag in ipairs(p.flags or {}) do
    self.root.shown[flag] = true
  end
  return math.tointeger(p.draw(self, x, y, w)) or 0
end

--- The columns that a piece takes on a line before the last of the left.
local function width_of(ctx: Ctx, p: Piece): integer
  return p.width and p.width(ctx) or p.min
end

--- The columns that a line of pieces needs: the margin, the pieces of the
--- left with a gap after each, the least of the last one, and the
--- pieces of the right with a gap before each, then a blank last column.
local function need(ctx: Ctx, left: {Piece}, right: {Piece}): integer
  local n = (left[1] and left[1].edge) and 0 or 1
  for i, p in ipairs(left) do
    n = n + (i < #left and width_of(ctx, p) + 1 or p.min)
  end
  for _, p in ipairs(right) do
    n = n + width_of(ctx, p) + 1
  end
  return n + 1
end

function Ctx:line(y: integer, left: {string}, right: {string})
  if y < 0 or y >= self.height then
    return
  end
  -- The pieces that have something to show.
  local function present(names: {string}): {Piece}
    local out: {Piece} = {}
    for _, name in ipairs(names) do
      local p = M.pieces:get(name)
      if p and not (p.has and not p.has(self)) then
        out[#out + 1] = p
      end
    end
    return out
  end
  local L, R = present(left), present(right)
  -- Short of room, the piece with the lowest `keep` goes first.
  while #L + #R > 1 and need(self, L, R) > self.width do
    local list, at, low = L, 1, math.huge
    for _, side in ipairs({L, R}) do
      for i, p in ipairs(side) do
        if p.keep < low then
          list, at, low = side, i, p.keep
        end
      end
    end
    table.remove(list, at)
  end
  -- The right side from the right edge, a gap before each piece. The last
  -- column stays blank, before the rule.
  local edge = self.width - 1
  for i = #R, 1, -1 do
    local n = width_of(self, R[i])
    local used = self:piece(R[i].name, edge - n, y, n)
    if used > 0 then
      edge = edge - used - 1
    end
  end
  -- The left side, a gap after each piece; the last gets what is left.
  local x = (L[1] and L[1].edge) and 0 or 1
  for i, p in ipairs(L) do
    if i < #L then
      local used = self:piece(p.name, x, y, edge - x)
      if used > 0 then
        x = x + used + 1
      end
    else
      for _, flag in ipairs(p.flags or {}) do
        self.root.shown[flag] = true
      end
      p.draw(self, x, y, math.max(1, edge - x))
    end
  end
end

function Ctx:text(x: integer, y: integer, w: integer, words: string, style: string)
  if w <= 0 or y < 0 or y >= self.height then
    return
  end
  if api.str_width(words) > w then
    words = paw.util.fit(words, w)
  end
  self.buf:text(x, y, words, style)
end

function Ctx:picture(x: integer, y: integer, w: integer, h: integer, key: string): boolean
  if not opt.head_pictures or w <= 0 or h <= 0 then
    return false
  end
  self.buf:image(x, y, w, h, key)
  return true
end

function Ctx:sub(x: integer, y: integer, w: integer, h: integer): contracts.HeadContext
  w = math.max(0, math.min(w, self.width - x))
  h = math.max(0, math.min(h, self.height - y))
  local ctx = new_ctx(self.buf:sub(x, y, w, h), w, h, self)
  ctx.ox, ctx.oy = self.ox + x, self.oy + y
  ctx.hits = self.root.hits
  return ctx
end

function Ctx:hit(x: integer, y: integer, w: integer, h: integer, action: HeadAction, name?: string)
  local list = self.root.hits
  list[#list + 1] = {x = self.ox + x, y = self.oy + y, w = w, h = h, action = action, name = name}
end

-- Drawing a row -------------------------------------------------------------------------

--- The switches of a part, in the order of the chips, with the style of
--- each when it is on.
local FLAGS: {{string, string, string}} = {
  {"mute", "M", "Mute"},
  {"solo", "S", "Solo"},
  {"armed", "R", "Armed"},
  {"monitor", "I", "Monitor"},
}
--- The colours a window lights each switch in.
local TONES: {string: string} = {mute = "mute", solo = "solo", armed = "rec", monitor = "select"}

--- The lit flags: each switch that is on and that the head did not show,
--- in the last cells of its first line, over what the head drew there.
local function lit_flags(ctx: Ctx)
  local lit: {{string, string, string}} = {}
  local fields = ctx.part as {string: boolean}
  for _, f in ipairs(FLAGS) do
    if fields[f[1]] and not ctx.shown[f[1]] then
      lit[#lit + 1] = f
    end
  end
  local x = ctx.width - 1 - #lit
  for i, f in ipairs(lit) do
    local props: contracts.SwitchMark = {
      letter = f[2],
      on = true,
      style = f[3],
      tone = TONES[f[1]],
      label = f[1],
    }
    ctx.buf:mark("switch", x + i - 1, 0, 1, 1, props)
  end
end

--- What a head drew, kept: the key it was drawn from and its hits.
local record Kept
  key: string
  hits: {Hit}
end
local kept: {string: Kept} = {}

-- A change of the project, of a device or of an option changes what a
-- head shows: the generation of what heads read. A fold that opens or
-- closes changes it too (`folds.generation`): a folded group's head
-- says how many parts it holds.
local generation = 0
local function changed()
  generation = generation + 1
end
events.on(kernel.changed, changed)
events.on(kernel.device_changed, changed)
events.on(kernel.device_ready, changed)
events.on(kernel.project_loaded, changed)
events.on(options.changed, changed)

--- All that the head of a row reads, as text: when it is the same, the
--- kept cells are the same. The levels of the meter and of the input
--- are in it, so a head draws again while the song plays.
local function keep_key(head: Head, ctx: Ctx, row: Row): string
  local stamp = ""
  if head.stamp then
    local ok, s = pcall(head.stamp, ctx.subject) as (boolean, string)
    stamp = ok and tostring(s) or "?"
  end
  local left, right, hold, clipped = paw.draw.part_peak(row.part.id)
  local input = row.part.input and string.format("%.4f", paw.audio.level(row.part)) or ""
  return table.concat(
    {
      head.name,
      generation,
      folds.generation,
      row.part.id,
      row.index or 0,
      ctx.width,
      ctx.height,
      tostring(row.selected),
      tostring(ctx.focused),
      stamp,
      string.format("%.4f %.4f %.4f %s", left, right, hold, tostring(clipped)),
      input,
    } as {string},
    "\0"
  )
end

--- Run `head`'s render on `ctx` under the limit of heads: nil, or the
--- first line of its error.
local function run(head: Head, ctx: Ctx): string
  M.draws = M.draws + 1
  -- The heads of the core are not timed: only the ones that the user or an
  -- extension gives.
  if core[head] then
    head.render(ctx)
    return nil
  end
  local ok, err = pcall(limit.within, limit_ms:get(), "the head " .. head.name, head.render, ctx) as (boolean, string)
  if ok then
    return nil
  end
  return (tostring(err):match("^[^\n]*"))
end

--- Draw the head of a row with its frame, its kept cells or a new render,
--- the lit switches, and what other modules mark there. Returns the places
--- that a click reaches, in the columns and lines of the view.
function M.draw(row: Row): {Hit}
  local g = paw.draw.g
  local buf, t = row.buf, row.part
  local frame: contracts.PartheadMark = {
    style = row.selected and "PartHeaderSel" or "PartHeader",
    stripe = row.selected and g.stripe_sel or g.stripe,
    stripe_style = row.hue.fg,
    color = paw.draw.part_colour(t, row.index),
    selected = row.selected or nil,
  }
  buf:mark("parthead", 0, row.y, buf.width, row.h, frame)
  local w = buf.width - 1
  local hb = buf:sub(1, row.y, w, row.h)
  local ctx = new_ctx(hb, w, row.h)
  ctx.class = M.class_of(w)
  ctx.subject = M.subject(t.id)
  ctx.part = t
  ctx.selected = row.selected
  ctx.focused = paw.ui.focused == "arrange"
  ctx.g = g
  local head = M.of(ctx.subject)
  local place = "head:" .. (hb as {string: integer}).x .. ":" .. (hb as {string: integer}).y
  local key = not paw.ui.scene_drawing and keep_key(head, ctx, row)
  local was = key and kept[place]
  if was and was.key == key and hb:put_kept(place, 0, 0, w, row.h) then
    ctx.hits = was.hits
  else
    local err = run(head, ctx)
    if err then
      -- A head that fails is out: the default head draws over its row,
      -- and paw says so once.
      M.out[head.name] = err
      paw.notify(string.format("the head %s failed: %s; paw shows the default head", head.name, err), "error")
      hb:fill(0, 0, w, row.h, " ", frame.style as string)
      local fallback = M.of(ctx.subject)
      ctx = new_ctx(hb, w, row.h, ctx)
      run(fallback, ctx)
    end
    lit_flags(ctx)
    if key then
      hb:keep(place, 0, 0, w, row.h)
      kept[place] = {key = key, hits = ctx.hits}
    end
  end
  -- What other modules mark on the head: `x` is the free column before
  -- the name, in the columns of `buf`.
  paw.ui.paint(
    "arrange", "header", {buf = buf, x = 1 + ctx.mark_at, y = row.y, width = buf.width, height = row.h, part = t.id}
  )
  local out: {Hit} = {}
  for _, h in ipairs(ctx.hits) do
    out[#out + 1] = {
      x = row.x + 1 + h.x,
      y = row.y + h.y,
      w = h.w,
      h = h.h,
      action = h.action,
      name = h.name,
      subject = ctx.subject,
    }
  end
  return out
end

-- Keys and K ------------------------------------------------------------------------------

--- The scope of the keys of the head of a part, or nil when the head has
--- no keys.
function M.scope(part: integer): string
  local head = M.of(M.subject(part))
  return head and head.keys and #head.keys > 0 and scope_of(head.name) or nil
end

--- The lines that `K` shows about the head of a part's row. When no
--- extension here defines the head that the row asks for, or the head is
--- out, the first line says so, and the head's own lines come after it.
function M.describe(part: integer): {string}
  local out: {string} = {}
  local s = M.subject(part)
  local name = wanted(part)
  if name and not M.heads:get(name) then
    out[#out + 1] = "head    " .. name .. " (no extension here defines it)"
  elseif name and M.out[name] then
    out[#out + 1] = "head    " .. name .. " (out: " .. M.out[name] .. ")"
  end
  local head = M.of(s)
  if head and head.describe then
    local ok, lines = pcall(head.describe, s) as (boolean, {string})
    for _, line in ipairs(ok and lines or {}) do
      out[#out + 1] = line
    end
  end
  return out
end

--- A render made of lines. The first line always shows, and each later line
--- shows when its pieces have something to show and there are rows left. A
--- line is a `HeadLine`, or the name of a piece that takes a whole line and
--- starts under the name.
function M.compose(lines: {contracts.HeadLine | string}): function(ctx: contracts.HeadContext)
  return function(ctx: contracts.HeadContext)
    local y = 0
    for i, l in ipairs(lines) do
      if y >= ctx.height then
        return
      end
      if l is string then
        local indent = ctx.class == "narrow" and 1 or 3
        if ctx:piece(l, indent, y, ctx.width - 1 - indent) > 0 then
          y = y + 1
        end
      else
        ctx:line(y, l.left or {}, l.right or {})
        y = y + 1
      end
      if i == 1 then
        y = 1
      end
    end
  end
end

return M
