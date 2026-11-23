-- The screen: views, the tabs and windows that arrange them (laid out by
-- paw/layout.tl), focus, messages and highlight groups.
--
-- A view is a table with a `render(self, buf, ctx)` function that draws into a
-- cell buffer. Everything on screen, including the built-in arrange view and
-- status line, is a view registered through `paw.ui.view`.
--
-- A view that also paints (`paint`, see `paw.canvas`) can show its pixels
-- in a terminal that shows images: its `render` keeps an area for them
-- with `buf:surface`, or the view sets `surface = true` to be all pixels.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua. The modules
-- that draw (paw/canvas.tl, paw/roles.tl, paw/statusline.tl, paw/scene.tl)
-- name this module's types, so it declares only the parts of them that it
-- calls.
local api = require("paw.api")
local L = require("paw.layout")
local events = require("paw.events")
local derived = require("paw.derived")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local seats = require("paw.seats")
local util = require("paw.util")
local Buf = require("paw.buf")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type KeybarModule = require("paw.keybar")
local type role_props = require("paw.role_props")
local type MouseModule = require("paw.mouse")
local type commands = require("paw.commands")
local type DrawModule = require("paw.draw")

local type View = contracts.View
local type Node = L.Node
local type Tab = L.Tab
local type Arrangement = L.Arrangement
local type ScreenRect = contracts.ScreenRect
local type MouseEvent = contracts.MouseEvent
local type RenderContext = contracts.RenderContext
local type Style = string | types.CellStyle
local opt = options.opt

--- A bar along the bottom of every tab: the status line, the key line.
local record Bar
  view: string
  size: integer
  hidden: boolean
end

--- A message on the command line (`paw.ui.notify`).
local record Message
  text: string
  level: string
  time: number
end

--- What `paw.ui.titlebar` takes.
local record TitlebarOptions
  name: string | number
  pill: {string}
  context: string | number
  right: string | number
  reserve: integer
  focused: boolean
end

--- A strip a view drew in cells for a window (`render_scene`): where it
--- shows, where that is in the whole strip, and what draws it.
local record Picture
  x: integer
  y: integer
  w: integer
  h: integer
  left: integer
  top: integer
  whole_w: integer
  whole_h: integer
  draw: function(g: contracts.Painter, px: contracts.StripPixels)
end

--- What `paw.ui.strip` takes besides the area: as `buf:strip` takes, and
--- the view it is for, and `paint` for a view's whole drawing.
local record StripOptions
  key: string
  under: boolean
  draw: function(g: contracts.Painter, px: contracts.StripPixels)
  view: string
  paint: boolean
end

--- A live part of the screen: its buffer and what draws it. With a
--- `stamp`, a text of the values it is drawn from, it is drawn again only
--- when that changes (`last` is the stamp it was drawn with); a part
--- without one is drawn again on each frame of what moves.
local type Stamp = function(): string
local record LivePart
  buf: Buf
  draw: function(b: Buf)
  stamp: Stamp
  last: string
end
local record Live
  {LivePart}
  width: integer
  height: integer
end

--- A meter's values now: the levels of its two channels, the peak held,
--- and whether it clipped.
local record Meter
  levels: {number}
  hold: number
  clipped: boolean
  --- The live frame it was read for (`refreshing.frame`).
  frame: integer
end

--- The live values of now, while the live parts are drawn again.
local type Bound = {string:number | string | boolean}
local record Refreshing
  position: number
  views: {contracts.LiveValues}
  --- The number of the live frame: a meter read for another is read again.
  frame: integer
end

--- A layer of a part of a view (`paw.ui.layer`).
local type Paint<C> = function(ctx: C)
local record Layer
  name: string
  order: number
  paint: function(ctx: Bound)
end

--- What `paw.ui.input` takes (the command line's prompt, paw/views/cmdline.lua).
local record InputOptions
  prompt: string
  text: string
  history: string
  label: string
  complete: function(text: string): {string | commands.Entry}
  preview: function(text: string): string, string
  on_change: function(text: string): string, string
  anchor: function(): types.Point
  on_key: function(key: string, text: string): boolean | string
  mode: string
  ghost: string
  select: boolean
  still: boolean
end

--- What `paw.ui.ask_value` takes (paw/views/cmdline.lua).
local record AskOptions
  label: string
  now: number
  unit: string
  min: number
  max: number
  show: function(value: number): string
  parse: function(text: string): number
end

--- What `paw.ui.page` takes besides the lines (paw/views/help.lua).
local record PageOptions
  bottom: boolean
  width: integer
  height: integer
end

--- The state of each seat's screen.
local record SeatState
  focused: string
  float: contracts.Float
  grabber: function(key: string, pasted?: boolean)
  rects: Arrangement
  tabs: {Tab}
  tab: integer
  pressed: string
end

--- The key line (paw/keybar.tl): the keys of each view in each mode.
local type KeyHint = DrawModule.KeyHint
local type Keybar = KeybarModule

-- The parts of the modules above this one that it calls: they name this
-- module's types, so it cannot name theirs.
local record Roles
  begin: function(name: string, win?: integer)
  finish: function()
  pointer: function(view: View, name: string, event: MouseEvent): boolean
end
local record OpenView
  win: Node
end
local record Colors
  fg: string
  bg: string
end
local record PaintOptions
  cell: types.Size
  glyphs: boolean
  surface: boolean
  colors: Colors
  marks: {contracts.PaintMark}
end
local record Drawing
  ops: {types.CanvasOp}
end
local record Canvas
  open_views: {string:OpenView}
  inside: string
  paint: function(name: string, width: number, height: number, opts?: PaintOptions): Drawing
  draw: function(draw: function(g: contracts.Painter, px: contracts.StripPixels), px: contracts.StripPixels): {types.CanvasOp}
  close: function(name: string)
end
local record Statusline
  winbar: function(view: string, focused: boolean): string
  tabline: function(width: integer): {contracts.Piece}
  tabline_always: function(): boolean
end
local record Waker
  wake: function()
end
local record Panes
  cells: function(): types.Size
end
local record Paw is partial.Paw
  keymap: KeymapModule
  roles: Roles
  canvas: Canvas
  statusline: Statusline
  scene: Waker
  remote: Waker
  panes: Panes
  mouse: MouseModule
  draw: DrawModule
end
local paw = (_G as {string:Paw}).paw
local function keymap(): KeymapModule return paw.keymap end

--- The payloads of the events this module sends and hears.
local record ViewFocused
  view: string
  old: string
end
local record WinResized
  win: integer
end
local record OptionChanged
  name: string
end
local view_focused: events.Event<ViewFocused> = events.event("view.focused")
local win_resized: events.Event<WinResized> = events.event("win.resized")
local option_changed: events.Event<OptionChanged> = events.event("option.changed")

local record M
  type Bar = Bar
  type Message = Message
  type TitlebarOptions = TitlebarOptions
  type Picture = Picture
  type StripOptions = StripOptions
  type Layer = Layer
  type InputOptions = InputOptions
  type AskOptions = AskOptions
  type PageOptions = PageOptions
  type Keybar = Keybar
  type Buf = Buf

  --- The views, by name.
  views: {string:View}
  --- The view of the window with the keyboard.
  focused: string
  --- Every message so far, oldest first.
  messages: {Message}
  --- The one on the command line now.
  message: Message
  --- A function that takes every key while set (prompts).
  grabber: function(key: string, pasted?: boolean)
  --- The floating view, if one is open.
  float: contracts.Float
  --- Where each view was last drawn.
  rects: Arrangement
  --- The tabs, each a tree of windows, and the current one.
  tabs: {Tab}
  tab: integer
  --- The tree of the current tab.
  layout: Node
  --- The status line and the command line, along the bottom of every tab.
  bars: {Bar}
  --- The view the button held went down in.
  pressed: string
  --- The smallest screen the program draws on; below it a notice says so.
  min_width: integer
  min_height: integer
  --- Views drawn on a background of their own: the status line and the key line.
  backgrounds: {string:string}
  --- The view being drawn now, and its window.
  drawing: string
  drawing_win: Node
  --- True while the terminal's screen is drawn.
  screen: boolean
  --- With `paw.opt.check_stamps`: each window that drew other cells
  --- with the same stamp, as a message. The test suite reads it.
  stamp_misses: {string}
  --- A window of the layout that `render_view` draws, and the strips a
  --- view keeps for a scene while it is drawn (`render_scene`).
  view_win: Node
  pictures: {Picture}
  scene_drawing: boolean
  --- The layers of each part of each view: view -> part -> layers.
  layers: {string:{string:{Layer}}}
  --- The locator of each view, by the view's name (`paw.ui.locator`).
  locators: {string:contracts.Locator}
  --- Whether the terminal has the keyboard focus of the desktop.
  has_focus: boolean
  --- The layout the configuration starts with (`paw.layout.start`).
  start_layout: L.Spec

  -- What other modules put here.
  --- The key line (paw/keybar.tl).
  keybar: Keybar
  --- A role (`paw.roles.define`) and every role.
  role: function<P is contracts.MarkProps>(name: string, spec: contracts.Role<P>)
  roles: {string:contracts.Role<contracts.MarkProps>}
  --- A menu at the pointer (paw/menu.tl), and what draws it.
  menu: function(items: {contracts.MenuEntry}, opts?: contracts.MenuOptions)
  draw_menu: function(buf: Buf)
  --- The command line's list over the screen (paw/views/cmdline.lua).
  draw_popup: function(buf: Buf)
  --- Ask for a value on the command line (paw/views/cmdline.lua).
  ask_value: function(opts: AskOptions, set: function(value: number))
  --- Show lines of text in a float (paw/views/help.lua).
  page: function(title: string, lines: {string | contracts.PageLine}, opts?: PageOptions)

  redraw: function()
  arrange: function(width?: integer, height?: integer): Arrangement
  focus_next: function(step?: integer)
  render_screen: function(buf: Buf)
  focus: function(name: string)
  wake: function()
  close: function()
  draw_hints: function(buf: Buf)
end

M.views = {}
M.stamp_misses = {}
M.messages = {}
M.rects = {}
rawset(M as {string:Buf}, "Buf", Buf)

-- The tabs, each a tree of windows (see paw/layout.tl for how a tree is
-- laid out), and the current one, whose tree is `M.layout`. The status line
-- and the command line are drawn along the bottom of every tab.
M.tabs = { { layout = L.default_tree() } }
M.tab = 1
M.layout = M.tabs[1].layout
M.focused = L.windows(M.layout)[1].view
M.bars = { { view = "status", size = 1 }, { view = "cmdline", size = 1 } }

-- Each seat has its own focus, floating view, prompt, tabs and windows,
-- and the view a held button went down in; a new one starts with the tabs
-- and windows of the instance's terminal.
seats.keep("ui",
  function(): SeatState
    return { focused = M.focused, float = M.float, grabber = M.grabber, rects = M.rects, tabs = M.tabs, tab = M.tab, pressed = M.pressed }
  end,
  function(s: SeatState)
    M.focused, M.float, M.grabber, M.rects, M.pressed = s.focused, s.float, s.grabber, s.rects, s.pressed
    M.tabs, M.tab, M.layout = s.tabs, s.tab, s.tabs[s.tab].layout
  end,
  function(s: SeatState): SeatState
    local copied = L.copy_tabs(s.tabs)
    local t = copied[s.tab]
    local win = t and (t.win and L.find_id(t.layout, t.win) or L.windows(t.layout)[1])
    return { focused = win and win.view, rects = {}, tabs = copied, tab = s.tab }
  end)

--- Register a view. It replaces a view with the same name.
---   paw.ui.view("clock", { render = function(self, buf) buf:text(0, 0, os.date()) end })
--- Optional fields: `focusable` (default true), `on_key(self, key)` for keys
--- with no mapping, `modal` (each key goes to `on_key`), `on_mouse(self, event)`,
--- `on_show(self)`, `on_hide(self)`. A view is a buffer type with one
--- buffer, with the name of the view or the name from `bufname`.
---
--- `window_state` names the fields of the view's table that are each
--- window's own (the cursor, the scroll, the open clip). Then any number of
--- windows show the view, and the table holds the state of the window that
--- draws or acts (`paw.layout.bind`). `window_fresh` names the fields a
--- new window starts without, such as caches. Without `window_state`, the
--- view shows in one window at a time. `open_target(self, target)` opens
--- a thing by name in the window (`:e roll://7`), and `window_target(self)`
--- gives that name back for a saved layout. `share` says what part of the
--- room the view keeps where windows share it: `{ column, least, most }`.
---
--- With `window_instances`, each window has its own table of the
--- `window_state` fields, which takes the rest from the view
--- (`paw.ui.instance_of`), and the view draws with that table as `self`.
--- The view that `paw.ui.view` returns then reads and writes those fields
--- in the window that drew or acted last.
function M.view<V is contracts.View>(name: string, def: V): V
  def.name = name
  -- With `window_instances`, `paw.ui.views` holds a proxy of the view
  -- (paw/layout.tl: `instances`), and each window an instance.
  if def.window_state and def.window_instances then
    def = L.instances(name, def, def.window_state, def.window_fresh)
  elseif def.window_state then
    L.window_fields(name, def as {string:L.Kept}, def.window_state, def.window_fresh)
  end
  M.views[name] = def
  api.ui_redraw()
  return def
end

local function bar(name: string): Bar
  for _, node in ipairs(M.bars) do
    if node.view == name then return node end
  end
end

--- True if a view is on the screen now.
function M.visible(name: string): boolean
  if M.float and M.float.name == name then return true end
  for _, rect in ipairs(M.arrange()) do
    if rect.name == name then return true end
  end
  return false
end

local function focusable(name: string): boolean
  local view = M.views[name]
  return view and view.focusable ~= false
end

--- Show a view: in its window if it has one in this tab, else where it was
--- docked. A view has one window at a time: one on screen in another tab
--- moves here.
function M.show(name: string)
  local node = bar(name)
  if node then
    node.hidden = false
  elseif not L.reveal(name) then
    error("view `" .. name .. "` is not in the layout", 2)
  end
  api.ui_redraw()
end

--- Close the window of a view, in each tab. The view keeps its place for
--- the next time. The last window of a tab does not close: it goes on
--- showing the view, as `Ctrl-w c` leaves it.
function M.hide(name: string)
  local node = bar(name)
  if node then
    node.hidden = true
  elseif L.conceal(name) then
    local view = M.views[name]
    if view and view.on_hide then view:on_hide() end
  end
  if M.focused == name and not M.visible(name) then
    -- The keyboard goes to the window that had it before.
    if not L.back() then M.focus_next() end
  end
  api.ui_redraw()
end

--- Show the view `name` in its window, or hide it if it shows now.
function M.toggle(name: string)
  local win = L.find(M.layout, name)
  if (win and not win.hidden) or not (win or L.homes[name]) then
    -- The only window of the tab does not close, as `Ctrl-w c` does not:
    -- it goes on showing the view.
    local alone = win and focusable(name)
    for _, other in ipairs(win and L.windows(M.layout) or {}) do
      if other ~= win and focusable(other.view) then alone = false end
    end
    if alone then return paw.notify("the last window does not close: `:e <name>` shows something else in it", "warn") end
    -- A view in several windows: the one found closes.
    if win and not L.one_window(name) then
      L.close(win)
      return
    end
    return M.hide(name)
  end
  M.show(name)
  if focusable(name) then M.focus(name) end
end

--- Add a view to the layout along one side of the screen.
---   paw.ui.dock("clock", { side = "top", size = 5 })
--- `side` is "top", "bottom" (above the status line), "left" or "right" (next to
--- the arrange view). Without `size`, the view shares the space that is
--- left. To dock a view that is already in the layout moves it. Other tabs
--- put it in the same place when they show it.
function M.dock(name: string, opts?: L.DockOptions)
  L.dock(name, opts or {})
  api.ui_redraw()
end

--- Give a view the keyboard, and show it first if it is hidden. The window
--- that contains it gets the keys, and paw goes to the tab of that window.
function M.focus(name: string)
  if not M.views[name] then error("no view `" .. tostring(name) .. "`", 2) end
  local win = L.reveal(name, true)
  if win then return L.enter(win) end
  if not (M.float and M.float.name == name) then
    -- A view with no window and no place of its own (its window showed a
    -- buffer since) goes into the current window, as `:b` would: focus is
    -- never given to a view that is not drawn.
    local cur = L.current()
    if not cur then error("no window to show `" .. name .. "` in", 2) end
    L.show_in(cur, name)
    return
  end
  if M.focused ~= name then
    local old = M.focused
    M.focused = name
    events.emit(view_focused, { view = name, old = old })
  end
  api.ui_redraw()
end

--- Focus the next (or with -1 the previous) window that takes the keyboard.
function M.focus_next(step?: integer)
  local wins: {integer} = {}
  local at = 0
  local cur = L.current()
  for _, rect in ipairs(M.arrange()) do
    if rect.win and focusable(rect.name) then
      wins[#wins + 1] = rect.win
      if cur and rect.win == cur.id and cur.view == M.focused then at = #wins end
    end
  end
  if #wins == 0 then return end
  local win = L.find_id(M.layout, wins[(at - 1 + (step or 1)) % #wins + 1])
  if win then L.enter(win) end
end

-- Sizes along a node: a child with a `size` gets that many cells, the rest
-- share what is left by weight, a child below its `min` given that much and
-- the rest shared again among the others. With no child left to share, the
-- last one takes what is left.
local function shares(children: {Node}, total: integer): {integer}
  local flexible: boolean
  for _, child in ipairs(children) do
    if not child.size then flexible = true end
  end
  local grow = not flexible and children[#children]
  local function size_of(child: Node): integer return child ~= grow and child.size or nil end
  local fixed = 0
  for _, child in ipairs(children) do fixed = fixed + (size_of(child) or 0) end
  local spare = math.max(0, total - fixed)
  local sizes: {integer} = {}
  for _ = 1, #children do
    local weights: number = 0
    local left = spare
    for i, child in ipairs(children) do
      if size_of(child) then sizes[i] = size_of(child) elseif sizes[i] then left = left - sizes[i] else weights = weights + (child.weight or 1) end
    end
    local grew = false
    local weight_seen: number = 0
    for i, child in ipairs(children) do
      if not size_of(child) and not sizes[i] then
        -- Round cumulatively, so the flexible children add up to exactly what is left.
        local before = math.floor(left * weight_seen / weights)
        weight_seen = weight_seen + (child.weight or 1)
        local size = math.floor(left * weight_seen / weights) - before
        if child.min and size < child.min then
          sizes[i], grew = math.min(child.min, spare), true
          break
        end
      end
    end
    if not grew then
      weight_seen = 0
      for i, child in ipairs(children) do
        if not size_of(child) and not sizes[i] then
          local before = math.floor(left * weight_seen / weights)
          weight_seen = weight_seen + (child.weight or 1)
          sizes[i] = math.floor(left * weight_seen / weights) - before
        end
      end
      break
    end
  end
  return sizes
end

--- The share of the room that the views in a node ask for (`view.share`):
--- the largest `least` or `column` of its windows, the smallest `most`.
local function share(node: Node, key: string): number
  local out: number
  for _, win in ipairs(node.view and { node } or L.windows(node)) do
    local view = M.views[win.view]
    local v = view and view.share and (view.share as {string:number})[key]
    if v then out = out and (key == "most" and math.min(out, v) or math.max(out, v)) or v end
  end
  return out
end

-- Move `amount` cells between the children at `others`: a positive amount
-- goes to them in proportion to their sizes, a negative one is taken from
-- them in proportion to what each can spare (down to its `min`, else one).
-- Returns how many cells moved.
local function spread(children: {Node}, sizes: {integer}, others: {integer}, amount: integer): integer
  local room: {integer:integer} = {}
  local sum = 0
  for _, j in ipairs(others) do
    room[j] = amount > 0 and sizes[j] or math.max(0, sizes[j] - (children[j].min or 1))
    sum = sum + room[j]
  end
  local moved = amount > 0 and amount or math.min(-amount, sum)
  if sum == 0 or moved == 0 then return 0 end
  local seen, given = 0, 0
  for _, j in ipairs(others) do
    seen = seen + room[j]
    local upto = math.floor(moved * seen / sum)
    sizes[j] = sizes[j] + (amount > 0 and 1 or -1) * (upto - given)
    given = upto
  end
  return moved
end

-- Where views share a node, the weights and the sizes of the panels beside
-- a view can leave it a sliver. A view says what it needs in `share`:
-- `column`, the part of a column's height it keeps (taken first from the
-- panels that share by weight and then from those with a size of their
-- own, down to their `min`, else one row); `least`, the part it keeps
-- where three or more share the room; `most`, the part it takes at most
-- there. The arrange view keeps two fifths of a column and a third of the
-- room, as `Ctrl-w =` gives it, and the notation view takes at most half.
local function limit_shares(children: {Node}, sizes: {integer}, total: integer, vertical: boolean)
  local flexible: {integer} = {}
  for i, child in ipairs(children) do
    if not child.size then flexible[#flexible + 1] = i end
  end
  local function others_of(i: integer, list: {integer}): {integer}
    local out: {integer} = {}
    for _, j in ipairs(list) do
      if j ~= i then out[#out + 1] = j end
    end
    return out
  end
  if #flexible >= 3 then
    for _, i in ipairs(flexible) do
      local most = share(children[i], "most")
      local cap = most and math.floor(total * most + 1e-9)
      if cap and sizes[i] > cap then
        sizes[i] = sizes[i] - spread(children, sizes, others_of(i, flexible), sizes[i] - cap)
      end
    end
    for _, i in ipairs(flexible) do
      local least = share(children[i], "least")
      local want = least and math.floor(total * least + 1e-9)
      if want and sizes[i] < want then
        sizes[i] = sizes[i] + spread(children, sizes, others_of(i, flexible), sizes[i] - want)
      end
    end
  end
  if not vertical or #children < 2 then return end
  for i, child in ipairs(children) do
    local column = share(child, "column")
    local want = column and math.floor(total * column + 1e-9)
    if want and sizes[i] < want then
      local fixed: {integer} = {}
      for j in ipairs(children) do
        if j ~= i and children[j].size then fixed[#fixed + 1] = j end
      end
      local need = want - sizes[i]
      need = need - spread(children, sizes, others_of(i, flexible), -need)
      if need > 0 then need = need - spread(children, sizes, fixed, -need) end
      sizes[i] = want - need
    end
  end
end

local function place(node: Node, x: integer, y: integer, w: integer, h: integer, out: Arrangement, screen_w: number, after?: string)
  out.nodes[node] = { x = x, y = y, w = w, h = h }
  if node.view then
    out[#out + 1] = { name = node.view, win = node.id, x = x, y = y, w = w, h = h, after = after }
    return
  end
  local vertical = node.dir ~= "h"
  local total = vertical and h or w
  local children: {Node} = {}
  for _, child in ipairs(node) do
    if L.shown(child) then
      if child.float_below and screen_w < child.float_below and child.view then
        -- Too narrow to stand beside the others: drawn over them instead.
        out.floating[#out.floating + 1] = child
      else
        children[#children + 1] = child
      end
    end
  end
  local sizes = shares(children, total)
  limit_shares(children, sizes, total, vertical)
  local pos = 0
  for i, child in ipairs(children) do
    local size = math.max(0, math.min(sizes[i] or 0, total - pos))
    if vertical then
      if i > 1 then out.borders[#out.borders + 1] = { node = node, a = children[i - 1], b = child, dir = "v", x = x, y = y + pos, w = w } end
      -- A rule on this node's left edge is on each of its rows' too.
      place(child, x, y + pos, w, size, out, screen_w, after)
    else
      if i > 1 then out.borders[#out.borders + 1] = { node = node, a = children[i - 1], b = child, dir = "h", x = x + pos, y = y, h = h } end
      -- A view beside another has a rule along its left edge.
      place(child, x + pos, y, size, h, out, screen_w, (i > 1 or after ~= nil) and "rule" or nil)
    end
    pos = pos + size
  end
end

--- Lay a tree of windows out over a rectangle, as `arrange` lays out a
--- tab's: in whatever unit its sizes are in (a graphical frontend's pixels).
function M.place(root: Node, x: integer, y: integer, w: integer, h: integer): Arrangement
  local out: Arrangement = { nodes = {}, borders = {}, floating = {} }
  place(root, x, y, w, h, out, math.huge)
  out.floating = nil
  return out
end

--- The size of the screen in cells. This is the size of the terminal. For
--- the seat of a graphical frontend that told the size of its main area, it
--- is the size of that area (`paw.panes`). So paw measures a split there
--- on what it shows.
function M.size(): integer, integer
  local cells = paw.panes and paw.panes.cells()
  if cells then return cells.w as integer, cells.h as integer end
  return api.ui_size()
end

--- The position of each visible view on a screen of the current size: a
--- list of `{ name, win, x, y, w, h }`. The tab line is along the top when
--- there is more than one tab. `.borders` contains the borders between
--- windows, and `.nodes` the position of each node of the tree, to resize them.
function M.arrange(width?: integer, height?: integer): Arrangement
  if not width then width, height = M.size() end
  local out: Arrangement = { nodes = {}, borders = {}, floating = {} }
  local top = (#M.tabs > 1 or paw.statusline.tabline_always()) and 1 or 0
  local below = 0
  for _, node in ipairs(M.bars) do
    if not node.hidden then below = below + node.size end
  end
  local area = math.max(0, height - top - below)
  place(M.layout, 0, top, width, area, out, width)
  local y = top + area
  for _, node in ipairs(M.bars) do
    if not node.hidden then
      local h = math.max(0, math.min(node.size, height - y))
      out[#out + 1] = { name = node.view, x = 0, y = y, w = width, h = h }
      y = y + h
    end
  end
  -- Panels that float on a narrow screen sit along the right edge, over the
  -- top part of the screen.
  for _, node in ipairs(out.floating) do
    local w = math.min(node.size or 40, width - 4)
    out[#out + 1] = { name = node.view, win = node.id, x = width - w, y = top, w = w, h = math.max(1, height - top - 2), after = "box" }
  end
  out.floating = nil
  out.tabline = top > 0 and { y = 0, w = width } or nil
  return out
end

M.min_width, M.min_height = 60, 16

-- Views drawn on a background of their own: the status line and the key line.
local backgrounds: {string:string} = { status = "StatusLine", cmdline = "KeyBar" }
M.backgrounds = backgrounds

local function draw_view(view: View, buf: Buf, ctx: RenderContext)
  M.drawing = view.name
  if view.surface == true and view.paint and buf:surface(0, 0, buf.width, buf.height) then return end
  if view.paint and not view.render then
    -- A view that only paints, on a terminal that shows no pictures.
    if not buf:surface(0, 0, buf.width, buf.height) then
      buf:text(1, 0, util.fit((view.title or view.name) .. ": drawn in a graphical window, or a terminal that shows pictures", buf.width - 1), "Dim")
    end
    return
  end
  local ok, err = xpcall(view.render, debug.traceback, view, buf, ctx) as (boolean, string)
  if not ok then
    -- Show the failure where the view would have been.
    buf:fill(0, 0, buf.width, buf.height, " ", "Normal")
    local row = 0
    for line in tostring(err):gmatch("[^\n]+") do
      buf:text(0, row, (line:gsub("\t", "  ")), "Error")
      row = row + 1
    end
  end
end

--- Draw a view; the strips it kept are its own until it is done, and what
--- is drawn over them after (a menu, a float) covers them.
local function draw(view: View, buf: Buf, ctx: RenderContext)
  M.drawing_win = ctx and ctx.win as Node
  -- The view draws with the state of its window.
  if ctx and ctx.win then L.bind(ctx.win as Node) end
  -- The hit regions it marks on the screen are where the pointer finds them.
  if M.screen then paw.roles.begin(view.name, ctx and ctx.win and ctx.win.id) end
  -- A view with instances draws with the instance of its window as `self`.
  local own = ctx and ctx.win and L.instance_of(ctx.win as Node)
  draw_view(own and own as View or view, buf, ctx)
  paw.roles.finish()
  M.drawing_win = nil
  if M.rects.surfaces then api.grid_surfaces_seal() end
end

local function float_rect(width: integer, height: integer): ScreenRect
  local f = M.float
  local w = math.min(f.width or 72, width - 2)
  local h = math.min(f.height or 24, height - 2)
  -- `top`: at the top of the screen, leaving what is below it in view.
  local y = f.top and 1 or math.floor((height - h) / 2)
  return { name = f.name, x = math.floor((width - w) / 2), y = y, w = w, h = h }
end

--- Draw a box around a buffer's edge and return a buffer for the inside.
function M.box(buf: contracts.Buf, title?: string, style?: string): contracts.Buf
  local w, h = buf.width, buf.height
  style = style or "Border"
  local g = paw.draw.g
  buf:fill(0, 0, w, h, " ", "Normal")
  buf:text(0, 0, g.tl .. string.rep(g.h, w - 2) .. g.tr, style)
  for row = 1, h - 2 do
    buf:text(0, row, g.v, style)
    buf:text(w - 1, row, g.v, style)
  end
  buf:text(0, h - 1, g.bl .. string.rep(g.h, w - 2) .. g.br, style)
  if title then buf:text(2, 0, " " .. title .. " ", "Title") end
  return buf:sub(1, 1, w - 2, h - 2)
end

--- Draw a title bar of one row along the top of a docked panel, and return
--- a buffer for the rest of it. `opts`: `name`, `pill` (`{ text, group }`,
--- before the name), `context` (after the name), `right` (state, at the
--- right end), `reserve` (columns to keep free at the right end, for the
--- view's own items), `focused`. When the panel has focus, the whole bar is
--- in the accent color, inverted.
---   local body = paw.ui.titlebar(buf, { name = "Mixer", context = "5 tracks", focused = ctx.focused })
function M.titlebar(buf: contracts.Buf, opts: TitlebarOptions): contracts.Buf
  local g = paw.draw.g
  local focused = opts.focused
  local plain = focused and "TitleBarFocus" or "TitleBar"
  buf:fill(0, 0, buf.width, 1, " ", plain)
  buf:text(0, 0, g.mark, focused and "TitleBarMarkFocus" or "TitleBarMark")
  local x = 2
  local right = opts.right and tostring(opts.right) or ""
  -- What the winbar (`paw.statusline`) adds, at the end of the state.
  local winbar = paw.statusline and M.drawing and paw.statusline.winbar(M.drawing, focused)
  if winbar then right = right ~= "" and (winbar .. "  " .. right) or winbar end
  -- Columns kept free at the right end for what the view puts there (its
  -- tools), left of which `right` goes.
  local reserve = opts.reserve or 0
  local right_w = api.str_width(right) + reserve
  if opts.pill then
    -- A coloured label ahead of the name, such as a clip in its track's colour.
    x = x + buf:text(x, 0, " " .. tostring(opts.pill[1]) .. " ", opts.pill[2]) + 1
  end
  if opts.name then
    local room = math.max(1, buf.width - x - (right_w > 0 and right_w + 2 or 0))
    local name = tostring(opts.name)
    if api.str_width(name) > room then name = util.fit(name, room) end
    x = x + buf:text(x, 0, name, focused and "TitleBarNameFocus" or "TitleBarName")
  end
  if opts.context and opts.context ~= "" then
    local room = buf.width - x - 2 - (right_w > 0 and right_w + 2 or 0)
    if room >= 4 then
      local text = tostring(opts.context)
      if api.str_width(text) > room then text = util.fit(text, room) end
      x = x + 2 + buf:text(x + 2, 0, text, plain)
    end
  end
  if right ~= "" and buf.width - right_w - 1 > x then buf:text(buf.width - right_w - 1, 0, right, focused and "TitleBarFocus" or "TitleBarFaint") end
  return buf:sub(0, 1, buf.width, buf.height - 1)
end

--- What is shown on a screen too small to draw on: the status line, the
--- command line, and in the middle how big the screen is and needs to be.
local function too_small(buf: Buf)
  local w, h = buf.width, buf.height
  local g = paw.draw.g
  local lines = {
    "Terminal too small: " .. w .. (g.ellipsis == "…" and "×" or "x") .. h,
    "needs " .. M.min_width .. (g.ellipsis == "…" and "×" or "x") .. M.min_height,
  }
  local top = math.max(0, math.floor((h - 2 - #lines) / 2))
  for i, line in ipairs(lines) do
    local x = math.max(0, math.floor((w - api.str_width(line)) / 2))
    buf:text(x, top + i - 1, line, i == 1 and "TooSmallTitle" or "TooSmall")
  end
  M.rects = {}
  for i, name in ipairs({ "status", "cmdline" }) do
    local y = h - 3 + i
    local view = M.views[name]
    if view and y >= 0 then
      M.rects[#M.rects + 1] = { name = name, x = 0, y = y, w = w, h = 1 }
      buf:fill(0, y, w, 1, " ", backgrounds[name])
      draw(view, buf:sub(0, y, w, 1), { focused = false, x = 0, y = y })
    end
  end
end

--- Keep an area of a buffer for pixels: see `Buf:strip`. Where it is kept
--- is in `paw.ui.rects.surfaces`: `{ key, name, win, x, y, w, h, cell = {
--- w, h }, under, draw, paint }` each, in cells of the screen (`name` the
--- view that kept it, `win` the id of its window, `paint` for a view's
--- whole drawing, `buf:surface`).
function M.strip(buf: Buf, x: number, y: number, w: number, h: number, opts?: StripOptions): boolean
  opts = opts or {}
  if opt.graphics == false then return false end
  if not M.screen then
    -- A view drawn in cells for a window (`M.render_scene`,
    -- `paw.canvas.paint_cells`): the window draws the strip's picture with
    -- the cells, under their text.
    if not (M.pictures and opts.draw and opts.under) then return false end
    local px, py, pw, ph = math.floor(buf.x + x), math.floor(buf.y + y), math.floor(w), math.floor(h)
    local x0, y0 = math.max(px, buf.cx), math.max(py, buf.cy)
    local x1, y1 = math.min(px + pw, buf.cx + buf.cw), math.min(py + ph, buf.cy + buf.ch)
    if x1 <= x0 or y1 <= y0 then return false end
    M.pictures[#M.pictures + 1] = { x = x0, y = y0, w = x1 - x0, h = y1 - y0, left = x0 - px, top = y0 - py,
      whole_w = pw, whole_h = ph, draw = opts.draw }
    return true
  end
  local caps = api.ui_caps()
  if not caps.pixels or (opts.under and not caps.under) then return false end
  local name = opts.view or M.drawing
  local win = M.drawing_win
  local key = opts.key or (tostring(name) .. "#" .. tostring(win and win.id or "float"))
  local sx, sy, sw, sh = math.floor(buf.x + x), math.floor(buf.y + y), math.floor(w), math.floor(h)
  if opts.paint then
    -- A view's paint lays out what shows of it.
    local x0, y0 = math.max(sx, buf.cx), math.max(sy, buf.cy)
    sx, sy, sw, sh = x0, y0, math.min(sx + sw, buf.cx + buf.cw) - x0, math.min(sy + sh, buf.cy + buf.ch) - y0
  end
  local index = api.grid_surface(key, sx, sy, sw, sh, buf.cx, buf.cy, buf.cw, buf.ch, opts.under == true)
  if not index then return false end
  -- What shows of it inside the buffer.
  local x0, y0 = math.max(sx, buf.cx), math.max(sy, buf.cy)
  local x1, y1 = math.min(sx + sw, buf.cx + buf.cw), math.min(sy + sh, buf.cy + buf.ch)
  M.rects.surfaces = M.rects.surfaces or {}
  table.insert(M.rects.surfaces, {
    key = key, name = name, win = win and win.id, index = index, x = x0, y = y0, w = x1 - x0, h = y1 - y0,
    left = x0 - sx, top = y0 - sy, whole_w = sw, whole_h = sh,
    cell = caps.cell, under = opts.under == true, draw = opts.draw, paint = opts.paint,
  })
  return true
end

--- Keep an area of a buffer for a view's pixels: see `Buf:surface`. A
--- strip, kept for the view's window, whose drawing is the view's `paint`.
function M.surface(buf: Buf, x: number, y: number, w: number, h: number, name?: string): boolean
  name = name or M.drawing
  local view = M.views[name]
  if not (view and view.paint) then return false end
  return M.strip(buf, x, y, w, h, { view = name, paint = true })
end

--- Paint what the views kept strips for, once the screen is drawn.
local function paint_surfaces()
  local caps = api.ui_caps()
  for _, s in ipairs(M.rects.surfaces or {}) do
    local cw, ch = s.cell.w, s.cell.h
    local w, h = s.w * cw, s.h * ch
    local ops: {types.CanvasOp}
    if s.draw then
      -- The whole strip, of which `view` shows: a strip partly off its
      -- window draws what shows and a piece's width either side of it.
      ops = paw.canvas.draw(s.draw, {
        w = s.whole_w * cw, h = s.whole_h * ch, cell = s.cell as contracts.StripPixels.Cell, fg = caps.fg, bg = caps.bg,
        view = { x = s.left * cw, y = s.top * ch, w = w, h = h },
      })
    else
      local drawing = paw.canvas.paint(s.name, w, h, {
        surface = true, glyphs = true, cell = s.cell, colors = { fg = caps.fg, bg = caps.bg },
      })
      ops = drawing and drawing.ops
    end
    api.grid_surface_ops(s.index, ops or {})
  end
end

-- Live parts: what moves on its own as the song plays (the playhead, the
-- meters, the status line's clock), on the terminal's screen. The kernel
-- keeps the frame drawn last and what was under each live part. Between
-- whole frames, `render_live` draws only these parts again, with the
-- values of now, and the kernel sends the cells that changed. A view says
-- that it draws all that moves in it as live parts with `view.live_roles`
-- (the roles of its marks bound to live values, as for a window), or that
-- nothing in it moves on its own with `view.still`.
local live: Live           -- the live parts of the seat's screen: `{ buf, draw }` each
local recording: Live      -- the list that the screen being drawn fills, or nil
local refreshing: Refreshing     -- the live values of now, while the parts are drawn again
-- The one table of live values, and the meters read, a table each for as
-- long as paw runs: a live frame makes no new ones.
local now_values: Refreshing = { frame = 0 }
local meters: {integer:Meter} = {}
-- The transport of the frame being drawn (`M.transport`).
local frame_transport: types.Transport

-- Windows kept whole. A view with `stamp(self, ctx)` gives a text of all
-- that its drawing reads. The screen keeps the cells of each window of
-- the view under that text. On a later whole frame, a window that does
-- not have the keyboard and has the same text gets its cells back, and
-- the view does not draw it (the design architecture-review-lua.md, L2).
-- The kernel forgets kept cells when a highlight group changes.
--
-- The live parts that the window drew (the playhead, the meters) come
-- back too: for each, the cells under it and the cells that it drew are
-- kept, so that a live frame can draw it again over the right cells.

--- A live part that a kept window drew: the part, the stamp of the values
--- that it drew, and the key that its cells are kept under.
local record KeptPart
  part: LivePart
  last: string
  key: string
end

--- A window as the screen kept it: its key, the text of its stamp, its
--- live parts, and with `paw.opt.check_stamps` what its drawing wrote.
local record KeptWindow
  key: string
  stamp: string
  parts: {KeptPart}
  calls: {string}
end

-- The kept windows, by their key (`window_key`).
local kept_windows: {string:KeptWindow} = {}
-- The window being drawn to keep, while it is drawn, else nil.
local keeping: KeptWindow
-- With `paw.opt.check_stamps`, while a kept window is drawn: what its
-- drawing writes, a text for each call (`checked_text`). Nil else.
local check_calls: {string}
seats.keep("ui.live", function(): Live return live end, function(l: Live) live = l end, function(): Live return nil end)

--- True if a live part drawn now is one of the terminal's screen.
function M.live_drawing(): boolean
  return recording ~= nil
end

--- The transport as `paw.api.transport_get` gives it. While a frame is
--- drawn, the one read first in that frame: the status line, the ruler
--- and the views read it once between them.
function M.transport(): types.Transport
  if not M.screen then return api.transport_get() end
  if not frame_transport then frame_transport = api.transport_get() end
  return frame_transport
end

-- Draw a live part: `part`, kept from the frame before, or a new one
-- with its `stamp` and the text `last` that it gave.
local function live_part(part: LivePart, buf: Buf, draw_part: function(b: Buf), stamp?: Stamp, last?: string)
  -- A window that is kept keeps the cells under each of its live parts.
  local kept_as: string = nil
  if keeping then
    kept_as = keeping.key .. ":" .. (#keeping.parts + 1)
    api.grid_keep(kept_as .. ":under", buf.x, buf.y, buf.width, buf.height, buf.cx, buf.cy, buf.cw, buf.ch)
  end
  local index = api.grid_live_begin(buf.x, buf.y, buf.width, buf.height, buf.cx, buf.cy, buf.cw, buf.ch)
  local was, was_calls = recording, check_calls
  recording, check_calls = nil, nil  -- what it draws inside is part of it, and moves
  local ok, result = pcall(draw_part, buf) as (boolean, string)
  recording, check_calls = was, was_calls
  if index then
    api.grid_live_end(index)
    local drawn = part or { buf = buf, draw = draw_part, stamp = stamp, last = last }
    recording[#recording + 1] = drawn
    if kept_as then
      -- And the cells that it drew.
      api.grid_keep(kept_as .. ":drawn", buf.x, buf.y, buf.width, buf.height, buf.cx, buf.cy, buf.cw, buf.ch)
      keeping.parts[#keeping.parts + 1] = { part = drawn, last = drawn.last, key = kept_as }
    end
  end
  if not ok then error(result, 0) end
end

--- Draw a live part on `buf`: `draw(buf)` draws it, now and each time it
--- is drawn again by itself. With `stamp`, a function that gives a text of
--- the values the part is drawn from (nil: unknown), the part is drawn
--- again only when that text changes; its cells stay as they were drawn.
function M.live(buf: Buf, draw_part: function(b: Buf), stamp?: Stamp)
  if not recording then return draw_part(buf) end
  local last: string = nil
  if stamp then
    -- What it is drawn from, read before it is drawn, so that a value that
    -- moves on while it is drawn shows on the next frame.
    local fine, got = pcall(stamp) as (boolean, string)
    last = fine and got or nil
  end
  live_part(nil, buf, draw_part, stamp, last)
end

-- Kept windows: the stamps -------------------------------------------------

--- What every window's drawing can read, read once for a whole frame: the
--- events sent so far (an edit, an option, the mode, the cursor of the
--- arrange view, a chord read again), the edits of the project, and the
--- transport.
local function frame_stamp(): string
  local t = M.transport()
  return table.concat({
    events.emitted(),
    (api.project_get as function(string): integer)("edits"),
    tostring(t.playing),
    tostring(t.recording),
    t.take or "",
    t.position,
    tostring(t.loop_enabled),
    t.loop_start,
    t.loop_end,
    tostring(t.punch_enabled),
    t.punch_start,
    t.punch_end,
  }, " ")
end

--- The stamp of a window: the view's own `stamp`, with what the screen
--- gives it (its place, its background, its winbar) and `frame` (the
--- `frame_stamp`). Nil when the window is drawn whatever it shows: its view
--- has no stamp, the window has the keyboard, or the screen is not the
--- terminal's.
local function window_stamp(view: View, area: Buf, ctx: RenderContext, background: string, frame: string): string
  if not (view.stamp and recording) or ctx.focused then return nil end
  if ctx.win then L.bind(ctx.win as Node) end
  -- A view with instances gives the stamp of the window's instance.
  local mine = ctx.win and L.instance_of(ctx.win as Node)
  local ok, own = pcall(view.stamp, mine and mine as View or view, ctx) as (boolean, string)
  if not ok or own == nil then return nil end
  local winbar = paw.statusline and paw.statusline.winbar(view.name, false)
  return table.concat({own, frame, area.x, area.y, area.width, area.height, background or "", winbar or ""}, "\n")
end

--- The key that the screen keeps a window under: by its seat and its
--- window, or by its view for a bar (the status line).
local function window_key(win: Node, name: string): string
  return "window:" .. seats.current .. ":" .. (win and tostring(win.id) or name)
end

--- Put back the cells of the kept window `kept` and its live parts, in
--- `area`. False when the kernel no longer has them, and nothing changed.
local function put_window(kept: KeptWindow, area: Buf): boolean
  if not area:put_kept(kept.key, 0, 0, area.width, area.height) then return false end
  for _, k in ipairs(kept.parts) do
    -- The kernel takes the part again as it took it when it was drawn:
    -- what was under it, then what it drew.
    local b = k.part.buf
    api.grid_put(k.key .. ":under", b.x, b.y, b.width, b.height, b.cx, b.cy, b.cw, b.ch)
    local index = api.grid_live_begin(b.x, b.y, b.width, b.height, b.cx, b.cy, b.cw, b.ch)
    api.grid_put(k.key .. ":drawn", b.x, b.y, b.width, b.height, b.cx, b.cy, b.cw, b.ch)
    if index then
      api.grid_live_end(index)
      -- A live frame since then drew it with other values.
      k.part.last = k.last
      recording[#recording + 1] = k.part
    end
  end
  -- What the window drew over its live parts.
  area:put_kept(kept.key, 0, 0, area.width, area.height)
  return true
end

-- Kept windows: the check ---------------------------------------------------

-- The functions of a buffer that write cells, as paw/buf.tl has them.
local buf_text, buf_fill, buf_put_kept = Buf.text, Buf.fill, Buf.put_kept

--- A style as a text, for `check_calls`.
local function style_text(style: Style): string
  if not style is types.CellStyle then return tostring(style) end
  local fields: {string} = {}
  for k, v in pairs(style as {string:string | number | boolean}) do fields[#fields + 1] = k .. "=" .. tostring(v) end
  table.sort(fields)
  return table.concat(fields, ",")
end

--- The functions of a buffer while a kept window is drawn and checked:
--- they list what they write in `check_calls`, and no kept cells come back.
local function checked_text(self: Buf, x: number, y: number, text: string, style?: Style): integer
  local calls = check_calls
  if calls then
    calls[#calls + 1] = table.concat({"text", self.x + x, self.y + y, self.cx, self.cy, self.cw, self.ch, text, style_text(style)}, " ")
  end
  return buf_text(self, x, y, text, style)
end
local function checked_fill(self: Buf, x: number, y: number, w: number, h: number, char?: string, style?: Style)
  local calls = check_calls
  if calls then
    calls[#calls + 1] = table.concat({"fill", self.x + x, self.y + y, w, h, self.cx, self.cy, self.cw, self.ch, char or "", style_text(style)}, " ")
  end
  buf_fill(self, x, y, w, h, char, style)
end
local function checked_put_kept(self: Buf, key: string, x: number, y: number, w: number, h: number): boolean
  if check_calls then return false end
  return buf_put_kept(self, key, x, y, w, h)
end

--- With `paw.opt.check_stamps`, around the drawing of a kept window:
--- from `check_begin` to `check_end`, what the buffers write is listed.
local function check_begin()
  check_calls = {}
  Buf.text, Buf.fill, Buf.put_kept = checked_text, checked_fill, checked_put_kept
end

--- The list of what the buffers wrote since `check_begin`.
local function check_end(): {string}
  Buf.text, Buf.fill, Buf.put_kept = buf_text, buf_fill, buf_put_kept
  local calls = check_calls
  check_calls = nil
  return calls
end

--- With `paw.opt.check_stamps`: note when the window of `name` wrote
--- `now` with the stamp that it wrote `before` with. Its stamp misses
--- something that its drawing reads.
local function check_same(name: string, before: {string}, now: {string})
  for i = 1, math.max(#before, #now) do
    if before[i] ~= now[i] then
      local miss = string.format(
        "paw.opt.check_stamps: the view %s drew other cells with the same stamp: %s, before %s",
        name, now[i] or "nothing", before[i] or "nothing"
      )
      M.stamp_misses[#M.stamp_misses + 1] = miss
      api.log(miss)
      return
    end
  end
end

-- Kept windows: the drawing -------------------------------------------------

--- Draw a window of the layout: `view` in `area`, on `background`. A
--- window with a stamp (`window_stamp`) is kept, and put back when its
--- stamp is the same as when it was kept. `frame` is the `frame_stamp`.
local function draw_window(view: View, area: Buf, ctx: RenderContext, background: string, frame: string)
  local stamp = window_stamp(view, area, ctx, background, frame)
  local key = stamp and window_key(ctx.win as Node, view.name)
  local was = key and kept_windows[key]
  local same = was and was.stamp == stamp
  local check = opt.check_stamps == true
  if same and not check and put_window(was, area) then return end
  if background then area:fill(0, 0, area.width, area.height, " ", background) end
  if not stamp then return draw(view, area, ctx) end
  local surfaces = M.rects.surfaces and #M.rects.surfaces or 0
  local now: KeptWindow = {key = key, stamp = stamp, parts = {}}
  keeping = now
  if check then check_begin() end
  local ok, err = pcall(draw, view, area, ctx) as (boolean, string)
  if check then now.calls = check_end() end
  keeping = nil
  if not ok then error(err, 0) end
  -- Pixels are drawn after the cells: a window with some is drawn again.
  if (M.rects.surfaces and #M.rects.surfaces or 0) > surfaces then
    kept_windows[key] = nil
    return
  end
  area:keep(key, 0, 0, area.width, area.height)
  kept_windows[key] = now
  if same and was.calls and now.calls then check_same(view.name, was.calls, now.calls) end
end

local function meter_of(values: Refreshing, id: integer): Meter
  local m = meters[id]
  if not m then
    m = { levels = { 0, 0 } }
    meters[id] = m
  end
  if m.frame ~= values.frame then
    local l, r, hold, clipped = paw.draw.track_peak(id)
    m.levels[1], m.levels[2], m.hold, m.clipped, m.frame = l, r, hold, clipped, values.frame
  end
  return m
end

-- The position of the playhead in a live frame: read once, without the
-- transport's table.
local function live_position(values: Refreshing): number
  if not values.position then
    local _, at = api.transport_playhead()
    values.position = at
  end
  return values.position
end

--- A text of the live value `bind` now (`position` or `meter:<id>`), to
--- tell whether a part bound to it changed: nil for any other value.
function M.live_stamp(bind: string): string
  if bind == "position" then
    return tostring(refreshing and live_position(refreshing) or M.transport().position)
  elseif bind:sub(1, 6) == "meter:" then
    local id = (tonumber(bind:sub(7)) or 0) as integer
    local l, r, hold, clipped: number, number, number, boolean
    if refreshing then
      local m = meter_of(refreshing, id)
      l, r, hold, clipped = m.levels[1], m.levels[2], m.hold, m.clipped
    else
      l, r, hold, clipped = paw.draw.track_peak(id)
    end
    return tostring(l) .. " " .. tostring(r) .. " " .. tostring(hold) .. (clipped and "!" or "")
  end
  return nil
end

--- While a live part is drawn again: set the props of a mark bound to
--- `bind` (`position`, `meter:<id>`, or a value that a view's
--- `live_values()` gives) to the values of now.
function M.live_value(bind: string, props: contracts.MarkProps)
  local values = refreshing
  if not values then return end
  local set = props as Bound
  if bind == "position" then
    set.at = live_position(values)
  elseif bind:sub(1, 6) == "meter:" then
    local m = meter_of(values, (tonumber(bind:sub(7)) or 0) as integer)
    local p = props as {string:{number} | number | boolean}
    p.levels, p.hold, p.clipped = m.levels, m.hold, m.clipped
  else
    if not values.views then
      values.views = {}
      for _, view in pairs(M.views) do
        if type(view.live_values) == "function" then
          local ok, got = pcall(view.live_values) as (boolean, contracts.LiveValues)
          if ok and type(got) == "table" then values.views[#values.views + 1] = got end
        end
      end
    end
    for _, got in ipairs(values.views) do
      for _, group in pairs(got) do
        local v = type(group) == "table" and group[bind] or nil
        if type(v) == "table" then
          for k, x in pairs(v) do set[k] = x end
          return
        end
      end
    end
  end
end

--- Whether the screen can be drawn by its live parts only: each view on
--- it says what moves in it (`view.live_roles`) or that nothing does
--- (`view.still`), and none must be drawn whole now (`view:moving()`).
-- Asked on each frame of what moves: the windows bound to another
-- window's state by `fits`, to put back when there are any.
local rebound = false

local function fits(name: string, win?: Node): boolean
  local view = M.views[name]
  if not view then return true end
  if not (view.live_roles or view.still or view.live_part) then return false end
  if view.moving then
    if win and L.bound(name) ~= win then
      L.bind(win)
      rebound = true
    end
    local moving = view:moving()
    if moving then return false end
  end
  return true
end

local function only_live(): boolean
  rebound = false
  local result = true
  for _, r in ipairs(M.rects) do
    local view = M.views[r.name]
    -- The window is looked for only when its view asks `moving`.
    local win = r.win and view and view.moving and L.find_id(M.layout, r.win) or nil
    if not fits(r.name, win) then
      result = false
      break
    end
  end
  result = result and not (M.float and not fits(M.float.name))
  if rebound then L.settle() end
  return result
end

-- What `M.live` lists while the live parts are drawn again: the screen
-- keeps its list of them, so this one is emptied and used each time.
local spare_live: Live = {}

-- What each live part is drawn from now, by its place, while the live
-- parts are drawn again: one table for all frames.
local live_stamps: {string} = {}

-- Draw the parts of `parts` again, listed in `into`. A part whose stamp
-- did not change keeps its cells, unless a part before it changed what is
-- under it (then the kernel says no).
local function redraw_live(parts: Live, into: Live)
  api.grid_live_restore()
  for i = #into, 1, -1 do into[i] = nil end
  recording = into
  for i, part in ipairs(parts) do
    local now = live_stamps[i]
    if now ~= nil and now == part.last and api.grid_live_keep(i) then
      into[#into + 1] = part
    else
      -- The list of parts stays the one of the whole frame: it keeps what
      -- each was drawn from last.
      part.last = now
      live_part(part, part.buf, part.draw)
    end
  end
end

--- Draw the live parts of the screen again, on the frame drawn last.
--- Called by the kernel (`paw.api.ui_redraw_live`). False when the screen
--- must be drawn whole instead.
function M.render_live(buf: Buf): boolean
  if not (live and live.width == buf.width and live.height == buf.height) then return false end
  -- The views say whether they move with the transport of this frame.
  M.screen, frame_transport = true, nil
  if not only_live() then
    M.screen, frame_transport = false, nil
    return false
  end
  now_values.frame, now_values.position, now_values.views = now_values.frame + 1, nil, nil
  refreshing = now_values
  local parts, into = live, spare_live
  -- What each part is drawn from now: when none changed, the frame stays.
  local changed = false
  for i, part in ipairs(parts) do
    local now: string = nil
    if part.stamp then
      local fine, got = pcall(part.stamp) as (boolean, string)
      now = fine and got or nil
    end
    live_stamps[i] = now
    changed = changed or now == nil or now ~= part.last
  end
  if not changed then
    refreshing, M.screen, frame_transport = nil, false, nil
    api.grid_live_still()
    return true
  end
  local ok, err = pcall(redraw_live, parts, into) as (boolean, string)
  -- A part of a view with a state for each window bound that window's.
  L.settle()
  recording, refreshing, M.screen, frame_transport = nil, nil, false, nil
  api.grid_live_seal()
  if not ok then
    live = nil
    error(err, 0)
  end
  return true
end

--- Draw the whole screen. Called by the kernel.
function M.render(buf: Buf)
  M.screen, frame_transport = true, nil
  recording = {}
  derived.frame_start()
  local ok, err = pcall(M.render_screen, buf) as (boolean, string)
  derived.frame_end()
  live, recording = recording, nil
  live.width, live.height = buf.width, buf.height
  api.grid_live_seal()
  M.screen, frame_transport = false, nil
  if not ok then
    live = nil
    error(err, 0)
  end
  M.wake()
end

--- Draw the whole screen into `buf`: the tab's windows, floats, the status
--- and command lines.
function M.render_screen(buf: Buf)
  buf:fill(0, 0, buf.width, buf.height, " ", "Normal")
  api.ui_mouse(opt.mouse ~= false)
  if buf.width < M.min_width or buf.height < M.min_height then return too_small(buf) end
  local sizes_before = M.rects.sizes or {}
  M.rects = M.arrange(buf.width, buf.height)
  local g = paw.draw.g
  local current = L.current()
  -- A time bound window with the keyboard is drawn first, and the other
  -- time bound windows take its time before they are drawn.
  local lead, followers = L.time_lead()
  local order: {ScreenRect} = {}
  for i, r in ipairs(M.rects) do order[i] = r end
  for i, r in ipairs(order) do
    if lead and r.win == lead.id and r.after ~= "box" then
      table.insert(order, 1, table.remove(order, i))
      break
    end
  end
  local sizes: {integer:string} = {}
  local resized: {integer} = {}
  local frame = frame_stamp()
  for _, r in ipairs(order) do
    local view = M.views[r.name]
    if view and r.w > 0 and r.h > 0 then
      local win = r.win and L.find_id(M.layout, r.win)
      local focused = M.focused == r.name and (not win or win == current)
      local area = buf:sub(r.x, r.y, r.w, r.h)
      if r.after == "rule" and r.w > 1 then
        -- A rule between this view and the one on its left.
        area:fill(0, 0, 1, r.h, g.rule, "Rule")
        r.x, r.w = r.x + 1, r.w - 1
        area = buf:sub(r.x, r.y, r.w, r.h)
      elseif r.after == "box" and r.w > 2 and r.h > 2 then
        area = M.box(area, nil, focused and "BorderFocus" or "Border") as Buf
        r.x, r.y, r.w, r.h = r.x + 1, r.y + 1, r.w - 2, r.h - 2
      end
      local follower = win and followers and followers[win.id]
      if follower then L.time_follow(lead, win) end
      local ctx: RenderContext = { focused = focused, x = r.x, y = r.y, win = win, follower = follower or nil }
      local background = backgrounds[r.name]
      if win and (r.w < L.min_width or r.h < (focusable(r.name) and 2 or 1)) then
        if background then area:fill(0, 0, r.w, r.h, " ", background) end
        area:text(0, 0, util.fit("too small", r.w), "TooSmall")
      elseif view.live_part then
        -- All of it moves (the status line's clock): a live part.
        M.live(area, function(b: Buf)
          if background then b:fill(0, 0, b.width, b.height, " ", background) end
          draw(view, b, ctx)
        end, view.live_stamp and function(): string return view:live_stamp(area.width) end)
      else
        draw_window(view, area, ctx, background, frame)
      end
      if win then
        sizes[win.id] = r.w .. "x" .. r.h
        if sizes_before[win.id] and sizes_before[win.id] ~= sizes[win.id] then resized[#resized + 1] = win.id end
      end
    end
  end
  M.rects.sizes = sizes
  L.settle()
  if #resized > 0 then
    paw.defer(function()
      for _, id in ipairs(resized) do events.emit(win_resized, { win = id }) end
    end)
  end
  if M.rects.tabline then
    -- The tabs along the top, the current one bright. Its sections may
    -- show what moves, as the status line's do: a live part.
    local tabline = M.rects.tabline
    M.live(buf:sub(0, 0, buf.width, 1), function(line: Buf)
      line:fill(0, 0, line.width, 1, " ", "TitleBar")
      local x = 0
      local spans: {L.Span} = {}
      for i, t in ipairs(M.tabs) do
        local mine = i == M.tab
        local used = line:text(x, 0, (mine and g.mark or " ") .. i .. " " .. L.tab_title(t) .. " ", mine and "TitleBarNameFocus" or "TitleBarName")
        spans[i] = { x = x, w = used }
        x = x + used + 1
      end
      tabline.spans = spans
      -- What the tab line's own sections hold goes at the right end.
      local right = paw.statusline.tabline(line.width)
      local used = 0
      for _, piece in ipairs(right) do used = used + api.str_width(piece[1]) end
      local at = line.width - used - 1
      if used > 0 and at > x then
        for _, piece in ipairs(right) do at = at + line:text(at, 0, piece[1], piece[2]) end
      end
    end)
  end
  if M.float and M.views[M.float.name] then
    local r = float_rect(buf.width, buf.height)
    local outer = buf:sub(r.x, r.y, r.w, r.h)
    local inner = M.box(outer, M.float.title, "BorderFocus") as Buf
    r.x, r.y, r.w, r.h = r.x + 1, r.y + 1, r.w - 2, r.h - 2
    M.rects[#M.rects + 1] = r
    draw(M.views[r.name], inner, { focused = true, x = r.x, y = r.y })
    -- The float's keys along its bottom border, as on the key line.
    local entries: {KeyHint} = {}
    if M.keybar and M.keybar.lines[r.name] then entries = M.keybar.entries() end
    if #entries > 0 and r.w > 12 then
      local footer = outer:sub(2, r.h + 1, r.w - 2, 1)
      local used = paw.draw.keys(footer, 1, 0, entries, r.w - 4, "FloatFooter")
      if used > 0 then
        footer:text(0, 0, " ", "FloatFooter")
        footer:text(used + 1, 0, " ", "FloatFooter")
      end
    end
  end
  M.draw_hints(buf)
  if M.draw_popup then M.draw_popup(buf) end
  if M.draw_menu then M.draw_menu(buf) end
  paint_surfaces()
end

--- Draw one view alone on a buffer of its own. A window of a graphical
--- frontend shows the result (see `paw.canvas.open_view`). A pane of its
--- main area also shows a window of the layout this way (`M.view_win`,
--- while paw draws it). Braille shows there as dots (`paw.canvas`),
--- because the font has no braille.
function M.render_view(name: string, buf: Buf)
  M.screen = false
  local view = M.views[name]
  buf:fill(0, 0, buf.width, buf.height, " ", backgrounds[name] or "Normal")
  if not view then return end
  local win = M.view_win
  local focused = M.focused == name
  local own = paw.canvas.open_views[name]
  if win and own and own.win == win then
    -- The view in a window of its own.
    focused = focused and paw.canvas.inside == name
  elseif win then
    focused = focused and win == L.current() and not (own and paw.canvas.inside == name)
  end
  draw(view, buf, { focused = focused, x = 0, y = 0, win = win })
end

--- Draw one view alone as a scene for a graphical frontend (see
--- crates/paw-scene). The scene is `w` by `h` units (fractions are
--- permitted). `cell` is the cell `{ w, h }` of the frontend in pixels, and
--- `win` is the window of the layout that it shows in, if any.
---
--- The text that `render_view` writes in whole cells becomes the runs and
--- fills of the scene. The strips that the view keeps under them become its
--- pictures. A view that paints is one picture of the whole area. The kernel
--- keeps the scene, and `paw.api.scene_end` tells what changed in it.
function M.render_scene(name: string, w: number, h: number, cell: types.Size, win?: Node)
  local view = M.views[name]
  api.scene_begin(w, h)
  if view and view.paint then
    local px = { w * cell.w, h * cell.h }
    if win then L.bind(win) end
    -- What the view marks over its picture (`ctx.marks`): roles that the
    -- frontend paints, such as a playhead that the live values move.
    local marks: {contracts.PaintMark} = {}
    local ok, drawing = pcall(paw.canvas.paint, name, px[1], px[2], { cell = cell, glyphs = true, marks = marks }) as (boolean, Drawing)
    L.settle()
    if not ok then error(drawing, 0) end
    api.scene_picture({ x = 0, y = 0, w = w, h = h }, { ops = drawing and drawing.ops or {}, px = px })
    for i, m in ipairs(marks) do
      local r: types.Rect = { x = m.x / cell.w, y = m.y / cell.h, w = m.w / cell.w, h = m.h / cell.h }
      local props: {string:Bound} = {}
      for k, v in pairs((m.props or {}) as {string:Bound}) do
        if k ~= "bind" then props[k] = v end
      end
      if api.scene_open(r, { role = m.role, props = props as role_props.Props, bind = m.props and m.props.bind, key = "mark:" .. i }) then api.scene_close() end
    end
    return
  end
  -- The roles it marks are nodes of the scene (paw/roles.tl).
  M.view_win, M.pictures, M.scene_drawing = win, {}, true
  local ok, err = pcall(api.scene_draw, name, math.floor(w), math.floor(h)) as (boolean, string)
  local pictures = M.pictures
  M.view_win, M.pictures, M.scene_drawing = nil, nil, nil
  L.settle()
  if not ok then error(err, 0) end
  for _, p in ipairs(pictures) do
    -- The whole strip, cut to the part that shows.
    local px: contracts.StripPixels = { w = p.whole_w * cell.w, h = p.whole_h * cell.h, cell = { w = cell.w, h = cell.h },
      view = { x = p.left * cell.w, y = p.top * cell.h, w = p.w * cell.w, h = p.h * cell.h } }
    api.scene_picture({ x = p.x - p.left, y = p.y - p.top, w = p.whole_w, h = p.whole_h }, {
      ops = paw.canvas.draw(p.draw, px), px = { px.w, px.h }, under = true,
      clip = { x = p.x, y = p.y, w = p.w, h = p.h },
    })
  end
end

--- List the keys that can follow a half-typed command, in a box along the
--- bottom of the screen.
function M.draw_hints(buf: Buf)
  if not opt.hints then return end
  local hints, title = keymap().hints()
  if not hints then return end
  local width = 0
  for _, hint in ipairs(hints) do width = math.max(width, api.str_width(hint.key) + api.str_width(hint.desc) + 4) end
  width = math.min(width, buf.width - 2)
  local columns = math.max(1, math.floor((buf.width - 2) / width))
  local rows = math.min(math.ceil(#hints / columns), buf.height - 6)
  if rows < 1 then return end
  local inner = M.box(buf:sub(0, buf.height - 2 - rows - 2, buf.width, rows + 2), title, "BorderFocus")
  for i, hint in ipairs(hints) do
    local col, row = math.floor((i - 1) / rows), (i - 1) % rows
    if col < columns then
      local x = col * width
      local used = inner:text(x + 1, row, hint.key, "HintKey")
      inner:text(x + 2 + used, row, util.fit(hint.desc, math.max(1, width - used - 3)), "Normal")
    end
  end
end

--- Open a view in a float over the other views. It takes the keyboard
--- until `paw.ui.close()`.
---   paw.ui.open("help", { title = "Keys", width = 80, height = 30 })
function M.open(name: string, opts?: contracts.FloatOptions)
  if not M.views[name] then error("no view `" .. tostring(name) .. "`", 2) end
  opts = opts or {}
  M.float = { name = name, title = opts.title, width = opts.width, height = opts.height, top = opts.top, back = M.float and M.float.back or M.focused }
  M.focused = name
  api.ui_redraw()
end

--- Close the float that has the keys, or the window of a view.
function M.close()
  if not M.float then
    -- A view drawn in a window of its own (`paw.canvas.open_view`) closes
    -- with it, as it would have closed floating.
    if paw.canvas.open_views[M.focused] then paw.canvas.close(M.focused) end
    return
  end
  M.focused = M.float.back
  M.float = nil
  api.ui_redraw()
end

--- A copy of an event with other fields laid over it.
local function merged(event: MouseEvent, extra: MouseEvent): MouseEvent
  local out: MouseEvent = {}
  for k, v in pairs(event as {string:Bound}) do (out as {string:Bound})[k] = v end
  for k, v in pairs(extra as {string:Bound}) do (out as {string:Bound})[k] = v end
  return out
end

--- A border between two windows held from a press: it follows the pointer.
local function hold_border(event: MouseEvent, border: L.Border, only_moved?: boolean)
  paw.mouse.grab(merged(event, { view_x = 0, view_y = 0 }), {
    drag = function(d: MouseEvent) L.drag_border(border, M.rects, d.x, d.y) end,
    up = function(u: MouseEvent)
      if u.moved or not only_moved then L.drag_border(border, M.rects, u.x, u.y) end
    end,
  })
end

local function route(event: MouseEvent)
  local tabline = M.rects.tabline
  if tabline and event.y == tabline.y and not M.float then
    -- A click on a tab goes to it.
    for i, span in ipairs(tabline.spans or {}) do
      if event.kind == "down" and event.x >= span.x and event.x < span.x + span.w then L.tab_go(i) end
    end
    return
  end
  local target: ScreenRect
  for _, r in ipairs(M.rects) do
    if event.x >= r.x and event.x < r.x + r.w and event.y >= r.y and event.y < r.y + r.h then target = r end
  end
  -- The rule between two windows side by side is a border to drag; so is
  -- the top row of a window below another, which the window hears first.
  local border = event.kind == "down" and not M.float and L.border_at(M.rects, event.x, event.y)
  if border and (border.dir == "h" or not target) then return hold_border(event, border) end
  -- A drag and its release belong to the view the button went down in,
  -- wherever the pointer has gone since.
  if event.kind == "down" then
    M.pressed = target and target.name
  elseif (event.kind == "drag" or event.kind == "up") and M.pressed then
    for _, r in ipairs(M.rects) do
      if r.name == M.pressed then target = r end
    end
    if event.kind == "up" then M.pressed = nil end
  end
  if M.float and (not target or target.name ~= M.float.name) then
    if event.kind == "down" then M.close() end
    return
  end
  if not target then return end
  local view = M.views[target.name]
  if not view then return end
  if event.kind == "down" and focusable(target.name) and not M.float then
    local win = target.win and L.find_id(M.layout, target.win)
    if win then L.enter(win) else M.focus(target.name) end
  end
  -- The view takes the pointer with the state of the window under it.
  local under = target.win and L.find_id(M.layout, target.win)
  if under then L.bind(under) end
  if paw.mouse.to_surface(target, event) then return end
  local e = merged(event, {
    x = event.x - target.x, y = event.y - target.y, view_x = target.x, view_y = target.y, w = target.w, h = target.h,
    win = target.win,
  })
  -- A hit region the view marked has it first (paw/roles.tl).
  if paw.roles.pointer(view, target.name, e) then return end
  if view.on_mouse then view:on_mouse(e) end
  -- A press on a window's top row that the window did not hold drags the
  -- border above it.
  if border and not paw.mouse.gesture() then hold_border(event, border, true) end
end

--- Send a mouse event to the view under the pointer, with coordinates
--- relative to that view (and `view_x`, `view_y`, `w`, `h`, the position of
--- the view). First, the floats over the views and a gesture in progress
--- get it (`paw.mouse`).
function M.mouse(event: MouseEvent)
  if paw.mouse.take(event) then return end
  route(event)
  paw.mouse.done(event)
  L.settle()
end

-- The timer that takes the message shown off the screen, while one is due:
-- one for any number of messages, so that a flood of them stays cheap.
local clearing: integer

local function clear_later(ms: number)
  clearing = paw.defer(function()
    clearing = nil
    local message = M.message
    if not message then return end
    local left = message.time + opt.message_time - api.now()
    if left > 0 then return clear_later(left) end
    M.message = nil
    api.ui_redraw()
  end, ms)
end

--- Show a message. `level` is "info" (default), "warn" or "error".
function M.notify(text: string, level?: string)
  -- What the kernel refused, as it said it, without the prefix its errors
  -- carry through Lua.
  text, level = (tostring(text):gsub("runtime error: ", "")), level or "info"
  local message: Message = { text = text, level = level, time = api.now() }
  M.messages[#M.messages + 1] = message
  if #M.messages > 500 then table.remove(M.messages, 1) end
  api.log(string.format("[%s] %s", level, text))
  -- Without a terminal the message also goes to stderr; a graphical
  -- frontend shows `M.message` like the command line does.
  if not api.ui_attached() then io.stderr:write(text, "\n") end
  M.message = message
  if not clearing then clear_later(opt.message_time) end
  api.ui_redraw()
end

-- Every group as it was defined, so that the colours can be made again for
-- a terminal that shows fewer of them (`paw.opt.termcolors`).
local defined: {string:Style} = {}
local set_raw = api.hl_set
local truecolor: boolean = nil

local function set(name: string, def: Style)
  defined[name] = def
  if truecolor == nil then truecolor = paw.draw.truecolor() end
  -- A window draws the group as defined, whatever the terminal shows.
  local shown = paw.draw.term_def(def, truecolor)
  set_raw(name, shown, shown ~= def and def or nil)
end
-- Groups set straight through the kernel's call get the same treatment.
api.hl_set = set

--- Define a highlight group: a table of `fg`, `bg`, `bold`, `dim`, `italic`,
--- `underline`, `reverse`, `strike`, or the name of a group to follow.
--- Colors are `#rrggbb`, or a number for one of the 256 colors of the
--- terminal. On a terminal without 24-bit color, each `#rrggbb` shows as
--- the nearest of the 256.
function M.hl(name: string, def: string | types.CellStyle)
  set(name, def)
end

--- Define many highlight groups at once.
function M.theme(groups: {string:string | types.CellStyle})
  for name, def in pairs(groups) do set(name, def) end
end

--- Set each group again. Call it after `paw.opt.termcolors` changes.
function M.recolour()
  truecolor = paw.draw.truecolor()
  for name, def in pairs(defined) do set(name, def) end
  api.ui_redraw()
end

events.on(option_changed, function(event: OptionChanged)
  if event.name == "termcolors" then M.recolour() end
  if event.name == "ascii" then paw.draw.use_glyphs() end
end)

--- Ask for a line of text on the command line.
---   paw.ui.input({ prompt = "Name: ", text = "Bass" }, function(text) ... end)
--- paw does not call the callback when the user cancels the prompt. The
--- options are those of the command line (`paw.views.cmdline.open`):
--- `complete`, `history`, `on_change` (live preview), `anchor` (draw it
--- next to its subject), `on_key`, `still` (the preview asks for a whole
--- frame itself when it changes another view).
function M.input(opts: InputOptions, on_submit: function(text: string))
  local record Cmdline
    open: function(opts: InputOptions, on_submit: function(text: string))
  end
  (require as function(string): Cmdline)("paw.views.cmdline").open(opts, on_submit)
end

M.redraw = api.ui_redraw

-- Layers and locators ----------------------------------------------------------
--
-- What modules draw over a view (diagnostics, annotations, a suggestion),
-- each a layer of a part of it, drawn in order; and how a view says where
-- things with an address are (paw/address.tl). The piano roll has layers
-- of its own (`paw.ui.views.pianoroll.layer`).

M.layers = {}  -- view -> part -> { { name, order, paint } }

--- Draw `paint(ctx)` as a layer of a part of a view (`"arrange", "header"`).
--- It replaces a layer with the same name (nil removes it). The view tells
--- what `ctx` contains where it calls `paw.ui.paint`.
function M.layer<C>(view: string, part: string, name: string, order: number, paint?: Paint<C>)
  M.layers[view] = M.layers[view] or {}
  local list = M.layers[view][part] or {}
  for i = #list, 1, -1 do
    if list[i].name == name then table.remove(list, i) end
  end
  if paint then list[#list + 1] = { name = name, order = order, paint = paint as function(ctx: Bound) } end
  table.sort(list, function(a: Layer, b: Layer): boolean return a.order < b.order end)
  M.layers[view][part] = list
  api.ui_redraw()
end

--- Draw the layers of a part of a view: views call this where the part is drawn.
function M.paint<C>(view: string, part: string, ctx: C)
  local list = M.layers[view] and M.layers[view][part]
  if not list then return end
  for _, layer in ipairs(list) do layer.paint(ctx as Bound) end
end

M.locators = {}

--- Say how a view places locations (`{ uri, selector }`):
---   at()            the location under its cursor, or nil
---   position()      where its cursor is, as a list of numbers to sort by
---   place(location) where a location is in it, the same way, or nil when it does not show it
---   go(location)    put its cursor there
function M.locator(view: string, spec: contracts.Locator) M.locators[view] = spec end

--- The state of a view for one window (a view with `window_instances`):
--- a table with the fields of `window_state` that takes the rest from the
--- view. Nil for another view.
function M.instance_of(win: contracts.Window): View
  return L.instance_of(win as Node) as View
end

--- The state of a view in its window with the keyboard, else in the
--- window that had it last, else in any window of the view. With no window,
--- the view itself (its proxy). Nil for a view without `window_instances`.
function M.instance(name: string): View
  local view = M.views[name]
  if not (view and view.window_instances) then return nil end
  local win = L.find(M.layout, name)
  return win and M.instance_of(win) or view
end

--- The location under the cursor of the focused view (or `view`). With
--- `win`, the cursor of that window: each window of a view has its own.
function M.location(view?: string, win?: Node): contracts.Location
  local loc = M.locators[view or M.focused]
  if not loc then return nil end
  if win then return L.within(win, loc.at) end
  return loc.at()
end

--- Go to a location in the view that shows it best, and focus that view.
--- The piano roll shows notes, the device panel shows devices and
--- parameters, and the arrange view shows tracks and time.
function M.go(location: contracts.Location)
  for _, name in ipairs({ "pianoroll", "devices", "arrange", "mixer" }) do
    local loc = M.locators[name]
    -- A window of the view that shows the place already has it first.
    for _, win in ipairs(loc and L.windows(M.layout) or {}) do
      if win.view == name and L.within(win, function(): {number} return loc.place(location) end) then
        L.enter(win)
        return loc.go(location)
      end
    end
    if loc and loc.place(location, true) then
      if not M.visible(name) then M.show(name) end
      M.focus(name)
      return loc.go(location)
    end
  end
end

-- Meters and the playhead move without anything changing in the project.
-- While the song plays, and for a moment after any activity, the live
-- parts of the screen are drawn again at most `paw.opt.fps` times a second,
-- and the kernel sends only the cells that changed: no frame when nothing
-- did. No timer runs while nothing moves: the song starting, a note played
-- (`poke`) or any frame wakes it again.
local active_until: number = 0
-- The timer of the next frame, while one waits.
local ticker: integer

--- How many milliseconds at least go between two frames while something
--- moves: 1000 / `paw.opt.fps`, as the option is now.
function M.frame_ms(): number
  return 1000 / opt.fps
end

-- True while a track listens to its audio input (armed or monitored): its
-- meters, the master's and a tuner on it move with the input, also while
-- the song is stopped. Counted again when a track changes, not per frame.
local listening = false

-- `track_get` with a key reads one field, without the clips of the track.
local field = api.track_get as function(integer, string): any

local function count_listening()
  listening = false
  for _, id in ipairs(api.track_list({all = true})) do
    local input = field(id, "input") as string
    if input and input ~= "" and (field(id, "armed") as boolean or field(id, "monitor") as boolean) then
      listening = true
      return
    end
  end
end

--- True if something moves on its own now: the song plays, a track listens
--- to its input, or a moment after activity (`poke`), while meters fall.
function M.active(): boolean
  -- Asked on each frame: the playing flag alone, without the transport's table.
  local playing = api.transport_playhead()
  return playing or listening or api.now() < active_until
end

local function moving(): boolean
  return api.ui_attached() and M.active()
end

-- True if only a poke keeps the frames going: the song does not play or
-- count in, and no track listens to its input.
local function only_poked(): boolean
  local playing, _, counting = api.transport_playhead()
  return not playing and (counting or 0) == 0 and not listening
end

-- Frames in a row that changed no cell: the ticker slows down after `still_ticks`
-- of them (a listening track with a silent input), and a poke ends. A poke
-- and any changed frame start the count again.
local still_ticks = 20
local slow_ms = 125
local still = 0
local last_frames: types.FrameCounts = nil

-- True if frames were drawn since the last tick and none changed a cell.
local function frames_unchanged(): boolean
  local f = api.ui_frames()
  local before = last_frames
  last_frames = f
  if not before then return false end
  local drawn = f.live - before.live
  return f.full == before.full and drawn > 0 and f.unchanged - before.unchanged == drawn
end

local function tick()
  ticker = nil
  -- A played note keeps the frames going until the meters it lit are at
  -- rest, also past the time of its poke.
  if api.now() + M.frame_ms() >= active_until and api.ui_attached() and only_poked() and paw.draw.meters_falling() then
    active_until = api.now() + 2 * M.frame_ms()
  end
  if not moving() then return end
  if frames_unchanged() then still = still + 1 else still = 0 end
  if still >= still_ticks and only_poked() then
    -- Only a poke keeps it live, and the meters are at rest.
    active_until = 0
    still = 0
    return
  end
  api.ui_redraw_live()
  local wait = M.frame_ms()
  if still >= still_ticks then wait = math.max(wait, slow_ms) end
  ticker = paw.defer(tick, wait)
end

--- Start the frames of what moves, unless they run: nothing happens when
--- nothing moves.
function M.wake()
  if ticker or not moving() then return end
  ticker = paw.defer(tick, M.frame_ms())
end

--- Keep the screen animated for some time, for example after paw plays a note.
function M.poke(ms?: number)
  active_until = math.max(active_until, api.now() + (ms or 1500))
  still = 0
  M.wake()
  -- And what graphical frontends are sent.
  if paw.scene and paw.scene.wake then paw.scene.wake() end
  if paw.remote and paw.remote.wake then paw.remote.wake() end
end

--- Draw what moves while the song plays: from when it starts.
function M.start_ticker()
  events.on(kernel.transport_play, function() M.wake() end)
  -- The meters fall for a moment after the song stops.
  events.on(kernel.transport_stop, function() M.poke(1500) end)
  -- Arming or monitoring an input starts the frames; the last one off ends them.
  local function recount()
    count_listening()
    M.poke()
  end
  events.on(kernel.track_changed, recount)
  events.on(kernel.track_added, recount)
  events.on(kernel.track_removed, recount)
  events.on(kernel.project_loaded, recount)
  count_listening()
  M.wake()
end

return M
