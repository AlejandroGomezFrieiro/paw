-- `require("paw")`: the whole scripting surface, assembled from the modules in
-- this directory. The kernel provides `paw.api`; everything else is Lua that
-- you can read, replace or extend.
local api = require("paw.api")

local paw = { api = api, version = "0.1.0" }
_G.paw = paw
package.loaded["paw"] = paw

paw.util = require("paw.util")
paw.inspect = paw.util.inspect

--- What a user sees of an error: one line, without the list of calls.
--- The place in the code (`paw/x.lua:12:`) moves to the end, where it does
--- not hide what went wrong. The whole error goes to the log.
--- @type function(err: string): string
function paw.failure(err)
  local text = tostring(err)
  local short = text:match("^(.-)\n*stack traceback:") or text
  short = short:gsub("%s+$", "")
  -- A module in Lua or in Teal (`paw/x.tl:12:`).
  local file, line, rest = short:match("^[^\n]-([%w_%-]+%.lua):(%d+): (.*)$")
  if not file then
    file, line, rest = short:match("^[^\n]-([%w_%-]+%.tl):(%d+): (.*)$")
  end
  if file then
    -- An error raised by the code itself (`attempt to index a nil value`)
    -- says where; one raised on purpose says what to do, and that is enough.
    local internal = rest:match("^attempt to ") or rest:match("^bad argument") or rest:match("^stack overflow")
    short = internal and string.format("%s (%s:%s)", rest, file, line) or rest
  end
  return short
end

--- Call a function. If it fails, show the error as a message and do not
--- raise it. Returns true and the results of the function, or false and the error.
--- The message is the first lines of the error (`paw.failure`). The log
--- keeps the list of calls.
function paw.try(fn, ...)
  local result = { xpcall(fn, debug.traceback, ...) }
  if not result[1] then
    local short = paw.failure(result[2])
    if short ~= tostring(result[2]) then api.log("[error] " .. tostring(result[2])) end
    paw.notify(short, "error")
  end
  return unpack(result)
end

local events = require("paw.events")
paw.on, paw.once, paw.off, paw.emit = events.on, events.once, events.off, events.emit
paw.events = events

local options = require("paw.options")
paw.opt, paw.option = options.opt, options
paw.limit = require("paw.limit")
-- Edits, undo, saving and keys heard of (paw/hooks.tl): before anything
-- keeps the kernel's undo and save functions of its own.
paw.hooks = require("paw.hooks")
-- Before anything that keeps state of its own for each terminal and window.
paw.seats = require("paw.seats")

--- The timers waiting, by handle: the function each runs. An extension's
--- go when it is unloaded (paw/ext.lua).
--- @type {integer:function()}
paw.timers = {}

--- Run `fn` once, after `ms` milliseconds (or when the current turn ends).
--- @type function(fn: function(), ms?: number): integer
function paw.defer(fn, ms)
  local handle
  handle = api.timer_start(ms or 0, false, function(...)
    paw.timers[handle] = nil
    return fn(...)
  end)
  paw.timers[handle] = fn
  return handle
end

--- Run `fn` every `ms` milliseconds. Returns a handle for `paw.cancel`.
--- @type function(ms: number, fn: function()): integer
function paw.every(ms, fn)
  local handle = api.timer_start(ms, true, fn)
  paw.timers[handle] = fn
  return handle
end

--- Stop a timer: `handle` is what `paw.defer` or `paw.every` returned.
--- @type function(handle: integer)
function paw.cancel(handle)
  if handle == nil then return end
  paw.timers[handle] = nil
  return api.timer_stop(handle)
end

--- Let `ms` milliseconds pass while timers fire and events are delivered, as
--- they do between key presses. A script run with `-l` is one long turn in
--- which neither happens unless it waits like this.
paw.wait = api.wait

paw.commands = require("paw.commands")
-- The types of what an extension gives paw (a view, a picker, ...) for an
-- extension in Teal: `paw.contracts.View`. An empty table here.
paw.contracts = require("paw.contracts")
--- Define a command: `paw.command(name, fn, opts)` (paw.commands.define),
--- and `paw.command.alias(alias, target)`.
--- @type contracts.Command
paw.command = setmetatable({ alias = paw.commands.alias }, {
  __call = function(_, ...) return paw.commands.define(...) end,
})
paw.cmd = paw.commands.run

paw.music = require("paw.music")
-- A note's MIDI 2.0 attribute and the articulations in it (paw/attr.tl).
paw.attr = require("paw.attr")
paw.params = require("paw.params")
paw.ui = require("paw.ui")
-- Buffers, windows and tabs (paw/layout.tl).
paw.layout = require("paw.layout")
paw.buf, paw.win, paw.tab = paw.layout.buf, paw.layout.win, paw.layout.tabs
paw.buftype, paw.layouts = paw.layout.buftype, paw.layout.layouts
paw.draw = require("paw.draw")
paw.ui.keybar = require("paw.keybar")
paw.mouse = require("paw.mouse")
-- Roles views mark on their buffers, and the widgets among them (paw/roles.tl).
paw.roles = require("paw.roles")
paw.ui.role, paw.ui.roles = paw.roles.define, paw.roles.registry
require("paw.roles.widgets")
require("paw.roles.notes")
require("paw.roles.arrange")
require("paw.menu")
paw.canvas = require("paw.canvas")
-- The tabs and windows as panes of a graphical frontend (paw/panes.tl).
paw.panes = require("paw.panes")
paw.notify = paw.ui.notify
paw.keymap = require("paw.keymap")
paw.keyrule = require("paw.keyrule")

local objects = require("paw.objects")
paw.Track, paw.Device, paw.Clip, paw.Lane = objects.Track, objects.Device, objects.Clip, objects.Lane
paw.tracks, paw.track, paw.device, paw.clip = objects.tracks, objects.track, objects.device, objects.clip
paw.lane = objects.lane
paw.add_track = objects.add_track
paw.restore_track, paw.restore_clip, paw.restore_device =
  objects.restore_track, objects.restore_clip, objects.restore_device
paw.master, paw.project, paw.transport, paw.time = objects.master, objects.project, objects.transport, objects.time
paw.midi = objects.midi
paw.tempo = require("paw.tempo")
paw.midifile = require("paw.midifile")
paw.audio = require("paw.audio")

-- Plugins an extension ships, and what plugins call their keys (paw/plugins.lua).
paw.plugins = require("paw.plugins")

--- Descriptions of each kind of device that you can add to a track. A kind
--- that an extension added (`paw.plugins.add_dir`) has its extension in `from`.
--- @type function(): {types.DeviceType}
function paw.device_types()
  local list = api.device_types()
  for _, info in ipairs(list) do
    info.from = paw.plugins.from[info.kind]
  end
  return list
end

--- Render a track with its devices to audio, as one clip on a new track
--- immediately below it, and mute the original. The new track sends its
--- sound where the original sent it. It uses `paw.render`, so
--- `render.before` runs. `opts.name` is the name of the new track
--- ("<name> (bounced)" by default). `opts.tail` is the seconds rendered
--- after its last clip (2). Returns the new track, or nil when the track
--- has no clips.
function paw.bounce(track, opts)
  opts = opts or {}
  track = type(track) == "table" and track or paw.track(track)
  local finish = 0
  for _, clip in ipairs(track:clips()) do
    finish = math.max(finish, clip.start + clip.length)
  end
  if finish <= 0 then return nil end
  local dir = api.media_dir()
  pcall(paw.api.fs_mkdir, dir)
  local path = string.format("%s/%s-bounce-%d-%d.wav", dir, track.name:gsub("[^%w%-_]", "_"), os.time(), track.id)
  paw.render(path, { tracks = { track.id }, start = 0, ["end"] = finish, tail = opts.tail or 2, bits = 32 })
  local index = 0
  for i, id in ipairs(api.track_list()) do
    if id == track.id then index = i end
  end
  local bounced =
    paw.add_track({ name = opts.name or (track.name .. " (bounced)"), index = index + 1, output = track.output })
  bounced:add_clip({ file = path, start = 0, name = track.name })
  track.mute = true
  return bounced
end

paw.undo, paw.redo = api.undo, api.redo
paw.cursor = require("paw.cursor")
paw.edit = require("paw.edit")
-- Files in languages that compile to Lua (Teal, ...): paw/lang.tl.
paw.lang = require("paw.lang")
paw.ext = require("paw.ext")
paw.vca = require("paw.vca")
paw.groups = require("paw.groups")
-- The folds of each window: tracks drawn as one row (paw/folds.tl).
paw.folds = require("paw.folds")
paw.lanes = require("paw.lanes")
-- The track column and the ruler's bar labels, which extensions add to.
paw.trackcolumn = require("paw.trackcolumn")
paw.ruler = require("paw.ruler")
paw.tempolane = require("paw.tempolane")
paw.frontend = require("paw.frontend")
paw.audition = require("paw.audition")
paw.regex = require("paw.regex")
paw.pick = require("paw.pick")
paw.track_kinds = require("paw.track_kinds")
-- Kinds of clip that extensions define (paw/clip_kinds.tl).
paw.clip_kinds = require("paw.clip_kinds")
paw.fx = require("paw.fx")
paw.routes = require("paw.routes")
paw.controls = require("paw.controls")
paw.takes = require("paw.takes")
paw.stretch = require("paw.stretch")
paw.harmony = require("paw.harmony")
paw.chords = require("paw.chords")
paw.snippet = require("paw.snippet")
-- The window's menus, shown by it and built here (paw/window_menus.tl).
require("paw.window_menus")

-- JSON, for what extensions keep in files: `paw.json.encode(value, pretty)`
-- gives text, `paw.json.decode(text)` the value, or nil and the reason.
paw.json = { encode = api.json_encode, decode = api.json_decode }
-- Binary formats: base64 and little-endian numbers (paw/bytes.tl), ZIP
-- archives (paw/zip.tl); under them, paw.api's base64_encode/decode,
-- deflate/inflate (raw, zlib, gzip) and crc32.
paw.bytes = require("paw.bytes")
paw.zip = require("paw.zip")
-- XML (paw/xml.tl) and TOML, read and written by the core: a TOML table
-- keeps the order of its keys in `getmetatable(t).__keys`.
paw.xml = require("paw.xml")
paw.toml = { encode = api.toml_encode, decode = api.toml_decode }
-- The files of other programs that `:import`, `:open` and `:export` take
-- (paw/formats.tl): MIDI files here, others from extensions.
paw.formats = require("paw.formats")

-- Values kept by the kernel, so they survive `:reload`.
paw.state = setmetatable({}, {
  __index = function(_, key) return api.state_get(key) end,
  __newindex = function(_, key, value) api.state_set(key, value) end,
})

--- Say what the kernel warns of: a few at most, and how many more there
--- are (in the log), when one edit warns of thousands of things.
local function warn()
  local list = api.warnings()
  for i, warning in ipairs(list) do
    if i <= 5 then
      paw.notify(warning, "warn")
    else
      api.log("[warn] " .. warning)
    end
  end
  if #list > 5 then paw.notify(string.format("and %d more warnings, in the log", #list - 5), "warn") end
end

-- Entry points the kernel calls. Not part of the scripting interface.
local K = {}
paw._kernel = K

function K.startup()
  paw.ui.theme(require("paw.theme").groups)
  paw.statusline = require("paw.statusline")
  for _, name in ipairs({
    "arrange",
    "status",
    "cmdline",
    "mixer",
    "devices",
    "pianoroll",
    "eventlist",
    "help",
    "effect_windows",
  }) do
    require("paw.views." .. name)
  end
  -- What the pointer does in them: the window's gestures, in cells.
  for _, name in ipairs({ "arrange_mouse", "pianoroll_mouse", "panels_mouse" }) do
    require("paw.views." .. name)
  end
  paw.address = require("paw.address")
  paw.diagnostic = require("paw.diagnostic")
  paw.annotation = require("paw.annotation")
  require("paw.locators")
  paw.lsp = require("paw.lsp")
  -- Step input from a MIDI controller, and the views that take it (paw/step.tl).
  paw.step = require("paw.step")
  require("paw.defaults")
  paw.layout.setup()
  paw.curves = require("paw.curves")
  paw.plot = require("paw.plot")
  paw.curves.editor = require("paw.views.curve")
  paw.complete = require("paw.complete")
  paw.fx.setup()
  paw.routes.setup()
  paw.media = require("paw.media")
  paw.external = require("paw.external")
  -- Rendering: `paw.render(path, opts)` renders the project to a file, and
  -- the module has stems, the tags and the render that runs in the
  -- background (paw/render.tl). The other names are older.
  paw.render = require("paw.render")
  paw.render_stems, paw.render_tags, paw.render_ranges = paw.render.stems, paw.render.tags, paw.render.ranges
  paw.render_status, paw.render_cancel = paw.render.status, paw.render.cancel
  -- Freezing tracks, and the scope of each window: a part of the song.
  paw.freeze = require("paw.freeze")
  paw.scope = require("paw.scope")
  paw.pick.sources.scopes = paw.scope.source
  paw.stems = require("paw.stems")
  paw.markers = require("paw.markers")
  -- Insert mode in the arrange view, and what its keys insert (paw/insert.tl).
  paw.insert = require("paw.insert")
  -- Listings edited as text (`:e paw://tracks`), and the kinds built in.
  paw.textbuf = require("paw.textbuf")
  require("paw.views.tracklist")
  paw.files = require("paw.views.files")
  paw.recent = require("paw.recent")
  paw.learn = require("paw.learn")
  paw.remote = require("paw.remote")
  -- What graphical frontends are sent of the views they show (paw/scene.tl).
  paw.scene = require("paw.scene")
  paw.autosave = require("paw.autosave")
  paw.loading = require("paw.loading")
  paw.reconnect = require("paw.reconnect")
  paw.qf = require("paw.qf")
  require("paw.views.qflist")
  paw.ex = require("paw.ex")
  -- Searching the project: queries over its tree, and its text.
  paw.query = require("paw.query")
  paw.grep = require("paw.grep")
  require("paw.structure")
  -- The manual inside the program (`:help`).
  paw.markdown = require("paw.markdown")
  paw.help = require("paw.help")
  paw.ui.start_ticker()

  paw.luadev = require("paw.luadev")
  -- `:checkhealth`, and the checks extensions add (paw/health.lua).
  paw.health = require("paw.health")
  local env = api.env()
  -- Extensions the program was built with (`paw.withExtensions` in the
  -- flake): part of the program, so loaded with `--clean` too.
  paw.ext.load_packaged(os.getenv("PAW_EXTENSIONS"))
  if not env.clean then
    paw.luadev.add_dir(env.config_dir .. "/devices", paw.luadev.RANK_CONFIG)
    paw.ext.load_dir(env.config_dir .. "/extensions")
    -- init.lua, or init.tl (or another language's) when there is no init.lua.
    local init = paw.lang.find(env.config_dir .. "/init")
    if init then
      local chunk, err = paw.lang.loadfile(init)
      if chunk then
        paw.try(paw.limit.untrusted(chunk))
      else
        paw.notify(err, "error")
      end
    end
    paw.snippet.load_dir(env.config_dir .. "/snippets", "config")
  end
  warn()
  paw.emit("startup", {})
end

--- The program is about to end.
function K.exit() paw.emit("exit", {}) end

function K.key(key)
  if paw.remote and paw.remote.touch then paw.remote.touch() end
  if not paw.hooks.key(key) then return end
  -- The keys of a finished command (`dd`, `3>ic`) label the undo step it makes.
  -- Keys typed into a prompt are text, not commands.
  local typed = not paw.ui.grabber and paw.keymap.pending() .. key
  -- A key acts in the window with the keyboard, with its state.
  paw.layout.settle()
  paw.limit.guard("the key " .. key, paw.keymap.dispatch, key)
  if typed and paw.keymap.pending() == "" then api.undo_keys(typed) end
end

function K.paste(text)
  if paw.ui.grabber then paw.limit.guard("pasting", paw.ui.grabber, text, true) end
end

function K.mouse(event)
  if paw.remote and paw.remote.touch then paw.remote.touch() end
  paw.limit.guard("the mouse", paw.ui.mouse, event)
end

--- The terminal or the window got the focus of the desktop, or lost it.
function K.focus(on)
  paw.ui.has_focus = on
  paw.emit("ui.focus", { focused = on })
end

function K.resize(width, height) paw.emit("ui.resized", { width = width, height = height }) end

--- Send the change events for the edits made until now. The kernel does
--- this at the end of each turn. Call `paw.flush()` to make handlers run sooner.
--- @type function()
local function settle()
  -- Handlers may edit the project and cause more events, so go round until
  -- it is quiet, with a limit in case two handlers keep triggering each other.
  for _ = 1, 64 do
    local events = api.events_take()
    if #events == 0 then return end
    for _, event in ipairs(events) do
      if event.name == "changed" then
        warn()
        api.ui_redraw()
      elseif event.name == "transport.record" then
        -- What starting a take has to say (a punch range already passed).
        warn()
      end
      paw.hooks.note(event.name, event.payload)
      paw.emit(event.name, event.payload)
    end
  end
  paw.notify("event handlers keep triggering each other; stopped delivering events for this turn", "error")
end

paw.flush = settle

--- The kernel's own call at the end of a turn: with the time limit on the
--- handlers it runs.
function K.settle()
  paw.limit.guard("an event handler", settle)
  -- Hooks first: `edit.before` may take the turn back, and the scenes
  -- sent after it must show what stayed.
  paw.limit.guard("the end of a turn", paw.hooks.turn)
  if paw.scene then paw.limit.guard("sending scenes", paw.scene.turn) end
  if paw.remote and paw.remote.turn then paw.limit.guard("sending the state", paw.remote.turn) end
end

function K.timer(fn) paw.limit.guard("a timer", fn) end

function K.render(width, height) paw.limit.guard("drawing the screen", paw.ui.render, paw.ui.Buf.root(width, height)) end

--- Only the live parts of the screen drawn again (`paw.api.ui_redraw_live`):
--- false when it must be drawn whole.
function K.render_live(width, height)
  local ok, done = paw.limit.guard("drawing what moves", paw.ui.render_live, paw.ui.Buf.root(width, height))
  return ok ~= false and done == true
end

--- One view drawn by itself, for a window: see `paw.api.ui_view_snapshot`.
function K.render_view(name, width, height)
  paw.limit.guard("drawing the view " .. name, paw.ui.render_view, name, paw.ui.Buf.root(width, height))
end

--- Calls from the control socket: `eval`, `cmd`, `keys`, what `paw.remote`
--- offers a connection (`client` is its number), or any `paw.api` function.
--- Each has the time limit a key has: the window's gestures come this way.
local function rpc(method, params, client)
  local offered = paw.remote and paw.remote.methods[method]
  if offered then
    return offered(client or 0, unpack(params))
  elseif method == "eval" then
    local code = params[1]
    if type(code) ~= "string" then error("`eval` takes the code to run, as a string", 0) end
    local chunk, err = loadstring("return " .. code, "=rpc")
    if not chunk then
      chunk, err = loadstring(code, "=rpc")
    end
    if not chunk then error(err, 0) end
    return chunk(unpack(params, 2))
  elseif method == "cmd" then
    local line = table.concat(params, " ")
    -- Named by the line, as one typed after `:` is.
    api.undo_label(nil)
    api.undo_label(":" .. line)
    return paw.commands.exec(line)
  elseif method == "keys" then
    return paw.keymap.feed(params[1])
  elseif method == "render" then
    -- Through `paw.render`, so that what listens for `render.before` hears of it.
    return paw.render(unpack(params))
  elseif api[method] then
    return api[method](unpack(params))
  end
  error("no method `" .. tostring(method) .. "`", 0)
end

function K.rpc(method, params, client)
  if type(params) ~= "table" then params = { params } end
  if paw.remote and paw.remote.touch then paw.remote.touch() end
  return paw.limit.call("the request `" .. tostring(method) .. "`", rpc, method, params, client)
end

--- A connection on the control socket closed.
function K.rpc_closed(client)
  if paw.remote then paw.remote.closed(client) end
  if paw.scene then paw.scene.closed(client) end
  paw.seats.close(client)
end

--- Whose turn it is: a connection with a seat of its own, or 0.
function K.seat(client) paw.seats.enter(client) end

--- A connection's terminal attached, or went away.
function K.seat_open(client, why) paw.seats.open(client, why) end

function K.seat_close(client, why) paw.limit.guard("leaving a seat", paw.seats.close, client, why) end

-- With a screen attached, stdout belongs to the terminal UI.
local raw_print = print
function print(...)
  if not api.ui_attached() then return raw_print(...) end
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring((select(i, ...)))
  end
  paw.notify(table.concat(parts, "  "))
end

return paw
