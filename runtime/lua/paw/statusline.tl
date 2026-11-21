-- The status line, like lualine's: sections of components, set up in Lua.
--
--   paw.statusline.setup({
--     sections = { a = { "mode" }, c = { "transport", "tempo" }, z = { "project" } },
--     theme = "default",
--     views = { pianoroll = { sections = { c = { "cursor" } } } },
--   })
--
-- Six sections, `a b c` from the left and `x y z` to the right edge. A
-- component is the name of one (`paw.statusline.components`), a function
-- `fn(ctx)`, or a table `{ name_or_function, min = 90, rank = 6, style =
-- "StatusDim", cond = fn, fmt = fn }`. What it returns is nothing (it has
-- nothing to say), a string, or a list of `{ text, style }` pieces. `min`
-- is the narrowest screen it is shown on and `rank` how late it is dropped
-- when the line is too long (higher goes first; 0 never). A component with
-- `key(ctx)` is called again only when that changes, so that a line with
-- many components costs what has changed. The window is told the same line
-- (`paw.frontend`), so that both show one status line.
--
-- Other bars use the same sections: `winbar` (on the title bar of the
-- window with the keys) and `inactive_winbar` (of the others), and
-- `tabline` (at the right of the tabs; `always = true` shows the row with
-- one tab too). `views` changes sections for the view that has the keys;
-- `inactive_sections` are used while a float has them.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local util = require("paw.util")
local options = require("paw.options")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local type contracts = require("paw.contracts")
local type types = require("paw.types")
local type partial = require("paw.partial")
local type UiModule = require("paw.ui")
local type MouseModule = require("paw.mouse")
local type objects = require("paw.objects")
local type TextbufModule = require("paw.textbuf")
local type CursorModule = require("paw.cursor")
local type DrawModule = require("paw.draw")
local type TempoModule = require("paw.tempo")

local type Context = contracts.StatusContext
local type Theme = contracts.StatusContext.Theme
local type Component = contracts.StatusComponent
local type StatusText = contracts.StatusText
local type Piece = contracts.Piece

--- A value this module copies and never reads.
local record Value
end

-- What this module reads of `paw`, which paw/init.lua makes, and of the
-- modules in Lua that it calls: their parts that it uses.
local record Visual
  kind: string
end
local record Keymap
  visual: Visual
  recording: function(): string
  pending: function(): string
end
local record Scope
  current: function(): integer
end
local record Audio
  load: function(cpu?: number): number
end
local record Lister
  status: function(): StatusText
end
local record Paw is partial.Paw
  ui: UiModule
  textbuf: TextbufModule
  audio: Audio
  cursor: CursorModule
  diagnostic: Lister
  draw: DrawModule
  mouse: MouseModule
  qf: Lister
  scope: Scope
  tempo: TempoModule
  time: objects.Time
end
local paw = (_G as {string:Paw}).paw
local opt = options.opt

--- A function that is a component (`fn(ctx)`).
local type ComponentFn = function(ctx?: Context): StatusText

--- An entry of a section given as a table: the component (its name or a
--- function) first, or as `fn`, and what changes it here.
local record Entry
  {string | ComponentFn}
  fn: ComponentFn
  min: integer
  rank: integer
  style: string
  cond: function(ctx?: Context): boolean
  fmt: function(text: string): string
end

--- An entry of a section: the name of a component, a function, or a table.
local type SectionEntry = string | ComponentFn | Entry

--- The sections by letter: `a b c` from the left, `x y z` to the right.
local type Sections = {string:{SectionEntry}}

--- The separators between sections and between components (nil for the
--- default, "" for none).
local record Separators
  section: string
  component: string
end

--- A bar's sections, and the sections for the view that has the keys.
local record Bar
  sections: Sections
  views: {string:Bar}
  --- The tab line shows with one tab too.
  always: boolean
end

--- What `setup` takes, and what the line is made from (`config`): the
--- theme, by name or as groups, the separators, the sections, the sections
--- of each view, the sections while a float has the keys, and the other bars.
local record Config
  theme: string | Theme
  separators: Separators
  sections: Sections
  views: {string:Bar}
  inactive_sections: Sections
  winbar: Bar
  inactive_winbar: Bar
  tabline: Bar
end

--- What `setup` takes: as `Config`, and false to take a bar away.
local record Setup
  theme: string | Theme
  separators: Separators
  sections: Sections
  views: {string:Bar}
  inactive_sections: Sections
  winbar: Bar | boolean
  inactive_winbar: Bar | boolean
  tabline: Bar | boolean
end

--- A segment of the line: its pieces, its `rank`, `pill` for a coloured
--- label, `name` for the segment cut before others go, and its section.
local record Segment
  {Piece}
  rank: integer
  pill: boolean
  name: boolean
  section: string
end

--- The segments of a line (`paw.statusline.segments`), and the errors of
--- the components that failed.
local record Segments
  left: {Segment}
  right: {Segment}
  errors: {string}
end

--- A line fitted to its width (`paw.statusline.line`): each side as pieces.
local record Line
  left: {Piece}
  right: {Piece}
  errors: {string}
end

--- What `M.draw`, `M.line` and `M.segments` may add to the context.
local record Extra
  view: string
  focused: boolean
end

--- What `paw.statusline.stats` counts: components called and taken from
--- their cache.
local record Stats
  calls: integer
  cached: integer
end

local record M
  type Context = Context
  type Theme = Theme
  type Entry = Entry
  type SectionEntry = SectionEntry
  type Sections = Sections
  type Separators = Separators
  type Bar = Bar
  type Config = Config
  type Setup = Setup
  type Segment = Segment
  type Segments = Segments
  type Line = Line
  type Extra = Extra
  type Stats = Stats
  components: {string:Component}
  themes: {string:Theme}
  stats: Stats
  --- True after `setup`.
  set_up: boolean
  config: function(): Config
  --- A component's spec, or its function.
  component: function(name: string, spec: Component | ComponentFn): Component
end
M.components, M.themes, M.stats = {}, {}, { calls = 0, cached = 0 }

local LEFT, RIGHT = { "a", "b", "c" }, { "x", "y", "z" }

-- What each is called, so that the line does not change shape as the width
-- changes by a column; see the specs below for the narrowest screens.
local default: Config = {
  theme = "default",
  separators = {},
  sections = {
    a = { "mode" },
    b = {},
    c = { "macro", "transport", "clock", "tempo", "flags", "render", "diagnostics", "qf", "pointer", "grid", "selection", "view" },
    x = { "keys", "scope", "project", "engine", "cpu" },
    y = {},
    z = {},
  },
}

local config: Config

local unpack = (_G as {string:function({SectionEntry}): SectionEntry...}).unpack

local function copy_sections(sections: Sections): Sections
  local out: Sections = {}
  for _, letter in ipairs({ "a", "b", "c", "x", "y", "z" }) do out[letter] = sections and sections[letter] and { unpack(sections[letter]) } or nil end
  return out
end

local function fresh(): Config
  return { theme = default.theme, separators = {}, sections = copy_sections(default.sections), views = {} }
end

--- Change the line: only what is given changes. `sections` replaces the
--- sections it names, `views` and the other bars likewise.
function M.setup(opts?: Setup)
  config = config or fresh()
  M.set_up = true
  opts = opts or {}
  if opts.theme ~= nil then config.theme = opts.theme end
  if opts.separators ~= nil then config.separators = opts.separators end
  if opts.inactive_sections ~= nil then config.inactive_sections = opts.inactive_sections end
  for letter, list in pairs(opts.sections or {}) do config.sections[letter] = list end
  for view, spec in pairs(opts.views or {}) do config.views[view] = spec end
  -- A bar given as false goes.
  local function bar(given: Bar | boolean): Bar
    if given is Bar then return given end
    return nil
  end
  if opts.winbar ~= nil then config.winbar = bar(opts.winbar) end
  if opts.inactive_winbar ~= nil then config.inactive_winbar = bar(opts.inactive_winbar) end
  if opts.tabline ~= nil then config.tabline = bar(opts.tabline) end
  api.ui_redraw()
end

--- Back to the line as it comes.
function M.reset()
  config = fresh()
  M.set_up = false
  api.ui_redraw()
end

--- The status line's configuration as `setup` made it.
function M.config(): Config
  config = config or fresh()
  return config
end

--- Add a component, as an extension does: `paw.statusline.component("pulse",
--- function(ctx) return "♥" end)`, or with the fields of a table (`fn`,
--- `min`, `rank`, `style`, `key`, `cond`).
function M.component(name: string, spec: Component | ComponentFn): Component
  local c: Component
  if spec is ComponentFn then c = { fn = spec } else c = spec end
  assert(type(name) == "string" and type(c) == "table" and type(c.fn) == "function", "usage: paw.statusline.component(name, function(ctx) ... end)")
  c.name = name
  M.components[name] = c
  api.ui_redraw()
  return c
end

-- Themes ----------------------------------------------------------------------------

-- Which highlight group each part is drawn in. `mode` is by mode letter
-- (`n`, `i`, `x`, `o`, `c`); a section's group is what a component that
-- gives only text is drawn in.
M.themes.default = {
  mode = { n = "StatusMode", i = "StatusInsert", x = "StatusVisual", o = "StatusPending", c = "StatusCommand" },
  a = "StatusLine", b = "StatusLine", c = "StatusLine", x = "StatusLine", y = "StatusLine", z = "StatusLine",
  sep = "StatusSep",
}

--- A theme with the groups of `over` laid over those of `base`.
local function merged(base: Theme, over: Theme): Theme
  return util.merge(base as {string:Value}, over as {string:Value}) as Theme
end

-- One colour for the mode, whichever it is.
M.themes.mono = merged(M.themes.default, { mode = { n = "StatusMode", i = "StatusMode", x = "StatusMode", o = "StatusMode", c = "StatusMode" } })

local function theme_of(name: string | Theme): Theme
  if name is Theme then return merged(M.themes.default, name) end
  return M.themes[name or "default"] or M.themes.default
end

-- Components ---------------------------------------------------------------------------

local modes: {string:string} = { n = "NORMAL", c = "COMMAND", i = "INSERT", o = "PENDING" }
local short: {string:string} = { n = "NOR", c = "CMD", i = "INS", o = "PND", VISUAL = "VIS", ["V-LINE"] = "VLN", ["V-BLOCK"] = "VBL", CLIPS = "CLP" }
local visual: {string:string} = { v = "VISUAL", V = "V-LINE", b = "V-BLOCK", clips = "CLIPS" }

--- A grid in beats as a note value: 1 is `1/4`, 0.25 is `1/16`.
function M.grid_text(grid: number): string
  local n = 4 / grid
  if math.abs(n - math.floor(n + 0.5)) < 1e-6 and n >= 1 then return "1/" .. math.floor(n + 0.5) end
  return string.format("%g beats", grid)
end

local function spec(name: string, def: Component)
  def.name = name
  def.rank = def.rank or 3
  def.min = def.min or 0
  M.components[name] = def
end

spec("mode", { rank = 0, pill = true, fn = function(ctx: Context): StatusText
  local mode = ctx.mode
  local km = (paw.keymap as Keymap)
  local name = mode == "x" and km.visual and visual[km.visual.kind] or modes[mode] or mode:upper()
  if ctx.width < 80 then
    name = short[name] or short[mode] or name:sub(1, 3)
  elseif paw.ui.focused then
    -- The view that has the keys, so that focus can be told at a glance.
    name = name .. ctx.g.dot .. paw.ui.focused
  end
  return { { " " .. name .. " ", ctx.theme.mode[mode] or ctx.theme.mode.n } }
end })

spec("macro", { rank = 1, fn = function(): StatusText
  local recording = (paw.keymap as Keymap).recording()
  if recording then return { { "@" .. recording, "StatusMacro" } } end
end })

spec("transport", { rank = 2, fn = function(ctx: Context): StatusText
  local t, g = ctx.transport, ctx.g
  local state: Piece = t.take and { g.rec, "StatusRec" } or t.playing and { g.play, "StatusPlay" } or { g.stop, "StatusStop" }
  if (t.counting or 0) > 0 then
    -- Counting in: the beats left before the take starts, in place of the time.
    return { state, { " count " .. t.counting, "StatusRec" } }
  end
  return { state, { " " .. paw.time.format(t.position), "StatusTime" } }
end })

-- The time in minutes and seconds.
spec("clock", { min = 90, rank = 8, fn = function(ctx: Context): StatusText
  return { { paw.time.clock(ctx.transport.position), "StatusDim" } }
end })

-- Tempo and time signature where the playhead is.
spec("tempo", { min = 70, rank = 5, fn = function(ctx: Context): StatusText
  local position = ctx.transport.position
  local num, den = paw.tempo.signature_at(position)
  local bpm = math.floor(paw.tempo.at(position) * 10 + 0.5) / 10
  return { { string.format("%g bpm %d/%d", bpm, num, den), "StatusLine" } }
end })

-- What is switched on, and only that.
spec("flags", { rank = 4, fn = function(ctx: Context): StatusText
  local t, g = ctx.transport, ctx.g
  local on: {Piece} = {}
  if t.loop_enabled then
    local bar = paw.time.bar()
    local from = math.floor(t.loop_start / bar + 1e-9) + 1
    local to = math.max(from, math.ceil(t.loop_end / bar - 1e-9))
    on[#on + 1] = { "loop " .. from .. (g.ellipsis == "…" and "–" or "-") .. to, "StatusOn" }
  end
  if t.metronome then on[#on + 1] = { "click", "StatusOn" } end
  if t.punch_enabled and t.punch_end > t.punch_start then
    local from = paw.time.bar_of(t.punch_start)
    local to = math.max(from, paw.time.bar_of(t.punch_end - 1e-9))
    on[#on + 1] = { "punch " .. from .. (g.ellipsis == "…" and "–" or "-") .. to, "StatusRec" }
  end
  if (t.count_in or 0) > 0 then on[#on + 1] = { "count " .. t.count_in, "StatusOn" } end
  if t.recording then on[#on + 1] = { "rec", "StatusRec" } end
  if t.write then on[#on + 1] = { "write", "StatusRec" } end
  if #on == 0 then return nil end
  local out: {Piece} = {}
  for i, piece in ipairs(on) do
    if i > 1 then out[#out + 1] = { " ", "StatusLine" } end
    out[#out + 1] = piece
  end
  return out
end })

-- A render in the background: how far it has got, and how to stop it;
-- only the percentage on a narrow screen.
spec("render", { fn = function(ctx: Context): StatusText
  local job = api.render_status()
  if not job then return nil end
  local width = ctx.width
  local pct = string.format("%d%%", math.floor(job.fraction * 100))
  local file = tostring(job.path):match("([^/]+)$") or tostring(job.path)
  local verb = job.stage == "encoding" and "encoding" or "rendering"
  local text = width >= 120 and (verb .. " " .. file .. " " .. pct .. " · Esc cancels")
    or width >= 80 and (verb:sub(1, 6) .. " " .. pct .. " · Esc") or (verb:sub(1, 6) .. " " .. pct)
  return { { text, "StatusRec" } }
end })

-- How many diagnostics of each kind, for the piano roll's clip or the project.
spec("diagnostics", { fn = function(): StatusText return paw.diagnostic and paw.diagnostic.status() end })

-- The quickfix list, while it has entries.
spec("qf", { fn = function(): StatusText return paw.qf and paw.qf.status() end })

-- What is under the pointer, or what it would do there, in what room is left.
spec("pointer", { fn = function(ctx: Context): StatusText
  local pointer = paw.mouse.hint_text()
  local room = ctx.width - 70
  if not (pointer and room >= 12) then return nil end
  if api.str_width(pointer) > room then pointer = util.fit(pointer, room) end
  return { { pointer, "StatusHint" } }
end })

-- The grid of the view that has focus: the roll and the drums keep their own.
local record Steps
  step: function(): number
  rows: number
end
spec("grid", { min = 100, rank = 9, fn = function(): StatusText
  local focused = paw.ui.views[paw.ui.focused]
  local cells = focused and focused.grid as Steps
  if not (cells and cells.step) or cells.rows then
    cells = { step = function(): number return opt.grid end }
  end
  return { { "grid " .. M.grid_text(cells.step()), "StatusDim" } }
end })

-- How much is selected, in visual mode.
spec("selection", { min = 110, rank = 10, fn = function(ctx: Context): StatusText
  local selection = ctx.mode == "x" and paw.ui.focused == "arrange" and paw.keymap.selection()
  if not selection then return nil end
  local tracks = selection.r1 - selection.r0 + 1
  local text = tracks .. (tracks == 1 and " track" or " tracks")
  if selection.kind ~= "line" then
    local beats = selection.c1 - selection.c0
    local bars = beats / paw.time.bar()
    text = text .. " " .. (math.abs(bars - math.floor(bars + 0.5)) < 1e-9 and string.format("%g bar%s", bars, bars == 1 and "" or "s")
      or string.format("%g beats", beats))
  end
  return { { "sel " .. text, "StatusLine" } }
end })

-- What the view with the keys says of itself (`status(ctx)`): a buffer
-- type's or a text buffer kind's own part of the line.
spec("view", { min = 90, rank = 5, fn = function(ctx: Context): StatusText
  local view = paw.ui.views[paw.ui.focused]
  if view and view.status then return view:status(ctx) end
end })

-- Keys typed so far, or the register chosen.
spec("keys", { fn = function(): StatusText
  local pending = (paw.keymap as Keymap).pending()
  if pending ~= "" then return { { pending, "StatusOn" } } end
end })

-- One field of a track, quicker than the whole track (`track_get(id, key)`).
local track_field = api.track_get as function(id: integer, key: string): string

-- The group a narrowed tab shows, and what the rest of the song does.
spec("scope", { rank = 2, fn = function(ctx: Context): StatusText
  local scope = paw.scope and paw.scope.current()
  if not scope then return end
  local out: {Piece} = { { "narrowed " .. track_field(scope, "name"), "StatusOn" } }
  local rest = opt.scope_rest
  if rest ~= "play" and ctx.width >= 100 then out[2] = { " rest " .. rest, "StatusDim" } end
  return out
end })

-- The project, with an amber dot when it has unsaved changes. Its name is
-- cut before anything is dropped. Its key reads the two fields alone: the
-- whole project (`ctx.project`) looks at every clip for its length, and
-- the key is asked for on each frame while the song plays.
local project_field = api.project_get as function(key: string): string | boolean
spec("project", { rank = 1, shrink = true, key = function(_: Context): string
  return tostring(project_field("name")) .. (project_field("modified") and "*" or "")
end, fn = function(ctx: Context): StatusText
  local p = ctx.project
  local out: {Piece} = { { p.name, "StatusName" } }
  if p.modified then table.insert(out, 1, { ctx.g.modified .. " ", "StatusModified" }) end
  return out
end })

-- The engine: backend, rate and block size.
spec("engine", { min = 120, rank = 7, key = function(ctx: Context): string
  local e = ctx.engine
  return table.concat({ tostring(e.backend), tostring(e.sample_rate), tostring(e.block), tostring(e.buffer_size) }, ":")
end, fn = function(ctx: Context): StatusText
  local e = ctx.engine
  local block = (e.block and e.block > 0) and e.block or e.buffer_size
  return { { string.format("%s %gk%s", e.backend, e.sample_rate / 1000, block and block > 0 and (" " .. block) or ""), "StatusDim" } }
end })

-- How busy the engine is, and dropouts since it started.
spec("cpu", { min = 90, rank = 6, key = function(ctx: Context): string
  local e = ctx.engine
  return paw.audio.load(e.cpu) .. ":" .. (e.xruns or 0)
end, fn = function(ctx: Context): StatusText
  local e = ctx.engine
  local busy = math.max(0, math.min(1, paw.audio.load(e.cpu)))
  local out: {Piece} = { { "cpu " .. ctx.g.eighths[1 + math.floor(busy * 7.99)] .. string.format(" %d%%", math.floor(busy * 100 + 0.5)),
    busy > 0.8 and "StatusError" or busy > 0.5 and "StatusWarn" or "StatusDim" } }
  if (e.xruns or 0) > 0 then out[#out + 1] = { " xrun " .. e.xruns, "StatusWarn" } end
  return out
end })

-- The track the cursor is on and the clip under it.
spec("cursor", { min = 100, rank = 6, fn = function(): StatusText
  local track = paw.cursor.track()
  if not track then return nil end
  local clip = paw.cursor.clip()
  local name = clip and clip.name ~= "" and clip.name or nil
  return { { track.name, "StatusName" }, { name and ("  " .. name) or "", "StatusDim" } }
end })

-- A take being recorded: its number, and the loop's passes.
spec("take", { rank = 2, fn = function(ctx: Context): StatusText
  local take = ctx.transport.take
  if take then return { { "take " .. take, "StatusRec" } } end
end })

-- The text buffer with the keys, with its name.
spec("buffer", { rank = 4, fn = function(ctx: Context): StatusText
  if paw.ui.focused ~= "textbuf" then return nil end
  local buf = paw.textbuf.buf()
  if not buf then return nil end
  -- A long address keeps its end, where the name is.
  local name = buf.name
  if api.str_width(name) > 40 then name = ctx.g.ellipsis .. name:sub(-39) end
  return { { name, "StatusName" } }
end })

-- MIDI coming in: lit for a moment after each message.
local last_midi: number
local midi_port: string
events.on(kernel.midi_in, function(event: types.MidiEvent)
  last_midi, midi_port = api.now(), event.port
  api.ui_redraw()
  paw.defer(function() api.ui_redraw() end, 400)
end)
spec("midi", { min = 90, rank = 7, fn = function(ctx: Context): StatusText
  if last_midi and api.now() - last_midi < 300 then
    return { { "midi " .. ctx.g.dot, "StatusOn" }, { midi_port and (" " .. midi_port) or "", "StatusDim" } }
  end
end })

-- Building ----------------------------------------------------------------------------------

--- A function that reads one of the values a context reads when asked.
local type Read = function(): Value

-- What a context reads when a component asks for it.
local lazy: {string:Read} = {
  transport = api.transport_get as Read, project = api.project_get as Read, engine = api.engine_get as Read,
}
local lazy_meta: metatable<{string:Value}> = { __index = function(t: {string:Value}, k: string): Value
  local read = lazy[k]
  if not read then return nil end
  local v = read()
  rawset(t, k, v)
  return v
end }

--- What a component is called with: the screen's width, the mode, the view
--- that has the keys, and (read when asked for) the transport, the project
--- and the engine.
local function context(width: integer, which: string, extra: Extra): Context
  local ctx: Context = {
    width = width, which = which, mode = paw.keymap.mode, view = paw.ui.focused, g = paw.draw.g,
    active = not paw.ui.float,
  }
  local fields = ctx as {string:Value}
  for k, v in pairs((extra or {}) as {string:Value}) do fields[k] = v end
  return setmetatable(fields, lazy_meta) as Context
end

--- What a component gave last, by the key it gave (`key(ctx)`).
local record Kept
  mark: string
  pieces: StatusText
end
local cached: {Component:Kept} = setmetatable({}, { __mode = "k" })

--- The pieces a component entry gives now, with its `min`, `rank` and the
--- rest of what it is: nil when it has nothing to show.
local function evaluate(entry: SectionEntry, ctx: Context, base: string): Segment, string
  local def: Entry = entry is Entry and entry or { entry as string | ComponentFn }
  local what = def[1] or def.fn
  local component: Component
  if what is string then
    component = M.components[what]
    if not component then return nil, "no status line component `" .. what .. "`" end
  elseif what is ComponentFn then
    component = { fn = what, rank = 3, min = 0 }
  else
    return nil, "a status line component is a name, a function or a table"
  end
  local min = def.min or component.min or 0
  if ctx.width < min then return nil end
  if def.cond and not def.cond(ctx) then return nil end
  local pieces: StatusText
  local key = component.key and component.key(ctx)
  local keep = key ~= nil and cached[component]
  local mark = key ~= nil and table.concat({ tostring(key), ctx.width, ctx.which, tostring(ctx.mode), tostring(ctx.view) }, "|")
  if keep and keep.mark == mark then
    M.stats.cached = M.stats.cached + 1
    pieces = keep.pieces
  else
    M.stats.calls = M.stats.calls + 1
    local ok, out = pcall(component.fn, ctx)
    if not ok then return nil, tostring(out):match("^[^\n]*") end
    pieces = out as StatusText
    if key ~= nil then cached[component] = { mark = mark, pieces = pieces } end
  end
  if pieces == nil or (pieces as boolean) == false or pieces == "" then return nil end
  local list: {Piece}
  if pieces is string then list = { { pieces } } else list = pieces end
  local style = def.style or component.style or base
  local seg: Segment = { rank = def.rank or component.rank or 3, pill = component.pill, name = component.shrink }
  for _, piece in ipairs(list) do
    local text = piece[1]
    if def.fmt then text = def.fmt(text) end
    seg[#seg + 1] = { tostring(text), piece[2] or style }
  end
  if #seg == 0 then return nil end
  return seg
end

local function sections_for(which: string, view: string, active: boolean): Sections
  local c = M.config()
  local bar: Bar
  if which == "status" then
    bar = c as Bar
  else
    bar = (c as {string:Bar})[which] or {}
  end
  local sections = bar.sections or {}
  if which == "status" and not active and c.inactive_sections then sections = util.merge(sections, c.inactive_sections) end
  local per = bar.views and bar.views[view]
  if per and per.sections then sections = util.merge(sections, per.sections) end
  return sections
end

--- The segments for a screen `width` wide, as `{ left = {...}, right = {...} }`.
--- Each is a list of `{ text, style }` pieces with a `rank` (lower ranks go
--- last) and the `section` that it came from. `pill` is for a colored label.
--- `name` is for the segment that paw cuts before it removes segments.
---   which: "status" (default), "winbar", "inactive_winbar" or "tabline"
function M.segments(width: integer, which?: string, extra?: Extra): Segments
  which = which or "status"
  local c = M.config()
  local theme = theme_of(c.theme)
  local ctx = context(width, which, extra)
  ctx.theme = theme
  local sections = sections_for(which, ctx.view, ctx.active)
  local out: Segments = { left = {}, right = {}, errors = {} }
  local styles = theme as {string:string}
  for side, letters in pairs({ left = LEFT, right = RIGHT }) do
    local into = side == "left" and out.left or out.right
    for _, letter in ipairs(letters) do
      for _, entry in ipairs(sections[letter] or {}) do
        local seg, err = evaluate(entry, ctx, styles[letter] or "StatusLine")
        if seg then
          seg.section = letter
          into[#into + 1] = seg
        elseif err then
          out.errors[#out.errors + 1] = err
        end
      end
    end
  end
  return out
end

-- Drawing ----------------------------------------------------------------------------------

local function width_of(seg: Segment): integer
  local n = 0
  for _, piece in ipairs(seg) do n = n + api.str_width(piece[1]) end
  return n
end

--- The text between a segment and the one before it, and its style.
local function between(prev: Segment, seg: Segment, theme: Theme): string, string
  if prev.pill then return " ", "StatusLine" end
  local c = M.config()
  local glyph = prev.section ~= seg.section and c.separators.section or c.separators.component
  if glyph == nil then glyph = paw.draw.g.sep end
  if glyph == "" then return " ", "StatusLine" end
  return " " .. glyph .. " ", theme.sep
end

local function total(segs: {Segment}, theme: Theme): integer
  local n = 0
  for i, seg in ipairs(segs) do
    n = n + width_of(seg)
    if i > 1 then n = n + api.str_width((between(segs[i - 1], seg, theme))) end
  end
  return n
end

--- Take segments from a line until both sides fit in `width`: the name
--- is cut to a few characters first, then the least needed go.
local function fit(s: Segments, width: integer, theme: Theme): Segments
  local left, right = s.left, s.right
  local function need(): integer return total(left, theme) + total(right, theme) + 2 end
  local named: Segment
  for _, seg in ipairs(right) do if seg.name then named = seg end end
  if need() > width and named then
    local piece = named[#named]
    local over = need() - width
    local keep = math.max(8, api.str_width(piece[1]) - over)
    if keep < api.str_width(piece[1]) then piece[1] = util.fit(piece[1], keep) end
  end
  while need() > width do
    local worst = -1
    local worst_list: {Segment}
    local worst_i: integer
    for _, list in ipairs({ left, right }) do
      for i, seg in ipairs(list) do
        if seg.rank > worst and seg.rank > 0 and not seg.name then worst, worst_list, worst_i = seg.rank, list, i end
      end
    end
    if not worst_list then break end
    table.remove(worst_list, worst_i)
  end
  return s
end

--- The line for `width` columns, fitted: `{ left, right }` as `segments`
--- gives them. `text` is for each side, as `{ text, style }` pieces with the
--- separators between them, ready to draw or to send to a window.
function M.line(width: integer, which?: string, extra?: Extra): Line
  local theme = theme_of(M.config().theme)
  local s = fit(M.segments(width, which, extra), width, theme)
  local function pieces(segs: {Segment}): {Piece}
    local out: {Piece} = {}
    for i, seg in ipairs(segs) do
      if i > 1 then
        local text, style = between(segs[i - 1], seg, theme)
        out[#out + 1] = { text, style }
      end
      for _, piece in ipairs(seg) do out[#out + 1] = piece end
    end
    return out
  end
  return { left = pieces(s.left), right = pieces(s.right), errors = s.errors }
end

local function pieces_width(list: {Piece}): integer
  local n = 0
  for _, piece in ipairs(list) do n = n + api.str_width(piece[1]) end
  return n
end

--- Draw the status line along the first row of `buf`.
function M.draw(buf: contracts.Buf, which?: string, y?: integer, extra?: Extra): Line
  y = y or 0
  local w = buf.width
  buf:fill(0, y, w, 1, " ", "StatusLine")
  local line = M.line(w, which, extra)
  local x = 0
  for _, piece in ipairs(line.left) do x = x + buf:text(x, y, piece[1], piece[2]) end
  x = math.max(x + 1, w - pieces_width(line.right) - 1)
  for _, piece in ipairs(line.right) do x = x + buf:text(x, y, piece[1], piece[2]) end
  return line
end

-- Other bars ---------------------------------------------------------------------------------

--- What the window with the keys (or another) adds to its title bar: the
--- text of the `winbar` (or `inactive_winbar`), or nil when there is none.
function M.winbar(view: string, focused: boolean): string
  local c = M.config()
  local which = focused and "winbar" or "inactive_winbar"
  if not (c as {string:Bar})[which] then return nil end
  local s = M.segments(1000, which, { view = view, focused = focused })
  local text: {string} = {}
  for _, side in ipairs({ s.left, s.right }) do
    for i, seg in ipairs(side) do
      if #text > 0 or i > 1 then text[#text + 1] = " " .. (c.separators.component or paw.draw.g.sep) .. " " end
      for _, piece in ipairs(seg) do text[#text + 1] = piece[1] end
    end
  end
  return #text > 0 and table.concat(text) or nil
end

--- What the tab line holds at its right end, as pieces, for `width` columns.
function M.tabline(width: integer): {Piece}
  local c = M.config()
  if not c.tabline then return {} end
  return M.line(width, "tabline").right
end

--- True if the tab line shows with one tab.
function M.tabline_always(): boolean
  local c = M.config()
  return c.tabline ~= nil and c.tabline.always == true
end

--- True if `setup` changed the line from the line that comes with paw.
function M.customized(): boolean return M.set_up == true end

--- What the window is told: the line as pieces, for the width it has.
function M.frontend(width?: integer): Line
  local line = M.line(width or 120)
  return { left = line.left, right = line.right }
end

config = fresh()
return M
