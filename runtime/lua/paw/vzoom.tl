-- Vertical zoom: how tall the rows of a view are, as `zi` and `zo` zoom
-- in time. `<C-=>` (or `z+`) makes the rows of the view under the cursor
-- taller, `<C-->` (`z-`) shorter, `<C-0>` (`z=`) gives back the height
-- the options say.
--
--   paw.vzoom.step(1)                 -- taller: the focused view's rows
--   paw.vzoom.step(-1, { count = 2 }) -- in the arrange view: two tracks only
--   paw.vzoom.fit()                   -- as the options say
--   paw.vzoom.key_rows()              -- the piano roll's rows per key
--
-- What changes by view: the arrange view, the rows of every track (on a
-- selection or with a count, of those tracks only), or of the automation
-- lanes when the cursor is on one; the piano roll, the rows of each key
-- (1 to 3). An extension's view adds its own with `paw.vzoom.define`.
--
-- The zoom is view state, as the folds are (paw/folds.tl): each window
-- keeps its own (`win.vzoom`), a split starts with that of the window it
-- comes from, a change is never an undo step, and the project's screen
-- (`screen.json`) keeps it. `paw.opt.track_height` stays the height of a
-- window that was not zoomed.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local commands = require("paw.commands")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")

local type Window = contracts.Window
local type VZoom = contracts.VZoom
local type registry = require("paw.registry")

-- The parts of the modules that this one reads.
local record Layout
  current: function(): Window
  bound: function(name: string): Window
end
local record Ui
  focused: string
  drawing_win: Window
  views: registry.Registry<contracts.View>
end
local record Groups
  rows: function(): {integer}
end
local record Cursor
  row: function(): integer
  lane_id: function(): integer
end
local record Opt
  track_height: integer | string
end
local record Paw is partial.Paw
  keymap: KeymapModule
  layout: Layout
  ui: Ui
  groups: Groups
  cursor: Cursor
  opt: Opt
end
local paw = (_G as {string: Paw}).paw

--- How a step is asked for: the `count` typed before the key (in the
--- arrange view, the tracks from the cursor that change) and the `view`
--- (by default the focused one).
local record StepOptions
  count: integer
  view: string
end

--- What a view does on a vertical zoom: `step(by, opts)` makes its rows
--- `by` taller (shorter when negative), `fit(opts)` gives back the height
--- the options say. Each returns what it did, for the message line.
local record Zoomer
  step: function(by: integer, opts: StepOptions): string
  fit: function(opts: StepOptions): string
end

local record M
  type Zoomer = Zoomer
  type StepOptions = StepOptions
  --- The most rows of a track, of a lane and of a key.
  max_track: integer
  max_lane: integer
  max_key: integer
end
M.max_track, M.max_lane, M.max_key = 12, 8, 3

local zoomers: {string: Zoomer} = {}

local function clamp(v: integer, lo: integer, hi: integer): integer
  return math.max(lo, math.min(hi, v))
end

--- The window of `view` whose zoom is meant: the one being drawn, the
--- focused one, else the one whose state the view has now.
function M.window(view: string): Window
  local u = paw.ui
  local w = u.drawing_win
  if w and w.view == view then
    return w
  end
  w = paw.layout.current()
  if w and w.view == view then
    return w
  end
  return paw.layout.bound(view) or w
end

--- The zoom of a window, nil fields where it has none.
local function of(view: string): VZoom
  local w = M.window(view)
  return w and w.vzoom or {}
end

--- The zoom of a window to change, made if it has none.
local function own(view: string): VZoom
  local w = M.window(view)
  if not w then
    error("no window to zoom in", 0)
  end
  w.vzoom = w.vzoom or {}
  return w.vzoom
end

--- Rows per track in the arrange view's window, or nil for the option's.
function M.track_rows(): integer
  return of("arrange").track_rows
end

--- The rows of a track of its own in the arrange view's window, or nil.
function M.rows_of(id: integer): integer
  for _, t in ipairs(of("arrange").tracks or {}) do
    if t.track == id then
      return t.rows
    end
  end
end

--- Whether some tracks of the arrange view's window have rows of their own.
function M.any_own(): boolean
  local list = of("arrange").tracks
  return list ~= nil and #list > 0
end

--- Rows per automation lane shown as a row in the arrange view: 2 at no zoom.
function M.lane_rows(): integer
  return of("arrange").lane_rows or 2
end

--- Rows per key in the piano roll: 1 at no zoom.
function M.key_rows(): integer
  return of("pianoroll").key_rows or 1
end

--- Add the vertical zoom of a view: `zoomer.step(by, opts)` and
--- `zoomer.fit(opts)`, each returning what it did. nil removes it.
---   paw.vzoom.define("notation", { step = function(by) ... return "staff size 5" end,
---     fit = function() ... return "staff size as the option says" end })
function M.define(view: string, zoomer: Zoomer)
  zoomers[view] = zoomer
end

local function run(fn: function(): string)
  local said = fn()
  api.ui_redraw()
  if said then
    paw.notify(said)
  end
end

--- Make the rows of a view `by` taller (shorter when negative): the
--- focused view's, or `opts.view`'s.
function M.step(by: integer, opts?: StepOptions)
  opts = opts or {}
  local view = opts.view or paw.ui.focused
  local z = zoomers[view]
  if not z then
    return paw.notify("the " .. tostring(view) .. " view has no vertical zoom", "warn")
  end
  run(function(): string return z.step(by, opts) end)
end

--- Give back the rows the options say: the focused view's, or `opts.view`'s.
function M.fit(opts?: StepOptions)
  opts = opts or {}
  local view = opts.view or paw.ui.focused
  local z = zoomers[view]
  if not z then
    return paw.notify("the " .. tostring(view) .. " view has no vertical zoom", "warn")
  end
  run(function(): string return z.fit(opts) end)
end

-- The arrange view -------------------------------------------------------------------------

--- The tracks a step in the arrange view changes on their own: those of
--- the selection (it ends), or `count` from the cursor's; nil for all.
local function chosen_tracks(opts: StepOptions): {integer}
  local rows = paw.groups.rows()
  local first, last: integer, integer
  if paw.keymap.mode == "x" then
    local r = paw.keymap.selection()
    paw.keymap.set_mode("n")
    if r then
      first, last = math.floor(r.r0), math.floor(r.r1)
    end
  elseif opts.count and opts.count > 0 then
    first = paw.cursor.row() or 1
    last = first + opts.count - 1
  end
  if not first then
    return nil
  end
  local out: {integer} = {}
  for i = math.max(1, math.min(first, last)), math.min(#rows, math.max(first, last)) do
    out[#out + 1] = rows[i]
  end
  return out
end

--- Rows per track now in the arrange view: the window's, the option's,
--- else what "auto" gave the last time it was drawn.
local function track_rows_now(): integer
  local now = M.track_rows() or math.tointeger(paw.opt.track_height)
  if not now then
    local g = (paw.ui.views:get("arrange") as contracts.ArrangeView).geometry
    now = g and g.th or 3
  end
  return now
end

local function set_own(z: VZoom, id: integer, rows: integer)
  z.tracks = z.tracks or {}
  for _, t in ipairs(z.tracks) do
    if t.track == id then
      t.rows = rows
      return
    end
  end
  z.tracks[#z.tracks + 1] = {track = id, rows = rows}
end

local function drop_own(z: VZoom, ids: {integer})
  local gone: {integer: boolean} = {}
  for _, id in ipairs(ids) do
    gone[id] = true
  end
  local kept: {contracts.TrackRows} = {}
  for _, t in ipairs(z.tracks or {}) do
    if not gone[t.track] then
      kept[#kept + 1] = t
    end
  end
  z.tracks = #kept > 0 and kept or nil
end

local function tracks_word(n: integer): string
  return n == 1 and "1 track" or (n .. " tracks")
end

M.define(
  "arrange",
  {
    step = function(by: integer, opts: StepOptions): string
      local z = own("arrange")
      local ids = chosen_tracks(opts)
      if not ids and paw.cursor.lane_id() then
        z.lane_rows = clamp((z.lane_rows or 2) + by, 2, M.max_lane)
        return "lane height " .. z.lane_rows
      end
      local base = track_rows_now()
      if ids then
        local rows = base
        for _, id in ipairs(ids) do
          rows = clamp((M.rows_of(id) or base) + by, 1, M.max_track)
          set_own(z, id, rows)
        end
        return string.format("track height %d: %s", rows, tracks_word(#ids))
      end
      z.track_rows = clamp(base + by, 1, M.max_track)
      -- Tracks of their own height grow and shrink with the others.
      for _, t in ipairs(z.tracks or {}) do
        t.rows = clamp(t.rows + by, 1, M.max_track)
      end
      return "track height " .. z.track_rows
    end,
    fit = function(opts: StepOptions): string
      local z = own("arrange")
      local ids = chosen_tracks(opts)
      if ids then
        drop_own(z, ids)
        return "track height as the others: " .. tracks_word(#ids)
      end
      if paw.cursor.lane_id() and z.lane_rows then
        z.lane_rows = nil
        return "lane height 2"
      end
      z.track_rows, z.tracks, z.lane_rows = nil, nil, nil
      local auto = math.tointeger(paw.opt.track_height)
      return auto and ("track height " .. auto) or "track height fits the tracks to the window"
    end,
  }
)

-- The piano roll ---------------------------------------------------------------------------

local function per_key(n: integer): string
  return string.format("piano roll: %d row%s per key", n, n == 1 and "" or "s")
end

M.define(
  "pianoroll",
  {
    step = function(by: integer, opts: StepOptions): string
      local z = own("pianoroll")
      local n = clamp((z.key_rows or 1) + by * math.max(1, opts.count or 1), 1, M.max_key)
      z.key_rows = n > 1 and n or nil
      return per_key(n)
    end,
    fit = function(): string own("pianoroll").key_rows = nil; return per_key(1) end,
  }
)

-- Commands ---------------------------------------------------------------------------------

commands.define(
  "vzoom",
  function(ctx: contracts.CommandContext): contracts.CommandResult
    local word = ctx.args[1] and tostring(ctx.args[1])
    if word == "fit" then
      M.fit({count = ctx.count})
      return
    end
    local by = math.tointeger(tonumber(word or "1"))
    if not by then
      error("vzoom takes a number of rows or `fit`: `vzoom 1`, `vzoom -1`, `vzoom fit`", 0)
    end
    M.step(by, {count = ctx.count})
  end,
  {
    label = "Vertical zoom",
    desc = "Taller or shorter rows in the focused view (tracks, lanes, piano roll keys), or back to the options' height: `vzoom 1`, `vzoom -1`, `vzoom fit`",
  }
)

return M
