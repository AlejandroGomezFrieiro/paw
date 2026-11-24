-- Windows, buffers and tabs, after Neovim's. docs/reference/windows.md says how they
-- are used, docs/reference/lua-views.md how to write a buffer type.
--
-- A buffer is something to show and edit; its type says how. A window is a
-- rectangle of the screen showing one buffer. A tab holds a tree of
-- windows: a node stacks its children in rows (`dir = "v"`) or columns
-- (`dir = "h"`); a child with a `size` gets exactly that many cells, the
-- rest share what is left by `weight` (default 1), each given at least its
-- `min` while there is room. The status line and the command line are not
-- windows: they stay along the bottom of every tab.
--
-- A window (a leaf of the tree) has `id`, `view` (its buffer's type), `buf`
-- (the buffer's number, for a type that has more than one), `opts` (window
-- options: `timebind`) and `state` (what the type keeps for this window).
-- A `hidden` window takes no room: a panel's window keeps its place while it
-- is closed, so that it comes back there. One with `float_below = n` is drawn
-- over the others, along the right edge, on screens narrower than `n`.
--
-- Every view registered with `paw.ui.view` is a buffer type with a single
-- buffer, shown in one window at a time: showing it in another window moves
-- it there. Types made with `paw.buftype` have a buffer for each target, and
-- any number of windows can show one.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua. This module
-- owns the records of the tree, the tabs and the arrangement of the screen
-- (paw/ui.tl lays them out), so paw/ui.tl and the modules above it name
-- them; it declares only the parts of those modules that it calls.
local api = require("paw.api")
local registry = require("paw.registry")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local seats = require("paw.seats")
local command_registry = require("paw.command")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type objects = require("paw.objects")

local type View = contracts.View
local type Buftype = contracts.Buftype
local type Buffer = contracts.LayoutBuffer
local type KeyContext = contracts.KeyContext
local type Region = contracts.Region
local type RenderContext = contracts.RenderContext
local type Context = command_registry.Context
local type Result = command_registry.Result
local opt = options.opt

--- Which way a split stacks its children: `v` in rows, `h` in columns.
local enum Dir
  "v"
  "h"
end

--- What a view keeps for a window (`window_keep`): this module passes it
--- from the view to the window and back, and never reads it.
local record Kept
end

--- The state of one window of a view with instances (`window_instances`):
--- the fields of the view's `window_state`. The rest comes from the view's
--- table through `__index`.
local type Instance = {string: Kept}

--- What a window showed before (`Ctrl-^`).
local record Alt
  view: string
  buf: integer
end

--- A node of a tab's tree: a split, which stacks its children, or a
--- window (a leaf, with `view`). A window has the fields of
--- `contracts.Window`; `kept` is its views' state while another window
--- has it, `alt` what it showed before, `pending` what its view opens in it
--- once it is in a tab (`import`).
local record Node is {Node}, contracts.Window
  dir: Dir
  size: integer
  weight: number
  min: integer
  float_below: integer
  kept: {Kept}
  instances: {string: Instance}
  alt: Alt
  pending: string
end

--- A tab: its tree, its name, the window with the keyboard (`win`), the
--- one before (`prev`), the window of each view that had it last, and what
--- `Ctrl-w |` hid.
local record Zoom
  win: integer
  hidden: {integer: boolean}
  size: integer
end
local record Tab
  name: string
  layout: Node
  win: integer
  prev: integer
  last: {string: integer}
  zoom: Zoom
end

--- Where a docked view goes when no window has it.
local record Home
  side: string
  size: integer
  weight: number
  min: integer
  float_below: integer
end

--- What `dock` takes.
local record DockOptions
  side: string
  size: integer
  weight: number
  min: integer
  hidden: boolean
end

--- The fields `leaf` gives a new window besides its view.
local record LeafFields
  buf: integer
  size: integer
  weight: number
  min: integer
  float_below: integer
  hidden: boolean
  opts: {string: string | number | boolean}
end

--- How a view keeps a state for each window: `get` gives it, `set` puts
--- it back, `fresh` gives what a new window starts with.
local record Keeper
  key: string
  get: function(): Kept
  set: function(Kept)
  fresh: function(Kept): Kept
end

--- A border between two windows of an arrangement: the node whose
--- children they are, the two sides, `h` for a rule between windows side
--- by side (`x`, `y` and its height `h`) or `v` for the top row of a window
--- below another (`x`, `y` and its width `w`).
local record Border
  node: Node
  a: Node
  b: Node
  dir: Dir
  x: integer
  y: integer
  w: integer
  h: integer
end

--- Where a node of the tree was laid out.
local record Place
  x: integer
  y: integer
  w: integer
  h: integer
end

--- A tab of the tab line: where it is drawn.
local record Span
  x: integer
  w: integer
end
local record Tabline
  y: integer
  w: integer
  spans: {Span}
end

--- An area a view keeps for pixels (`buf:strip`, `buf:surface`), in cells
--- of the screen: the view that kept it (`name`), its window, its index in
--- the kernel's grid, the part that shows (`x`, `y`, `w`, `h`), where that
--- is in the whole strip (`left`, `top`, `whole_w`, `whole_h`), the cell in
--- pixels, and what draws it: `draw`, or the view's `paint`.
local record Surface
  key: string
  name: string
  win: integer
  index: integer
  x: integer
  y: integer
  w: integer
  h: integer
  left: integer
  top: integer
  whole_w: integer
  whole_h: integer
  cell: types.Size
  under: boolean
  draw: function(g: contracts.Painter, px: contracts.StripPixels)
  paint: boolean
end

--- Where each view is on a screen (`paw.ui.arrange`, `paw.ui.place`): a
--- list of `contracts.ScreenRect`, with the borders between windows, the
--- place of each node of the tree, the tab line, and once drawn the size
--- of each window (`sizes`) and the areas kept for pixels (`surfaces`).
local record Arrangement is {contracts.ScreenRect}
  nodes: {Node: Place}
  borders: {Border}
  floating: {Node}
  tabline: Tabline
  sizes: {integer: string}
  surfaces: {Surface}
end

--- A layout as a configuration writes it, or as `capture` gives it: a
--- view's name (`"roll"`), a window (`{ view = "roll", size = 20 }`), a
--- split (`{ dir = "h", "arrange", "roll" }`, or with `children`), a tab
--- (`{ name, layout, current }`), a list of tabs, or `{ tab, tabs }`.
local record SpecNode is {string | SpecNode}
  view: string
  target: string
  size: integer
  weight: number
  min: integer
  float_below: integer
  hidden: boolean
  opts: {string: string | number | boolean}
  dir: string
  children: {string | SpecNode}
  name: string
  layout: string | SpecNode
  current: integer
  tab: integer
  tabs: {SpecNode}
  scope: {types.SavedScope}
  folds: {types.SavedFold}
  foldlevel: integer
  vzoom: types.SavedVZoom
end
local type Spec = string | SpecNode

--- What `split` takes.
local record SplitOptions
  vertical: boolean
  view: string
  buf: integer
  target: string
  win: Node
end

--- What `drag_border` takes: a frontend's cell in pixels, and its
--- arrangement's nodes to the nodes of the tree.
local record DragOptions
  unit: types.Size
  map: {Node: Node}
end

--- A window and the number of its tab.
local record TabWindow
  win: Node
  tab: integer
end

--- What the keymap's functions of a type get, and give.
local type KeyFn = function(ctx?: KeyContext, region?: Region): Region
local type Wrap = function(fn: KeyFn): KeyFn

-- The parts of paw/ui.tl and of paw/canvas.tl that this module calls:
-- those modules name this one's records, so this one cannot name theirs.
local record Ui
  views: registry.Registry<View>
  tabs: {Tab}
  tab: integer
  layout: Node
  focused: string
  float: contracts.Float
  start_layout: Spec
  arrange: function(width?: integer, height?: integer): Arrangement
  close: function()
  focus: function(name: string)
  page: function(title: string, lines: {string | contracts.PageLine})
end
local record OpenView
  win: Node
end
local record Canvas
  open_views: {string: OpenView}
  inside: string
end
--- The options of a key mapping, and its modes (paw/keymap.tl).
local type MapOptions = KeymapModule.MapOptions
local type Mode = KeymapModule.Mode
--- What a window's scope is (paw/scope.tl, which names this module's types).
local record Scopes
  current: function(win?: contracts.Window): contracts.Scope
end
local record Paw is partial.Paw
  keymap: KeymapModule
  ui: Ui
  canvas: Canvas
  scope: Scopes
  clip: function(id: integer): objects.Clip
  project: objects.Project
  time: objects.Time
end
local paw = (_G as {string: Paw}).paw

-- Lua 5.1's function that Teal's library leaves out.
local record Lua51
  unpack: function<T>({T}, ?integer, ?integer): T...
end
local unpack = (_G as Lua51).unpack

--- The payloads of the events this module sends.
local record WinEvent
  win: integer
end
local record BufEvent
  buf: integer
  name: string
end
local record ViewFocused
  view: string
  old: string
end
local record TabEvent
  tab: integer
end
local record WinOption
  win: integer
  name: string
  value: string | number | boolean
end
local record SeatOpened
  seat: integer
end

local win_leave: events.Event<WinEvent> = events.event("win.leave")
local win_enter: events.Event<WinEvent> = events.event("win.enter")
local buf_leave: events.Event<BufEvent> = events.event("buf.leave")
local buf_enter: events.Event<BufEvent> = events.event("buf.enter")
local view_focused: events.Event<ViewFocused> = events.event("view.focused")
local tab_enter: events.Event<TabEvent> = events.event("tab.enter")
local win_option: events.Event<WinOption> = events.event("win.option")
local project_saving: events.Event<kernel.Nothing> = events.event("project.saving")
local seat_opened: events.Event<SeatOpened> = events.event("seat.opened")

local record M
  type Dir = Dir
  type Kept = Kept
  type Node = Node
  type Tab = Tab
  type Home = Home
  type DockOptions = DockOptions
  type LeafFields = LeafFields
  type Keeper = Keeper
  type Border = Border
  type Place = Place
  type Tabline = Tabline
  type Span = Span
  type Surface = Surface
  type Arrangement = Arrangement
  type Spec = Spec
  type SpecNode = SpecNode
  type SplitOptions = SplitOptions
  type DragOptions = DragOptions
  type TabWindow = TabWindow
  type KeyFn = KeyFn
  type Wrap = Wrap

  --- Buffer types made with `paw.buftype`, by name, with the extension that
  --- made each one.
  types: registry.Registry<Buftype>
  --- Every buffer, by number.
  buffers: {integer: Buffer}
  --- Where a docked view goes when no window has it.
  homes: {string: Home}
  --- Short names for the buffers of built-in views, to type after `:vs`.
  names: {string: string}
  --- What a docked view's pane is called, where the view has no title of its own.
  pane_titles: {string: string}
  --- What the built-in views are called in lists.
  titles: {string: string}
  --- The smallest window a split leaves, and the smallest that is drawn.
  min_width: integer
  min_height: integer
  --- How each view keeps a state for each window.
  keepers: {string: {Keeper}}
  --- Layouts a configuration names, by name: `paw.layouts.edit = { ... }`.
  layouts: {string: Spec}

  record Bufs
    list: function(): {Buffer}
    get: function(name: string | integer): Buffer
    create: function(type_name: string, target?: string): Buffer
    delete: function(name: string | integer)
    current: function(): Buffer
    of: function(win: Node): Buffer
    title: function(buf: Buffer): string
  end
  record Wins
    current: function(): Node
    list: function(): {Node}
    get: function(id: integer): Node, integer
    enter: function(win: Node)
    split: function(opts: SplitOptions): Node, string
    close: function(win?: Node): boolean
    only: function(win?: Node)
    show: function(win: Node, name: string | integer): Node
    resize: function(win: Node, axis: string, n: integer, relative?: boolean): boolean
    equalize: function()
    maximize: function(): boolean
    option: function(win: Node, name: string, value?: string | number | boolean): string | number | boolean
    buf: function(win: Node): Buffer
  end
  record Tabs
    list: function(): {Tab}
    current: function(): integer
    new: function(name?: string, buffer?: string): Tab
    go: function(i: integer): boolean
    close: function(i?: integer): boolean
    move: function(i: integer, to: integer): boolean
    title: function(t: Tab): string
  end
  --- `paw.buf`: buffers.
  buf: Bufs
  --- `paw.win`: windows.
  win: Wins
  --- `paw.tab`: tabs.
  tabs: Tabs

  shown: function(node: Node): boolean
  parent_of: function(node: Node, target: Node): Node, integer
  tab: function(): Tab
  focusable_windows: function(): {Node}
  export: function(node: Node, scopes?: boolean): SpecNode
  import: function(spec: Spec): Node
  get: function(id: integer): Node, integer
  find_id: function(root: Node, id: integer): Node
  find: function(root: Node, name: string, on_screen?: boolean): Node
  view_named: function(name: string): string
  title: function(buf: Buffer): string
  all_windows: function(): {TabWindow}
  close: function(win?: Node): boolean
  show_in: function(win: Node, name: string, buf?: integer, target?: string): Node
  current: function(): Node
  powers: function(scope: string, def: contracts.Powers, wrap?: Wrap)
  tab_go: function(i: integer): boolean
  tab_close: function(i?: integer): boolean
  tab_new: function(name?: string, view?: string, win?: Node, buf?: integer, target?: string): Tab
  set_size: function(node: Node, axis: string, size: integer)
  load: function(name: string): boolean, string
end

M.types = registry.new("buftypes", "buffer types")
M.buffers = {}
M.homes = {}
M.names = {pianoroll = "roll"}
M.pane_titles = {
  arrange = "Arrange",
  pianoroll = "Piano roll",
  mixer = "Mixer",
  devices = "Devices",
}
M.titles = {
  arrange = "the arrange view",
  pianoroll = "the piano roll",
  mixer = "the mixer",
  devices = "the device panel",
  eventlist = "the event list",
  help = "keys",
  empty = "an empty window",
}
local by_view: {string: Buffer} = {} -- view name -> its buffer
local next_win, next_buf = 0, 0

M.min_width, M.min_height = 10, 3

local function ui(): Ui
  return paw.ui
end

local function focusable(name: string): boolean
  local view = ui().views:get(name)
  return view ~= nil and view.focusable ~= false
end

local function copy<T>(value: T): T
  return seats.copy(value)
end

--- A window's folds as plain data, or from it: a copy, for a window of
--- its own (a split keeps the folds of the window it comes from, as Vim's
--- windows do).
local function copy_folds(folds: {contracts.Fold}): {contracts.Fold}
  if not folds then
    return nil
  end
  local out: {contracts.Fold} = {}
  for i, f in ipairs(folds) do
    out[i] = {
      kind = f.kind as contracts.ScopeKind,
      id = f.id,
      tracks = f.tracks and copy(f.tracks),
      from = f.from,
      to = f.to,
      name = f.name,
      closed = f.closed,
    }
  end
  return out
end

--- A new window that shows `view`, with fields such as `size` or `hidden`.
function M.leaf(view: string, fields?: LeafFields): Node
  next_win = next_win + 1
  local win: Node = {view = view, id = next_win, opts = {}, state = {}}
  for k, v in pairs((fields or {}) as {string: Kept}) do
    (win as {string: Kept})[k] = v
  end
  return win
end

--- The tree that paw starts with when the configuration names no start
--- layout (`paw.ui.start_layout`): the arrange view, and the panels' places
--- next to it, closed. Nothing else depends on it: any view can be alone
--- in a tab.
function M.default_tree(): Node
  return {
    dir = "v",
    {dir = "h", M.leaf("arrange"), M.leaf("devices", {size = 40, hidden = true, float_below = 80})},
    M.leaf("pianoroll", {hidden = true, weight = 2}),
    M.leaf("mixer", {weight = 0.5, min = 14, hidden = true}),
  }
end

M.homes.devices = {side = "right", size = 40, float_below = 80}
M.homes.pianoroll = {side = "bottom", weight = 2}
M.homes.mixer = {side = "bottom", weight = 0.5, min = 14}

-- The tree ----------------------------------------------------------------------

--- True if a node takes space: a window that is not hidden, or a node with such a window.
local function shown(node: Node): boolean
  if node.hidden then
    return false
  end
  if node.view then
    return true
  end
  for _, child in ipairs(node) do
    if shown(child) then
      return true
    end
  end
  return false
end
M.shown = shown

--- The windows of a tree in order, the hidden ones too with `all`. A window
--- made by code that only gave it a view gets what a window has.
function M.windows(root?: Node, all?: boolean): {Node}
  local out: {Node} = {}
  local function walk(node: Node)
    if node.view then
      if not node.id then
        next_win = next_win + 1
        node.id, node.opts, node.state = next_win, node.opts or {}, node.state or {}
      end
      if all or not node.hidden then
        out[#out + 1] = node
      end
      return
    end
    for _, child in ipairs(node) do
      walk(child)
    end
  end
  walk(root or ui().layout)
  return out
end

--- The split that contains `target` in the tree under `node`, and its place there.
local function parent_of(node: Node, target: Node): Node, integer
  for i, child in ipairs(node) do
    if child == target then
      return node, i
    end
    if not child.view then
      local parent, at = parent_of(child, target)
      if parent then
        return parent, at
      end
    end
  end
end
M.parent_of = parent_of

-- Views with a state for each window ---------------------------------------------
--
-- A view keeps its state in its own table (`self.clip_id`), as it always
-- did. A view that names that state (`window_state` in `paw.ui.view`, or
-- `M.window_keep`) is shown by any number of windows, each with a state of
-- its own: before the view draws in a window, or a key, the pointer or a
-- command acts in one, paw puts the state of that window in the table and
-- keeps the state of the window before. So the view's code is the same for
-- one window or many.
M.keepers = {} -- view name -> { { key, get, set, fresh } }
local bound: {string: Node} = {} -- view name -> the window whose state is in the view's table now
-- Windows that are in no tab: a view in a window of its own in a graphical
-- frontend (paw/canvas.tl). Each has a state of its own, as a window of a
-- tab has.
local loose: {Node: boolean} = setmetatable({}, {__mode = "k"})
seats.keep(
  "layout.bound",
  function(): {string: Node} return bound end,
  function(b: {string: Node}) bound = b end,
  function(): {string: Node} return {} end
)

--- Keep some state of a view for each window. `get()` gives it (one
--- value), `set(value)` puts it back, `fresh(value)` gives what a new
--- window starts with from the value of the window it is split from.
--- `key` names it: the same key again (a module loaded again) replaces it.
function M.window_keep<T>(name: string, get: function(): (T), set: function(T), fresh?: function(T): (T), key?: string)
  local list = M.keepers[name] or {}
  M.keepers[name] = list
  local entry: Keeper = {
    key = key,
    get = get as function(): (Kept),
    set = set as function(Kept),
    fresh = (fresh as function(Kept): (Kept)) or function(v: Kept): Kept return v end,
  }
  for i, k in ipairs(list) do
    if key ~= nil and k.key == key then
      list[i] = entry
      return
    end
  end
  list[#list + 1] = entry
end

--- Keep fields of a view's table for each window: `keys` names them,
--- `fresh` the ones a new window starts without (caches, what drawing
--- measures). A new window starts with the others as they are.
function M.window_fields(name: string, tbl: {string: Kept}, keys: {string}, fresh?: {string}, key?: string)
  local without: {string: boolean} = {}
  for _, k in ipairs(fresh or {}) do
    without[k] = true
  end
  M.window_keep(
    name,
    function(): {Kept}
      local out: {Kept} = {}
      for i, k in ipairs(keys) do
        out[i] = tbl[k]
      end
      return out
    end,
    function(values: {Kept})
      for i, k in ipairs(keys) do
        tbl[k] = values[i]
      end
    end,
    function(values: {Kept}): {Kept}
      local out: {Kept} = {}
      for i, k in ipairs(keys) do
        local v = values[i]
        if without[k] then
          v = nil
        elseif type(v) == "table" then
          -- A list or a set of the window's own, not shared with the other.
          local copied: {Kept: Kept} = {}
          for kk, x in pairs(v as {Kept: Kept}) do
            copied[kk] = x
          end
          v = copied as Kept
        end
        out[i] = v
      end
      return out
    end,
    key or "fields"
  )
end

-- Views with an instance for each window -----------------------------------------
--
-- The spike of the view instance spike: a view that says `window_instances` gets one table
-- for each window, an instance. The instance holds the fields of
-- `window_state`, and takes the rest (the methods, the shared fields) from
-- the view's table through `__index`. `bind` sets a pointer and copies no
-- field. The name of the view in `paw.ui.views` is a proxy: it reads and
-- writes the fields of `window_state` in the instance of the bound window,
-- so that a reader outside the view reads as before.

--- A view with instances. `base` is the view's table: it never holds a
--- field of `keys`. `order` lists the keys, `fresh` the keys that a split
--- starts without, `start` what a new seat starts with, and `home` the
--- state when no window has the view (the seat keeps it).
local record Instanced
  base: {string: Kept}
  keys: {string: boolean}
  order: {string}
  fresh: {string: boolean}
  start: Instance
  home: Instance
  meta: metatable<Instance>
end
local instanced: {string: Instanced} = {}

--- True if a window is in use and shows the view `name`.
local function shows(win: Node, name: string): boolean
  return win.view == name and (loose[win] or M.get(win.id) ~= nil)
end

--- A copy of a state. A split (`split`) starts without the fresh keys and
--- with its own copy of each list or set, as `window_fields` does.
local function copy_state(entry: Instanced, from: Instance, split: boolean, meta?: metatable<Instance>): Instance
  local out: Instance = setmetatable({}, meta)
  for _, k in ipairs(entry.order) do
    local v = rawget(from, k)
    if split and entry.fresh[k] then
      v = nil
    elseif split and type(v) == "table" then
      local copied: {Kept: Kept} = {}
      for kk, x in pairs(v as {Kept: Kept}) do
        copied[kk] = x
      end
      v = copied as Kept
    end
    rawset(out, k, v)
  end
  return out
end

--- The instance of the view that a window shows, made the first time:
--- a split takes a fresh copy of the bound window's state, a window after
--- one that went takes all of its state, and the first window takes the
--- home state. Nil for a view without instances.
function M.instance_of(win: Node): Instance
  local name = win and win.view
  local entry = name and instanced[name]
  if not entry then
    return nil
  end
  win.instances = win.instances or {}
  local own = win.instances[name]
  if own then
    return own
  end
  local was = bound[name]
  local from = was and was ~= win and was.instances and was.instances[name]
  own = copy_state(entry, from or entry.home, from ~= nil and shows(was, name), entry.meta)
  win.instances[name] = own
  return own
end

--- The state that the view's proxy reads and writes: the instance of the
--- bound window, else the home state.
local function current_state(name: string, entry: Instanced): Instance
  local win = bound[name]
  return win and win.instances and win.instances[name] or entry.home
end

--- When a window stops showing a view with instances: the home state
--- takes its state if it is the bound window, as the view's table kept the
--- state of the last window with the swap of fields.
local function drop_instances(win: Node)
  for name, own in pairs(win.instances or {}) do
    local entry = instanced[name]
    if entry and bound[name] == win then
      entry.home = copy_state(entry, own, false)
    end
  end
  win.instances = nil
end

--- Give a view an instance for each window. `def` is the view's table and
--- `keys` the fields of each window (`fresh`: the ones a split starts
--- without). The fields leave `def` for the home state. Returns the proxy
--- that `paw.ui.views` holds.
function M.instances<V>(name: string, def: V, keys: {string}, fresh?: {string}): V
  local base = def as {string: Kept}
  local had = instanced[name]
  local entry: Instanced = {base = base, keys = {}, order = keys, fresh = {}, home = {}}
  for _, k in ipairs(fresh or {}) do
    entry.fresh[k] = true
  end
  for _, k in ipairs(keys) do
    entry.keys[k] = true
    entry.home[k] = base[k]
    base[k] = nil
  end
  -- A deep copy: a new seat shares no list with this one.
  entry.start = copy(entry.home)
  -- An instance: its own fields of `keys`, the rest from the view.
  entry.meta = {
    __index = base,
    __newindex = function(own: Instance, k: string, v: Kept)
      if entry.keys[k] then
        rawset(own, k, v)
      else
        base[k] = v
      end
    end,
  }
  instanced[name] = entry
  -- Each seat has its own home state. A view loaded again keeps the keeper.
  if not had then
    seats.keep(
      "layout.instances." .. name,
      function(): Instance return instanced[name].home end,
      function(home: Instance) instanced[name].home = home end,
      function(): Instance return copy(instanced[name].start) end
    )
  end
  local proxy: {string: Kept} = setmetatable(
    {},
    {
      __index = function(_: {string: Kept}, k: string): Kept
        if entry.keys[k] then
          return current_state(name, entry)[k]
        end
        return base[k]
      end,
      __newindex = function(_: {string: Kept}, k: string, v: Kept)
        if entry.keys[k] then
          current_state(name, entry)[k] = v
        else
          base[k] = v
        end
      end,
    } as metatable<{string: Kept}>
  )
  return proxy as V
end

--- True if a view keeps a state for each window: by fields that `bind`
--- swaps (`window_keep`), or by instances (`instances`).
function M.per_window(name: string): boolean
  return M.keepers[name] ~= nil or instanced[name] ~= nil
end

--- True if a view is shown in one window at a time: a view without a
--- state for each window. A buffer type is not.
function M.one_window(name: string): boolean
  return not M.types:get(name) and not M.per_window(name)
end

--- Put the state of `win` in the table of its view, and keep the state of
--- the window before. A window new to the view starts from that state
--- (`fresh`). Nothing happens for a view with one state.
function M.bind(win: Node)
  local name = win and win.view
  -- A view with instances: the window's instance, and a pointer to it.
  local entry = name and instanced[name]
  if entry then
    local was = bound[name]
    if was == win then
      return
    end
    -- The window before went or shows another view: its state is the
    -- view's latest, and this window takes it in place of its own.
    local latest = was and was.instances and was.instances[name]
    if latest and win.instances and win.instances[name] and not shows(was, name) then
      win.instances[name] = copy_state(entry, latest, false, entry.meta)
    end
    M.instance_of(win)
    bound[name] = win
    return
  end
  local keep = name and M.keepers[name]
  if not keep or bound[name] == win then
    return
  end
  local was = bound[name]
  local now: {Kept} = {}
  for i, k in ipairs(keep) do
    now[i] = k.get()
  end
  local saved = win.kept
  -- The window before went (another layout, a closed tab) or shows
  -- another view now: what the table holds is the view's latest state,
  -- and this window takes it.
  if was and (was.view ~= name or not (loose[was] or M.get(was.id))) then
    was, saved = nil, nil
  end
  if was then
    was.kept = now
    if not saved then
      saved = {}
      for i, k in ipairs(keep) do
        saved[i] = k.fresh(now[i])
      end
    end
  else
    -- The first window takes the state that the table has.
    saved = saved or now
  end
  for i, k in ipairs(keep) do
    k.set(saved[i])
  end
  win.kept = nil
  bound[name] = win
end

--- The window whose state the table of a view holds now, if any.
function M.bound(name: string): Node
  return bound[name]
end

--- A window in no tab for the view `name`: a view in a window of its own
--- of a graphical frontend. It starts from the state of the window `from`
--- (the pane that it leaves), else of the window whose state the view
--- holds now. It keeps its own state from then on.
function M.loose(name: string, from?: Node): Node
  if from and from.view == name then
    M.bind(from)
  end
  local win = M.leaf(name)
  loose[win] = true
  M.bind(win)
  return win
end

--- True if a window of this number is in a tab of the seat, or is a
--- window in no tab (`M.loose`) that is still in use.
function M.alive(id: integer): boolean
  if M.get(id) then
    return true
  end
  for win in pairs(loose) do
    if win.id == id then
      return true
    end
  end
  return false
end

--- Give the state of the window `from` to the window `to` of the same
--- view, in place of its own: a view in a window of its own that returns
--- into its pane takes what it showed there.
function M.hand_over(from: Node, to: Node)
  if not (from and to and from.view == to.view and M.per_window(from.view)) then
    return
  end
  M.bind(from)
  to.kept = nil
  if instanced[from.view] then
    to.instances = {[from.view] = M.instance_of(from)}
  end
  bound[from.view] = to
end

--- What `pcall` of a function gives, as `{ ok, results... }`.
local record Results is {Kept}
  n: integer
end
local function pack(...: Kept): Results
  local out: Results = {...}
  out.n = select("#", ...)
  return out
end

--- Run `fn(...)` with the state of `win` in its view's table, then put
--- back the state that was there.
function M.within<A, R>(win: Node, fn: function(...: A): (R...), ...: A): R...
  local name = win and win.view
  local before = name and bound[name]
  if not (name and M.per_window(name)) or before == win then
    return fn(...)
  end
  M.bind(win)
  local result = pack((pcall as function(function(...: A): (R...), ...: A): (Kept...))(fn, ...))
  if before then
    M.bind(before)
  end
  if not result[1] then
    error(result[2], 0)
  end
  return (unpack as function(Results, integer, integer): R...)(result, 2, result.n)
end

--- After a window drew or took the pointer: each view's table holds the
--- state of its window in the current tab that had the keyboard last, so
--- that keys and commands act there.
function M.settle()
  local u = ui()
  local t = u.tabs and u.tabs[u.tab]
  if not t then
    return
  end
  local canvas = paw.canvas
  local names: {string: boolean} = {}
  for name in pairs(M.keepers) do
    names[name] = true
  end
  for name in pairs(instanced) do
    names[name] = true
  end
  for name in pairs(names) do
    -- A view in a window of its own of a graphical frontend, which has
    -- the keyboard there.
    local window = canvas and canvas.open_views[name]
    local own = window and window.win
    local win = own and canvas.inside == name and u.focused == name and own or (t.win and M.find_id(t.layout, t.win))
    if not (win and win.view == name) then
      local id = t.last and t.last[name]
      win = id and M.find_id(t.layout, id)
    end
    -- Else a window of the view in the tab, its window of its own, or its
    -- closed place: what acts on the view meanwhile acts on what it will show.
    if not (win and win.view == name and (not win.hidden or win == own)) then
      win = M.find(t.layout, name, true) or own or M.find(t.layout, name)
    end
    if win then
      M.bind(win)
    end
  end
end

--- A copy of a seat's tabs for a new seat: the windows keep their places
--- and options, and start from that seat's state.
function M.copy_tabs(tabs: {Tab}): {Tab}
  local function walk(value: Kept): Kept
    if type(value) ~= "table" then
      return value
    end
    local out: {Kept: Kept} = {}
    for k, v in pairs(value as {Kept: Kept}) do
      if k ~= "kept" as Kept and k ~= "instances" as Kept then
        out[k] = walk(v)
      end
    end
    return out as Kept
  end
  return walk(tabs as Kept) as {Tab}
end

-- The first window numbered `id` under `node`, or `found`. It walks the
-- whole tree as `M.windows` does, and gives a window made by code its
-- number the same way, but makes no list: a frame looks up windows often.
local function find_id_in(node: Node, id: integer, found: Node): Node
  if node.view then
    if not node.id then
      next_win = next_win + 1
      node.id, node.opts, node.state = next_win, node.opts or {}, node.state or {}
    end
    if not found and node.id == id then
      return node
    end
    return found
  end
  for _, child in ipairs(node) do
    found = find_id_in(child, id, found)
  end
  return found
end

-- The first window of the view `name` under `node` that is not hidden and
-- is numbered `id` (any number without), or with `any` the first window of
-- the view at all. It makes no list of the windows: a frame looks up views.
local function view_in(node: Node, name: string, id: integer, any: boolean): Node
  if node.view then
    if node.view == name and (any or not node.hidden and (id == nil or node.id == id)) then
      return node
    end
    return nil
  end
  for _, child in ipairs(node) do
    local win = view_in(child, name, id, any)
    if win then
      return win
    end
  end
  return nil
end

--- The window of a view in a tree, one on screen first: the window with
--- the keyboard, else the one whose state the view holds, else the one
--- that had the keyboard last. With `shown`, only one on screen.
function M.find(root: Node, name: string, on_screen?: boolean): Node
  local u = ui()
  local t = u.tabs and u.tabs[u.tab]
  local mine = t and t.layout == root
  root = root or u.layout
  -- Each window gets its number first, as `M.windows` gives it.
  find_id_in(root, -1, nil)
  if mine then
    local win = t.win and view_in(root, name, t.win, false)
      or t.last and t.last[name] and view_in(root, name, t.last[name], false)
    if win then
      return win
    end
  end
  local win = bound[name] and view_in(root, name, bound[name].id, false) or view_in(root, name, nil, false)
  if win or on_screen then
    return win
  end
  return view_in(root, name, nil, true)
end

--- A window by its number, and the tab it is in.
function M.get(id: integer): Node, integer
  local u = ui()
  for _, win in ipairs(M.windows(u.layout, true)) do
    if win.id == id then
      return win, u.tab
    end
  end
  for i, t in ipairs(u.tabs) do
    for _, win in ipairs(M.windows(t.layout, true)) do
      if win.id == id then
        return win, i
      end
    end
  end
end

--- Turn a tab's tree into one stacked in rows at the top, in place: the
--- table stays the one the tab and `paw.ui.layout` hold.
local function to_rows(root: Node)
  if root.dir == "v" then
    return
  end
  local inner: Node = {dir = root.dir}
  for i, child in ipairs(root) do
    inner[i] = child
  end
  for i = #root, 1, -1 do
    root[i] = nil
  end
  root.dir, root[1] = "v", inner
end

--- Take out nodes left empty and nodes left with one child (which takes its
--- place and its size).
local function tidy(node: Node)
  for i = #node, 1, -1 do
    local child = node[i]
    if not child.view then
      tidy(child)
      if #child == 0 then
        table.remove(node, i)
      elseif #child == 1 then
        local only = child[1]
        only.size, only.weight, only.min = child.size, child.weight, child.min
        node[i] = only
      end
    end
  end
end

--- Merge splits of one child and splits the same way as their parent.
function M.tidy(root: Node)
  tidy(root)
  to_rows(root)
end

--- Take a view's window (a view has one) out of a tree, but `keep`.
--- Returns whether one that was on screen went.
local function remove_view(root: Node, name: string, keep?: Node): boolean
  local was_shown = false
  local function walk(node: Node)
    for i = #node, 1, -1 do
      local child = node[i]
      if child.view then
        if child.view == name and child ~= keep and not child.buf then
          was_shown = was_shown or not child.hidden
          table.remove(node, i)
        end
      else
        walk(child)
      end
    end
  end
  walk(root)
  tidy(root)
  return was_shown
end

--- The window of a tree that has the keyboard, if the tree is the current
--- tab's, else the tree's first window that takes it.
local function keyboard_in(root: Node): Node
  local u = ui()
  local t = u.tabs and u.tabs[u.tab]
  if t and t.layout == root and t.win then
    for _, win in ipairs(M.windows(root)) do
      if win.id == t.win then
        return win
      end
    end
  end
  for _, win in ipairs(M.windows(root)) do
    if focusable(win.view) then
      return win
    end
  end
end

--- Put a window for a docked view where it docks: on its side of the
--- window that has the keyboard, as a split in Neovim is.
local function place_home(root: Node, name: string, home: Home, hidden?: boolean): Node
  local win = M.leaf(
    name, {size = home.size, weight = home.weight, min = home.min, float_below = home.float_below, hidden = hidden}
  )
  local side = home.side or "bottom"
  local dir: Dir = (side == "left" or side == "right") and "h" or "v"
  local before = side == "left" or side == "top"
  local cur = keyboard_in(root)
  local parent, at: Node, integer
  if cur then
    parent, at = parent_of(root, cur)
  end
  if not parent then
    -- Nothing to stand beside: along that side of the tab.
    if dir == "h" then
      local row: Node = {dir = "h"}
      for i, child in ipairs(root) do
        row[i] = child
      end
      for i = #root, 1, -1 do
        root[i] = nil
      end
      root[1] = row
      table.insert(row, before and 1 or #row + 1, win)
    else
      table.insert(root, before and 1 or #root + 1, win)
    end
    return win
  end
  if parent.dir == dir then
    table.insert(parent, before and at or at + 1, win)
  else
    local node: Node = {dir = dir, size = cur.size, weight = cur.weight, min = cur.min}
    cur.size, cur.weight, cur.min = nil, nil, nil
    node[1], node[2] = before and win or cur, before and cur or win
    parent[at] = node
  end
  return win
end

--- Dock a view in the current tab and remember the place for other tabs.
--- See `paw.ui.dock`.
function M.dock(name: string, opts: DockOptions)
  local home: Home = {side = opts.side or "bottom", size = opts.size, weight = opts.weight, min = opts.min}
  M.homes[name] = home
  local root = ui().layout
  remove_view(root, name)
  place_home(root, name, home, opts.hidden)
  M.tidy(root)
end

-- Buffers -----------------------------------------------------------------------

--- A view's buffer: every view has one.
local function single(name: string): Buffer
  local buf = by_view[name]
  if not buf and ui().views:get(name) and not M.types:get(name) then
    next_buf = next_buf + 1
    local view = ui().views:get(name)
    buf = {id = next_buf, name = view.bufname or M.names[name] or name, type = name, single = true, listed = true}
    M.buffers[buf.id] = buf
    by_view[name] = buf
  end
  return buf
end

--- The buffer a window shows.
function M.buf_of(win: Node): Buffer
  if not win then
    return nil
  end
  if win.buf then
    return M.buffers[win.buf]
  end
  return single(win.view)
end

--- A buffer of a type for a target, made if there is none. A view's type
--- has one buffer, whatever the target.
function M.buf_create(type_name: string, target?: string): Buffer
  local def = M.types:get(type_name)
  if not def then
    return single(type_name)
  end
  if target ~= nil then
    for _, buf in pairs(M.buffers) do
      if buf.type == type_name and buf.target == target then
        return buf
      end
    end
  end
  next_buf = next_buf + 1
  local buf: Buffer = {
    id = next_buf, type = type_name, target = target, listed = def.listed ~= false, options = copy(def.options or {})
  }
  buf.name = def.bufname and def.bufname(target, buf)
    or (target ~= nil and type_name .. "://" .. tostring(target))
    or type_name
  M.buffers[buf.id] = buf
  buf.state = def.create and def.create(target, buf) or {}
  return buf
end

--- The type and the buffer of a name. The name is the name or the number of
--- a buffer, or the name or the short name of a view (`roll`). It can also
--- be a type with a target (`type://target`). Nil when the name is not known.
function M.resolve(name: string | integer): string, Buffer, string
  if name == nil then
    return nil
  end
  local number = tonumber(name)
  if number then
    local buf = M.buffers[number as integer]
    return buf and buf.type, buf
  end
  local text = tostring(name)
  for _, buf in pairs(M.buffers) do
    if buf.name == text then
      return buf.type, buf
    end
  end
  for view, short in pairs(M.names) do
    if short == text and ui().views:get(view) then
      return view, single(view)
    end
  end
  local views = ui().views
  for view, def in pairs(views:entries()) do
    if def.bufname == text then
      return view, single(view)
    end
  end
  if M.types:get(text) then
    return text, M.buf_create(text)
  end
  if views:get(text) and views:get(text).focusable ~= false then
    return text, single(text)
  end
  -- A type may take names of its own form as targets (`paw://lane/3`).
  for type_name, def in pairs(M.types:entries()) do
    if def.claims and def.claims(text) then
      return type_name, M.buf_create(type_name, text)
    end
  end
  local kind, target = text:match("^([%w_]+)://(.*)$")
  if kind and M.types:get(kind) then
    return kind, M.buf_create(kind, target ~= "" and target or nil)
  end
  -- A view that opens a thing of its own in its window (`roll://7`, the
  -- piano roll on clip 7): the view, and what to open, for `open_target`.
  local view = kind and target ~= "" and M.view_named(kind)
  if view and views:get(view).open_target then
    return view, single(view), target
  end
end

--- The view a name or a short name (`roll`) stands for, or nil.
function M.view_named(name: string): string
  local views = ui().views
  for view, short in pairs(M.names) do
    if short == name and views:get(view) then
      return view
    end
  end
  if views:get(name) and views:get(name).focusable ~= false and not M.types:get(name) then
    return name
  end
end

--- The clip a name of a window's thing stands for: an id (`7`), an
--- address (`paw://clip/7`) or the name of a clip, the first in the order
--- of the tracks. Nil if there is none.
function M.clip_named(target: string | integer): objects.Clip
  local id = tonumber(target) or tonumber(tostring(target):match("^paw://clip/(%d+)"))
  if id then
    return pcall(api.clip_get, id as integer) and paw.clip(id as integer) or nil
  end
  for _, track in ipairs(api.track_list({all = true})) do
    for _, c in ipairs(api.clip_list(track)) do
      if c.name == target then
        return paw.clip(c.id)
      end
    end
  end
end

--- Open `target` in a window that shows the view `name`, by the view's
--- `open_target(target)`: false and why when it cannot.
local function aim(name: string, target: string): boolean, string
  if target == nil then
    return true
  end
  local view = ui().views:get(name)
  if not (view and view.open_target) then
    return false, name .. " opens nothing by name"
  end
  local ok, why = view:open_target(target)
  if ok == false then
    return false, why or ("nothing called `" .. tostring(target) .. "`")
  end
  api.ui_redraw()
  return true
end

--- The buffers to list (`:ls`), by number: the views' that are in the
--- layout or docked, and every other made since and not deleted.
function M.buffers_list(): {Buffer}
  local u = ui()
  for _, t in ipairs(u.tabs) do
    for _, win in ipairs(M.windows(t.layout, true)) do
      M.buf_of(win)
    end
  end
  for name in pairs(M.homes) do
    if u.views:get(name) then
      single(name)
    end
  end
  local out: {Buffer} = {}
  for _, buf in pairs(M.buffers) do
    -- A buffer of a view or a type that an extension took away when it
    -- unloaded cannot be shown: it is not listed.
    local showable = buf.single and u.views:get(buf.type) ~= nil or not buf.single and M.types:get(buf.type) ~= nil
    if buf.listed and showable then
      out[#out + 1] = buf
    end
  end
  table.sort(out, function(a: Buffer, b: Buffer): boolean return a.id < b.id end)
  return out
end

--- Names to complete after `:b`, `:e`, `:sp`, `:vs`: every buffer's and
--- every view's that can be shown.
function M.buffer_names(): {command_registry.Item}
  local out: {command_registry.Item} = {}
  local seen: {string: boolean} = {}
  local function add(name: string, desc: string)
    if not seen[name] then
      seen[name] = true
      out[#out + 1] = {text = name, desc = desc}
    end
  end
  for _, buf in ipairs(M.buffers_list()) do
    add(buf.name, M.title(buf))
  end
  for name, view in pairs(ui().views:entries()) do
    if view.focusable ~= false and not M.types:get(name) then
      add(view.bufname or M.names[name] or name, view.title)
    end
  end
  table.sort(out, function(a: command_registry.Item, b: command_registry.Item): boolean return a.text < b.text end)
  return out
end

--- What a buffer is called on screen.
function M.title(buf: Buffer): string
  local def = M.types:get(buf.type)
  if def and def.title then
    local ok, text = pcall(def.title, buf) as (boolean, string)
    if ok and text then
      return tostring(text)
    end
  end
  local view = ui().views:get(buf.type)
  -- A view's title may say what it shows now (`view:title_of()`).
  if view and view.title_of then
    local ok, text = pcall(view.title_of, view) as (boolean, string)
    if ok and text then
      return tostring(text)
    end
  end
  return view and view.title or M.pane_titles[buf.type] or M.titles[buf.type] or buf.name
end

--- A view's buffer's name, for messages.
local function called(name: string): string
  local buf = by_view[name]
  return buf and buf.name or M.names[name] or name
end

--- Forget a buffer that no window shows any more, if it is one to forget:
--- an unlisted one (an empty window's).
local function reap(id: integer)
  local buf = id and M.buffers[id]
  if not buf or buf.listed then
    return
  end
  for _, t in ipairs(ui().tabs) do
    for _, win in ipairs(M.windows(t.layout, true)) do
      if win.buf == id then
        return
      end
    end
  end
  M.buffers[id] = nil
end

-- A seat that closes takes its tabs and windows with it, and so the buffers
-- that only its windows showed (an empty window's), as `reap` does when a
-- window closes. The event comes while the seat's tabs are the current ones.
events.on(
  events.event("seat.closing") as events.Event<events.Payload>,
  function()
    for _, t in ipairs(ui().tabs) do
      for _, win in ipairs(M.windows(t.layout, true)) do
        local buf = win.buf and M.buffers[win.buf]
        if buf and not buf.listed then
          M.buffers[win.buf] = nil
        end
      end
    end
  end
)

--- Delete a buffer (`:bd`): its windows close, and a buffer of a type that
--- has more than one is forgotten. A view's buffer stays, as the view does.
function M.buf_delete(buf: Buffer)
  for _, tab_win in ipairs(M.all_windows()) do
    local win = tab_win.win
    if (buf.single and win.view == buf.type and not win.buf) or win.buf == buf.id then
      if not win.hidden then
        if not M.close(win) then
          M.show_in(win, "empty")
        end
      end
    end
  end
  if buf.single then
    buf.listed = false
  else
    local def = M.types:get(buf.type)
    if def and def.delete then
      def.delete(buf)
    end
    M.buffers[buf.id] = nil
    for _, t in ipairs(ui().tabs) do
      local function walk(node: Node)
        for i = #node, 1, -1 do
          local child = node[i]
          if child.view then
            if child.buf == buf.id then
              table.remove(node, i)
            end
          else
            walk(child)
          end
        end
      end
      walk(t.layout)
      M.tidy(t.layout)
    end
  end
  api.ui_redraw()
end

--- Close the windows of buffers whose target is gone, as when another
--- project is opened (a window with `paw://lane/9` in it): a type says so
--- with `alive(buf)`. A window that cannot close, the last one, is left empty.
function M.drop_dead()
  local dead: {Buffer} = {}
  for _, buf in pairs(M.buffers) do
    local def = M.types:get(buf.type)
    if def and def.alive and not buf.single and not def.alive(buf) then
      dead[#dead + 1] = buf
    end
  end
  for _, buf in ipairs(dead) do
    M.buf_delete(buf)
  end
end
events.on(kernel.project_loaded, function() M.drop_dead() end)

-- Buffer types ----------------------------------------------------------------

--- A value of a table this module copies and never reads.
local record Value
end

--- Make a buffer type. See `docs/reference/lua-views.md`.
---   paw.buftype("notes", { create = function(target) return {} end, render = function(win, canvas, ctx) end })
--- The fields are these. `create(target, buf)` gives the state of the
--- buffer. `render(win, canvas, ctx)` draws (`ctx.buf` is the buffer, and
--- `win.state` is the state of the window). `on_key(win, key)` gets keys
--- with no mapping. Also `on_mouse(win, event)`, `title(buf)` and
--- `bufname(target, buf)`. `options` is the options of the buffer at the
--- start.
---
--- `listed` false keeps its buffers off `:ls`, and forgets each
--- buffer when no window shows it. Also `delete(buf)` and `time` (see
--- `timebind`). `claims(name)` tells if a name is a target of the type by
--- its form (`:vs paw://lane/3`). `window()` is the window to draw when no
--- window in the tabs shows the type (one in a separate window of a
--- graphical frontend). Map keys for its windows with `{ view = name }`.
---
--- A type can also do all that a view can do, for each window. `grid(win)`
--- is the cursor that the keymap moves, as the `grid` of a view.
--- `describe(win)` is the text of `K`. `status(win, ctx)` is the `view`
--- component of the status line. Also `subscope(win)`, `paint(win, g, ctx)`
--- and `pointer(win, e)` (pixels in a graphical frontend), and `help`.
---
--- It can also have the fields that `paw.layout.powers` maps: `keymaps`,
--- `motions`, `textobjects` and `operators`. Their functions get `ctx.win`
--- and `ctx.buf`.
function M.buftype<B is contracts.Buftype>(name: string, def: B): B
  def.name = name
  M.types:put(name, def)
  local function win_of(ctx?: RenderContext): Node
    if ctx and ctx.win then
      return ctx.win as Node
    end
    local current = M.current()
    if current and current.view == name then
      return current
    end
    for _, win in ipairs(M.windows(ui().layout)) do
      if win.view == name then
        return win
      end
    end
    if def.window then
      return def.window() as Node
    end
  end
  -- The keymap, the drawing and the mouse reach a type through a view of
  -- its name, as they reach every view.
  local view: View = {
    name = name,
    buftype = def,
    window = false,
    modal = def.modal,
    help = def.help,
    render = function(_: View, canvas: contracts.Buf, ctx?: RenderContext)
      local win = win_of(ctx)
      if not win then
        return
      end
      local merged: RenderContext = {}
      for k, v in pairs((ctx or {}) as {string: Value}) do
        (merged as {string: Value})[k] = v
      end
      merged.win, merged.buf = win, M.buf_of(win)
      if def.render then
        def.render(win, canvas, merged)
      end
    end,
    on_key = function(_: View, key: string): boolean
      local win = win_of()
      if win and def.on_key then
        return def.on_key(win, key)
      end
    end,
    on_mouse = function(_: View, event: contracts.MouseEvent): boolean
      local win = event.win and M.get(event.win) or win_of()
      if win and def.on_mouse then
        return def.on_mouse(win, event)
      end
    end,
  }
  if def.time then
    view.time_axis = function(_: View, ctx?: RenderContext): number, number, number return def.time.get(win_of(ctx)) end
    view.set_time_axis = function(_: View, left: number, zoom: number, ctx?: RenderContext)
      def.time.set(win_of(ctx), left, zoom)
    end
  end
  if def.describe then
    view.describe = function(): contracts.Description return def.describe(win_of()) end
  end
  if def.status then
    view.status = function(_: View, ctx?: contracts.StatusContext): contracts.StatusText
      return def.status(win_of(), ctx)
    end
  end
  if def.subscope then
    view.subscope = function(): string return def.subscope(win_of()) end
  end
  if def.paint then
    view.paint = function(_: View, g: contracts.Painter, ctx?: contracts.PaintContext)
      def.paint(win_of(ctx as RenderContext), g, ctx)
    end
  end
  if def.pointer then
    view.pointer = function(_: View, e: contracts.PointerEvent): boolean return def.pointer(win_of(), e) end
  end
  ui().views:put(name, view)
  if type(def.grid) == "function" then
    -- The grid of the window with the keys, asked for each time.
    local grid_of = def.grid
    view.grid = setmetatable(
      {} as contracts.Grid,
      {
        __index = function(_: contracts.Grid, key: string): Value
          local win = win_of()
          local g = win and grid_of(win)
          return g and (g as {string: Value})[key]
        end,
      } as metatable<contracts.Grid>
    )
  elseif def.grid then
    view.grid = def.grid as contracts.Grid
  end
  M.powers(
    name,
    def,
    function(fn: KeyFn): KeyFn
      return function(ctx?: KeyContext, region?: Region): Region
        local win = win_of()
        ctx = ctx or {}
        ctx.win, ctx.buf = win, win and M.buf_of(win)
        return fn(ctx, region)
      end
    end
  )
  api.ui_redraw()
  return def
end

--- Map the items that `def` declares in key scope `scope` (the name of a
--- view, or a part of a view: see `paw.keymap.scopes`). So a buffer type
--- or a kind of text buffer declares its keys where it is made:
---   keymaps     = { ["<localleader>r"] = fn or "command line" or { fn, desc = "...", mode = ... } }
---   motions     = { ["]p"] = fn }      -- also after operators and in visual mode
---   textobjects = { ip = fn }          -- fn(ctx) returns a region
---   operators   = { gq = fn }          -- fn(region, ctx)
--- `wrap(fn)`, if given, makes each function that the keymap calls. It can
--- add to the `ctx` of the function (the first argument).
function M.powers(scope: string, def: contracts.Powers, wrap?: Wrap)
  local keymap = paw.keymap
  local wrapping = wrap or function(fn: KeyFn): KeyFn return fn end
  -- Each item as the keymap takes it: what it runs, and the options of a
  -- `{ fn, desc = ..., mode = ... }` entry in the view's scope.
  local function each(
    list: {string: contracts.KeyRhs}, how: function(lhs: string, rhs: contracts.KeyRhs, opts: MapOptions)
  )
    for lhs, entry in pairs(list or {}) do
      local rhs: contracts.KeyRhs = entry
      local opts: MapOptions = {view = scope}
      if entry is contracts.KeyEntry then
        rhs = entry[1]
        opts.desc, opts.mode, opts.role = entry.desc, entry.mode as Mode | {Mode}, entry.role
        opts.motion, opts.linewise, opts.jump = entry.motion, entry.linewise, entry.jump
        opts.repeatable, opts.nowait = entry.repeatable, entry.nowait
      end
      how(lhs, rhs, opts)
    end
  end
  local function wrapped(rhs: contracts.KeyRhs): KeymapModule.Rhs
    if rhs is contracts.KeyFn then
      return wrapping(rhs as KeyFn) as contracts.KeyFn
    end
    return rhs as string
  end
  each(
    def.keymaps, function(lhs: string, rhs: contracts.KeyRhs, opts: MapOptions) keymap.set(lhs, wrapped(rhs), opts) end
  )
  each(
    def.motions,
    function(lhs: string, rhs: contracts.KeyRhs, opts: MapOptions)
      opts.motion = true
      keymap.set(lhs, wrapped(rhs), opts)
    end
  )
  each(
    def.textobjects as {string: contracts.KeyRhs},
    function(lhs: string, fn: contracts.KeyRhs, opts: MapOptions)
      keymap.textobject(lhs, wrapping(fn as KeyFn) as KeymapModule.TextObject, opts)
    end
  )
  -- An operator's function gets the region first, and `ctx` second.
  each(
    def.operators as {string: contracts.KeyRhs},
    function(lhs: string, rhs: contracts.KeyRhs, opts: MapOptions)
      local fn = rhs as function(region: Region, ctx?: KeyContext): Region
      local wrapped_fn = wrapping(function(ctx?: KeyContext, region?: Region): Region return fn(region, ctx) end)
      keymap.operator(lhs, function(region: Region, ctx?: KeyContext) wrapped_fn(ctx, region) end, opts)
    end
  )
end

-- Tabs and the current window ---------------------------------------------------

--- The current tab.
local function tab(): Tab
  local u = ui()
  return u.tabs[u.tab]
end
M.tab = tab

--- Every window of every tab, as `{ win, tab }`.
function M.all_windows(): {TabWindow}
  local out: {TabWindow} = {}
  for i, t in ipairs(ui().tabs) do
    for _, win in ipairs(M.windows(t.layout, true)) do
      out[#out + 1] = {win = win, tab = i}
    end
  end
  return out
end

local function first_window(root: Node): Node
  for _, win in ipairs(M.windows(root)) do
    if focusable(win.view) then
      return win
    end
  end
end

--- The window that has the keyboard, in the current tab. This is the last
--- window entered, or the window of the focused view when paw gave focus by
--- the name of the view.
function M.current(): Node
  local u, t = ui(), tab()
  local win = t.win and M.find_id(t.layout, t.win)
  if win and win.hidden then
    win = nil
  end
  if not (win and win.view == u.focused) then
    local named = u.focused and M.find(t.layout, u.focused)
    if named and not named.hidden then
      win = named
    end
  end
  win = win or first_window(t.layout)
  if win and t.win ~= win.id then
    t.prev, t.win = t.win, win.id
  end
  return win
end

--- The window of an id in the tree under `root`.
function M.find_id(root: Node, id: integer): Node
  return find_id_in(root or ui().layout, id, nil)
end

--- Make a window the current one and give it the keyboard.
function M.enter(win: Node)
  local u, t = ui(), tab()
  local old = M.current()
  if old ~= win then
    local old_buf, new_buf = M.buf_of(old), M.buf_of(win)
    if old then
      events.emit(win_leave, {win = old.id})
    end
    if old_buf and old_buf ~= new_buf then
      events.emit(buf_leave, {buf = old_buf.id, name = old_buf.name})
    end
    t.prev, t.win = old and old.id, win.id
    events.emit(win_enter, {win = win.id})
    if new_buf and old_buf ~= new_buf then
      events.emit(buf_enter, {buf = new_buf.id, name = new_buf.name})
    end
  end
  -- The view's table holds this window's state while it has the keyboard.
  M.bind(win)
  -- A view in a window of its own no longer has the keyboard there.
  if paw.canvas then
    paw.canvas.inside = nil
  end
  t.last = t.last or {}
  t.last[win.view] = win.id
  if u.focused ~= win.view then
    local before = u.focused
    u.focused = win.view
    events.emit(view_focused, {view = win.view, old = before})
  end
  api.ui_redraw()
end

--- Hide a single view's windows in the tabs other than the current one: it
--- is shown in one window at a time.
local function take(name: string)
  local u = ui()
  if not M.one_window(name) then
    return
  end
  for i, t in ipairs(u.tabs) do
    if i ~= u.tab then
      for _, win in ipairs(M.windows(t.layout)) do
        if win.view == name and not win.buf then
          win.hidden = true
          paw.notify(called(name) .. " moved here from tab " .. i)
          -- A tab is not left without a window: it has an empty one instead.
          if not first_window(t.layout) then
            win.hidden, win.view, win.buf, win.state = false, "empty", M.buf_create("empty").id, {}
            win.size, win.weight, win.min, win.float_below = nil, nil, nil, nil
          end
        end
      end
    end
  end
end

--- Put a view's window on screen in the current tab: where it was, else
--- where it docked. With `go`, a view on screen in another tab is gone to
--- instead. Returns the window, or nil for a view that has no place (one
--- that floats).
function M.reveal(name: string, go?: boolean): Node
  local u = ui()
  local t = tab()
  local win = M.find(t.layout, name)
  if win and not win.hidden then
    return win
  end
  if go then
    for i, other in ipairs(u.tabs) do
      local there = i ~= u.tab and M.find(other.layout, name)
      if there and not there.hidden then
        M.tab_go(i)
        return there
      end
    end
  end
  if not win then
    local home = M.homes[name]
    if not home then
      return nil
    end
    win = place_home(t.layout, name, home)
    M.tidy(t.layout)
  end
  win.hidden = false
  take(name)
  local buf = single(name)
  if buf then
    buf.listed = true
  end
  local view = u.views:get(name)
  if view and view.on_show then
    view:on_show()
  end
  api.ui_redraw()
  return win
end

--- Hide the windows of a view in each tab, but the last window of a tab,
--- which stays. Returns true if one that was on the screen went.
function M.conceal(name: string): boolean
  local was = false
  for _, t in ipairs(ui().tabs) do
    for _, win in ipairs(M.windows(t.layout)) do
      if win.view == name and not win.buf then
        win.hidden = true
        if first_window(t.layout) then
          was = true
        else
          win.hidden = false
        end
      end
    end
  end
  return was
end

--- The windows of the current tab that take the keyboard.
local function focusable_windows(): {Node}
  local out: {Node} = {}
  for _, win in ipairs(M.windows(ui().layout)) do
    if focusable(win.view) then
      out[#out + 1] = win
    end
  end
  return out
end
M.focusable_windows = focusable_windows

--- Close a window. The window of a view keeps its place, hidden. Other
--- windows go. The last window of a tab closes the tab. The last window of
--- all does not close. Returns true if it closed.
function M.close(win?: Node): boolean
  local u, t = ui(), tab()
  win = win or M.current()
  if not win then
    return false
  end
  local others = 0
  for _, w in ipairs(focusable_windows()) do
    if w ~= win then
      others = others + 1
    end
  end
  if others == 0 then
    if #u.tabs > 1 then
      M.tab_close()
      return true
    end
    return false
  end
  local current = M.current() == win
  -- A second window of a view with a state for each goes, as a buffer's
  -- does: the view keeps one place in the tab.
  local again = M.per_window(win.view) and not win.buf
  if again then
    again = false
    for _, w in ipairs(M.windows(t.layout, true)) do
      if w ~= win and w.view == win.view then
        again = true
      end
    end
  end
  if win.buf or again then
    local parent, at = parent_of(t.layout, win)
    if parent then
      table.remove(parent, at)
    end
    M.tidy(t.layout)
    reap(win.buf)
    drop_instances(win)
    if bound[win.view] == win then
      bound[win.view] = nil
    end
  else
    win.hidden = true
    local view = u.views:get(win.view)
    if view and view.on_hide then
      view:on_hide()
    end
  end
  if t.zoom and t.zoom.win == win.id then
    t.zoom = nil
  end
  if current then
    local prev = t.prev and M.find_id(t.layout, t.prev)
    if not (prev and not prev.hidden and focusable(prev.view)) then
      prev = first_window(t.layout)
    end
    if prev then
      M.enter(prev)
    end
  end
  api.ui_redraw()
  return true
end

--- Give the keyboard to the window that had it before the current one
--- (`Ctrl-w p`), else to another window of the tab. Returns false when
--- the current window is the only one.
function M.back(): boolean
  local t = tab()
  local cur = M.current()
  local win = t.prev and M.find_id(t.layout, t.prev)
  if not (win and win ~= cur and not win.hidden and focusable(win.view)) then
    win = nil
    for _, w in ipairs(focusable_windows()) do
      if w ~= cur then
        win = w
        break
      end
    end
  end
  if not win then
    return false
  end
  M.enter(win)
  return true
end

--- Close every window of the current tab but one.
function M.only(win?: Node)
  win = win or M.current()
  if not win then
    return
  end
  for _, w in ipairs(focusable_windows()) do
    if w ~= win then
      M.close(w)
    end
  end
  M.enter(win)
end

--- Where each window of the current tab is drawn, by window number, from a
--- fresh arrangement of the screen.
local function rect_of(win: Node): contracts.ScreenRect
  for _, r in ipairs(ui().arrange()) do
    if r.win == win.id then
      return r
    end
  end
end

--- Split a window (the current one) and show a buffer in the new half,
--- which gets the keyboard. `opts`: `vertical` (side by side), `view` (the
--- type; "empty" by default), `buf` (a buffer of a type that has more than
--- one), `target` (what the view opens there, as in `roll://7`), `win`.
--- Returns the new window, or nil and why not.
function M.split(opts: SplitOptions): Node, string
  local u, t = ui(), tab()
  local cur = opts.win or M.current()
  local name = opts.view or "empty"
  if not u.views:get(name) then
    return nil, "no buffer `" .. tostring(name) .. "`"
  end
  local single_view = not M.types:get(name)
  local one = M.one_window(name)
  if one and cur and cur.view == name then
    return nil, name .. " is in this window already"
  end
  if cur then
    local r = rect_of(cur)
    local room = r and (opts.vertical and r.w or r.h)
    local least = opts.vertical and M.min_width or M.min_height
    -- Without a screen (a script, the graphical frontend) there is no room to measure.
    if room and room > 0 and room < least * 2 + 1 then
      return nil, "not enough room"
    end
  end
  local buf = opts.buf or (not single_view and M.buf_create(name).id) or nil
  local moved = one and remove_view(t.layout, name)
  local win = M.leaf(name, {buf = buf})
  -- A new window shows the part of the song that the one it is split
  -- from shows, as Vim's windows keep their folds.
  win.scope = cur and cur.scope
  win.folds = cur and copy_folds(cur.folds)
  win.foldlevel = cur and cur.foldlevel
  win.vzoom = cur and copy(cur.vzoom)
  local root = t.layout
  local parent, at: Node, integer
  if cur then
    parent, at = parent_of(root, cur)
  end
  if not parent then
    root[#root + 1] = win
  else
    local dir: Dir = opts.vertical and "h" or "v"
    local after = opts.vertical and opt.splitright or (not opts.vertical and opt.splitbelow)
    if parent.dir == dir then
      -- The new window takes half of the one split.
      if cur.size then
        win.size = math.floor(cur.size / 2)
        cur.size = cur.size - win.size
      else
        cur.weight = (cur.weight or 1) / 2
        win.weight = cur.weight
      end
      table.insert(parent, after and at + 1 or at, win)
    else
      local node: Node = {dir = dir, size = cur.size, weight = cur.weight, min = cur.min}
      cur.size, cur.weight, cur.min, cur.float_below = nil, nil, nil, nil
      node[1], node[2] = after and cur or win, after and win or cur
      parent[at] = node
    end
  end
  M.tidy(root)
  if single_view then
    take(name)
    single(name).listed = true
    local view = u.views:get(name)
    if moved then
      paw.notify(called(name) .. " moved to the new window")
    elseif view.on_show then
      -- A view with a state for each window starts the new window from
      -- the state of the window it was split from, or of its last.
      M.within(win, function() view:on_show() end)
    end
  end
  M.enter(win)
  local ok, why = aim(name, opts.target)
  if not ok then
    paw.notify(why, "warn")
  end
  return win
end

--- Show a buffer in a window instead of the one it shows. A view on
--- screen in another window moves here. `target` is what the view opens
--- there (`roll://7`: clip 7).
function M.show_in(win: Node, name: string, buf?: integer, target?: string): Node
  local u, t = ui(), tab()
  if win.view == name and win.buf == buf then
    if target ~= nil then
      M.enter(win)
      local ok, why = aim(name, target)
      if not ok then
        paw.notify(why, "warn")
      end
    end
    return win
  end
  local old_view, old_buf = win.view, win.buf
  local before = M.buf_of(win)
  -- What `Ctrl-^` goes back to.
  win.alt = {view = old_view, buf = old_buf}
  local single_view = not M.types:get(name)
  if M.one_window(name) then
    local moved = remove_view(t.layout, name, win)
    take(name)
    if moved then
      paw.notify(called(name) .. " moved to this window")
    end
  elseif not single_view and not buf then
    buf = M.buf_create(name).id
  end
  drop_instances(win)
  win.view, win.buf, win.state, win.kept = name, not single_view and buf or nil, {}, nil
  M.buf_of(win).listed = M.buf_of(win).listed or single_view
  if old_view ~= name and not old_buf and not M.find(t.layout, old_view, true) then
    local view = u.views:get(old_view)
    if view and view.on_hide then
      view:on_hide()
    end
  end
  if single_view and old_view ~= name then
    local view = u.views:get(name)
    if view.on_show then
      M.within(win, function() view:on_show() end)
    end
  end
  reap(old_buf)
  local after = M.buf_of(win)
  if t.win == win.id and before ~= after then
    if before then
      events.emit(buf_leave, {buf = before.id, name = before.name})
    end
    if after then
      events.emit(buf_enter, {buf = after.id, name = after.name})
    end
  end
  M.enter(win)
  local ok, why = aim(name, target)
  if not ok then
    paw.notify(why, "warn")
  end
  return win
end

--- Show again what a window (the current one) showed before what it shows
--- now: Vim's alternate buffer, `Ctrl-^` and `:b#`.
function M.alternate(win?: Node): Node
  win = win or M.current()
  local alt = win and win.alt
  if not alt or not (M.types:get(alt.view) or ui().views:get(alt.view)) then
    paw.notify("this window has shown nothing else", "warn")
    return nil
  end
  -- A buffer closed since is made again, as `:e` would.
  return M.show_in(win, alt.view, alt.buf and M.buffers[alt.buf] and alt.buf or nil)
end

--- The window next to the current one in a direction ("h", "j", "k",
--- "l"), `count` steps on.
function M.neighbour(dir: string, count?: integer): Node
  local cur = M.current()
  if not cur then
    return
  end
  local rects = ui().arrange()
  local by_id: {integer: contracts.ScreenRect} = {}
  for _, r in ipairs(rects) do
    if r.win then
      by_id[r.win] = r
    end
  end
  local at = by_id[cur.id]
  for _ = 1, count or 1 do
    if not at then
      return
    end
    local best: contracts.ScreenRect
    local best_d: integer
    for _, r in ipairs(rects) do
      if r.win and r ~= at and focusable(r.name) then
        local d: integer
        local ok: boolean
        -- Beside it (a rule may stand between), and level with its top row
        -- or at least overlapping it.
        if dir == "h" or dir == "l" then
          ok = (dir == "h" and r.x + r.w <= at.x) or (dir == "l" and r.x >= at.x + at.w)
          d = dir == "h" and at.x - (r.x + r.w) or r.x - (at.x + at.w)
          local level = r.y <= at.y and at.y < r.y + r.h
          ok = ok and (r.y < at.y + at.h and at.y < r.y + r.h)
          d = d * 2 + (level and 0 or 1)
        else
          ok = (dir == "k" and r.y + r.h <= at.y) or (dir == "j" and r.y >= at.y + at.h)
          d = dir == "k" and at.y - (r.y + r.h) or r.y - (at.y + at.h)
          local level = r.x <= at.x and at.x < r.x + r.w
          ok = ok and (r.x < at.x + at.w and at.x < r.x + r.w)
          d = d * 2 + (level and 0 or 1)
        end
        if ok and (not best_d or d < best_d) then
          best, best_d = r, d
        end
      end
    end
    if not best then
      break
    end
    at = best
  end
  if at and at.win ~= cur.id then
    return M.find_id(ui().layout, at.win)
  end
end

--- Move the current window to an edge of the tab ("H", "J", "K", "L"),
--- the whole height or width of it.
function M.move_to_edge(edge: string)
  local t = tab()
  local cur = M.current()
  if not cur or #focusable_windows() < 2 then
    return
  end
  local root = t.layout
  local parent, at = parent_of(root, cur)
  if not parent then
    return
  end
  table.remove(parent, at)
  cur.size, cur.weight, cur.min, cur.float_below = nil, nil, nil, nil
  M.tidy(root)
  if edge == "K" then
    table.insert(root, 1, cur)
  elseif edge == "J" then
    root[#root + 1] = cur
  else
    local rest: Node = {dir = "v"}
    for i, child in ipairs(root) do
      rest[i] = child
    end
    for i = #root, 1, -1 do
      root[i] = nil
    end
    root[1] = edge == "H" and {dir = "h", cur, rest} or {dir = "h", rest, cur}
  end
  M.tidy(root)
  api.ui_redraw()
end

--- Exchange the current window with the next window next to it, or with the
--- window number `count`, in their row or column. When it is the last window, use the
--- previous window. The next window can be a split of several windows.
function M.exchange(count?: integer)
  local t = tab()
  local cur = M.current()
  if not cur then
    return
  end
  local parent, at = parent_of(t.layout, cur)
  if not parent then
    return
  end
  local list: {integer} = {}
  for i, child in ipairs(parent) do
    if shown(child) then
      list[#list + 1] = i
    end
  end
  local mine: integer
  for k, i in ipairs(list) do
    if i == at then
      mine = k
    end
  end
  local other = list[count or mine + 1] or list[mine - 1]
  if not other or other == at then
    return
  end
  local a, b = parent[at], parent[other]
  -- Sizes belong to the places, not to the windows.
  a.size, b.size = b.size, a.size
  a.weight, b.weight = b.weight, a.weight
  a.min, b.min = b.min, a.min
  parent[at], parent[other] = b, a
  api.ui_redraw()
end

--- Rotate the windows of the current window's row or column: each moves
--- one place on (`back`: one place back).
function M.rotate(back?: boolean)
  local t = tab()
  local cur = M.current()
  local parent = cur and parent_of(t.layout, cur)
  if not parent then
    return
  end
  local places: {integer} = {}
  for i, child in ipairs(parent) do
    if shown(child) then
      places[#places + 1] = i
    end
  end
  if #places < 2 then
    return
  end
  local nodes: {Node} = {}
  for k, i in ipairs(places) do
    nodes[k] = parent[i]
  end
  for k, i in ipairs(places) do
    local from = back and (k % #places) + 1 or ((k - 2) % #places) + 1
    parent[i] = nodes[from]
  end
  api.ui_redraw()
end

--- Move the current window to a tab of its own.
function M.to_tab(): boolean
  local cur = M.current()
  if not cur or #focusable_windows() < 2 then
    return false
  end
  local t = tab()
  local parent, at = parent_of(t.layout, cur)
  table.remove(parent, at)
  M.tidy(t.layout)
  cur.size, cur.weight, cur.min, cur.float_below = nil, nil, nil, nil
  M.tab_new(nil, nil, cur)
  return true
end

--- Give every window of the current tab an equal share, but strips that do
--- not take the keyboard.
function M.equalize()
  local function walk(node: Node)
    for _, child in ipairs(node) do
      if not (child.view and not focusable(child.view)) then
        child.size, child.weight = nil, nil
      end
      if not child.view then
        walk(child)
      end
    end
  end
  walk(ui().layout)
  api.ui_redraw()
end

--- Resize a window (the current one): `axis` "height" or "width", to `n`
--- cells, or by `n` with `relative`. It is the window's row or column in
--- the split along that axis that changes. Returns false when nothing can.
function M.resize(win: Node, axis: string, n: integer, relative?: boolean): boolean
  local u = ui()
  win = win or M.current()
  if not win then
    return false
  end
  local dir: Dir = axis == "height" and "v" or "h"
  local root = u.layout
  local node, parent: Node, Node = win, nil
  while true do
    parent = parent_of(root, node)
    if not parent then
      return false
    end
    local count = 0
    for _, child in ipairs(parent) do
      if shown(child) then
        count = count + 1
      end
    end
    if parent.dir == dir and count > 1 then
      break
    end
    node = parent
  end
  local rects = u.arrange()
  local r = rects.nodes and rects.nodes[node]
  local now = r and (axis == "height" and r.h or r.w) or node.size or 0
  local total = rects.nodes
    and rects.nodes[parent]
    and (axis == "height" and rects.nodes[parent].h or rects.nodes[parent].w) or now
  local size = relative and now + n or n
  M.set_size(node, axis, math.max(1, math.min(size, total - 1)))
  api.ui_redraw()
  return true
end

--- Set the size a node takes along its parent: a panel whose size is an
--- option (`devices_width`) has it set there.
function M.set_size(node: Node, axis: string, size: integer)
  local option = node.view and node.view .. "_" .. axis
  if option and opt[option] ~= nil then
    opt[option] = size
  else
    node.size = size
  end
end

--- The border between two windows at a cell of an arrangement
--- (`paw.ui.arrange`). This is the rule between windows side by side, or
--- the top row of a window below a different window.
function M.border_at(rects: Arrangement, x: number, y: number): Border
  for _, b in ipairs(rects.borders or {}) do
    if b.dir == "h" and x == b.x and y >= b.y and y < b.y + b.h then
      return b
    end
  end
  for _, b in ipairs(rects.borders or {}) do
    if b.dir == "v" and y == b.y and x >= b.x and x < b.x + b.w then
      return b
    end
  end
end

--- Move a border to the position of the pointer. If one of the two sides
--- has its own size, it keeps a size. If not, the first side gets a size.
--- A graphical frontend lays the tree out in pixels (paw/panes.tl):
--- `opts.unit` is its cell `{ w, h }`, and `opts.map` takes each node
--- of its arrangement to the node of the tree. Sizes stay in cells.
function M.drag_border(border: Border, rects: Arrangement, x: number, y: number, opts?: DragOptions)
  opts = opts or {}
  local nodes = rects.nodes or {}
  local a, b = nodes[border.a], nodes[border.b]
  if not (a and b) then
    return
  end
  local across = border.dir == "h"
  local start = across and a.x or a.y
  local finish = across and b.x + b.w or b.y + b.h
  local at = math.max(start + 1, math.min(across and x or y, finish - 1))
  local axis = across and "width" or "height"
  local unit = opts.unit and (across and opts.unit.w or opts.unit.h) or 1
  local first, second = border.a, border.b
  if opts.map then
    first, second = opts.map[first], opts.map[second]
  end
  if second.size and not first.size then
    M.set_size(second, axis, math.max(1, math.floor((finish - at) / unit + 0.5)))
  else
    M.set_size(first, axis, math.max(1, math.floor((at - start) / unit + 0.5)))
  end
  api.ui_redraw()
end

--- Give the current window the whole tab, or put the others back.
function M.maximize(): boolean
  local t = tab()
  if t.zoom then
    local zoom = t.zoom
    t.zoom = nil
    for _, win in ipairs(M.windows(t.layout, true)) do
      local hidden = zoom.hidden[win.id]
      if hidden ~= nil then
        win.hidden = hidden
      end
    end
    local win = M.find_id(t.layout, zoom.win)
    if win then
      win.size = zoom.size
      M.enter(win)
    end
    return false
  end
  local cur = M.current()
  if not cur then
    return
  end
  t.zoom = {win = cur.id, hidden = {}, size = cur.size}
  for _, win in ipairs(M.windows(t.layout, true)) do
    if win ~= cur and focusable(win.view) then
      t.zoom.hidden[win.id] = win.hidden == true
      win.hidden = true
    end
  end
  cur.size = nil
  M.enter(cur)
  return true
end

--- Make a tab after the current tab, and go to it. It shows a buffer (the
--- name of a view; `buf`, a buffer of a type with many) or the window
--- `win`. Without them, it shows an empty window, the start page. `target`
--- is what the view opens there (`roll://7`).
function M.tab_new(name?: string, view?: string, win?: Node, buf?: integer, target?: string): Tab
  local u = ui()
  if not win then
    view = view or "empty"
    if M.types:get(view) then
      buf = buf or M.buf_create(view).id
    end
    win = M.leaf(view, {buf = buf})
  end
  local t: Tab = {name = name, layout = {dir = "v", win}, win = win.id}
  table.insert(u.tabs, u.tab + 1, t)
  M.tab_go(u.tab + 1)
  -- A view shown in one window at a time leaves the other tabs, each left
  -- with a window (`take`).
  take(win.view)
  local ok, why = aim(win.view, target)
  if not ok then
    paw.notify(why, "warn")
  end
  return t
end

--- Open in each window of a tree what its view opens there, as it was
--- saved (`M.import` keeps it as `pending`).
local function open_pending(root: Node)
  for _, win in ipairs(M.windows(root, true)) do
    local target = win.pending
    win.pending = nil
    if target ~= nil then
      M.within(win, function(): boolean, string return aim(win.view, target) end)
    end
  end
end

--- Make a tab with the same windows as the current one, after it, and go
--- to it, the keyboard in the same kind of window. Views shown in a window
--- of each show the same state in both.
function M.tab_copy(name?: string): Tab
  local u = ui()
  local from = tab()
  local here = M.current()
  local root = M.import(M.export(from.layout, true))
  if root.view then
    root = {dir = "v", root}
  end
  M.tidy(root)
  local t: Tab = {name = name, layout = root}
  for _, win in ipairs(M.windows(root)) do
    if here and win.view == here.view then
      t.win = win.id
    end
  end
  table.insert(u.tabs, u.tab + 1, t)
  open_pending(root)
  M.tab_go(u.tab + 1)
  return t
end

--- Go to tab `i`.
function M.tab_go(i: integer): boolean
  local u = ui()
  if not u.tabs[i] then
    return false
  end
  local changed = i ~= u.tab
  u.tab = i
  u.layout = u.tabs[i].layout
  local t = u.tabs[i]
  local win = t.win and M.find_id(t.layout, t.win)
  if not (win and not win.hidden) then
    win = first_window(t.layout)
  end
  if changed then
    events.emit(tab_enter, {tab = i})
  end
  if win then
    M.enter(win)
  end
  api.ui_redraw()
  return true
end

--- Go `n` tabs on (back, when negative), round the end.
function M.tab_step(n: integer)
  local u = ui()
  M.tab_go((u.tab - 1 + n) % #u.tabs + 1)
end

--- Close tab `i` (the current tab). The last tab does not close.
function M.tab_close(i?: integer): boolean
  local u = ui()
  i = i or u.tab
  if #u.tabs < 2 or not u.tabs[i] then
    return false
  end
  local gone = table.remove(u.tabs, i)
  for _, win in ipairs(M.windows(gone.layout, true)) do
    reap(win.buf)
  end
  local go = math.min(u.tab > i and u.tab - 1 or u.tab, #u.tabs)
  u.tab = 0
  M.tab_go(go)
  return true
end

--- Move tab `i` (the current tab) to place `to` among the tabs: 1 is the
--- first. The current tab stays the current tab.
function M.tab_move(to: integer, i?: integer): boolean
  local u = ui()
  i = i or u.tab
  if not u.tabs[i] then
    return false
  end
  to = math.max(1, math.min(#u.tabs, math.floor(to)))
  local current = u.tabs[u.tab]
  table.insert(u.tabs, to, table.remove(u.tabs, i))
  for k, t in ipairs(u.tabs) do
    if t == current then
      u.tab = k
    end
  end
  api.ui_redraw()
  return true
end

--- What a tab is called: its name, else the buffer of its current window.
function M.tab_title(t: Tab): string
  if t.name then
    return t.name
  end
  local win = t.win and M.find_id(t.layout, t.win) or first_window(t.layout)
  -- A window in a scope names its tab after the scope.
  local scope = win and win.scope and paw.scope and paw.scope.current(win)
  if scope then
    return scope.name
  end
  local buf = M.buf_of(win)
  return buf and buf.name or "?"
end

-- Saved layouts -------------------------------------------------------------------

--- A window's scope stack as plain data, outermost first.
function M.scope_levels(s: contracts.Scope): {types.SavedScope}
  local out: {types.SavedScope} = {}
  while s do
    table.insert(
      out, 1, {kind = s.kind, id = s.id, tracks = s.tracks, from = s.from, to = s.to, name = s.name, clip = s.clip}
    )
    s = s.parent
  end
  return out
end
local scope_levels = M.scope_levels

--- A scope stack from its plain data: the innermost level, each naming its parent.
function M.scope_chain(levels: {types.SavedScope}): contracts.Scope
  local s: contracts.Scope
  for _, level in ipairs(levels or {}) do
    s = {
      kind = level.kind as contracts.ScopeKind,
      id = level.id,
      tracks = level.tracks,
      from = level.from,
      to = level.to,
      name = level.name,
      clip = level.clip,
      parent = s,
    }
  end
  return s
end
local scope_chain = M.scope_chain

--- A tree of windows as plain data, for `paw.layouts` and to save. With
--- `scopes`, each window's scope stack too: the project's screen keeps
--- them, a named layout does not (its tracks are another project's).
local function export(node: Node, scopes?: boolean): SpecNode
  local out: SpecNode = {size = node.size, weight = node.weight, min = node.min}
  if node.view then
    out.view, out.float_below, out.hidden = node.view, node.float_below, node.hidden or nil
    if scopes and node.scope then
      out.scope = scope_levels(node.scope)
    end
    if scopes and node.folds and #node.folds > 0 then
      out.folds = copy_folds(node.folds) as {types.SavedFold}
    end
    if scopes then
      out.foldlevel = node.foldlevel
      out.vzoom = copy(node.vzoom) as types.SavedVZoom
    end
    if node.opts and next(node.opts) then
      out.opts = copy(node.opts)
    end
    local buf = node.buf and M.buffers[node.buf]
    if buf then
      out.target = buf.target
    end
    -- What a view opens in the window (its clip), as `roll://7` names it.
    local view = not buf and ui().views:get(node.view)
    if view and view.window_target then
      local ok, target = pcall(M.within, node, function(): string | integer return view:window_target() end)
        as (boolean, string)
      if ok then
        out.target = target
      end
    end
    return out
  end
  out.dir, out.children = node.dir, {}
  for i, child in ipairs(node) do
    out.children[i] = export(child, scopes)
  end
  return out
end

M.export = export

--- The tabs and windows as plain data: what `:layout save` writes. With
--- `scopes`, the windows' scope stacks too (what the project keeps).
function M.capture(scopes?: boolean): types.SavedLayout
  local u = ui()
  local tabs: {types.SavedTab} = {}
  for i, t in ipairs(u.tabs) do
    -- Which window has the keyboard, counted in the tree's order: in a
    -- tab where none was entered yet, the one that would have it.
    local has = i == u.tab and M.current() or (t.win and M.find_id(t.layout, t.win)) or first_window(t.layout)
    local current: integer
    for k, win in ipairs(M.windows(t.layout, true)) do
      if win == has then
        current = k
      end
    end
    tabs[i] = {name = t.name, layout = export(t.layout, scopes) as types.SavedNode, current = current}
  end
  return {tab = u.tab, tabs = tabs}
end

--- A node as saved, or as a configuration writes it: `"roll"` or
--- `{ view = "roll", size = 20 }` for a window, `{ dir = "h", "arrange",
--- "roll" }` (or with `children`) for a split. Windows of views that are
--- not there (an extension not loaded) are left out.
local function import(spec: Spec): Node
  local node_spec: SpecNode
  if spec is string then
    node_spec = {view = spec}
  else
    node_spec = spec
  end
  if type(node_spec) ~= "table" then
    return nil
  end
  if node_spec.view then
    local name, _, named = M.resolve(node_spec.view)
    if not name then
      return nil
    end
    local win = M.leaf(
      name,
      {
        size = node_spec.size,
        weight = node_spec.weight,
        min = node_spec.min,
        float_below = node_spec.float_below,
        hidden = node_spec.hidden,
        opts = copy(node_spec.opts or {}),
      }
    )
    win.scope = scope_chain(node_spec.scope)
    win.folds = copy_folds(node_spec.folds as {contracts.Fold})
    win.foldlevel = node_spec.foldlevel
    win.vzoom = copy(node_spec.vzoom) as contracts.VZoom
    if M.types:get(name) then
      win.buf = M.buf_create(name, node_spec.target).id
    else
      -- What the view opens there, once the window is in a tab.
      win.pending = node_spec.target or named
    end
    return win
  end
  local node: Node = {
    dir = node_spec.dir == "h" and "h" or "v", size = node_spec.size, weight = node_spec.weight, min = node_spec.min
  }
  for _, child in ipairs(node_spec.children or node_spec as {Spec}) do
    local made = import(child)
    if made then
      node[#node + 1] = made
    end
  end
  return node
end

M.import = import

--- Put back tabs and windows from `M.capture()`'s data, or from a list of
--- tabs as a configuration writes them:
---   { { name = "Edit", layout = { dir = "h", "arrange", "roll" } }, { name = "Mix", layout = "mixer" } }
--- Returns false when it holds no window.
function M.restore(saved: SpecNode): boolean
  local u = ui()
  local tabs: {Tab} = {}
  for _, entry in ipairs(saved.tabs or saved as {Spec}) do
    local spec = entry as SpecNode
    local root = import((spec.layout or spec[1] or spec) as Spec)
    if root then
      if root.view then
        root = {dir = "v", root}
      end
      M.tidy(root)
      -- A view has one window in a tab: the first of any more.
      local seen: {string: Node} = {}
      for _, win in ipairs(M.windows(root, true)) do
        if M.one_window(win.view) then
          if seen[win.view] then
            remove_view(root, win.view, seen[win.view])
          else
            seen[win.view] = win
          end
        end
      end
      if first_window(root) then
        local current = spec.current and M.windows(root, true)[spec.current]
        tabs[#tabs + 1] = {name = spec.name, layout = root, win = current and current.id}
      end
    end
  end
  if #tabs == 0 then
    return false
  end
  -- The windows of the old tabs close: an empty window's buffer goes with
  -- its window, as when the window closes by itself.
  local old: {integer} = {}
  for _, t in ipairs(u.tabs or {}) do
    for _, win in ipairs(M.windows(t.layout, true)) do
      old[#old + 1] = win.buf
    end
  end
  u.tabs, u.tab = tabs, 0
  for _, id in ipairs(old) do
    reap(id)
  end
  local go = math.max(1, math.min(tonumber(saved.tab) or 1, #tabs)) as integer
  for _, t in ipairs(tabs) do
    open_pending(t.layout)
  end
  -- An open float keeps the keyboard: a layout put back under it (a project
  -- that another seat opened, for example) becomes where the float goes
  -- back to when it closes.
  local float = u.float
  M.tab_go(go)
  if float and u.float == float and u.focused ~= float.name then
    float.back = u.focused
    u.focused = float.name
  end
  return true
end

--- A layout as `M.restore` takes it, from any of the forms a configuration
--- writes: a view's name (`"notation"`), a tree (`{ dir = "h", "roll",
--- "notation" }`), a list of tabs, or what `M.capture` gives.
function M.as_tabs(spec: Spec): SpecNode
  if spec is string then
    return {{layout = spec}}
  end
  if type(spec) ~= "table" then
    return {}
  end
  if spec.view or spec.dir or spec.children then
    return {{layout = spec}}
  end
  return spec
end

--- The tabs and windows that the project keeps: `{ default, seats }`,
--- `seats` the layout of each kind of seat (`paw.seats.kind`), each in
--- the form `M.capture` gives. Nil when it keeps none. A project saved
--- with one layout gives it as the default.
function M.project_screen(): types.ProjectScreen
  local screen = api.project_screen()
  if type(screen) ~= "table" then
    return nil
  end
  if screen.tabs then
    return {default = screen as types.SavedLayout, seats = {}}
  end
  if type(screen.seats) ~= "table" then
    screen.seats = {}
  end
  if not (screen.default or next(screen.seats)) then
    return nil
  end
  return screen
end

--- Lay out the screen as the configuration starts it: `paw.ui.start_layout
--- = "notation"` in init.lua (any form `M.as_tabs` takes), or a named
--- layout, `paw.opt.layout = "edit"`. Without either, the screen is the
--- default tree. paw does this once its configuration has run.
function M.start()
  local start = paw.ui.start_layout
  if start ~= nil and not M.restore(M.as_tabs(start)) then
    paw.notify("paw.ui.start_layout has no window that paw can show", "warn")
  end
  local name = opt.layout
  if name and name ~= "" then
    local ok, why = M.load(name)
    if not ok then
      paw.notify(why, "warn")
    end
  end
end

M.layouts = {}

local function layout_dir(): string
  return api.env().state_dir .. "/layouts"
end
local function layout_file(name: string): string
  return layout_dir() .. "/" .. (tostring(name):gsub("[^%w%-_]", "_")) .. ".json"
end

--- Write the tabs and windows as layout `name`, in the state directory.
function M.save(name: string): boolean, string
  local file = layout_file(name)
  pcall(api.fs_mkdir, layout_dir())
  local handle = io.open(file .. ".tmp", "wb")
  if not handle then
    return false, "cannot write " .. file
  end
  handle:write(api.json_encode(M.capture(), true))
  handle:close()
  os.rename(file .. ".tmp", file)
  return true, file
end

--- Layout `name` as `M.restore` takes it: the one saved with `:layout
--- save`, else the configuration's (`paw.layouts`). Nil and the reason
--- when there is none.
function M.layout_spec(name: string): SpecNode, string
  -- A saved layout wins: the user saved it after the configuration (or
  -- the defaults) named one with the same name.
  local handle = io.open(layout_file(name), "rb")
  if not handle then
    local spec = M.layouts[name]
    if spec == nil then
      return nil, "no layout `" .. tostring(name) .. "`"
    end
    return M.as_tabs(spec)
  end
  local text = handle:read("*a")
  handle:close()
  local ok, data = pcall(api.json_decode, text) as (boolean, SpecNode)
  if not ok or type(data) ~= "table" then
    return nil, "layout `" .. tostring(name) .. "` cannot be read"
  end
  return data
end

--- Put back layout `name`: the one saved, else the configuration's.
function M.load(name: string): boolean, string
  local spec, why = M.layout_spec(name)
  if not spec then
    return false, why
  end
  if not M.restore(spec) then
    return false, "layout `" .. tostring(name) .. "` has no window"
  end
  return true
end

--- The names of the layouts there are: the configuration's and those saved.
function M.layout_names(): {string}
  local out: {string} = {}
  local seen: {string: boolean} = {}
  for name in pairs(M.layouts) do
    seen[name] = true
    out[#out + 1] = name
  end
  local ok, entries = pcall(api.read_dir, layout_dir()) as (boolean, {types.DirEntry})
  for _, entry in ipairs(ok and entries or {}) do
    local name = entry.name:match("^(.*)%.json$")
    if name and not seen[name] then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

-- Time bound windows ----------------------------------------------------------------

--- Before the windows are drawn: the current window, if it is time bound,
--- leads the others that are. Returns the window to draw first and the set
--- of windows that follow it.
function M.time_lead(): Node, {integer: boolean}
  local u = ui()
  local lead = M.current()
  if not (lead and lead.opts and lead.opts.timebind) then
    return nil
  end
  local view = u.views:get(lead.view)
  if not (view and view.time_axis) then
    return nil
  end
  local followers: {integer: boolean} = {}
  for _, win in ipairs(M.windows(u.layout)) do
    local other = u.views:get(win.view)
    if win ~= lead and win.opts and win.opts.timebind and other and other.set_time_axis then
      followers[win.id] = true
    end
  end
  if not next(followers) then
    return nil
  end
  -- Playing, the windows follow the playhead together, whichever leads.
  local t = api.transport_get()
  local left, zoom, span = view:time_axis({win = lead})
  local position = t.playing and paw.time.local_beat(t.position) or 0
  if t.playing and opt.follow and left and span and (position < left or position >= left + span) then
    view:set_time_axis(paw.time.bar_floor(position), zoom, {win = lead})
  end
  return lead, followers
end

--- Call it after paw draws the main window. The other windows take its time.
function M.time_follow(lead: Node, win: Node)
  local u = ui()
  local lead_view, view = u.views:get(lead.view), u.views:get(win.view)
  local left, zoom = M.within(lead, function(): number, number, number return lead_view:time_axis({win = lead}) end)
  if left then
    M.within(win, function() view:set_time_axis(left, zoom, {win = win}) end)
  end
end

--- Set a window option (`timebind`) on a window (the current one).
function M.set_option(win: Node, name: string, value: string | number | boolean)
  win = win or M.current()
  if not win then
    return
  end
  win.opts = win.opts or {}
  win.opts[name] = value
  events.emit(win_option, {win = win.id, name = name, value = value})
  api.ui_redraw()
end

-- The script interface ----------------------------------------------------------------

M.buf = {
  list = M.buffers_list,
  get = function(name: string | integer): Buffer local _, buf = M.resolve(name); return buf end,
  create = M.buf_create,
  delete = function(name: string | integer)
    local _, buf = M.resolve(name)
    if buf then
      M.buf_delete(buf)
    end
  end,
  current = function(): Buffer return M.buf_of(M.current()) end,
  of = M.buf_of,
  title = M.title,
}

M.win = {
  current = M.current,
  list = function(): {Node} return M.windows(ui().layout) end,
  get = M.get,
  enter = M.enter,
  split = M.split,
  close = M.close,
  only = M.only,
  show = function(win: Node, name: string | integer): Node
    local view, buf, target = M.resolve(name)
    if not view then
      error("no buffer `" .. tostring(name) .. "`", 2)
    end
    return M.show_in(win or M.current(), view, buf and not buf.single and buf.id or nil, target)
  end,
  resize = M.resize,
  equalize = M.equalize,
  maximize = M.maximize,
  option = function(win: Node, name: string, value?: string | number | boolean): string | number | boolean
    win = win or M.current()
    if value == nil then
      return win and win.opts and win.opts[name]
    end
    M.set_option(win, name, value)
  end,
  buf = M.buf_of,
}

M.tabs = {
  list = function(): {Tab} return ui().tabs end,
  current = function(): integer return ui().tab end,
  new = function(name?: string, buffer?: string): Tab
    local view = buffer and M.resolve(buffer)
    return M.tab_new(name, view)
  end,
  go = M.tab_go,
  close = M.tab_close,
  move = function(i: integer, to: integer): boolean return M.tab_move(to, i) end,
  title = M.tab_title,
}

-- Commands and keys -------------------------------------------------------------------

--- What a command of this module gets: the arguments as words.
local type Ctx = Context

--- Make the empty buffer type, the commands and the keys. Run once the
--- default commands are there, as some of these take over their short names.
function M.setup()
  local command, alias = command_registry.define, command_registry.alias
  local map = paw.keymap.set

  -- An empty window shows the start page: what `:vnew` and `:tabnew` open.
  (require as function(string))("paw.views.start")

  options.define("splitright", true)
  options.define("splitbelow", true)
  options.define("layout", "")

  local names = function(_: string, _: command_registry.Info): {string | command_registry.Candidate}
    return M.buffer_names() as {string | command_registry.Candidate}
  end

  -- What a split without a name shows, as Vim shows the same buffer: a
  -- buffer of a type with many (a text list) again, a view with a state
  -- for each window again (from where this window is); a view shown in
  -- one window at a time leaves the new window empty, on the start page.
  local function same_buffer(): string, Buffer
    local buf = M.buf_of(M.current())
    if not buf then
      return "empty"
    end
    if not buf.single or not M.one_window(buf.type) then
      return buf.type, buf
    end
    return "empty"
  end

  local function split(vertical: boolean, empty?: boolean): function(ctx: Ctx): Result
    return function(ctx: Ctx): Result
      local name = ctx.args[1]
      local view, buf, target: string, Buffer, string = "empty", nil, nil
      if name ~= nil then
        view, buf, target = M.resolve(name as string)
        if not view then
          paw.notify("no buffer `" .. tostring(name) .. "`: `:ls` lists them", "warn")
          return
        end
      elseif not empty then
        view, buf = same_buffer()
      end
      local made, why = M.split(
        {vertical = vertical, view = view, buf = buf and not buf.single and buf.id or nil, target = target}
      )
      if not made then
        paw.notify(why, "warn")
      end
    end
  end
  command(
    "split",
    split(false),
    {
      desc = "Split the window in two, one above the other, the new one showing a buffer: `sp roll`, or the same buffer without a name (the arrange view and the piano roll show each other, any other view leaves an empty window)",
      complete = names,
    }
  )
  command(
    "vsplit",
    split(true),
    {
      desc = "Split the window in two side by side, the new one showing a buffer: `vs roll`, or the same buffer without a name (see `split`)",
      complete = names,
    }
  )
  alias("sp", "split")
  alias("vs", "vsplit")
  command("vnew", split(true, true), {desc = "A new empty window beside this one"})

  local function close_window(): boolean
    if paw.ui.float then
      paw.ui.close()
      return true
    end
    -- A view in a window of the graphical frontend closes with it.
    local u = paw.ui
    local docked = M.find(u.layout, u.focused)
    if not (docked and not docked.hidden) and paw.canvas.open_views[u.focused] then
      u.close()
      return true
    end
    return M.close()
  end
  command(
    "close",
    function(): Result
      if not close_window() then
        paw.notify("the last window does not close: `:q` quits", "warn")
      end
    end,
    {desc = "Close the window; a panel's comes back where it was"}
  )
  -- A view's own name goes to it: `:arrange`, `:mixer`, `:roll`.
  for _, view in ipairs({"arrange", "mixer", "pianoroll"}) do
    local word = M.names[view] or view
    if ui().views:get(view) and not command_registry.get(word) then
      command(word, function(): Result paw.ui.focus(view) end, {desc = "Show " .. M.titles[view] .. " and go to it"})
    end
  end
  command("only", function(): Result M.only() end, {desc = "Close every window but this one"})
  -- `:q` closes the window, and quits from the last one.
  command(
    "q",
    function(): Result
      if not close_window() then
        command_registry.run("quit")
      end
    end,
    {desc = "Close the window; in the last one, quit unless there are unsaved changes"}
  )
  command(
    "q!",
    function(): Result
      if not close_window() then
        command_registry.run("quit!")
      end
    end,
    {desc = "Close the window; in the last one, quit without saving"}
  )
  -- `:e roll` shows a buffer here; `:e song` opens a project.
  command(
    "e",
    function(ctx: Ctx): Result return command_registry.run("edit", ctx.args, ctx) end,
    {
      desc = "Show a buffer in this window: `e roll`; or open a file as `open` does: `e song`, `e song.mid`, `e take.wav`",
      complete = function(text: string, info: command_registry.Info): {string | command_registry.Candidate}
        if info.index > 1 then
          return {}
        end
        local out = M.buffer_names() as {string | command_registry.Candidate}
        for _, c in ipairs(command_registry.completers:get("openable")(text)) do
          out[#out + 1] = c as command_registry.Candidate
        end
        return out
      end,
    }
  )
  -- `:e!` as in Vim: the saved project again, or another, without the unsaved work.
  paw.project.allow_discard("e")

  local function listed_step(step: integer)
    local list = M.buffers_list()
    if #list == 0 then
      return
    end
    local here = M.buf_of(M.current())
    local at = 0
    for i, buf in ipairs(list) do
      if buf == here then
        at = i
      end
    end
    local buf = list[(at - 1 + step) % #list + 1]
    if at == 0 and step < 0 then
      buf = list[#list]
    end
    M.show_in(M.current(), buf.type, not buf.single and buf.id or nil)
  end
  command(
    "buffer",
    function(ctx: Ctx): Result
      if ctx.args[1] == "#" then
        M.alternate()
        return
      end
      local view, buf, target = M.resolve(ctx.args[1] as string)
      if not view then
        paw.notify("no buffer `" .. tostring(ctx.args[1]) .. "`: `:ls` lists them", "warn")
        return
      end
      M.show_in(M.current(), view, buf and not buf.single and buf.id or nil, target)
    end,
    {
      desc = "Show a buffer in this window, by name or number: `b roll`, `b 3`; `b #` what it showed before",
      complete = names,
    }
  )
  alias("b", "buffer")
  command(
    "bnext", function(ctx: Ctx): Result listed_step(ctx.count or 1) end, {desc = "Show the next buffer in this window"}
  )
  command(
    "bprevious",
    function(ctx: Ctx): Result listed_step(-(ctx.count or 1)) end,
    {desc = "Show the previous buffer in this window"}
  )
  alias("bn", "bnext")
  alias("bp", "bprevious")
  command(
    "bdelete",
    function(ctx: Ctx): Result
      local buf: Buffer
      if ctx.args[1] ~= nil then
        local _: string
        _, buf = M.resolve(ctx.args[1] as string)
      else
        buf = M.buf_of(M.current())
      end
      if not buf then
        paw.notify("no buffer `" .. tostring(ctx.args[1]) .. "`", "warn")
        return
      end
      M.buf_delete(buf)
    end,
    {desc = "Close every window of a buffer (this one's without a name); an empty one is forgotten", complete = names}
  )
  alias("bd", "bdelete")
  command(
    "buffers",
    function(): Result
      local here = M.buf_of(M.current())
      local on_screen: {integer: boolean} = {}
      for _, t in ipairs(paw.ui.tabs) do
        for _, win in ipairs(M.windows(t.layout)) do
          local buf = M.buf_of(win)
          if buf then
            on_screen[buf.id] = true
          end
        end
      end
      local lines: {string | contracts.PageLine} = {}
      for _, buf in ipairs(M.buffers_list()) do
        local flags = (buf == here and "%" or " ") .. (on_screen[buf.id] and "a" or "h")
        lines[#lines + 1] = string.format("%3d %s  %-14s %s", buf.id, flags, buf.name, M.title(buf))
      end
      lines[#lines + 1] = {
        text = "% this window's   a in a window   h in none; `:b <name>` shows one here, `:vs <name>` beside",
        style = "Dim",
      }
      -- A project kept in a folder: its files, each a buffer that `:w`
      -- writes, `+` when it differs from the disk.
      local files = api.project_files()
      if #files > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = {text = "Files", style = "Title"}
        local changed = 0
        for _, f in ipairs(files) do
          if f.modified then
            changed = changed + 1
          end
          lines[#lines + 1] = string.format("  %s  %-10s %s", f.modified and "+" or " ", f.what, f.path)
        end
        lines[#lines + 1] = {
          text = string.format(
            "+ differs from the disk (%d); `:w` writes this window's files, `:wa` all of them", changed
          ),
          style = "Dim",
        }
      end
      paw.ui.page("Buffers", lines)
    end,
    {desc = "List the buffers"}
  )
  alias("ls", "buffers")

  command(
    "tabnew",
    function(ctx: Ctx): Result
      local name = ctx.args[1]
      local view, buf, target: string, Buffer, string
      if name ~= nil then
        view, buf, target = M.resolve(name as string)
      end
      -- `:tabnew mixer` shows the mixer in it, `:tabnew roll://7` the piano
      -- roll on clip 7; any other word names it.
      M.tab_new(
        name ~= nil and tostring(name) or nil, view or nil, nil, buf and not buf.single and buf.id or nil, target
      )
    end,
    {
      desc = "A new tab: `tabnew Mix` named, `tabnew mixer` showing the mixer, `tabnew roll://riff` the piano roll on the clip riff",
      complete = names,
    }
  )
  command(
    "tabclose",
    function(ctx: Ctx): Result
      local n = ctx.args[1] and tonumber(ctx.args[1]) as integer
      if ctx.args[1] and not (n and paw.ui.tabs[n]) then
        paw.notify("no tab " .. tostring(ctx.args[1]), "warn")
        return
      end
      if not M.tab_close(n) then
        paw.notify("the last tab does not close", "warn")
      end
    end,
    {desc = "Close the tab, or tab n: `tabclose 2`"}
  )
  -- As in Vim: `:tabmove` to the end, `:tabmove 0` to the start,
  -- `:tabmove 2` after tab 2, `:tabmove +1` and `:tabmove -1` one on or back.
  command(
    "tabmove",
    function(ctx: Ctx): Result
      local u = paw.ui
      local text = ctx.args[1] and tostring(ctx.args[1])
      local to: integer
      if not text then
        to = #u.tabs
      else
        local sign, digits = text:match("^([%+%-]?)(%d*)$")
        if not sign or (sign == "" and digits == "") then
          paw.notify("usage: tabmove, tabmove 0, tabmove 2, tabmove +1, tabmove -1", "warn")
          return
        end
        local n = tonumber(digits) as integer or 1
        if sign == "+" then
          to = u.tab + n
        elseif sign == "-" then
          to = u.tab - n
        else
          to = n < u.tab and n + 1 or n
        end
      end
      if to < 1 or to > #u.tabs then
        paw.notify("no place " .. text .. " for the tab", "warn")
        return
      end
      M.tab_move(to)
    end,
    {desc = "Move the tab: `tabmove` to the end, `tabmove 0` to the start, `tabmove 2` after tab 2, `tabmove +1`"}
  )
  command(
    "tabnext",
    function(ctx: Ctx): Result
      local n = tonumber(ctx.args[1]) as integer
      if n then
        M.tab_go(n)
        return
      end
      M.tab_step(ctx.count or 1)
    end,
    {desc = "The next tab, or tab n: `tabn 2`"}
  )
  command(
    "tabprevious",
    function(ctx: Ctx): Result M.tab_step(-((tonumber(ctx.args[1]) as integer) or ctx.count or 1)) end,
    {desc = "The previous tab"}
  )
  alias("tabn", "tabnext")
  alias("tabp", "tabprevious")
  command(
    "tabs",
    function(): Result
      local lines: {string | contracts.PageLine} = {}
      local here = M.current()
      for i, t in ipairs(paw.ui.tabs) do
        lines[#lines + 1] = {
          text = "Tab " .. i .. (t.name and " " .. t.name or "") .. (i == paw.ui.tab and "  (this one)" or ""),
          style = "Title",
        }
        for _, win in ipairs(M.windows(t.layout)) do
          local buf = M.buf_of(win)
          if buf and focusable(win.view) then
            lines[#lines + 1] = string.format("  %s %s", win == here and ">" or " ", buf.name)
          end
        end
      end
      paw.ui.page("Tabs", lines)
    end,
    {desc = "List the tabs and their windows"}
  )

  -- `:resize 20`, `:resize +5`, `:vertical resize -10`.
  local function resize(axis: string, text: string)
    local sign, digits = tostring(text or ""):match("^%s*([%+%-]?)(%d+)%s*$")
    if not digits then
      paw.notify("usage: resize 20, resize +5, resize -5", "warn")
      return
    end
    local n = tonumber(digits) as integer
    if sign == "-" then
      n = -n
    end
    if not M.resize(nil, axis, n, sign ~= "") then
      paw.notify("the window has nothing to share its " .. axis .. " with", "warn")
    end
  end
  command(
    "resize",
    function(ctx: Ctx): Result resize("height", ctx.args[1] as string) end,
    {desc = "Set the window's height, or change it: `resize 20`, `resize +5`", raw = true}
  )
  command(
    "vertical",
    function(ctx: Ctx): Result
      local rest = tostring(ctx.args[1] or ""):match("^%s*res[a-z]*%s+(.*)$")
      if not rest then
        paw.notify("usage: vertical resize 40, vertical resize +5", "warn")
        return
      end
      resize("width", rest)
    end,
    {desc = "Set the window's width, or change it: `vertical resize 40`, `vertical resize -5`", raw = true}
  )

  -- Window options: `:setlocal timebind`, `:setlocal notimebind`, `:setlocal timebind!`.
  local window_options: {string: boolean} = {timebind = true}
  command(
    "setlocal",
    function(ctx: Ctx): Result
      local word = tostring(ctx.args[1] or "")
      local name, flip = word:match("^(%a+)(!?)$")
      local value = true
      if name and name:sub(1, 2) == "no" and window_options[name:sub(3)] then
        name, value = name:sub(3), false
      end
      if not (name and window_options[name]) then
        local win = M.current()
        local text: {string} = {}
        for option in pairs(window_options) do
          text[#text + 1] = option .. "=" .. tostring(win and win.opts[option] or false)
        end
        paw.notify(table.concat(text, " "))
        return
      end
      if flip == "!" then
        value = not M.win.option(nil, name)
      end
      M.set_option(nil, name, value)
      paw.notify(name .. (value and " on" or " off") .. " in this window")
    end,
    {
      desc = "Set an option of this window: `setlocal timebind` scrolls and zooms it with the other time bound windows",
      complete = function(): {string | command_registry.Candidate} return {"timebind", "notimebind", "timebind!"} end,
    }
  )
  alias("setl", "setlocal")

  command(
    "layout",
    function(ctx: Ctx): Result
      local first, name = ctx.args[1], ctx.args[2]
      if first == nil then
        local list = M.layout_names()
        paw.notify(
          #list > 0 and "layouts: " .. table.concat(list, ", ")
            or "no layouts yet: `:layout save <name>` keeps the tabs and windows as they are"
        )
        return
      end
      if first == "save" then
        if name == nil then
          paw.notify("usage: layout save <name>", "warn")
          return
        end
        local ok, where = M.save(tostring(name))
        paw.notify(ok and "layout " .. tostring(name) .. " saved" or where, ok and "info" or "error")
        return
      end
      local ok, why = M.load(tostring(first))
      if not ok then
        paw.notify(why, "warn")
      end
    end,
    {
      desc = "Put back a layout of tabs and windows: `layout edit`; `layout save edit` keeps the one now",
      complete = function(_: string, info: command_registry.Info): {string | command_registry.Candidate}
        if info.index == 2 and info.words[1] == "save" then
          return M.layout_names() as {string | command_registry.Candidate}
        end
        if info.index > 1 then
          return {}
        end
        local out: {string | command_registry.Candidate} = {
          {text = "save", desc = "keep the tabs and windows as they are"}
        }
        for _, name in ipairs(M.layout_names()) do
          out[#out + 1] = name
        end
        return out
      end,
    }
  )

  local acts: {string: function(ctx: Ctx)} = {
    s = function() split(false)({args = {}}) end,
    v = function() split(true)({args = {}}) end,
    n = function() split(false, true)({args = {}}) end,
    c = function() command_registry.run("close") end,
    q = function() command_registry.run("q") end,
    o = function() M.only() end,
    x = function(ctx: Ctx) M.exchange(ctx.count) end,
    r = function() M.rotate(false) end,
    R = function() M.rotate(true) end,
    T = function()
      if not M.to_tab() then
        paw.notify("the only window is a tab already", "warn")
      end
    end,
    p = function()
      local t = tab()
      local win = t.prev and M.find_id(t.layout, t.prev)
      if win and not win.hidden and focusable(win.view) then
        M.enter(win)
      end
    end,
  }
  for _, dir in ipairs({"h", "j", "k", "l"}) do
    acts[dir] = function(ctx: Ctx)
      local win = M.neighbour(dir, ctx.count)
      if win then
        M.enter(win)
      end
    end
    acts[dir:upper()] = function() M.move_to_edge(dir:upper()) end
  end
  command(
    "wincmd",
    function(ctx: Ctx): Result
      local act = acts[tostring(ctx.args[1] or "")]
      if not act then
        paw.notify("usage: wincmd h, wincmd s, ... (what follows Ctrl-w)", "warn")
        return
      end
      act(ctx)
    end,
    {desc = "Do what Ctrl-w and a key do: `wincmd l` goes to the window on the right"}
  )

  local keys: {{string}} = {
    {"s", "Split the window, one above the other"},
    {"v", "Split the window, side by side"},
    {"n", "A new empty window above or below"},
    {"h", "The window on the left"},
    {"j", "The window below"},
    {"k", "The window above"},
    {"l", "The window on the right"},
    {"H", "Move the window to the far left"},
    {"J", "Move the window to the bottom"},
    {"K", "Move the window to the top"},
    {"L", "Move the window to the far right"},
    {"x", "Exchange the window with the next one"},
    {"r", "Rotate the windows of the row or column"},
    {"R", "Rotate them the other way"},
    {"T", "Move the window to a tab of its own"},
    {"p", "The window that had the keyboard before"},
    {"c", "Close the window"},
    {"q", "Close the window; in the last one, quit"},
    {"o", "Close every other window"},
  }
  for _, k in ipairs(keys) do
    map("<C-w>" .. k[1], "wincmd " .. k[1], {desc = k[2]})
  end
  map("<C-w>w", "view.next", {desc = "The next window"})
  map("<C-w>W", "view.prev", {desc = "The previous window"})
  map("<C-w>|", "view.maximize", {desc = "Give the window the whole tab, or put the others back"})
  map("gt", "tabnext", {desc = "The next tab"})
  map("gT", "tabprevious", {desc = "The previous tab"})

  -- The project keeps the tabs and windows of each kind of seat (the
  -- graphical window, a terminal: `paw.seats.kind`), and a default: those
  -- of the seat that saved it. Opening it gives each seat its own, else
  -- the default. A project saved before keeps one layout, the default.
  options.define("project_screen", true)
  events.on(
    project_saving,
    function()
      if not opt.project_screen then
        return
      end
      -- The fields that other modules keep there stay (the workspaces of
      -- paw/workspace.tl), also when the project has no layout yet.
      local screen = M.project_screen() or api.project_screen() or {}
      screen.seats = screen.seats or {}
      screen.default = M.capture(true)
      screen.seats[seats.kind()] = screen.default
      -- The other seats open now keep theirs too.
      for _, id in ipairs(seats.list()) do
        if id ~= seats.current then
          screen.seats[seats.kind(id)] = seats.within(id, M.capture, true)
        end
      end
      api.project_screen_set(screen)
    end
  )
  events.on(
    kernel.project_loaded,
    function()
      -- The scopes, folds and heights were the last project's: its
      -- tracks and regions.
      local function wide()
        for _, tw in ipairs(M.all_windows()) do
          tw.win.scope, tw.win.folds, tw.win.foldlevel, tw.win.vzoom = nil, nil, nil, nil
        end
      end
      for _, id in ipairs(seats.list()) do
        if id == seats.current then
          wide()
        else
          seats.within(id, wide)
        end
      end
      if not opt.project_screen then
        return
      end
      local screen = M.project_screen()
      if not screen then
        return
      end
      for _, id in ipairs(seats.list()) do
        local mine = screen.seats[seats.kind(id)] or screen.default
        if mine then
          if id == seats.current then
            M.restore(mine as SpecNode)
          else
            seats.within(id, M.restore, mine as SpecNode)
          end
        end
      end
    end
  )
  -- A seat that opens after the project did (a window attached to it)
  -- takes the layout that the project keeps for its kind, if any.
  events.on(
    seat_opened,
    function(event: SeatOpened)
      if not opt.project_screen then
        return
      end
      local screen = M.project_screen()
      local mine = screen and screen.seats[seats.kind(event.seat)]
      if mine then
        paw.defer(function() seats.within(event.seat, M.restore, mine as SpecNode) end)
      end
    end
  )

  events.on(events.startup, function() M.start() end)
end

return M
