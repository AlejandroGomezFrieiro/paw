-- What connections on the control socket can ask to be sent, on top of
-- calling into the kernel: events as they happen, and the state a graphical
-- frontend draws, pushed when it changes instead of asked for thirty times
-- a second. docs/reference/protocol.md describes the whole protocol; the transport
-- (the socket, TCP, the token) is in crates/paw-core/src/rpc.rs.
--
--   subscribe "transport.*" "project.saved"   -- events are pushed as they happen
--   unsubscribe                               -- all of them, or the ones named
--   frontend.watch                            -- `frontend.state` events from now on
--   frontend.unwatch
--
-- An extension can add methods of its own:
--   paw.remote.methods["mything.status"] = function(client, ...) return ... end
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local commands = require("paw.commands")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local seats = require("paw.seats")
local type FrontendModule = require("paw.frontend")
local type SceneModule = require("paw.scene")

--- A value that a connection sends or is sent, which this module passes on.
local record Value
end

--- A method of the remote API: what the connection `client` sent, and the answer.
local type Method = function(client: integer, ...: Value): Value

--- A connection that watches the state of the frontend: the revision of
--- the project it has, the last tick it was sent, the JSON of each section
--- it was sent, and the milliseconds between two pushes.
local record Watcher
  revision: integer
  tick: string
  sent: {string:string}
  interval: number
end

--- What `frontend.watch` takes: the milliseconds between two pushes, and
--- `seat = "instance"` for a window that shares the instance's seat.
local record WatchOptions
  interval: number
  seat: string
end

--- A connection that listens (`M.listeners`).
local record Listener
  client: integer
  patterns: {string}
  watching: boolean
end

--- The parts of the state that only change with the project.
local record View
  selected: integer
  cursor: number
end
local record Sections
  project: {string:Value}
  lines: {FrontendModule.Line}
  tracks: {FrontendModule.TrackState}
  clips: {FrontendModule.ClipState}
  devices: {FrontendModule.DeviceState}
  routing: FrontendModule.Routing | boolean
  kinds: {string}
  view: View
end

-- What this module reads of `paw`, which paw/init.lua makes, and of the
-- modules in Lua that it calls: their parts that it uses.
local type UiModule = require("paw.ui")
local record Paw
  frontend: FrontendModule
  scene: SceneModule
  ui: UiModule
  defer: function(fn: function(), ms?: number): integer
  cancel: function(handle: integer)
  notify: function(text: string, level?: string)
end
local paw = (_G as {string:Paw}).paw

local record M
  type Method = Method
  type Value = Value
  --- The methods a connection can call, by name: an extension adds its own.
  methods: {string:Method}
  --- How many turns had input: what a frontend is sent of the keyboard and
  --- the panes can change only then (`paw.frontend.state`).
  touches: integer
  closed: function(client: integer)
end
M.methods = {}

local subs: {integer:{string}} = {}       -- connection -> list of event patterns
local watchers: {integer:Watcher} = {}    -- connection -> { revision, tick, sent = { section -> its JSON } }
local timer: integer

local function matches(pattern: string, name: string): boolean
  if pattern == "*" or pattern == name then return true end
  local family = pattern:match("^(.-)%.%*$")
  return family ~= nil and name:sub(1, #family + 1) == family .. "."
end

M.methods.subscribe = function(client: integer, ...: string): {string}
  local list = subs[client] or {}
  for _, pattern in ipairs({ ... }) do
    if type(pattern) == "string" then list[#list + 1] = pattern end
  end
  subs[client] = list
  return list
end as Method

M.methods.unsubscribe = function(client: integer, ...: string): {string}
  local drop = { ... }
  if #drop == 0 then
    subs[client] = nil
    return {}
  end
  local keep: {string} = {}
  for _, pattern in ipairs(subs[client] or {}) do
    local gone = false
    for _, d in ipairs(drop) do gone = gone or d == pattern end
    if not gone then keep[#keep + 1] = pattern end
  end
  subs[client] = #keep > 0 and keep or nil
  return keep
end as Method

-- Every event goes to the connections that asked for it. What cannot be
-- written as JSON (an extension's event carrying a function) is not sent.
events.on(events.pattern("*"), function(payload: events.Payload, name: string)
  for client, patterns in pairs(subs) do
    for _, pattern in ipairs(patterns) do
      if matches(pattern, name) then
        local ok, sent = pcall(api.rpc_push, client, name, payload)
        if ok and not sent then subs[client] = nil end
        break
      end
    end
  end
end)

-- The parts of `paw.frontend.state` that only change with the project, each
-- sent again only when it differs from what the connection last got. The
-- bar and beat lines are a part of their own: they are most of a long
-- song's state and change least.
local function sections_of(state: FrontendModule.State): Sections
  local project: {string:Value} = {}
  for k, v in pairs(state.project as {string:Value}) do project[k] = v end
  project.lines = nil
  return {
    project = project, lines = state.project.lines or {}, tracks = state.tracks or {},
    clips = state.clips or {}, devices = state.devices or {}, routing = state.routing or false,
    kinds = state.kinds, view = { selected = state.selected, cursor = state.cursor },
  }
end

local SECTION_KEYS = { "project", "tracks", "clips", "devices", "routing", "kinds", "selected", "cursor" }

-- Numbers that tremble (a meter falling towards nothing) are rounded to
-- what a frontend can show, so that an idle program has nothing new to
-- say; the engine's load comes steady already (`paw.audio.load`).
local function steady(list: {number})
  for i, level in ipairs(list or {}) do list[i] = math.floor(level * 10000 + 0.5) / 10000 end
end

--- Send to a connection the changes of the state of the frontend after the
--- last send. Send nothing when nothing changed.
function M.push(client: integer)
  local w = watchers[client]
  if not w then return end
  -- What the window draws is seen from its own seat.
  local state = seats.within(client, paw.frontend.state, w.revision)
  local fields = state as {string:Value}
  local changed: {string:Value}
  if state.project then
    w.revision = state.revision
    for name, value in pairs(sections_of(state) as {string:Value}) do
      local text = api.json_encode(value)
      if w.sent[name] ~= text then
        w.sent[name] = text
        changed = changed or {}
        changed[name] = value
      end
    end
    for _, key in ipairs(SECTION_KEYS) do fields[key] = nil end
  end
  steady(state.levels)
  steady(state.inputs)
  local text = api.json_encode(state)
  if not changed and text == w.tick then return end
  w.tick = text
  fields.sections = changed as Value
  if not api.rpc_push(client, "frontend.state", state) then M.closed(client) end
end

-- While something moves (the song plays, meters fall), the state is
-- pushed at the watchers' pace (`frontend.pace`); else once a second, for
-- what changes slowly on its own (the engine's load). What a key, the
-- pointer, a call or an edit changes is pushed after its turn (`M.turn`).
local fast: boolean  -- the timer waiting is at the pace
local touched = false
local last_push: number = 0
local pending: integer
local seen_revision: integer
local seen_redraws: integer

local function push_all()
  last_push = api.now()
  for client in pairs(watchers) do M.push(client) end
end

local function retime()
  local fastest: number
  for _, w in pairs(watchers) do fastest = math.min(fastest or w.interval, w.interval) end
  if timer then paw.cancel(timer) end
  timer = nil
  if not fastest then return end
  fast = paw.ui.active()
  timer = paw.defer(function()
    timer = nil
    push_all()
    retime()
  end, fast and fastest or 1000)
end

--- Something started to move (the song, a note played): push at the pace
--- from now.
function M.wake()
  if next(watchers) and not fast then retime() end
end

events.on(kernel.transport_play, M.wake)

--- A turn had input: a key, the pointer, a call. What the frontends show
--- can be different.
function M.touch()
  touched = true
  M.touches = M.touches + 1
end

M.touches = 0

--- After each turn of the kernel: push now what its input or its edits
--- changed, at most once in 8 ms.
function M.turn()
  if not next(watchers) or pending then return end
  local revision, redraws = paw.frontend.revision, api.ui_redraws()
  if not touched and revision == seen_revision and redraws == seen_redraws then return end
  touched, seen_revision, seen_redraws = false, revision, redraws
  local wait = 8 - (api.now() - last_push)
  if wait <= 0 then return push_all() end
  pending = paw.defer(function()
    pending = nil
    push_all()
  end, wait)
end

M.methods["frontend.watch"] = function(client: integer, opts: WatchOptions): boolean
  if client == 0 then error("only a connection can watch", 0) end
  local interval = type(opts) == "table" and tonumber(opts.interval) or 33
  watchers[client] = { revision = -1, sent = {}, interval = math.max(16, interval) }
  -- A window has a seat of its own, unless it shares the instance's (one
  -- that started its kernel itself, and is the instance's only face).
  if not (type(opts) == "table" and opts.seat == "instance") then
    seats.open(client, "window")
    seats.enter(client)
  end
  retime()
  -- The whole state at once, without waiting for the first tick.
  M.push(client)
  return true
end as Method

--- The window says how often it draws what moves (`paw.opt.window_fps`):
--- the milliseconds between two frames. The state and the live values are
--- pushed at that pace while the song plays.
M.methods["frontend.pace"] = function(client: integer, given: number): boolean
  local ms = math.max(8, math.min(1000, tonumber(given) or 33))
  if watchers[client] then watchers[client].interval = ms end
  if paw.scene then paw.scene.set_pace(ms) end
  retime()
  return true
end as Method

M.methods["frontend.unwatch"] = function(client: integer): boolean
  watchers[client] = nil
  retime()
  seats.close(client, "window")
  return true
end as Method

--- A connection closed: nothing more is sent to it.
function M.closed(client: integer)
  subs[client] = nil
  if watchers[client] then
    watchers[client] = nil
    retime()
    seats.close(client, "window")
  end
end

--- The listeners: `{ client = { patterns = {...}, watching = bool }, ... }`.
function M.listeners(): {Listener}
  local out: {Listener} = {}
  for _, client in ipairs(api.rpc_clients()) do
    out[#out + 1] = { client = client, patterns = subs[client] or {}, watching = watchers[client] ~= nil }
  end
  return out
end

--- What `file.wanted` asks of an attached terminal's program.
local record Wanted
  path: string
  import: boolean
end

-- The instance cannot read the disk of the machine a terminal is attached
-- from, so it asks that terminal's program to send the file (`file.wanted`),
-- which sends it into the project's media folder and imports it.
commands.define("upload", function(ctx: commands.Context): commands.Result
  local path = ctx.args[1] as string
  if not path or path == "" then return paw.notify("upload what? `upload ~/takes/bass.wav`", "warn") end
  local client = api.ui_client()
  if not seats.has(client) then
    return paw.notify("this terminal is the instance's own: `:import` reads this machine's files", "warn")
  end
  local wanted: Wanted = { path = path, import = true }
  api.rpc_push(client, "file.wanted", wanted)
  paw.notify("asked for " .. path .. " from the attached terminal's machine")
end, { desc = "From a terminal attached with `paw attach`: send a sound file from that machine and import it: `upload ~/take.wav`", raw = true })

-- Sound plays on the instance's machine; a terminal or window attached from
-- another can have it played there too (`monitor.listen`), which its own
-- program starts and stops.
commands.define("listen", function(): commands.Result
  local client = api.ui_client()
  if not seats.has(client) then
    return paw.notify("this is the instance's own terminal: its sound plays here already", "warn")
  end
  api.rpc_push(client, "monitor.toggle", {})
end, { desc = "From a terminal or window attached from another machine: hear the instance's sound there, or stop" })

commands.define("detach", function(): commands.Result
  local client = api.ui_client()
  -- A connection without a seat of its own (`paw ctl`) is no terminal.
  if not seats.has(client) then
    return paw.notify("this is the program's own terminal: `:q` quits; `paw attach` from another terminal can be detached", "warn")
  end
  api.ui_detach(client)
end, { desc = "Leave a terminal that was attached with `paw attach`; the program runs on" })

return M
