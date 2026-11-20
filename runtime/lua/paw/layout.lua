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
local api = paw.api
local M = {
  types = {},      -- buffer types made with `paw.buftype`, by name
  buffers = {},    -- every buffer, by number
  homes = {},      -- where a docked view goes when no window has it: { side, size, weight, min, float_below }
  -- Short names for the buffers of built-in views, to type after `:vs`,
  -- and what they are called in lists.
  names = { pianoroll = "roll" },
  -- What a docked view's pane is called, where the view has no title of its own.
  pane_titles = {
    arrange = "Arrange", pianoroll = "Piano roll", mixer = "Mixer", devices = "Devices",
  },
  titles = {
    arrange = "the arrange view", pianoroll = "the piano roll", mixer = "the mixer", devices = "the device panel",
    eventlist = "the event list", help = "keys", empty = "an empty window",
  },
}
local by_view = {}   -- view name -> its buffer
local next_win, next_buf = 0, 0

-- The smallest window a split leaves, and the smallest that is drawn.
M.min_width, M.min_height = 10, 3

local function ui() return paw.ui end

local function focusable(name)
  local view = ui().views[name]
  return view ~= nil and view.focusable ~= false
end

local function copy(value) return paw.seats.copy(value) end

--- A new window that shows `view`, with fields such as `size` or `hidden`.
function M.leaf(view, fields)
  next_win = next_win + 1
  local win = { view = view, id = next_win, opts = {}, state = {} }
  for k, v in pairs(fields or {}) do win[k] = v end
  return win
end

--- The tree that paw starts with when the configuration names no start
--- layout (`paw.ui.start_layout`): the arrange view, and the panels' places
--- next to it, closed. Nothing else depends on it: any view can be alone
--- in a tab.
function M.default_tree()
  return {
    dir = "v",
    { dir = "h", M.leaf("arrange"), M.leaf("devices", { size = 40, hidden = true, float_below = 80 }) },
    M.leaf("pianoroll", { hidden = true, weight = 2 }),
    M.leaf("mixer", { weight = 0.5, min = 14, hidden = true }),
  }
end

M.homes.devices = { side = "right", size = 40, float_below = 80 }
M.homes.pianoroll = { side = "bottom", weight = 2 }
M.homes.mixer = { side = "bottom", weight = 0.5, min = 14 }

-- The tree ----------------------------------------------------------------------

--- True if a node takes space: a window that is not hidden, or a node with such a window.
local function shown(node)
  if node.hidden then return false end
  if node.view then return true end
  for _, child in ipairs(node) do
    if shown(child) then return true end
  end
  return false
end
M.shown = shown

--- The windows of a tree in order, the hidden ones too with `all`. A window
--- made by code that only gave it a view gets what a window has.
function M.windows(root, all)
  local out = {}
  local function walk(node)
    if node.view then
      if not node.id then
        next_win = next_win + 1
        node.id, node.opts, node.state = next_win, node.opts or {}, node.state or {}
      end
      if all or not node.hidden then out[#out + 1] = node end
      return
    end
    for _, child in ipairs(node) do walk(child) end
  end
  walk(root or ui().layout)
  return out
end

--- The split that contains `target` in the tree under `node`, and its place there.
local function parent_of(node, target)
  for i, child in ipairs(node) do
    if child == target then return node, i end
    if not child.view then
      local parent, at = parent_of(child, target)
      if parent then return parent, at end
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
M.keepers = {}    -- view name -> { { key, get, set, fresh } }
local bound = {}  -- view name -> the window whose state is in the view's table now
-- Windows that are in no tab: a view in a window of its own in a graphical
-- frontend (paw/canvas.tl). Each has a state of its own, as a window of a
-- tab has.
local loose = setmetatable({}, { __mode = "k" })
paw.seats.keep("layout.bound", function() return bound end, function(b) bound = b end, function() return {} end)

--- Keep some state of a view for each window. `get()` gives it (one
--- value), `set(value)` puts it back, `fresh(value)` gives what a new
--- window starts with from the value of the window it is split from.
--- `key` names it: the same key again (a module loaded again) replaces it.
function M.window_keep(name, get, set, fresh, key)
  local list = M.keepers[name] or {}
  M.keepers[name] = list
  local entry = { key = key, get = get, set = set, fresh = fresh or function(v) return v end }
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
function M.window_fields(name, tbl, keys, fresh, key)
  local without = {}
  for _, key in ipairs(fresh or {}) do without[key] = true end
  M.window_keep(name,
    function()
      local out = {}
      for i, key in ipairs(keys) do out[i] = tbl[key] end
      return out
    end,
    function(values)
      for i, key in ipairs(keys) do tbl[key] = values[i] end
    end,
    function(values)
      local out = {}
      for i, key in ipairs(keys) do
        local v = values[i]
        if without[key] then
          v = nil
        elseif type(v) == "table" then
          -- A list or a set of the window's own, not shared with the other.
          local copied = {}
          for k, x in pairs(v) do copied[k] = x end
          v = copied
        end
        out[i] = v
      end
      return out
    end, key or "fields")
end

--- True if a view is shown in one window at a time: a view without a
--- state for each window. A buffer type is not.
function M.one_window(name)
  return not M.types[name] and not M.keepers[name]
end

--- Put the state of `win` in the table of its view, and keep the state of
--- the window before. A window new to the view starts from that state
--- (`fresh`). Nothing happens for a view with one state.
function M.bind(win)
  local name = win and win.view
  local keep = name and M.keepers[name]
  if not keep or bound[name] == win then return end
  local was = bound[name]
  local now = {}
  for i, k in ipairs(keep) do now[i] = k.get() end
  local saved = win.kept
  -- The window before went (another layout, a closed tab) or shows
  -- another view now: what the table holds is the view's latest state,
  -- and this window takes it.
  if was and (was.view ~= name or not (loose[was] or M.get(was.id))) then was, saved = nil, nil end
  if was then
    was.kept = now
    if not saved then
      saved = {}
      for i, k in ipairs(keep) do saved[i] = k.fresh(now[i]) end
    end
  else
    -- The first window takes the state that the table has.
    saved = saved or now
  end
  for i, k in ipairs(keep) do k.set(saved[i]) end
  win.kept = nil
  bound[name] = win
end

--- The window whose state the table of a view holds now, if any.
function M.bound(name) return bound[name] end

--- A window in no tab for the view `name`: a view in a window of its own
--- of a graphical frontend. It starts from the state of the window `from`
--- (the pane that it leaves), else of the window whose state the view
--- holds now. It keeps its own state from then on.
function M.loose(name, from)
  if from and from.view == name then M.bind(from) end
  local win = M.leaf(name)
  loose[win] = true
  M.bind(win)
  return win
end

--- True if a window of this number is in a tab of the seat, or is a
--- window in no tab (`M.loose`) that is still in use.
function M.alive(id)
  if M.get(id) then return true end
  for win in pairs(loose) do
    if win.id == id then return true end
  end
  return false
end

--- Give the state of the window `from` to the window `to` of the same
--- view, in place of its own: a view in a window of its own that returns
--- into its pane takes what it showed there.
function M.hand_over(from, to)
  if not (from and to and from.view == to.view and M.keepers[from.view]) then return end
  M.bind(from)
  to.kept = nil
  bound[from.view] = to
end

local function pack(...) return { n = select("#", ...), ... } end

--- Run `fn(...)` with the state of `win` in its view's table, then put
--- back the state that was there.
function M.within(win, fn, ...)
  local name = win and win.view
  local before = name and bound[name]
  if not (name and M.keepers[name]) or before == win then return fn(...) end
  M.bind(win)
  local result = pack(pcall(fn, ...))
  if before then M.bind(before) end
  if not result[1] then error(result[2], 0) end
  return unpack(result, 2, result.n)
end

--- After a window drew or took the pointer: each view's table holds the
--- state of its window in the current tab that had the keyboard last, so
--- that keys and commands act there.
function M.settle()
  local u = ui()
  local t = u.tabs and u.tabs[u.tab]
  if not t then return end
  local canvas = paw.canvas
  for name in pairs(M.keepers) do
    -- A view in a window of its own of a graphical frontend, which has
    -- the keyboard there.
    local own = canvas and canvas.open_views[name]
    own = own and own.win
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
    if win then M.bind(win) end
  end
end

--- A copy of a seat's tabs for a new seat: the windows keep their places
--- and options, and start from that seat's state.
function M.copy_tabs(tabs)
  local function walk(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do
      if k ~= "kept" then out[k] = walk(v) end
    end
    return out
  end
  return walk(tabs)
end

--- The window of a view in a tree, one on screen first: the window with
--- the keyboard, else the one whose state the view holds, else the one
--- that had the keyboard last. With `shown`, only one on screen.
function M.find(root, name, shown)
  local u = ui()
  local t = u.tabs and u.tabs[u.tab]
  local prefer = {}
  if t and t.layout == root then
    prefer[#prefer + 1] = t.win or false
    prefer[#prefer + 1] = t.last and t.last[name] or false
  end
  prefer[#prefer + 1] = bound[name] and bound[name].id or false
  local all = M.windows(root, true)
  for _, id in ipairs(prefer) do
    for _, win in ipairs(all) do
      if id and win.id == id and win.view == name and not win.hidden then return win end
    end
  end
  local hidden
  for _, win in ipairs(all) do
    if win.view == name then
      if not win.hidden then return win end
      hidden = hidden or win
    end
  end
  if not shown then return hidden end
end

--- A window by its number, and the tab it is in.
function M.get(id)
  local u = ui()
  for _, win in ipairs(M.windows(u.layout, true)) do
    if win.id == id then return win, u.tab end
  end
  for i, tab in ipairs(u.tabs) do
    for _, win in ipairs(M.windows(tab.layout, true)) do
      if win.id == id then return win, i end
    end
  end
end

--- Turn a tab's tree into one stacked in rows at the top, in place: the
--- table stays the one the tab and `paw.ui.layout` hold.
local function to_rows(root)
  if root.dir == "v" then return end
  local inner = { dir = root.dir }
  for i, child in ipairs(root) do inner[i] = child end
  for i = #root, 1, -1 do root[i] = nil end
  root.dir, root[1] = "v", inner
end

--- Take out nodes left empty and nodes left with one child (which takes its
--- place and its size).
local function tidy(node)
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
function M.tidy(root)
  tidy(root)
  to_rows(root)
end

--- Take a view's window (a view has one) out of a tree, but `keep`.
--- Returns whether one that was on screen went.
local function remove_view(root, name, keep)
  local was_shown = false
  local function walk(node)
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
local function keyboard_in(root)
  local u = ui()
  local t = u.tabs and u.tabs[u.tab]
  if t and t.layout == root and t.win then
    for _, win in ipairs(M.windows(root)) do
      if win.id == t.win then return win end
    end
  end
  for _, win in ipairs(M.windows(root)) do
    if focusable(win.view) then return win end
  end
end

--- Put a window for a docked view where it docks: on its side of the
--- window that has the keyboard, as a split in Neovim is.
local function place_home(root, name, home, hidden)
  local win = M.leaf(name, { size = home.size, weight = home.weight, min = home.min, float_below = home.float_below, hidden = hidden })
  local side = home.side or "bottom"
  local dir = (side == "left" or side == "right") and "h" or "v"
  local before = side == "left" or side == "top"
  local cur = keyboard_in(root)
  local parent, at
  if cur then parent, at = parent_of(root, cur) end
  if not parent then
    -- Nothing to stand beside: along that side of the tab.
    if dir == "h" then
      local row = { dir = "h" }
      for i, child in ipairs(root) do row[i] = child end
      for i = #root, 1, -1 do root[i] = nil end
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
    local node = { dir = dir, size = cur.size, weight = cur.weight, min = cur.min }
    cur.size, cur.weight, cur.min = nil, nil, nil
    node[1], node[2] = before and win or cur, before and cur or win
    parent[at] = node
  end
  return win
end

--- Dock a view in the current tab and remember the place for other tabs.
--- See `paw.ui.dock`.
function M.dock(name, opts)
  local home = { side = opts.side or "bottom", size = opts.size, weight = opts.weight, min = opts.min }
  M.homes[name] = home
  local root = ui().layout
  remove_view(root, name)
  place_home(root, name, home, opts.hidden)
  M.tidy(root)
end

-- Buffers -----------------------------------------------------------------------

--- A view's buffer: every view has one.
local function single(name)
  local buf = by_view[name]
  if not buf and ui().views[name] and not M.types[name] then
    next_buf = next_buf + 1
    local view = ui().views[name]
    buf = { id = next_buf, name = view.bufname or M.names[name] or name, type = name, single = true, listed = true }
    M.buffers[buf.id] = buf
    by_view[name] = buf
  end
  return buf
end

--- The buffer a window shows.
function M.buf_of(win)
  if not win then return nil end
  if win.buf then return M.buffers[win.buf] end
  return single(win.view)
end

--- A buffer of a type for a target, made if there is none. A view's type
--- has one buffer, whatever the target.
function M.buf_create(type_name, target)
  local def = M.types[type_name]
  if not def then return single(type_name) end
  if target ~= nil then
    for _, buf in pairs(M.buffers) do
      if buf.type == type_name and buf.target == target then return buf end
    end
  end
  next_buf = next_buf + 1
  local buf = { id = next_buf, type = type_name, target = target, listed = def.listed ~= false, options = copy(def.options or {}) }
  buf.name = def.bufname and def.bufname(target, buf) or (target ~= nil and type_name .. "://" .. tostring(target)) or type_name
  M.buffers[buf.id] = buf
  buf.state = def.create and def.create(target, buf) or {}
  return buf
end

--- The type and the buffer of a name. The name is the name or the number of
--- a buffer, or the name or the short name of a view (`roll`). It can also
--- be a type with a target (`type://target`). Nil when the name is not known.
function M.resolve(name)
  if name == nil then return nil end
  local number = tonumber(name)
  if number then
    local buf = M.buffers[number]
    return buf and buf.type, buf
  end
  name = tostring(name)
  for _, buf in pairs(M.buffers) do
    if buf.name == name then return buf.type, buf end
  end
  for view, short in pairs(M.names) do
    if short == name and ui().views[view] then return view, single(view) end
  end
  local views = ui().views
  for view, def in pairs(views) do
    if def.bufname == name then return view, single(view) end
  end
  if M.types[name] then return name, M.buf_create(name) end
  if views[name] and views[name].focusable ~= false then return name, single(name) end
  -- A type may take names of its own form as targets (`paw://lane/3`).
  for type_name, def in pairs(M.types) do
    if def.claims and def.claims(name) then return type_name, M.buf_create(type_name, name) end
  end
  local kind, target = name:match("^([%w_]+)://(.*)$")
  if kind and M.types[kind] then return kind, M.buf_create(kind, target ~= "" and target or nil) end
  -- A view that opens a thing of its own in its window (`roll://7`, the
  -- piano roll on clip 7): the view, and what to open, for `open_target`.
  local view = kind and target ~= "" and M.view_named(kind)
  if view and views[view].open_target then return view, single(view), target end
end

--- The view a name or a short name (`roll`) stands for, or nil.
function M.view_named(name)
  local views = ui().views
  for view, short in pairs(M.names) do
    if short == name and views[view] then return view end
  end
  if views[name] and views[name].focusable ~= false and not M.types[name] then return name end
end

--- The clip a name of a window's thing stands for: an id (`7`), an
--- address (`paw://clip/7`) or the name of a clip, the first in the order
--- of the tracks. Nil if there is none.
function M.clip_named(target)
  local id = tonumber(target) or tonumber(tostring(target):match("^paw://clip/(%d+)"))
  if id then return pcall(api.clip_get, id) and paw.clip(id) or nil end
  for _, track in ipairs(api.track_list()) do
    for _, c in ipairs(api.clip_list(track)) do
      if c.name == target then return paw.clip(c.id) end
    end
  end
end

--- Open `target` in a window that shows the view `name`, by the view's
--- `open_target(target)`: false and why when it cannot.
local function aim(name, target)
  if target == nil then return true end
  local view = ui().views[name]
  if not (view and view.open_target) then return false, name .. " opens nothing by name" end
  local ok, why = view:open_target(target)
  if ok == false then return false, why or ("nothing called `" .. tostring(target) .. "`") end
  api.ui_redraw()
  return true
end

--- The buffers to list (`:ls`), by number: the views' that are in the
--- layout or docked, and every other made since and not deleted.
function M.buffers_list()
  local u = ui()
  for _, tab in ipairs(u.tabs) do
    for _, win in ipairs(M.windows(tab.layout, true)) do M.buf_of(win) end
  end
  for name in pairs(M.homes) do
    if u.views[name] then single(name) end
  end
  local out = {}
  for _, buf in pairs(M.buffers) do
    if buf.listed then out[#out + 1] = buf end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

--- Names to complete after `:b`, `:e`, `:sp`, `:vs`: every buffer's and
--- every view's that can be shown.
function M.buffer_names()
  local out, seen = {}, {}
  local function add(name, desc)
    if not seen[name] then
      seen[name] = true
      out[#out + 1] = { text = name, desc = desc }
    end
  end
  for _, buf in ipairs(M.buffers_list()) do add(buf.name, M.title(buf)) end
  for name, view in pairs(ui().views) do
    if view.focusable ~= false and not M.types[name] then add(view.bufname or M.names[name] or name, view.title) end
  end
  table.sort(out, function(a, b) return a.text < b.text end)
  return out
end

--- What a buffer is called on screen.
function M.title(buf)
  local def = M.types[buf.type]
  if def and def.title then
    local ok, text = pcall(def.title, buf)
    if ok and text then return tostring(text) end
  end
  local view = ui().views[buf.type]
  -- A view's title may say what it shows now (`view:title_of()`).
  if view and view.title_of then
    local ok, text = pcall(view.title_of, view)
    if ok and text then return tostring(text) end
  end
  return view and view.title or M.pane_titles[buf.type] or M.titles[buf.type] or buf.name
end

--- A view's buffer's name, for messages.
local function called(name)
  local buf = by_view[name]
  return buf and buf.name or M.names[name] or name
end

--- Forget a buffer that no window shows any more, if it is one to forget:
--- an unlisted one (an empty window's).
local function reap(id)
  local buf = id and M.buffers[id]
  if not buf or buf.listed then return end
  for _, tab in ipairs(ui().tabs) do
    for _, win in ipairs(M.windows(tab.layout, true)) do
      if win.buf == id then return end
    end
  end
  M.buffers[id] = nil
end

--- Delete a buffer (`:bd`): its windows close, and a buffer of a type that
--- has more than one is forgotten. A view's buffer stays, as the view does.
function M.buf_delete(buf)
  for _, tab_win in ipairs(M.all_windows()) do
    local win = tab_win.win
    if (buf.single and win.view == buf.type and not win.buf) or win.buf == buf.id then
      if not win.hidden then
        if not M.close(win) then M.show_in(win, "empty") end
      end
    end
  end
  if buf.single then
    buf.listed = false
  else
    local def = M.types[buf.type]
    if def and def.delete then def.delete(buf) end
    M.buffers[buf.id] = nil
    for _, tab in ipairs(ui().tabs) do
      local function walk(node)
        for i = #node, 1, -1 do
          local child = node[i]
          if child.view then
            if child.buf == buf.id then table.remove(node, i) end
          else
            walk(child)
          end
        end
      end
      walk(tab.layout)
      M.tidy(tab.layout)
    end
  end
  api.ui_redraw()
end

--- Close the windows of buffers whose target is gone, as when another
--- project is opened (a window with `paw://lane/9` in it): a type says so
--- with `alive(buf)`. A window that cannot close, the last one, is left empty.
function M.drop_dead()
  local dead = {}
  for _, buf in pairs(M.buffers) do
    local def = M.types[buf.type]
    if def and def.alive and not buf.single and not def.alive(buf) then dead[#dead + 1] = buf end
  end
  for _, buf in ipairs(dead) do M.buf_delete(buf) end
end
paw.on("project.loaded", function() M.drop_dead() end)

-- Buffer types ----------------------------------------------------------------

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
--- @type function<B is contracts.Buftype>(name: string, def: B): B
function M.buftype(name, def)
  def.name = name
  M.types[name] = def
  local function win_of(ctx)
    if ctx and ctx.win then return ctx.win end
    local current = M.current()
    if current and current.view == name then return current end
    for _, win in ipairs(M.windows(ui().layout)) do
      if win.view == name then return win end
    end
    if def.window then return def.window() end
  end
  -- The keymap, the drawing and the mouse reach a type through a view of
  -- its name, as they reach every view.
  ui().views[name] = {
    name = name, buftype = def, window = false, modal = def.modal,
    render = function(_, canvas, ctx)
      local win = win_of(ctx)
      if not win then return end
      ctx = paw.util.merge(ctx or {}, { win = win, buf = M.buf_of(win) })
      if def.render then return def.render(win, canvas, ctx) end
    end,
    on_key = function(_, key)
      local win = win_of()
      if win and def.on_key then return def.on_key(win, key) end
    end,
    on_mouse = function(_, event)
      local win = event.win and M.get(event.win) or win_of()
      if win and def.on_mouse then return def.on_mouse(win, event) end
    end,
    time_axis = def.time and function(_, ctx) return def.time.get(win_of(ctx)) end,
    set_time_axis = def.time and function(_, left, zoom, ctx) return def.time.set(win_of(ctx), left, zoom) end,
    help = def.help,
    describe = def.describe and function() return def.describe(win_of()) end,
    status = def.status and function(_, ctx) return def.status(win_of(), ctx) end,
    subscope = def.subscope and function() return def.subscope(win_of()) end,
    paint = def.paint and function(_, g, ctx) return def.paint(win_of(ctx), g, ctx) end,
    pointer = def.pointer and function(_, e) return def.pointer(win_of(), e) end,
  }
  local view = ui().views[name]
  if type(def.grid) == "function" then
    -- The grid of the window with the keys, asked for each time.
    view.grid = setmetatable({}, { __index = function(_, key)
      local win = win_of()
      local g = win and def.grid(win)
      return g and g[key]
    end })
  elseif def.grid then
    view.grid = def.grid
  end
  M.powers(name, def, function(fn)
    return function(ctx, ...)
      local win = win_of()
      ctx = ctx or {}
      ctx.win, ctx.buf = win, win and M.buf_of(win)
      return fn(ctx, ...)
    end
  end)
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
function M.powers(scope, def, wrap)
  local keymap = paw.keymap
  wrap = wrap or function(fn) return fn end
  local function each(list, how)
    for lhs, entry in pairs(list or {}) do
      local rhs, opts = entry, { view = scope }
      if type(entry) == "table" then
        rhs = entry[1]
        for k, v in pairs(entry) do
          if k ~= 1 then opts[k] = v end
        end
      end
      how(lhs, rhs, opts)
    end
  end
  each(def.keymaps, function(lhs, rhs, opts)
    keymap.set(lhs, type(rhs) == "function" and wrap(rhs) or rhs, opts)
  end)
  each(def.motions, function(lhs, rhs, opts)
    opts.motion = true
    keymap.set(lhs, type(rhs) == "function" and wrap(rhs) or rhs, opts)
  end)
  each(def.textobjects, function(lhs, fn, opts) keymap.textobject(lhs, wrap(fn), opts) end)
  -- An operator's function gets the region first, and `ctx` second.
  each(def.operators, function(lhs, fn, opts)
    local wrapped = wrap(function(ctx, region) return fn(region, ctx) end)
    keymap.operator(lhs, function(region, ctx) return wrapped(ctx, region) end, opts)
  end)
end

-- Tabs and the current window ---------------------------------------------------

--- The current tab.
local function tab() local u = ui() return u.tabs[u.tab] end
M.tab = tab

--- Every window of every tab, as `{ win, tab }`.
function M.all_windows()
  local out = {}
  for i, t in ipairs(ui().tabs) do
    for _, win in ipairs(M.windows(t.layout, true)) do out[#out + 1] = { win = win, tab = i } end
  end
  return out
end

local function first_window(root)
  for _, win in ipairs(M.windows(root)) do
    if focusable(win.view) then return win end
  end
end

--- The window that has the keyboard, in the current tab. This is the last
--- window entered, or the window of the focused view when paw gave focus by
--- the name of the view.
function M.current()
  local u, t = ui(), tab()
  local win = t.win and M.find_id(t.layout, t.win)
  if win and win.hidden then win = nil end
  if not (win and win.view == u.focused) then
    local named = u.focused and M.find(t.layout, u.focused)
    if named and not named.hidden then win = named end
  end
  win = win or first_window(t.layout)
  if win and t.win ~= win.id then t.prev, t.win = t.win, win.id end
  return win
end

--- The window of an id in the tree under `root`.
function M.find_id(root, id)
  for _, win in ipairs(M.windows(root, true)) do
    if win.id == id then return win end
  end
end

--- Make a window the current one and give it the keyboard.
function M.enter(win)
  local u, t = ui(), tab()
  local old = M.current()
  if old ~= win then
    local old_buf, new_buf = M.buf_of(old), M.buf_of(win)
    if old then paw.emit("win.leave", { win = old.id }) end
    if old_buf and old_buf ~= new_buf then paw.emit("buf.leave", { buf = old_buf.id, name = old_buf.name }) end
    t.prev, t.win = old and old.id, win.id
    paw.emit("win.enter", { win = win.id })
    if new_buf and old_buf ~= new_buf then paw.emit("buf.enter", { buf = new_buf.id, name = new_buf.name }) end
  end
  -- The view's table holds this window's state while it has the keyboard.
  M.bind(win)
  -- A view in a window of its own no longer has the keyboard there.
  if paw.canvas then paw.canvas.inside = nil end
  t.last = t.last or {}
  t.last[win.view] = win.id
  if u.focused ~= win.view then
    local before = u.focused
    u.focused = win.view
    paw.emit("view.focused", { view = win.view, old = before })
  end
  api.ui_redraw()
end

--- Hide a single view's windows in the tabs other than the current one: it
--- is shown in one window at a time.
local function take(name)
  local u = ui()
  if not M.one_window(name) then return end
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
function M.reveal(name, go)
  local u = ui()
  local t = tab()
  local win = M.find(t.layout, name)
  if win and not win.hidden then return win end
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
    if not home then return nil end
    win = place_home(t.layout, name, home)
    M.tidy(t.layout)
  end
  win.hidden = false
  take(name)
  local buf = single(name)
  if buf then buf.listed = true end
  local view = u.views[name]
  if view and view.on_show then view:on_show() end
  api.ui_redraw()
  return win
end

--- Hide the windows of a view in each tab, but the last window of a tab,
--- which stays. Returns true if one that was on the screen went.
function M.conceal(name)
  local was = false
  for _, t in ipairs(ui().tabs) do
    for _, win in ipairs(M.windows(t.layout)) do
      if win.view == name and not win.buf then
        win.hidden = true
        if first_window(t.layout) then was = true else win.hidden = false end
      end
    end
  end
  return was
end

--- The windows of the current tab that take the keyboard.
local function focusable_windows()
  local out = {}
  for _, win in ipairs(M.windows(ui().layout)) do
    if focusable(win.view) then out[#out + 1] = win end
  end
  return out
end
M.focusable_windows = focusable_windows

--- Close a window. The window of a view keeps its place, hidden. Other
--- windows go. The last window of a tab closes the tab. The last window of
--- all does not close. Returns true if it closed.
function M.close(win)
  local u, t = ui(), tab()
  win = win or M.current()
  if not win then return false end
  local others = 0
  for _, w in ipairs(focusable_windows()) do
    if w ~= win then others = others + 1 end
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
  local again = M.keepers[win.view] and not win.buf
  if again then
    again = false
    for _, w in ipairs(M.windows(t.layout, true)) do
      if w ~= win and w.view == win.view then again = true end
    end
  end
  if win.buf or again then
    local parent, at = parent_of(t.layout, win)
    if parent then table.remove(parent, at) end
    M.tidy(t.layout)
    reap(win.buf)
    if bound[win.view] == win then bound[win.view] = nil end
  else
    win.hidden = true
    local view = u.views[win.view]
    if view and view.on_hide then view:on_hide() end
  end
  if t.zoom and t.zoom.win == win.id then t.zoom = nil end
  if current then
    local prev = t.prev and M.find_id(t.layout, t.prev)
    if not (prev and not prev.hidden and focusable(prev.view)) then prev = first_window(t.layout) end
    if prev then M.enter(prev) end
  end
  api.ui_redraw()
  return true
end

--- Give the keyboard to the window that had it before the current one
--- (`Ctrl-w p`), else to another window of the tab. Returns false when
--- the current window is the only one.
function M.back()
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
  if not win then return false end
  M.enter(win)
  return true
end

--- Close every window of the current tab but one.
function M.only(win)
  win = win or M.current()
  if not win then return end
  for _, w in ipairs(focusable_windows()) do
    if w ~= win then M.close(w) end
  end
  M.enter(win)
end

--- Where each window of the current tab is drawn, by window number, from a
--- fresh arrangement of the screen.
local function rect_of(win)
  for _, r in ipairs(ui().arrange()) do
    if r.win == win.id then return r end
  end
end

--- Split a window (the current one) and show a buffer in the new half,
--- which gets the keyboard. `opts`: `vertical` (side by side), `view` (the
--- type; "empty" by default), `buf` (a buffer of a type that has more than
--- one), `target` (what the view opens there, as in `roll://7`), `win`.
--- Returns the new window, or nil and why not.
function M.split(opts)
  local u, t = ui(), tab()
  local cur = opts.win or M.current()
  local name = opts.view or "empty"
  if not u.views[name] then return nil, "no buffer `" .. tostring(name) .. "`" end
  local single_view = not M.types[name]
  local one = M.one_window(name)
  if one and cur and cur.view == name then return nil, name .. " is in this window already" end
  if cur then
    local r = rect_of(cur)
    local room = r and (opts.vertical and r.w or r.h)
    local least = opts.vertical and M.min_width or M.min_height
    -- Without a screen (a script, the graphical frontend) there is no room to measure.
    if room and room > 0 and room < least * 2 + 1 then return nil, "not enough room" end
  end
  local buf = opts.buf or (not single_view and M.buf_create(name).id) or nil
  local moved = one and remove_view(t.layout, name)
  local win = M.leaf(name, { buf = buf })
  local root = t.layout
  local parent, at
  if cur then parent, at = parent_of(root, cur) end
  if not parent then
    root[#root + 1] = win
  else
    local dir = opts.vertical and "h" or "v"
    local after = opts.vertical and paw.opt.splitright or (not opts.vertical and paw.opt.splitbelow)
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
      local node = { dir = dir, size = cur.size, weight = cur.weight, min = cur.min }
      cur.size, cur.weight, cur.min, cur.float_below = nil, nil, nil, nil
      node[1], node[2] = after and cur or win, after and win or cur
      parent[at] = node
    end
  end
  M.tidy(root)
  if single_view then
    take(name)
    single(name).listed = true
    local view = u.views[name]
    if moved then
      paw.notify(called(name) .. " moved to the new window")
    elseif view.on_show then
      -- A view with a state for each window starts the new window from
      -- the state of the window it was split from, or of its last.
      M.within(win, view.on_show, view)
    end
  end
  M.enter(win)
  local ok, why = aim(name, opts.target)
  if not ok then paw.notify(why, "warn") end
  return win
end

--- Show a buffer in a window instead of the one it shows. A view on
--- screen in another window moves here. `target` is what the view opens
--- there (`roll://7`: clip 7).
function M.show_in(win, name, buf, target)
  local u, t = ui(), tab()
  if win.view == name and win.buf == buf then
    if target ~= nil then
      M.enter(win)
      local ok, why = aim(name, target)
      if not ok then paw.notify(why, "warn") end
    end
    return win
  end
  local old_view, old_buf = win.view, win.buf
  local before = M.buf_of(win)
  -- What `Ctrl-^` goes back to.
  win.alt = { view = old_view, buf = old_buf }
  local single_view = not M.types[name]
  if M.one_window(name) then
    local moved = remove_view(t.layout, name, win)
    take(name)
    if moved then paw.notify(called(name) .. " moved to this window") end
  elseif not single_view and not buf then
    buf = M.buf_create(name).id
  end
  win.view, win.buf, win.state, win.kept = name, single_view and nil or buf, {}, nil
  M.buf_of(win).listed = M.buf_of(win).listed or single_view
  if old_view ~= name and not old_buf and not M.find(t.layout, old_view, true) then
    local view = u.views[old_view]
    if view and view.on_hide then view:on_hide() end
  end
  if single_view and old_view ~= name then
    local view = u.views[name]
    if view.on_show then M.within(win, view.on_show, view) end
  end
  reap(old_buf)
  local after = M.buf_of(win)
  if t.win == win.id and before ~= after then
    if before then paw.emit("buf.leave", { buf = before.id, name = before.name }) end
    if after then paw.emit("buf.enter", { buf = after.id, name = after.name }) end
  end
  M.enter(win)
  local ok, why = aim(name, target)
  if not ok then paw.notify(why, "warn") end
  return win
end

--- Show again what a window (the current one) showed before what it shows
--- now: Vim's alternate buffer, `Ctrl-^` and `:b#`.
function M.alternate(win)
  win = win or M.current()
  local alt = win and win.alt
  if not alt or not (M.types[alt.view] or ui().views[alt.view]) then
    return paw.notify("this window has shown nothing else", "warn")
  end
  -- A buffer closed since is made again, as `:e` would.
  return M.show_in(win, alt.view, alt.buf and M.buffers[alt.buf] and alt.buf or nil)
end

--- The window next to the current one in a direction ("h", "j", "k",
--- "l"), `count` steps on.
function M.neighbour(dir, count)
  local cur = M.current()
  if not cur then return end
  local rects = ui().arrange()
  local by_id = {}
  for _, r in ipairs(rects) do
    if r.win then by_id[r.win] = r end
  end
  local at = by_id[cur.id]
  for _ = 1, count or 1 do
    if not at then return end
    local best, best_d
    for _, r in ipairs(rects) do
      if r.win and r ~= at and focusable(r.name) then
        local d, ok
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
        if ok and (not best_d or d < best_d) then best, best_d = r, d end
      end
    end
    if not best then break end
    at = best
  end
  if at and at.win ~= cur.id then return M.find_id(ui().layout, at.win) end
end

--- Move the current window to an edge of the tab ("H", "J", "K", "L"),
--- the whole height or width of it.
function M.move_to_edge(edge)
  local t = tab()
  local cur = M.current()
  if not cur or #focusable_windows() < 2 then return end
  local root = t.layout
  local parent, at = parent_of(root, cur)
  if not parent then return end
  table.remove(parent, at)
  cur.size, cur.weight, cur.min, cur.float_below = nil, nil, nil, nil
  M.tidy(root)
  if edge == "K" then
    table.insert(root, 1, cur)
  elseif edge == "J" then
    root[#root + 1] = cur
  else
    local rest = { dir = "v" }
    for i, child in ipairs(root) do rest[i] = child end
    for i = #root, 1, -1 do root[i] = nil end
    root[1] = edge == "H" and { dir = "h", cur, rest } or { dir = "h", rest, cur }
  end
  M.tidy(root)
  api.ui_redraw()
end

--- Exchange the current window with the next window next to it, or with the
--- window number `count`, in their row or column. When it is the last window, use the
--- previous window. The next window can be a split of several windows.
function M.exchange(count)
  local t = tab()
  local cur = M.current()
  if not cur then return end
  local parent, at = parent_of(t.layout, cur)
  if not parent then return end
  local list = {}
  for i, child in ipairs(parent) do
    if shown(child) then list[#list + 1] = i end
  end
  local mine
  for k, i in ipairs(list) do
    if i == at then mine = k end
  end
  local other = list[count or mine + 1] or list[mine - 1]
  if not other or other == at then return end
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
function M.rotate(back)
  local t = tab()
  local cur = M.current()
  local parent = cur and parent_of(t.layout, cur)
  if not parent then return end
  local places = {}
  for i, child in ipairs(parent) do
    if shown(child) then places[#places + 1] = i end
  end
  if #places < 2 then return end
  local nodes = {}
  for k, i in ipairs(places) do nodes[k] = parent[i] end
  for k, i in ipairs(places) do
    local from = back and (k % #places) + 1 or ((k - 2) % #places) + 1
    parent[i] = nodes[from]
  end
  api.ui_redraw()
end

--- Move the current window to a tab of its own.
function M.to_tab()
  local cur = M.current()
  if not cur or #focusable_windows() < 2 then return false end
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
  local function walk(node)
    for _, child in ipairs(node) do
      if not (child.view and not focusable(child.view)) then
        child.size, child.weight = nil, nil
      end
      if not child.view then walk(child) end
    end
  end
  walk(ui().layout)
  api.ui_redraw()
end

--- Resize a window (the current one): `axis` "height" or "width", to `n`
--- cells, or by `n` with `relative`. It is the window's row or column in
--- the split along that axis that changes. Returns false when nothing can.
function M.resize(win, axis, n, relative)
  local u = ui()
  win = win or M.current()
  if not win then return false end
  local dir = axis == "height" and "v" or "h"
  local root = u.layout
  local node, parent = win, nil
  while true do
    parent = parent_of(root, node)
    if not parent then return false end
    local count = 0
    for _, child in ipairs(parent) do
      if shown(child) then count = count + 1 end
    end
    if parent.dir == dir and count > 1 then break end
    node = parent
  end
  local rects = u.arrange()
  local r = rects.nodes and rects.nodes[node]
  local now = r and (axis == "height" and r.h or r.w) or node.size or 0
  local total = rects.nodes and rects.nodes[parent] and (axis == "height" and rects.nodes[parent].h or rects.nodes[parent].w) or now
  local size = relative and now + n or n
  M.set_size(node, axis, math.max(1, math.min(size, total - 1)))
  api.ui_redraw()
  return true
end

--- Set the size a node takes along its parent: a panel whose size is an
--- option (`devices_width`) has it set there.
function M.set_size(node, axis, size)
  local option = node.view and node.view .. "_" .. axis
  if option and paw.opt[option] ~= nil then
    paw.opt[option] = size
  else
    node.size = size
  end
end

--- The border between two windows at a cell of an arrangement
--- (`paw.ui.arrange`). This is the rule between windows side by side, or
--- the top row of a window below a different window.
function M.border_at(rects, x, y)
  for _, b in ipairs(rects.borders or {}) do
    if b.dir == "h" and x == b.x and y >= b.y and y < b.y + b.h then return b end
  end
  for _, b in ipairs(rects.borders or {}) do
    if b.dir == "v" and y == b.y and x >= b.x and x < b.x + b.w then return b end
  end
end

--- Move a border to the position of the pointer. If one of the two sides
--- has its own size, it keeps a size. If not, the first side gets a size.
--- A graphical frontend lays the tree out in pixels (paw/panes.lua):
--- `opts.unit` is its cell `{ w, h }`, and `opts.map` takes each node
--- of its arrangement to the node of the tree. Sizes stay in cells.
function M.drag_border(border, rects, x, y, opts)
  opts = opts or {}
  local nodes = rects.nodes or {}
  local a, b = nodes[border.a], nodes[border.b]
  if not (a and b) then return end
  local across = border.dir == "h"
  local start = across and a.x or a.y
  local finish = across and b.x + b.w or b.y + b.h
  local at = math.max(start + 1, math.min(across and x or y, finish - 1))
  local axis = across and "width" or "height"
  local unit = opts.unit and (across and opts.unit.w or opts.unit.h) or 1
  local first, second = border.a, border.b
  if opts.map then first, second = opts.map[first], opts.map[second] end
  if second.size and not first.size then
    M.set_size(second, axis, math.max(1, math.floor((finish - at) / unit + 0.5)))
  else
    M.set_size(first, axis, math.max(1, math.floor((at - start) / unit + 0.5)))
  end
  api.ui_redraw()
end

--- Give the current window the whole tab, or put the others back.
function M.maximize()
  local t = tab()
  if t.zoom then
    local zoom = t.zoom
    t.zoom = nil
    for _, win in ipairs(M.windows(t.layout, true)) do
      local hidden = zoom.hidden[win.id]
      if hidden ~= nil then win.hidden = hidden end
    end
    local win = M.find_id(t.layout, zoom.win)
    if win then
      win.size = zoom.size
      M.enter(win)
    end
    return false
  end
  local cur = M.current()
  if not cur then return end
  t.zoom = { win = cur.id, hidden = {}, size = cur.size }
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
function M.tab_new(name, view, win, buf, target)
  local u = ui()
  if not win then
    view = view or "empty"
    if M.types[view] then buf = buf or M.buf_create(view).id end
    win = M.leaf(view, { buf = buf })
  end
  local t = { name = name, layout = { dir = "v", win }, win = win.id }
  table.insert(u.tabs, u.tab + 1, t)
  M.tab_go(u.tab + 1)
  -- A view shown in one window at a time leaves the other tabs, each left
  -- with a window (`take`).
  take(win.view)
  local ok, why = aim(win.view, target)
  if not ok then paw.notify(why, "warn") end
  return t
end

--- Open in each window of a tree what its view opens there, as it was
--- saved (`M.import` keeps it as `pending`).
local function open_pending(root)
  for _, win in ipairs(M.windows(root, true)) do
    local target = win.pending
    win.pending = nil
    if target ~= nil then M.within(win, aim, win.view, target) end
  end
end

--- Make a tab with the same windows as the current one, after it, and go
--- to it, the keyboard in the same kind of window. Views shown in a window
--- of each show the same state in both.
function M.tab_copy(name)
  local u = ui()
  local from = tab()
  local here = M.current()
  local root = M.import(M.export(from.layout))
  if root.view then root = { dir = "v", root } end
  M.tidy(root)
  local t = { name = name, layout = root }
  for _, win in ipairs(M.windows(root)) do
    if here and win.view == here.view then t.win = win.id end
  end
  table.insert(u.tabs, u.tab + 1, t)
  open_pending(root)
  M.tab_go(u.tab + 1)
  return t
end

--- Go to tab `i`.
function M.tab_go(i)
  local u = ui()
  if not u.tabs[i] then return false end
  local changed = i ~= u.tab
  u.tab = i
  u.layout = u.tabs[i].layout
  local t = u.tabs[i]
  local win = t.win and M.find_id(t.layout, t.win)
  if not (win and not win.hidden) then win = first_window(t.layout) end
  if changed then paw.emit("tab.enter", { tab = i }) end
  if win then M.enter(win) end
  api.ui_redraw()
  return true
end

--- Go `n` tabs on (back, when negative), round the end.
function M.tab_step(n)
  local u = ui()
  M.tab_go((u.tab - 1 + n) % #u.tabs + 1)
end

--- Close tab `i` (the current tab). The last tab does not close.
function M.tab_close(i)
  local u = ui()
  i = i or u.tab
  if #u.tabs < 2 or not u.tabs[i] then return false end
  local gone = table.remove(u.tabs, i)
  for _, win in ipairs(M.windows(gone.layout, true)) do reap(win.buf) end
  local go = math.min(u.tab > i and u.tab - 1 or u.tab, #u.tabs)
  u.tab = 0
  M.tab_go(go)
  return true
end

--- Move tab `i` (the current tab) to place `to` among the tabs: 1 is the
--- first. The current tab stays the current tab.
function M.tab_move(to, i)
  local u = ui()
  i = i or u.tab
  if not u.tabs[i] then return false end
  to = math.max(1, math.min(#u.tabs, math.floor(to)))
  local current = u.tabs[u.tab]
  table.insert(u.tabs, to, table.remove(u.tabs, i))
  for k, t in ipairs(u.tabs) do
    if t == current then u.tab = k end
  end
  api.ui_redraw()
  return true
end

--- What a tab is called: its name, else the buffer of its current window.
function M.tab_title(t)
  if t.name then return t.name end
  local win = t.win and M.find_id(t.layout, t.win) or first_window(t.layout)
  local buf = M.buf_of(win)
  return buf and buf.name or "?"
end

-- Saved layouts -------------------------------------------------------------------

--- A tree of windows as plain data, for `paw.layouts` and to save.
local function export(node)
  local out = { size = node.size, weight = node.weight, min = node.min }
  if node.view then
    out.view, out.float_below, out.hidden = node.view, node.float_below, node.hidden or nil
    if node.opts and next(node.opts) then out.opts = copy(node.opts) end
    local buf = node.buf and M.buffers[node.buf]
    if buf then out.target = buf.target end
    -- What a view opens in the window (its clip), as `roll://7` names it.
    local view = not buf and ui().views[node.view]
    if view and view.window_target then
      local ok, target = pcall(M.within, node, view.window_target, view)
      if ok then out.target = target end
    end
    return out
  end
  out.dir, out.children = node.dir, {}
  for i, child in ipairs(node) do out.children[i] = export(child) end
  return out
end

M.export = export

--- The tabs and windows as plain data: what `:layout save` writes.
function M.capture()
  local u = ui()
  local tabs = {}
  for i, t in ipairs(u.tabs) do
    -- Which window has the keyboard, counted in the tree's order: in a
    -- tab where none was entered yet, the one that would have it.
    local has = i == u.tab and M.current() or (t.win and M.find_id(t.layout, t.win)) or first_window(t.layout)
    local current
    for k, win in ipairs(M.windows(t.layout, true)) do
      if win == has then current = k end
    end
    tabs[i] = { name = t.name, layout = export(t.layout), current = current }
  end
  return { tab = u.tab, tabs = tabs }
end

--- A node as saved, or as a configuration writes it: `"roll"` or
--- `{ view = "roll", size = 20 }` for a window, `{ dir = "h", "arrange",
--- "roll" }` (or with `children`) for a split. Windows of views that are
--- not there (an extension not loaded) are left out.
local function import(spec)
  if type(spec) == "string" then spec = { view = spec } end
  if type(spec) ~= "table" then return nil end
  if spec.view then
    local name, _, named = M.resolve(spec.view)
    if not name then return nil end
    local win = M.leaf(name, { size = spec.size, weight = spec.weight, min = spec.min, float_below = spec.float_below, hidden = spec.hidden, opts = copy(spec.opts or {}) })
    if M.types[name] then
      win.buf = M.buf_create(name, spec.target).id
    else
      -- What the view opens there, once the window is in a tab.
      win.pending = spec.target or named
    end
    return win
  end
  local node = { dir = spec.dir == "h" and "h" or "v", size = spec.size, weight = spec.weight, min = spec.min }
  for _, child in ipairs(spec.children or spec) do
    local made = import(child)
    if made then node[#node + 1] = made end
  end
  return node
end

M.import = import

--- Put back tabs and windows from `M.capture()`'s data, or from a list of
--- tabs as a configuration writes them:
---   { { name = "Edit", layout = { dir = "h", "arrange", "roll" } }, { name = "Mix", layout = "mixer" } }
--- Returns false when it holds no window.
function M.restore(saved)
  local u = ui()
  local tabs = {}
  for _, spec in ipairs(saved.tabs or saved) do
    local root = import(spec.layout or spec[1] or spec)
    if root then
      if root.view then root = { dir = "v", root } end
      M.tidy(root)
      -- A view has one window in a tab: the first of any more.
      local seen = {}
      for _, win in ipairs(M.windows(root, true)) do
        if M.one_window(win.view) then
          if seen[win.view] then remove_view(root, win.view, seen[win.view]) else seen[win.view] = win end
        end
      end
      if first_window(root) then
        local current = spec.current and M.windows(root, true)[spec.current]
        tabs[#tabs + 1] = { name = spec.name, layout = root, win = current and current.id }
      end
    end
  end
  if #tabs == 0 then return false end
  u.tabs, u.tab = tabs, 0
  local go = math.max(1, math.min(tonumber(saved.tab) or 1, #tabs))
  for _, t in ipairs(tabs) do open_pending(t.layout) end
  M.tab_go(go)
  return true
end

--- A layout as `M.restore` takes it, from any of the forms a configuration
--- writes: a view's name (`"notation"`), a tree (`{ dir = "h", "roll",
--- "notation" }`), a list of tabs, or what `M.capture` gives.
function M.as_tabs(spec)
  if type(spec) == "string" then return { { layout = spec } } end
  if type(spec) ~= "table" then return {} end
  if spec.view or spec.dir or spec.children then return { { layout = spec } } end
  return spec
end

--- The tabs and windows that the project keeps: `{ default, seats }`,
--- `seats` the layout of each kind of seat (`paw.seats.kind`), each in
--- the form `M.capture` gives. Nil when it keeps none. A project saved
--- with one layout gives it as the default.
function M.project_screen()
  local screen = api.project_screen()
  if type(screen) ~= "table" then return nil end
  if screen.tabs then return { default = screen, seats = {} } end
  if type(screen.seats) ~= "table" then screen.seats = {} end
  if not (screen.default or next(screen.seats)) then return nil end
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
  local name = paw.opt.layout
  if name and name ~= "" then
    local ok, why = M.load(name)
    if not ok then paw.notify(why, "warn") end
  end
end

--- Layouts a configuration names, by name: `paw.layouts.edit = { ... }` in
--- init.lua, in the form `M.restore` takes.
M.layouts = {}

local function layout_dir() return api.env().state_dir .. "/layouts" end
local function layout_file(name) return layout_dir() .. "/" .. tostring(name):gsub("[^%w%-_]", "_") .. ".json" end

--- Write the tabs and windows as layout `name`, in the state directory.
function M.save(name)
  local file = layout_file(name)
  pcall(paw.api.fs_mkdir, layout_dir())
  local handle = io.open(file .. ".tmp", "wb")
  if not handle then return false, "cannot write " .. file end
  handle:write(api.json_encode(M.capture(), true))
  handle:close()
  os.rename(file .. ".tmp", file)
  return true, file
end

--- Put back layout `name`: the configuration's, else one saved.
function M.load(name)
  local spec = M.layouts[name]
  if not spec then
    local handle = io.open(layout_file(name), "rb")
    if not handle then return false, "no layout `" .. tostring(name) .. "`" end
    local text = handle:read("*a")
    handle:close()
    local ok, data = pcall(api.json_decode, text)
    if not ok or type(data) ~= "table" then return false, "layout `" .. tostring(name) .. "` cannot be read" end
    spec = data
  end
  if not M.restore(spec) then return false, "layout `" .. tostring(name) .. "` has no window" end
  return true
end

--- The names of the layouts there are: the configuration's and those saved.
function M.layout_names()
  local out, seen = {}, {}
  for name in pairs(M.layouts) do
    seen[name] = true
    out[#out + 1] = name
  end
  local ok, entries = pcall(api.read_dir, layout_dir())
  for _, entry in ipairs(ok and entries or {}) do
    local name = entry.name:match("^(.*)%.json$")
    if name and not seen[name] then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

-- Time bound windows ----------------------------------------------------------------

--- Before the windows are drawn: the current window, if it is time bound,
--- leads the others that are. Returns the window to draw first and the set
--- of windows that follow it.
function M.time_lead()
  local u = ui()
  local lead = M.current()
  if not (lead and lead.opts and lead.opts.timebind) then return nil end
  local view = u.views[lead.view]
  if not (view and view.time_axis) then return nil end
  local followers = {}
  for _, win in ipairs(M.windows(u.layout)) do
    local other = u.views[win.view]
    if win ~= lead and win.opts and win.opts.timebind and other and other.set_time_axis then followers[win.id] = true end
  end
  if not next(followers) then return nil end
  -- Playing, the windows follow the playhead together, whichever leads.
  local t = api.transport_get()
  local left, zoom, span = view:time_axis({ win = lead })
  if t.playing and paw.opt.follow and left and span and (t.position < left or t.position >= left + span) then
    view:set_time_axis(paw.time.bar_floor(t.position), zoom, { win = lead })
  end
  return lead, followers
end

--- Call it after paw draws the main window. The other windows take its time.
function M.time_follow(lead, win)
  local u = ui()
  local lead_view, view = u.views[lead.view], u.views[win.view]
  local left, zoom = M.within(lead, lead_view.time_axis, lead_view, { win = lead })
  if left then M.within(win, view.set_time_axis, view, left, zoom, { win = win }) end
end

--- Set a window option (`timebind`) on a window (the current one).
function M.set_option(win, name, value)
  win = win or M.current()
  if not win then return end
  win.opts = win.opts or {}
  win.opts[name] = value
  paw.emit("win.option", { win = win.id, name = name, value = value })
  api.ui_redraw()
end

-- The script interface ----------------------------------------------------------------

--- `paw.buf`: buffers.
M.buf = {
  list = M.buffers_list,
  get = function(name) local _, buf = M.resolve(name) return buf end,
  create = M.buf_create,
  delete = function(name)
    local _, buf = M.resolve(name)
    if buf then M.buf_delete(buf) end
  end,
  current = function() return M.buf_of(M.current()) end,
  of = M.buf_of,
  title = M.title,
}

--- `paw.win`: windows.
M.win = {
  current = M.current,
  list = function() return M.windows(ui().layout) end,
  get = M.get,
  enter = M.enter,
  split = M.split,
  close = M.close,
  only = M.only,
  show = function(win, name)
    local view, buf, target = M.resolve(name)
    if not view then error("no buffer `" .. tostring(name) .. "`", 2) end
    return M.show_in(win or M.current(), view, buf and not buf.single and buf.id or nil, target)
  end,
  resize = M.resize,
  equalize = M.equalize,
  maximize = M.maximize,
  option = function(win, name, value)
    win = win or M.current()
    if value == nil then return win and win.opts and win.opts[name] end
    M.set_option(win, name, value)
  end,
  buf = M.buf_of,
}

--- `paw.tab`: tabs.
M.tabs = {
  list = function() return ui().tabs end,
  current = function() return ui().tab end,
  new = function(name, buffer)
    local view = buffer and M.resolve(buffer)
    return M.tab_new(name, view)
  end,
  go = M.tab_go,
  close = M.tab_close,
  move = function(i, to) return M.tab_move(to, i) end,
  title = M.tab_title,
}

-- Commands and keys -------------------------------------------------------------------

--- Make the empty buffer type, the commands and the keys. Run once the
--- default commands are there, as some of these take over their short names.
function M.setup()
  local command, map = paw.command, paw.keymap.set

  -- An empty window shows the start page: what `:vnew` and `:tabnew` open.
  require("paw.views.start")

  paw.option.define("splitright", true)
  paw.option.define("splitbelow", true)
  paw.option.define("layout", "")

  local names = function() return M.buffer_names() end

  -- What a split without a name shows, as Vim shows the same buffer: a
  -- buffer of a type with many (a text list) again, a view with a state
  -- for each window again (from where this window is); a view shown in
  -- one window at a time leaves the new window empty, on the start page.
  local function same_buffer()
    local buf = M.buf_of(M.current())
    if not buf then return "empty" end
    if not buf.single or not M.one_window(buf.type) then return buf.type, buf end
    return "empty"
  end

  local function split(vertical, empty)
    return function(ctx)
      local name = ctx.args[1]
      local view, buf, target = "empty", nil, nil
      if name ~= nil then
        view, buf, target = M.resolve(name)
        if not view then return paw.notify("no buffer `" .. tostring(name) .. "`: `:ls` lists them", "warn") end
      elseif not empty then
        view, buf = same_buffer()
      end
      local made, why = M.split({ vertical = vertical, view = view, buf = buf and not buf.single and buf.id or nil, target = target })
      if not made then paw.notify(why, "warn") end
    end
  end
  command("split", split(false), { desc = "Split the window in two, one above the other, the new one showing a buffer: `sp roll`, or the same buffer without a name (the arrange view and the piano roll show each other, any other view leaves an empty window)", complete = names })
  command("vsplit", split(true), { desc = "Split the window in two side by side, the new one showing a buffer: `vs roll`, or the same buffer without a name (see `split`)", complete = names })
  command.alias("sp", "split")
  command.alias("vs", "vsplit")
  command("vnew", split(true, true), { desc = "A new empty window beside this one" })

  local function close_window()
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
  command("close", function()
    if not close_window() then paw.notify("the last window does not close: `:q` quits", "warn") end
  end, { desc = "Close the window; a panel's comes back where it was" })
  -- A view's own name goes to it: `:arrange`, `:mixer`, `:roll`.
  for _, view in ipairs({ "arrange", "mixer", "pianoroll" }) do
    local word = M.names[view] or view
    if ui().views[view] and not paw.commands.get(word) then
      command(word, function() paw.ui.focus(view) end, { desc = "Show " .. M.titles[view] .. " and go to it" })
    end
  end
  command("only", function() M.only() end, { desc = "Close every window but this one" })
  -- `:q` closes the window, and quits from the last one.
  command("q", function()
    if not close_window() then paw.cmd("quit") end
  end, { desc = "Close the window; in the last one, quit unless there are unsaved changes" })
  command("q!", function()
    if not close_window() then paw.cmd("quit!") end
  end, { desc = "Close the window; in the last one, quit without saving" })
  -- `:e roll` shows a buffer here; `:e song` opens a project.
  command("e", function(ctx) return paw.commands.run("edit", ctx.args, ctx) end, { desc = "Show a buffer in this window: `e roll`; or open a file as `open` does: `e song`, `e song.mid`, `e take.wav`",
    complete = function(text, info)
      if info.index > 1 then return {} end
      local out = M.buffer_names()
      for _, c in ipairs(paw.commands.completers.openable(text)) do out[#out + 1] = c end
      return out
    end })
  -- `:e!` as in Vim: the saved project again, or another, without the unsaved work.
  paw.project.allow_discard("e")

  local function listed_step(step)
    local list = M.buffers_list()
    if #list == 0 then return end
    local here = M.buf_of(M.current())
    local at = 0
    for i, buf in ipairs(list) do
      if buf == here then at = i end
    end
    local buf = list[(at - 1 + step) % #list + 1]
    if at == 0 and step < 0 then buf = list[#list] end
    M.show_in(M.current(), buf.type, not buf.single and buf.id or nil)
  end
  command("buffer", function(ctx)
    if ctx.args[1] == "#" then return M.alternate() end
    local view, buf, target = M.resolve(ctx.args[1])
    if not view then return paw.notify("no buffer `" .. tostring(ctx.args[1]) .. "`: `:ls` lists them", "warn") end
    M.show_in(M.current(), view, buf and not buf.single and buf.id or nil, target)
  end, { desc = "Show a buffer in this window, by name or number: `b roll`, `b 3`; `b #` what it showed before", complete = names })
  command.alias("b", "buffer")
  command("bnext", function(ctx) listed_step(ctx.count or 1) end, { desc = "Show the next buffer in this window" })
  command("bprevious", function(ctx) listed_step(-(ctx.count or 1)) end, { desc = "Show the previous buffer in this window" })
  command.alias("bn", "bnext")
  command.alias("bp", "bprevious")
  command("bdelete", function(ctx)
    local buf
    if ctx.args[1] ~= nil then
      local _
      _, buf = M.resolve(ctx.args[1])
    else
      buf = M.buf_of(M.current())
    end
    if not buf then return paw.notify("no buffer `" .. tostring(ctx.args[1]) .. "`", "warn") end
    M.buf_delete(buf)
  end, { desc = "Close every window of a buffer (this one's without a name); an empty one is forgotten", complete = names })
  command.alias("bd", "bdelete")
  command("buffers", function()
    local here = M.buf_of(M.current())
    local shown = {}
    for _, t in ipairs(paw.ui.tabs) do
      for _, win in ipairs(M.windows(t.layout)) do
        local buf = M.buf_of(win)
        if buf then shown[buf.id] = true end
      end
    end
    local lines = {}
    for _, buf in ipairs(M.buffers_list()) do
      local flags = (buf == here and "%" or " ") .. (shown[buf.id] and "a" or "h")
      lines[#lines + 1] = string.format("%3d %s  %-14s %s", buf.id, flags, buf.name, M.title(buf))
    end
    lines[#lines + 1] = { text = "% this window's   a in a window   h in none; `:b <name>` shows one here, `:vs <name>` beside", style = "Dim" }
    -- A project kept in a folder: its files, each a buffer that `:w`
    -- writes, `+` when it differs from the disk.
    local files = paw.api.project_files()
    if #files > 0 then
      lines[#lines + 1] = ""
      lines[#lines + 1] = { text = "Files", style = "Title" }
      local changed = 0
      for _, f in ipairs(files) do
        if f.modified then changed = changed + 1 end
        lines[#lines + 1] = string.format("  %s  %-10s %s", f.modified and "+" or " ", f.what, f.path)
      end
      lines[#lines + 1] = { text = string.format("+ differs from the disk (%d); `:w` writes this window's files, `:wa` all of them", changed), style = "Dim" }
    end
    paw.ui.page("Buffers", lines)
  end, { desc = "List the buffers" })
  command.alias("ls", "buffers")

  command("tabnew", function(ctx)
    local name = ctx.args[1]
    local view, buf, target
    if name ~= nil then view, buf, target = M.resolve(name) end
    -- `:tabnew mixer` shows the mixer in it, `:tabnew roll://7` the piano
    -- roll on clip 7; any other word names it.
    M.tab_new(name ~= nil and tostring(name) or nil, view or nil, nil, buf and not buf.single and buf.id or nil, target)
  end, { desc = "A new tab: `tabnew Mix` named, `tabnew mixer` showing the mixer, `tabnew roll://riff` the piano roll on the clip riff", complete = names })
  command("tabclose", function(ctx)
    local n = ctx.args[1] and tonumber(ctx.args[1])
    if ctx.args[1] and not (n and paw.ui.tabs[n]) then return paw.notify("no tab " .. tostring(ctx.args[1]), "warn") end
    if not M.tab_close(n) then paw.notify("the last tab does not close", "warn") end
  end, { desc = "Close the tab, or tab n: `tabclose 2`" })
  -- As in Vim: `:tabmove` to the end, `:tabmove 0` to the start,
  -- `:tabmove 2` after tab 2, `:tabmove +1` and `:tabmove -1` one on or back.
  command("tabmove", function(ctx)
    local u = paw.ui
    local arg = ctx.args[1] and tostring(ctx.args[1])
    local to
    if not arg then
      to = #u.tabs
    else
      local sign, n = arg:match("^([%+%-]?)(%d*)$")
      if not sign or (sign == "" and n == "") then return paw.notify("usage: tabmove, tabmove 0, tabmove 2, tabmove +1, tabmove -1", "warn") end
      n = tonumber(n) or 1
      if sign == "+" then
        to = u.tab + n
      elseif sign == "-" then
        to = u.tab - n
      else
        to = n < u.tab and n + 1 or n
      end
    end
    if to < 1 or to > #u.tabs then return paw.notify("no place " .. arg .. " for the tab", "warn") end
    M.tab_move(to)
  end, { desc = "Move the tab: `tabmove` to the end, `tabmove 0` to the start, `tabmove 2` after tab 2, `tabmove +1`" })
  command("tabnext", function(ctx)
    local n = tonumber(ctx.args[1])
    if n then return M.tab_go(n) end
    M.tab_step(ctx.count or 1)
  end, { desc = "The next tab, or tab n: `tabn 2`" })
  command("tabprevious", function(ctx) M.tab_step(-(tonumber(ctx.args[1]) or ctx.count or 1)) end, { desc = "The previous tab" })
  command.alias("tabn", "tabnext")
  command.alias("tabp", "tabprevious")
  command("tabs", function()
    local lines = {}
    local here = M.current()
    for i, t in ipairs(paw.ui.tabs) do
      lines[#lines + 1] = { text = "Tab " .. i .. (t.name and " " .. t.name or "") .. (i == paw.ui.tab and "  (this one)" or ""), style = "Title" }
      for _, win in ipairs(M.windows(t.layout)) do
        local buf = M.buf_of(win)
        if buf and focusable(win.view) then
          lines[#lines + 1] = string.format("  %s %s", win == here and ">" or " ", buf.name)
        end
      end
    end
    paw.ui.page("Tabs", lines)
  end, { desc = "List the tabs and their windows" })

  -- `:resize 20`, `:resize +5`, `:vertical resize -10`.
  local function resize(axis, text)
    local sign, n = tostring(text or ""):match("^%s*([%+%-]?)(%d+)%s*$")
    if not n then return paw.notify("usage: resize 20, resize +5, resize -5", "warn") end
    n = tonumber(n)
    if sign == "-" then n = -n end
    if not M.resize(nil, axis, n, sign ~= "") then paw.notify("the window has nothing to share its " .. axis .. " with", "warn") end
  end
  command("resize", function(ctx) resize("height", ctx.args[1]) end, { desc = "Set the window's height, or change it: `resize 20`, `resize +5`", raw = true })
  command("vertical", function(ctx)
    local rest = tostring(ctx.args[1] or ""):match("^%s*res[a-z]*%s+(.*)$")
    if not rest then return paw.notify("usage: vertical resize 40, vertical resize +5", "warn") end
    resize("width", rest)
  end, { desc = "Set the window's width, or change it: `vertical resize 40`, `vertical resize -5`", raw = true })

  -- Window options: `:setlocal timebind`, `:setlocal notimebind`, `:setlocal timebind!`.
  local window_options = { timebind = true }
  command("setlocal", function(ctx)
    local word = tostring(ctx.args[1] or "")
    local name, flip = word:match("^(%a+)(!?)$")
    local value = true
    if name and name:sub(1, 2) == "no" and window_options[name:sub(3)] then name, value = name:sub(3), false end
    if not (name and window_options[name]) then
      local win = M.current()
      local text = {}
      for option in pairs(window_options) do text[#text + 1] = option .. "=" .. tostring(win and win.opts[option] or false) end
      return paw.notify(table.concat(text, " "))
    end
    if flip == "!" then value = not M.win.option(nil, name) end
    M.set_option(nil, name, value)
    paw.notify(name .. (value and " on" or " off") .. " in this window")
  end, { desc = "Set an option of this window: `setlocal timebind` scrolls and zooms it with the other time bound windows",
    complete = function() return { "timebind", "notimebind", "timebind!" } end })
  command.alias("setl", "setlocal")

  command("layout", function(ctx)
    local first, name = ctx.args[1], ctx.args[2]
    if first == nil then
      local list = M.layout_names()
      return paw.notify(#list > 0 and "layouts: " .. table.concat(list, ", ") or "no layouts yet: `:layout save <name>` keeps the tabs and windows as they are")
    end
    if first == "save" then
      if name == nil then return paw.notify("usage: layout save <name>", "warn") end
      local ok, where = M.save(tostring(name))
      return paw.notify(ok and "layout " .. tostring(name) .. " saved" or where, ok and "info" or "error")
    end
    local ok, why = M.load(tostring(first))
    if not ok then paw.notify(why, "warn") end
  end, { desc = "Put back a layout of tabs and windows: `layout edit`; `layout save edit` keeps the one now",
    complete = function(_, info)
      if info.index == 2 and info.words[1] == "save" then return M.layout_names() end
      if info.index > 1 then return {} end
      local out = { { text = "save", desc = "keep the tabs and windows as they are" } }
      for _, name in ipairs(M.layout_names()) do out[#out + 1] = name end
      return out
    end })

  local acts = {
    s = function() split(false)({ args = {} }) end,
    v = function() split(true)({ args = {} }) end,
    n = function() split(false, true)({ args = {} }) end,
    c = function() paw.cmd("close") end,
    q = function() paw.cmd("q") end,
    o = function() M.only() end,
    x = function(ctx) M.exchange(ctx.count) end,
    r = function() M.rotate(false) end,
    R = function() M.rotate(true) end,
    T = function()
      if not M.to_tab() then paw.notify("the only window is a tab already", "warn") end
    end,
    p = function()
      local t = tab()
      local win = t.prev and M.find_id(t.layout, t.prev)
      if win and not win.hidden and focusable(win.view) then M.enter(win) end
    end,
  }
  for _, dir in ipairs({ "h", "j", "k", "l" }) do
    acts[dir] = function(ctx)
      local win = M.neighbour(dir, ctx.count)
      if win then M.enter(win) end
    end
    acts[dir:upper()] = function() M.move_to_edge(dir:upper()) end
  end
  command("wincmd", function(ctx)
    local act = acts[tostring(ctx.args[1] or "")]
    if not act then return paw.notify("usage: wincmd h, wincmd s, ... (what follows Ctrl-w)", "warn") end
    act(ctx)
  end, { desc = "Do what Ctrl-w and a key do: `wincmd l` goes to the window on the right" })

  local keys = {
    { "s", "Split the window, one above the other" }, { "v", "Split the window, side by side" },
    { "n", "A new empty window above or below" },
    { "h", "The window on the left" }, { "j", "The window below" }, { "k", "The window above" }, { "l", "The window on the right" },
    { "H", "Move the window to the far left" }, { "J", "Move the window to the bottom" },
    { "K", "Move the window to the top" }, { "L", "Move the window to the far right" },
    { "x", "Exchange the window with the next one" }, { "r", "Rotate the windows of the row or column" },
    { "R", "Rotate them the other way" }, { "T", "Move the window to a tab of its own" },
    { "p", "The window that had the keyboard before" }, { "c", "Close the window" },
    { "q", "Close the window; in the last one, quit" }, { "o", "Close every other window" },
  }
  for _, k in ipairs(keys) do map("<C-w>" .. k[1], "wincmd " .. k[1], { desc = k[2] }) end
  map("<C-w>w", "view.next", { desc = "The next window" })
  map("<C-w>W", "view.prev", { desc = "The previous window" })
  map("<C-w>|", "view.maximize", { desc = "Give the window the whole tab, or put the others back" })
  map("gt", "tabnext", { desc = "The next tab" })
  map("gT", "tabprevious", { desc = "The previous tab" })

  -- The project keeps the tabs and windows of each kind of seat (the
  -- graphical window, a terminal: `paw.seats.kind`), and a default: those
  -- of the seat that saved it. Opening it gives each seat its own, else
  -- the default. A project saved before keeps one layout, the default.
  paw.option.define("project_screen", true)
  paw.on("project.saving", function()
    if not paw.opt.project_screen then return end
    local screen = M.project_screen() or { seats = {} }
    screen.default = M.capture()
    screen.seats[paw.seats.kind()] = screen.default
    -- The other seats open now keep theirs too.
    for _, id in ipairs(paw.seats.list()) do
      if id ~= paw.seats.current then
        screen.seats[paw.seats.kind(id)] = paw.seats.within(id, M.capture)
      end
    end
    api.project_screen_set(screen)
  end)
  paw.on("project.loaded", function()
    if not paw.opt.project_screen then return end
    local screen = M.project_screen()
    if not screen then return end
    for _, id in ipairs(paw.seats.list()) do
      local mine = screen.seats[paw.seats.kind(id)] or screen.default
      if mine then
        if id == paw.seats.current then M.restore(mine) else paw.seats.within(id, M.restore, mine) end
      end
    end
  end)
  -- A seat that opens after the project did (a window attached to it)
  -- takes the layout that the project keeps for its kind, if any.
  paw.on("seat.opened", function(event)
    if not paw.opt.project_screen then return end
    local screen = M.project_screen()
    local mine = screen and screen.seats[paw.seats.kind(event.seat)]
    if mine then paw.defer(function() paw.seats.within(event.seat, M.restore, mine) end) end
  end)

  paw.on("startup", M.start)
end

return M
