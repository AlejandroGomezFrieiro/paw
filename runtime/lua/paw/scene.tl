-- Scenes for graphical frontends: every window a frontend shows from the
-- kernel's drawing (a pane of its main area that it does not draw itself,
-- a view in a window of its own) is sent as a scene (crates/paw-scene) and
-- then as what changed of it, pushed as it changes. The frontend says how
-- big each window is in cell units (`scene.area`), sends the pointer back in
-- the same units (`scene.input`), and asks once for each drawing sent by its
-- content key (`scene.blob`) and for each picture of pixels a drawing names
-- (`scene.pixels`). docs/reference/protocol.md has the whole protocol.
--
--   scene.watch { cell = { w, h }, live = true }   scenes from now on
--   scene.area  win w h                            a window's size in units
--   scene.input win { kind, x, y, button, ... }    the pointer, in units
--   scene.blob  key                                a drawing by its key
--   scene.pixels key                               a picture of pixels by its key
--   scene.unwatch
--
-- A window is named by a string: a window of the layout by its number
-- ("3"), a view in a window of its own as `view:<name>`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type UiModule = require("paw.ui")
local type LayoutModule = require("paw.layout")
local type CanvasModule = require("paw.canvas")
local type DrawModule = require("paw.draw")
local type RolesModule = require("paw.roles")
local type SeatsModule = require("paw.seats")

local type View = contracts.View
local type Window = contracts.Window

--- A value this module passes on and never reads.
local record Value
end

-- What this module reads of `paw`, which paw/init.lua makes, and of the
-- modules that it calls: their parts that it uses. It keeps a window of
-- paw/layout.tl as a `contracts.Window`, as paw/canvas.tl does.

--- A tree of windows of a tab (paw/layout.tl), which this module only
--- passes on.
local record Tree
end
local record Layout
  find_id: function(root: Tree, id: integer): Window
  bind: function(win: Window)
  settle: function()
end
local record Ui
  layout: Tree
  render_scene: function(name: string, w: number, h: number, cell: types.Size, win: Window)
  active: function(): boolean
end
--- A pane of the frontend's main area (`paw.panes.state`): its window,
--- its view, and `native` for one the frontend draws itself.
local record Pane
  win: integer
  view: string
  kind: string
end
local record PanesState
  panes: {Pane}
end
local record Panes
  state: function(): PanesState
  pointer: function(id: integer, e: contracts.PointerEvent, drawn: Area)
end
local record AudioInput
  input: string
end
local record Audio
  levels: function(): {number}
  level: function(t: AudioInput, levels?: {number}): number
  load: function(cpu?: number): number
end
local record Time
  clock: function(beat: number): string
  local_beat: function(song_beat: number): number
end
--- A method of the remote API: what the connection `client` sent.
local type Method = function(client: integer, ...: Value): Value
local record Remote
  methods: {string: Method}
end
local record Paw is partial.Paw
  ui: UiModule
  layout: LayoutModule
  audio: Audio
  canvas: CanvasModule
  draw: DrawModule
  panes: Panes
  remote: Remote
  roles: RolesModule
  seats: SeatsModule
  time: Time
end
local paw = (_G as {string: Paw}).paw
local L = paw.layout as Layout

--- A window a watcher shows, as it gave its size (`scene.area`): `w` and
--- `h` in units, the redraw it was last drawn at (`drawn`), when (`at`),
--- the view it showed and the view's key then. A pointer event in cells
--- adds the cell and the size in cells.
local record Area
  w: number
  h: number
  drawn: integer
  at: number
  view: string
  key: string
  cell: types.Size
  cols: integer
  rows: integer
end

--- What each watching connection has: its cell in pixels, its windows'
--- sizes (`areas`, by name), whether it hears the live values (`live`) and
--- what it was last told of them, the drag it holds, and the roles it
--- paints by the live values.
local record Watcher
  cell: types.Size
  areas: {string: Area}
  live: boolean
  told: string
  held: RolesModule.Held
  roles: {string: boolean}
end

--- A window a seat's frontend shows from the kernel's drawing: its view,
--- and its window of the layout.
local record Shown
  view: string
  win: Window
end

--- The values that move the bound nodes of a frontend (`scene.live`), and
--- what views add for their own bound nodes.
local record Live
  position: number
  playing: boolean
  recording: boolean
  clock: string
  cpu: number
  meters: {string: {number}}
  peaks: {string: number}
  clips: {string: boolean}
  inputs: {string: number}
end

--- What `scene.watch` takes: the cell in pixels, whether to hear the live
--- values, and the roles the frontend paints itself.
local record WatchOptions
  cell: types.Size
  live: boolean
  roles: {string}
end

--- What `scene.watch` answers: the palette, and the version of the roles.
local record Watching
  theme: CanvasModule.Palette
  roles_version: integer
end

local record M
  type Area = Area
  type Watcher = Watcher
  type Live = Live
  --- A watcher, by connection, and the names of the windows whose size it gave.
  record WatcherInfo
    client: integer
    windows: {string}
  end
  pace: number
  live: function(): Live
  closed: function(client: integer)
end

local watchers: {integer: Watcher} = {}
local timer: integer
-- The redraw the windows were last looked at for, after a turn.
local looked: integer

--- The windows a seat's frontend shows from the kernel's drawing, by name:
--- `{ view, win }` each, `win` the window of the layout.
local function shown(): {string: Shown}
  local out: {string: Shown} = {}
  local state = paw.panes.state()
  for _, pane in ipairs(state and state.panes or {}) do
    if pane.kind ~= "native" then
      out[tostring(pane.win)] = {view = pane.view, win = L.find_id((paw.ui as Ui).layout, pane.win)}
    end
  end
  -- A view in a window of its own draws with that window's state.
  for _, w in ipairs(paw.canvas.windows()) do
    local own = paw.canvas.open_views[w.name]
    out["view:" .. w.name] = {view = w.name, win = own and own.win}
  end
  return out
end

--- Whether nothing of the view `name` moves on its own but what the
--- watcher `w` moves by the live values: a view names the roles it draws
--- such things with in `view.live_roles` (the mixer's meters and peaks),
--- and a watcher that paints them all needs no new scene of it as the song
--- plays, unless the view says it moves all the same (`view:moving()`: the
--- arrange view scrolls to follow the playhead).
---
--- A view can also give a key of what its drawing in a window shows but
--- the live values (`view:scene_key()`, a string; notation: the system of
--- the playhead): while the key stays the same as at the last drawing of
--- the window `area`, the scene stays too. It names the roles that it
--- moves by the live values in `view.scene_roles`.
local function key_of(view: View, win: Window): string
  if not view.scene_key then
    return nil
  end
  if win then
    L.bind(win)
  end
  local ok, key = pcall(view.scene_key, view)
  L.settle()
  return ok and key as string or nil
end

local function still(w: Watcher, name: string, area: Area, win: Window): boolean
  local view = paw.ui.views:get(name)
  if view and view.scene_key then
    for _, role in ipairs(view.scene_roles or {}) do
      if not w.roles[role] then
        return false
      end
    end
    local key = key_of(view, win)
    return key ~= nil and key == area.key
  end
  local roles = view and view.live_roles
  if not roles then
    return false
  end
  -- A view may draw other things that move, only at times (`view:moving()`).
  if view.moving and view:moving() then
    return false
  end
  for _, role in ipairs(roles) do
    if not w.roles[role] then
      return false
    end
  end
  return true
end

--- How often a view that moves is drawn again while the song plays, in
--- milliseconds: every tick, or less often if the view says so
--- (`view.redraw_every`, for a view whose moving parts are small).
local function every(name: string): number
  local view = paw.ui.views:get(name)
  return view and view.redraw_every or 30
end

--- Draw again the windows of a connection whose drawing may have changed
--- (all of them with `all`, as on a tick: what moves while playing, and
--- once a second what changes on its own, such as times), and push what
--- changed of each.
local function push(client: integer, all?: boolean)
  local w = watchers[client]
  if not w then
    return
  end
  paw.seats.within(
    client,
    function()
      local redraws, now, playing = api.ui_redraws(), api.now(), api.transport_get().playing
      local wanted = shown()
      for id, area in pairs(w.areas) do
        local what = wanted[id]
        if not what then
          if area.drawn then
            api.scene_forget(client, id)
          end
          area.drawn, area.view = nil, nil
        elseif
          area.drawn ~= redraws
          or area.view ~= what.view
          or (
            all
            and now - area.at >= (playing and every(what.view) or 1000) - 5
            and not still(w, what.view, area, what.win)
          )
        then
          area.drawn, area.view, area.at = redraws, what.view, now
          local ok, err = pcall((paw.ui as Ui).render_scene, what.view, area.w, area.h, w.cell, what.win)
            as (boolean, string)
          if not ok then
            api.log("the scene of " .. what.view .. " failed: " .. tostring(err))
          end
          area.key = key_of(paw.ui.views:get(what.view) or {}, what.win)
          local _, open = api.scene_end(client, id)
          if not open then
            return M.closed(client)
          end
        end
      end
    end
  )
end

--- The values that move the bound nodes of a frontend (see the `bind` of
--- crates/paw-scene). These are the playhead, the clock and the load of the
--- engine. For each track id, they are the meter, the recent peak, the clip
--- light and the input. paw rounds them to what a frontend can show. So a program that
--- does nothing has no new data to send (the load is as `paw.audio.load`
--- gives it, as `frontend.watch` sends it). Each call gives the current values.
local function live(): Live
  local t, e = api.transport_get(), api.engine_get()
  local meters: {string: {number}} = {}
  local peaks: {string: number} = {}
  local clips: {string: boolean} = {}
  local inputs: {string: number} = {}
  local levels = paw.audio.levels()
  local function round(v: number): number
    return math.floor(v * 10000 + 0.5) / 10000
  end
  local function meter(id: integer)
    local l, r, hold, clipped = paw.draw.track_peak(id)
    meters[tostring(id)], peaks[tostring(id)] = {round(l), round(r)}, round(hold)
    if clipped then
      clips[tostring(id)] = true
    end
  end
  local track_input = api.track_get as function(id: integer, key: string): string
  for _, id in ipairs(api.track_list({all = true})) do
    meter(id)
    inputs[tostring(id)] = round(paw.audio.level({input = track_input(id, "input")}, levels))
  end
  -- The master's, as track 0.
  meter(0)
  local out: Live = {
    position = t.position,
    playing = t.playing,
    recording = t.take ~= nil,
    clock = paw.time.clock(paw.time.local_beat(t.position)),
    cpu = paw.audio.load(e.cpu),
    meters = meters,
    peaks = peaks,
    clips = clips,
    inputs = inputs,
  }
  -- What views add for their own bound nodes (`view.live_values()`, a
  -- table of values by name): the device panel's parameters that lanes move.
  local fields = out as {string: Value}
  for _, view in pairs(paw.ui.views:entries()) do
    if type(view.live_values) == "function" then
      local ok, values = pcall(view.live_values)
      if ok and type(values) == "table" then
        for k, v in pairs(values as {string: Value}) do
          fields[k] = v
        end
      end
    end
  end
  return out
end

M.live = live

--- Push the live values to the watcher `w` of `client` when they differ
--- from what it was told last. `text` is the JSON of `values`.
local function tell(client: integer, w: Watcher, values: Live, text: string)
  if text ~= w.told and api.rpc_push(client, "scene.live", values) then
    w.told = text
  end
end

local function tick()
  local values: Live
  local text: string
  for client, w in pairs(watchers) do
    push(client, true)
    if w.live and watchers[client] then
      values = values or live()
      text = text or api.json_encode(values)
      tell(client, w, values, text)
    end
  end
end

--- The milliseconds between two ticks while something moves: the pace of
--- the window, which says it with `frontend.pace` (`paw.opt.window_fps`).
M.pace = 33

-- While something moves, a tick each `M.pace`; else one a second, for
-- what changes slowly on its own (times). A turn that changes the drawing
-- pushes at once (`M.turn`).
local retime: function()
local function ticked()
  timer = nil
  tick()
  retime()
end

local fast: boolean -- the timer waiting is at the pace
retime = function()
  if timer then
    paw.cancel(timer)
  end
  timer = nil
  if not next(watchers) then
    return
  end
  fast = (paw.ui as Ui).active()
  timer = paw.defer(ticked, fast and M.pace or 1000)
end

--- Something started to move (the song, a note played): tick at the pace
--- from now.
function M.wake()
  if next(watchers) and not fast then
    retime()
  end
end

events.on(kernel.transport_play, function() M.wake() end)

--- Tick every `ms` while something moves (`frontend.pace`).
function M.set_pace(ms: number)
  M.pace = ms
  retime()
end

--- Call it after a turn of the kernel. paw pushes now, not at the next
--- tick, the windows whose drawing can be different.
function M.turn()
  if not next(watchers) then
    return
  end
  local redraws = api.ui_redraws()
  if redraws == looked then
    return
  end
  looked = redraws
  for client in pairs(watchers) do
    push(client)
  end
end

--- Send connection `client` now what it would get after the turn: the
--- windows whose drawing changed, and the live values when they changed.
--- A window that moves only with time waits for its next tick.
--- `frontend.sync` calls it.
function M.sync(client: integer)
  local w = watchers[client]
  if not w then
    return
  end
  push(client)
  if w.live and watchers[client] then
    local values = live()
    tell(client, w, values, api.json_encode(values))
  end
end

local methods = paw.remote.methods

methods["scene.watch"] = function(client: integer, given: WatchOptions): Watching
  if client == 0 then
    error("only a connection can watch", 0)
  end
  local opts: WatchOptions = given is WatchOptions and given or {}
  local asked = opts.cell or {}
  local cell: types.Size = {w = tonumber(asked.w) or paw.canvas.cell.w, h = tonumber(asked.h) or paw.canvas.cell.h}
  -- The frontend's main area is laid out on its cell (paw/panes.tl).
  paw.canvas.cell = cell
  api.scene_forget(client)
  -- The roles it paints itself are sent as roles, without their cells.
  local roles: {string} = {}
  local known: {string: boolean} = {}
  local asked_roles = opts.roles
  for _, name in ipairs(asked_roles is {string} and asked_roles or {}) do
    if name is string then
      roles[#roles + 1], known[name] = name, true
    end
  end
  api.scene_roles(client, roles)
  watchers[client] = {
    cell = cell, areas = {}, live = opts.live == true, held = {}, roles = opts.live == true and known or {}
  }
  retime()
  return {theme = paw.canvas.palette, roles_version = paw.roles.version}
end as Method

methods["scene.unwatch"] = function(client: integer): boolean M.closed(client); return true end as Method

methods["scene.area"] = function(
  client: integer, name: string | number, width: number | string, height: number | string
): boolean
  local watcher = watchers[client]
  if not watcher then
    error("scene.area before scene.watch", 0)
  end
  local id = tostring(name)
  local w, h = math.max(0, tonumber(width) or 0), math.max(0, tonumber(height) or 0)
  if w == 0 or h == 0 then
    -- No longer shown: its next scene is sent whole.
    watcher.areas[id] = nil
    api.scene_forget(client, id)
    return true
  end
  local area = watcher.areas[id]
  if area and area.w == w and area.h == h then
    return true
  end
  watcher.areas[id] = {w = w, h = h}
  push(client)
  return true
end as Method

--- A pointer event as the frontend sends it, in units of the window, as
--- the views take them: in pixels of the watcher's cell.
local function in_pixels(event: RolesModule.SceneEvent, cell: types.Size): contracts.PointerEvent
  local out: {string: Value} = {}
  for k, v in pairs(event as {string: Value}) do
    out[k] = v
  end
  local e = out as contracts.PointerEvent
  e.x, e.y = (tonumber(event.x) or 0) * cell.w, (tonumber(event.y) or 0) * cell.h
  return e
end

local input: function(client: integer, name: string | number, event: RolesModule.SceneEvent): boolean

methods["scene.input"] = function(client: integer, name: string | number, event: RolesModule.SceneEvent): boolean
  -- The view takes the pointer with the state of the window under it
  -- (paw/layout.tl), and then of the window with the keyboard again.
  local number = tonumber(name) as integer
  local win = number and L.find_id((paw.ui as Ui).layout, number)
  local own = not win and paw.canvas.open_views[tostring(name):match("^view:(.+)$") or ""]
  win = win or (own and own.win)
  if win then
    L.bind(win)
  end
  local ok, result = pcall(input, client, name, event)
  L.settle()
  if not ok then
    error(result, 0)
  end
  return result as boolean
end as Method

input = function(client: integer, name: string | number, event: RolesModule.SceneEvent): boolean
  local watcher = watchers[client]
  if not (watcher and type(event) == "table") then
    return false
  end
  local id = tostring(name)
  local own = id:match("^view:(.+)$")
  -- On a hit region of the scene it was sent, the view's gesture has it
  -- in units (paw/roles.tl); anything else goes on as a terminal's would.
  local area = watcher.areas[id]
  local view = paw.ui.views:get(own or (area and area.view) or "")
  if view and paw.roles.input(client, id, view, not own and tonumber(id) as integer or nil, event, watcher.held) then
    return true
  end
  local e = in_pixels(event, watcher.cell)
  if own then
    paw.canvas.pointer(own, e)
    return true
  end
  -- The window's area keeps the button held, for a drag in cells.
  local drawn = watcher.areas[id] or {}
  drawn.cell, drawn.cols, drawn.rows = watcher.cell, math.floor(drawn.w or 0), math.floor(drawn.h or 0)
  paw.panes.pointer(tonumber(id) as integer, e, drawn)
  return true
end

methods["scene.blob"] = function(client: integer, key: string): {types.CanvasOp} return api.scene_blob(client, key) end
  as Method

methods["scene.pixels"] = function(_client: integer, key: string): types.PictureBlob return api.canvas_pixels(key) end
  as Method

--- A connection closed or stopped to watch. paw keeps no more data for it.
function M.closed(client: integer)
  if not watchers[client] then
    return
  end
  watchers[client] = nil
  api.scene_forget(client)
  retime()
end

--- The watchers: `{ client, windows }` each. `windows` is the names of the
--- windows whose size it gave.
function M.watchers(): {M.WatcherInfo}
  local out: {M.WatcherInfo} = {}
  for client, w in pairs(watchers) do
    local windows: {string} = {}
    for id in pairs(w.areas) do
      windows[#windows + 1] = id
    end
    table.sort(windows)
    out[#out + 1] = {client = client, windows = windows}
  end
  table.sort(out, function(a: M.WatcherInfo, b: M.WatcherInfo): boolean return a.client < b.client end)
  return out
end

return M
