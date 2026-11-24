-- Roles: named elements a view marks over a rectangle of its buffer, which
-- every frontend shows as well as it can (see crates/paw-scene).
--
--   paw.ui.role("hit", {                       a role: its look in cells, and what its props are
--     props = { velocity = "number 0..127" },
--     cells = function(buf, p, ctx) ... end,   draws it on `buf`, the rectangle marked
--   })
--   buf:mark("fader", x, y, w, h, props)       a fader there; `props.hit` makes it a hit region,
--                                              `props.bind` ties it to a live value (`meter:4`)
--   buf:hit(x, y, w, h, action)                a hit region with no look of its own
--   buf:plane(x, y, w, h, opts)                a rectangle with a domain of its own, beats
--                                              along and pitches up, that marks are put in
--                                              (see "Planes" below)
--
-- A terminal draws a role with its `cells`, as the view's own drawing; so
-- does a window for a role it does not know. A window that knows it (the
-- widget roles of paw/roles/widgets.lua) is sent the role and its props
-- instead, and paints it in pixels: crisp faders, meters moved by
-- `scene.live`. The rectangle is the view's layout, the same in both.
--
-- A hit region's `action` (a mark's `props.hit`) is data: `{ kind = "fader",
-- part = 4 }`. A press, a move or the wheel on it goes to the view's
-- gesture for its kind, `view.gestures[kind](view, e)`, with `e.hit` the
-- action and `e.rect` the region, whichever frontend it came from. `e.x`,
-- `e.y` and `e.rect` are in the view's cells: whole in a terminal (the
-- cell's corner), fractions in a window, which says so (`e.fine`); a
-- gesture returns false to leave the event to the view's `on_mouse`. A kind
-- the view has no gesture for may say what a click does itself: `keys`
-- (typed), `cmd` (an Ex command); and `hint`, what the status line says of
-- it under the pointer.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local registry = require("paw.registry")
local time_axis = require("paw.axis")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type UiModule = require("paw.ui")
local type MouseModule = require("paw.mouse")
local type PanesModule = require("paw.panes")
local type role_props = require("paw.role_props")
local Buf = require("paw.buf")
local type CanvasModule = require("paw.canvas")
local command = require("paw.command")
local type LimitModule = require("paw.limit")
local type SeatsModule = require("paw.seats")
local type UtilModule = require("paw.util")

local type View = contracts.View
local type MarkProps = contracts.MarkProps
local type HitAction = contracts.HitAction
local type MouseEvent = contracts.MouseEvent
local type Axis = contracts.Axis
local type Data = UtilModule.Data

-- What this module reads of `paw`, which paw/init.lua makes.
local record Paw is partial.Paw
  keymap: KeymapModule
  ui: UiModule
  canvas: CanvasModule
  limit: LimitModule
  mouse: MouseModule
  panes: PanesModule
  seats: SeatsModule
  util: UtilModule
end
local paw = (_G as {string: Paw}).paw

--- Where a terminal's hit region in a plane is (`plane:region()`): the
--- corner of the plane's buffer on the screen, and the plane.
local record PlaceIn
  x: number
  y: number
  plane: Plane
end

--- A hit region of the terminal's screen, in screen cells: its action,
--- and the plane it is in, if any.
local record Region
  x: number
  y: number
  w: number
  h: number
  hit: HitAction
  plane: PlaceIn
end

--- What the frontend that gets scenes holds of a drag that started on a
--- hit region (`held`, which its watcher keeps).
local record Held
  gesture: MouseModule.Handlers
  button: string
end

--- A pointer event from a frontend that gets scenes, in units of its window.
local type SceneEvent = contracts.PointerEvent

local record M
  type Region = Region
  type Held = Held
  type SceneEvent = SceneEvent
  --- A plane (`buf:plane`): its buffer, its axes, its name in the scene,
  --- and whether a scene is being drawn. The record is its class too.
  record Plane is contracts.Plane
    buf: Buf
    x: Axis
    y: Axis
    key: string
    scene: boolean
    at: function(self: Plane, cx: number, cy: number): types.Point
    region: function(self: Plane): PlaceIn
  end
  --- Every role by name, with the extension that defined it. `define`
  --- puts one.
  registry: registry.Registry<contracts.Role<contracts.MarkProps>>
  --- The version of the roles a frontend may know (`scene.watch`'s `roles`).
  version: integer
  gesture: function(view: View, e: MouseEvent): boolean
end
local Plane = M.Plane
M.version = 1
-- A change of a role tells the frontends that paint roles that the set
-- changed, and draws again.
M.registry = registry.new(
  "roles",
  "roles",
  {
    changed = function() M.version = M.version + 1; api.ui_redraw() end,
  }
)

-- The hit regions each window of the terminal's screen drew last, by the
-- view's name and its window: `{ x, y, w, h, hit }` each, in screen cells.
-- A seat's screen is its own.
local hits: {string: {Region}} = {}
local drawing: {Region} = nil
paw.seats.keep(
  "roles",
  function(): {string: {Region}} return hits end,
  function(h: {string: {Region}}) hits = h end,
  function(): {string: {Region}} return {} end
)

--- Define a role. `spec.cells(buf, props, ctx)` draws it in cells. It is
--- necessary, because the terminal comes first. `spec.props` names its
--- props and their contents, for documentation and `paw.ui.roles`.
--- `spec.bound` is the props that a frontend takes from the live value when
--- the mark is bound to one. paw does not send these props. `spec.stamp(buf,
--- props)`, a text of what `cells` shows, lets a bound mark keep its cells
--- between whole frames while it does not change.
function M.define<P is contracts.MarkProps>(name: string, spec: contracts.Role<P>)
  if type(name) ~= "string" or name == "" then
    error("a role needs a name", 2)
  end
  if type(spec) ~= "table" or type(spec.cells) ~= "function" then
    error("role " .. name .. ": cells(buf, props, ctx) draws it", 2)
  end
  M.registry:put(name, spec as contracts.Role<contracts.MarkProps>)
end

--- What of a role's props goes to a frontend: data only, and not what it
--- takes from a live value (`left`, names to leave out).
local function wire(props: MarkProps, left: {string}): role_props.Props
  local out: {string: Data} = {}
  for k, v in pairs(props as {string: Data}) do
    if k ~= "hit" and k ~= "bind" and k ~= "key" and type(v) ~= "function" then
      out[k] = v
    end
  end
  for _, k in ipairs(left or {}) do
    out[k] = nil
  end
  return out as role_props.Props
end

local function key_of(name: string, win: integer): string
  return tostring(name) .. "#" .. tostring(win or "")
end

--- A view is about to be drawn on the terminal's screen (`win`, the id of
--- its window, if any): its hit regions start afresh.
function M.begin(name: string, win?: integer)
  drawing = {}
  hits[key_of(name, win)] = drawing
end

--- The view being drawn is done: what it marks after is no hit region.
function M.finish()
  drawing = nil
end

--- What `buf`'s rectangle `x, y, w, h` shows of the screen: nil for none.
local function shown(buf: Buf, x: number, y: number, w: number, h: number): Region
  local x0, y0 = math.max(buf.x + x, buf.cx), math.max(buf.y + y, buf.cy)
  local x1, y1 = math.min(buf.x + x + w, buf.cx + buf.cw), math.min(buf.y + y + h, buf.cy + buf.ch)
  if x1 <= x0 or y1 <= y0 then
    return nil
  end
  return {x = x0, y = y0, w = x1 - x0, h = y1 - y0}
end

--- Whether `buf`'s rectangle `x, y, w, h` shows on the screen: `shown`
--- with no table made, for each mark of a plane.
local function shows(buf: Buf, x: number, y: number, w: number, h: number): boolean
  return math.min(buf.x + x + w, buf.cx + buf.cw) > math.max(buf.x + x, buf.cx)
    and math.min(buf.y + y + h, buf.cy + buf.ch) > math.max(buf.y + y, buf.cy)
end

--- Open a node of a scene being drawn over `buf`'s rectangle `x, y, w, h`;
--- true when one was, to be closed.
local function open(buf: Buf, x: number, y: number, w: number, h: number, opts: types.SceneOpenOptions): boolean
  if not paw.ui.scene_drawing then
    return false
  end
  local r: types.Rect = {x = buf.x + x, y = buf.y + y, w = w, h = h}
  local cut = shown(buf, x, y, w, h)
  if not cut then
    return false
  end
  if cut.x ~= r.x or cut.y ~= r.y or cut.w ~= r.w or cut.h ~= r.h then
    opts.clip = cut as types.Rect
  end
  return api.scene_open(r, opts)
end

--- A hit region of the terminal's screen, where it shows; `plane` the
--- plane it is in, if any, for where in its domain a press is.
local function region(buf: Buf, x: number, y: number, w: number, h: number, action: HitAction, plane?: PlaceIn)
  if not drawing then
    return
  end
  local r = shown(buf, x, y, w, h)
  if r then
    r.hit, r.plane = action, plane
    drawing[#drawing + 1] = r
  end
end

--- What the view's cells hold of a role's props, and what goes to a
--- frontend: the opts of its node.
local function node_opts(
  role: string, spec: contracts.Role<contracts.MarkProps>, props: MarkProps
): types.SceneOpenOptions
  return {
    role = role, props = wire(props, props.bind and spec.bound), hit = props.hit, bind = props.bind, key = props.key
  }
end

--- The context each role's cells get, one for each role: it says only
--- the role's name, so it is made once.
local contexts: {string: contracts.RoleContext} = {}

local function spec_of(role: string): contracts.Role<contracts.MarkProps>
  local spec = M.registry:get(role)
  if not spec then
    error("no role " .. tostring(role), 3)
  end
  return spec
end

--- Draw a role's cells. A mark bound to a live value on the terminal's
--- screen is a live part of it, which paw draws again by itself as the
--- value moves (`paw.ui.live`).
local function cells(sub: Buf, role: string, spec: contracts.Role<contracts.MarkProps>, props: MarkProps)
  local ctx = contexts[role]
  if not ctx then
    ctx = {role = role}
    contexts[role] = ctx
  end
  local u = paw.ui
  if props.bind and spec.bound and u.live_drawing() then
    -- Drawn again only when what it shows moves (a meter at rest, a
    -- playhead of a song that is stopped keep their cells).
    local bind = props.bind
    local stamp: function(): string
    if spec.stamp then
      stamp = function(): string u.live_value(bind, props); return spec.stamp(sub, props) end
    else
      stamp = function(): string return u.live_stamp(bind) end
    end
    return u.live(sub, function(b: Buf) u.live_value(bind, props); spec.cells(b, props, ctx) end, stamp)
  end
  return spec.cells(sub, props, ctx)
end

--- Draw a role's cells inside the node of a scene opened for it (`opened`),
--- which is closed after them, even when they fail.
local function cells_in(
  opened: boolean, sub: Buf, role: string, spec: contracts.Role<contracts.MarkProps>, props: MarkProps
)
  if not opened then
    return cells(sub, role, spec, props)
  end
  local ok, err = pcall(cells, sub, role, spec, props) as (boolean, string)
  api.scene_close()
  if not ok then
    error(err, 0)
  end
end

--- `buf:mark(role, x, y, w, h, props)`: mark a role over an area. A
--- terminal draws the cells of the role there. A frontend that knows the
--- role paints it as what it is. `props.hit` makes it a hit region, and
--- `props.bind` ties it to a live value. Returns the buffer of the area.
---   buf:mark("fader", 4, 2, 3, 12, { at = 0.8, hit = { kind = "fader", part = id } })
function M.mark(buf: Buf, role: string, x: number, y: number, w: number, h: number, props?: MarkProps): Buf
  local spec = spec_of(role)
  props = props or {}
  local sub = buf:sub(x, y, w, h)
  -- What goes to a frontend is made only while a scene is drawn.
  local opened = paw.ui.scene_drawing and open(buf, x, y, sub.width, sub.height, node_opts(role, spec, props))
  cells_in(opened, sub, role, spec, props)
  if props.hit then
    region(buf, x, y, sub.width, sub.height, props.hit)
  end
  return sub
end

--- `buf:hit(x, y, w, h, action)`: make an area a hit region. A press, a
--- move or the wheel there goes to the view's gesture for `action.kind`,
--- in either frontend.
function M.hit(buf: Buf, x: number, y: number, w: number, h: number, action: HitAction)
  if open(buf, x, y, w, h, {hit = action}) then
    api.scene_close()
  end
  region(buf, x, y, w, h, action)
end

-- Planes: a rectangle of a buffer whose kids are placed in a domain of
-- their own, beats along and pitches up, say (see crates/paw-scene).
--
--   local roll = buf:plane(5, 2, w, h, {
--     key = "roll",                                       its name in the scene
--     x = { domain = "beat", from = scroll, per = zoom }, columns a beat from `from`
--     y = { domain = "pitch", from = top + 1, per = -1 }, a row a pitch, `top` first
--     hit = { kind = "grid" },                            its empty part, a hit region
--   })
--   roll:mark("note", start, pitch, length, 1, props)    a role over a rectangle of the domain
--   roll:hit(start, pitch, length, 1, action)            a hit region there
--   roll:cells(start, pitch, length, 1)                  where a terminal shows it: x, y, w, h
--
-- An axis puts `from` at the plane's edge and runs `per` units for each
-- unit of its domain, backwards when negative. A terminal shows a mark on
-- the cells that its edges are in, by the rule of paw/axis.tl: from the
-- cell of its first edge up to the cell of its last, that cell not
-- included (one at least each way); a window paints it
-- where it is, between cells. A press on a plane, or on what is in it,
-- comes with `e.at`: where in the domain it was (a terminal's at the
-- middle of the cell).
local PlaneMeta = Plane as metatable<Plane>
PlaneMeta.__index = Plane

--- Where along an axis a stretch of its domain is, in cells from the
--- plane's edge: the first and how many (one at least).
local function along(axis: Axis, v: number, len: number): integer, integer
  local a, b = (v - axis.from) * axis.per, (v + len - axis.from) * axis.per
  if a > b then
    a, b = b, a
  end
  local first = time_axis.cell(a)
  return first, math.max(1, time_axis.cell(b) - first)
end

--- The cells of the plane's buffer that a rectangle of its domain shows on.
function Plane:cells(x: number, y: number, w: number, h: number): integer, integer, integer, integer
  local cx, cw = along(self.x, x, w)
  local cy, ch = along(self.y, y, h)
  return cx, cy, cw, ch
end

--- A point of the plane's buffer (fractions of its cells) in its domain.
function Plane:at(cx: number, cy: number): types.Point
  return {x = self.x.from + cx / self.x.per, y = self.y.from + cy / self.y.per}
end

--- What a terminal's hit region in the plane says of where a press is.
function Plane:region(): PlaceIn
  return {x = self.buf.x, y = self.buf.y, plane = self}
end

--- Put a role (`role`, nil for a hit region alone, `hit`) over a
--- rectangle of the plane's domain. Returns the buffer of the cells it
--- shows on.
local function put(
  plane: Plane,
  x: number,
  y: number,
  w: number,
  h: number,
  role: string,
  spec: contracts.Role<contracts.MarkProps>,
  props: MarkProps,
  hit: HitAction
): Buf
  local cx, cy, cw, ch = plane:cells(x, y, w, h)
  local buf = plane.buf
  local sub = buf:sub(cx, cy, cw, ch)
  if not shows(buf, cx, cy, cw, ch) then
    return sub
  end
  local opened = false
  if plane.scene then
    -- What goes to a frontend is made only while a scene is drawn.
    local opts: types.SceneOpenOptions = role and node_opts(role, spec, props) or {hit = hit}
    opts.into = plane.key
    opened = api.scene_open({x = x, y = y, w = w, h = h}, opts)
  end
  if role then
    cells_in(opened, sub, role, spec, props)
  elseif opened then
    api.scene_close()
  end
  if hit then
    region(buf, cx, cy, cw, ch, hit, plane:region())
  end
  return sub
end

--- `plane:mark(role, x, y, w, h, props)`: a role over a rectangle of the
--- plane's domain. Returns the buffer of the cells it shows on.
function Plane:mark(role: string, x: number, y: number, w: number, h: number, props?: MarkProps): contracts.Buf
  local spec = spec_of(role)
  props = props or {}
  return put(self, x, y, w, h, role, spec, props, props.hit)
end

--- `plane:hit(x, y, w, h, action)`: a hit region over a rectangle of the
--- plane's domain.
function Plane:hit(x: number, y: number, w: number, h: number, action: HitAction)
  put(self, x, y, w, h, nil, nil, nil, action)
end

--- `buf:plane(x, y, w, h, opts)`: a plane over an area. Each axis of the
--- plane has its own domain, `opts.x` and `opts.y` (`{ domain, from, per }`):
--- `per` is the cells for one unit of the domain, and `from` is the value at
--- the edge of the area. A terminal shows a mark on the cells it rounds to.
--- A window shows it at its exact position.
---   local roll = buf:plane(5, 2, 60, 20, { key = "roll", x = { domain = "beat", from = 0, per = 4 },
---     y = { domain = "pitch", from = 73, per = -1 }, hit = { kind = "grid" } })
---   roll:mark("note", 1.5, 60, 0.5, 1, { label = "C4" })
function M.plane(buf: Buf, x: number, y: number, w: number, h: number, opts: contracts.PlaneOptions): Plane
  local sub = buf:sub(x, y, w, h)
  local plane = setmetatable({buf = sub, x = opts.x, y = opts.y, key = opts.key or "plane"} as Plane, PlaneMeta)
  if open(buf, x, y, sub.width, sub.height, {plane = {x = opts.x, y = opts.y}, key = plane.key, hit = opts.hit}) then
    api.scene_close()
    plane.scene = true
  end
  if opts.hit then
    region(buf, x, y, sub.width, sub.height, opts.hit, plane:region())
  end
  return plane
end

--- An event on a hit region (`e.hit`, `e.rect`) to its view: true when it
--- was taken.
function M.gesture(view: View, e: MouseEvent): boolean
  local h = e.hit
  local fn = view.gestures and view.gestures[h.kind]
  if fn then
    local taken = fn(view, e)
    if taken ~= false then
      return true
    end
  end
  if e.kind == "move" and h.hint then
    paw.mouse.hint(h.hint)
    return true
  end
  if fn or e.kind ~= "down" or e.button ~= "left" then
    return false
  end
  if h.keys then
    paw.keymap.feed(h.keys)
  elseif h.cmd then
    command.exec(h.cmd)
  else
    return false
  end
  api.ui_redraw()
  return true
end

--- The last region drawn in `list` under the point `x, y`.
local function under(list: {Region}, x: number, y: number): Region
  for i = #list, 1, -1 do
    local r = list[i]
    if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
      return r
    end
  end
end

--- A mouse event in the terminal, in the cells of the view it is over (as
--- its `on_mouse` takes it, with `view_x`, `view_y`, `win`): to the gesture
--- of the hit region under it. True when it was taken.
function M.pointer(view: View, name: string, event: MouseEvent): boolean
  local kind = event.kind
  if kind ~= "down" and kind ~= "move" and not kind:match("^scroll") then
    return false
  end
  local list = hits[key_of(name, event.win)]
  local ox, oy = event.view_x or 0, event.view_y or 0
  local r = list and under(list, event.x + ox, event.y + oy)
  if not r then
    return false
  end
  local rect: types.Rect = {x = r.x - ox, y = r.y - oy, w = r.w, h = r.h}
  local e = paw.util.merge(event as {string: Data}, {hit = r.hit as {Data: Data}, rect = rect as {Data: Data}})
    as MouseEvent
  -- In a plane, where in its domain: at the middle of the cell.
  local p = r.plane
  if p then
    e.at = p.plane:at(event.x + ox - p.x + 0.5, event.y + oy - p.y + 0.5)
  end
  return M.gesture(view, e)
end

--- A pointer event from a frontend that gets scenes (paw/scene.tl), in
--- units of its window `id`, over the view `view` (its window of the
--- layout `win`, if any). On a hit region of the scene, the event goes to
--- the gesture of the region, with `x` and `y` in units. A drag that
--- started there continues in units (`held`, which the watcher of the
--- frontend keeps). True when it takes the event.
function M.input(client: integer, id: string, view: View, win: integer, event: SceneEvent, held: Held): boolean
  local kind = event.kind
  -- The pointer left the window: what the status line said of it goes.
  if kind == "leave" then
    if not paw.mouse.gesture() then
      paw.mouse.hint(nil)
    end
    return true
  end
  local mods = (event.ctrl and "C" or "") .. (event.alt and "A" or "") .. (event.shift and "S" or "")
  local x, y = tonumber(event.x) or 0, tonumber(event.y) or 0
  if kind == "move" or kind == "up" then
    local g = paw.mouse.gesture()
    if not (g and g == held.gesture) then
      return false
    end
    if kind == "up" then
      held.gesture = nil
    end
    local e: MouseEvent = {
      kind = kind == "move" and "drag" or "up", x = x, y = y, button = held.button, mods = mods, fine = true
    }
    paw.limit.named("the mouse", function(): boolean return paw.mouse.to_view(view, e) end)
    api.ui_redraw()
    return true
  end
  local e: MouseEvent
  if kind == "down" then
    e = {kind = "down", button = event.button or "left"}
  elseif kind == "hover" then
    e = {kind = "move", button = ""}
  elseif kind == "wheel" then
    local dx, dy = tonumber(event.dx) or 0, tonumber(event.dy) or 0
    if event.shift and dx == 0 then
      dx, dy = dy, 0
    end
    if math.abs(dx) > math.abs(dy) then
      e = {kind = dx > 0 and "scroll_left" or "scroll_right"}
    else
      e = {kind = dy > 0 and "scroll_up" or "scroll_down"}
    end
    e.button = ""
  else
    return false
  end
  local found = api.scene_hit(client, id, x, y)
  if not found then
    return false
  end
  if kind == "down" then
    if win then
      paw.panes.focus(win)
    else
      paw.canvas.focus(view.name)
    end
  end
  e.x, e.y, e.mods, e.view_x, e.view_y, e.win, e.fine = x, y, mods, 0, 0, win, true
  e.hit, e.rect, e.at = found.hit as HitAction, found.rect, found.at
  if kind == "down" then
    paw.mouse.mark_double(e)
  end
  if not paw.limit.named("the mouse", function(): boolean return M.gesture(view, e) end) then
    return false
  end
  if kind == "down" then
    -- The gesture holds the pointer from here on, in units.
    held.gesture, held.button = paw.mouse.gesture(), e.button
  end
  api.ui_redraw()
  return true
end

-- A buffer's `mark`, `hit` and `plane` are these (paw/buf.tl).
Buf.mark, Buf.hit, Buf.plane = M.mark, M.hit, M.plane

return M
