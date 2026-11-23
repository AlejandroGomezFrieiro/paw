-- Rendering: `paw.render`, stems, the `:render` command, and the render
-- that runs in the background with its progress and cancelling. The work is
-- in the kernel (crates/paw-core/src/session/render.rs).
--
-- `paw.render` is this module, and a call of it renders:
-- `paw.render(path, opts)` is `paw.render.render(path, opts)`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local commands = require("paw.commands")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local util = require("paw.util")
local type types = require("paw.types")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type objects = require("paw.objects")
local type CursorModule = require("paw.cursor")
local type GroupsModule = require("paw.groups")

--- A range that a render can take: where it starts and ends, in beats (no
--- end: the end of the last clip), or nil and why not.
local type Range = function(): number, number | string

--- The options of `paw.render` (see `M.render`): what the kernel takes
--- (`types.RenderOptions`), and what only Lua knows: `range`, `rate`,
--- `channels` as a word, `background`, and `format` for stems (false
--- takes it out).
local record Options
  range: string
  start: number
  ["end"]: number
  tail: number
  sample_rate: integer
  rate: integer
  bits: integer
  channels: integer | string
  dither: boolean
  quality: string
  bitrate: integer | string
  tags: types.RenderTags
  normalize: number
  loudness: number
  tracks: {integer}
  master: boolean
  threads: integer
  freeze: integer
  block: integer
  through: {integer}
  sleep: boolean
  settle: number
  ffmpeg: string
  background: boolean
  format: string | boolean
end

--- The render that runs in the background, and how many wait after it.
local record Status
  path: string
  fraction: number
  seconds: number
  cancelling: boolean
  stage: types.RenderStage
  queued: integer
end

--- The payload of `render.before`: the file, and the options as the kernel
--- takes them. A measure of the sound (`paw.api.measure`) writes no file:
--- it has no `path`, and `measure` is true.
local record Before
  path: string
  opts: types.RenderOptions
  measure: boolean
end

--- An entry of `M.options`: the key with its `=`, the values to complete, and what it is.
local record Option is {string | {string}}
end

--- A value that a copy passes on and never reads.
local record Value
end

-- What this module reads of `paw`, which paw/init.lua makes, and of the
-- modules in Lua that it calls: their parts that it uses.
--- `paw.stems` (paw/stems.lua), as far as `:render` calls it.
local record Stems
  names_group: function(word: commands.Arg): boolean
  command: function(ctx: commands.Context, opts: Options)
end
--- `paw.files` (paw/views/files.lua): a path from the folder `:cd` set.
local record Files
  path: function(name: string): string
end
local type UiModule = require("paw.ui")
local record Paw is partial.Paw
  keymap: KeymapModule
  ui: UiModule
  cursor: CursorModule
  groups: GroupsModule
  tracks: function(): {objects.Track}
end
local paw = (_G as {string: Paw}).paw

local record M
  type Range = Range
  type Options = Options
  type Status = Status
  type Before = Before
  --- Named ranges a render can take besides beats: each a function giving
  --- `start, end` in beats, or nil and why not. Extensions may add their own
  --- (`paw.render_ranges.chorus = function() return 32, 48 end`).
  ranges: {string: Range}
  --- The tags that `paw.render_tags` reads and sets, in order.
  tag_names: {string}
  --- What `:render` takes, for its description and completion: `{ key=, values, what }`.
  options: {Option}
  --- The event `render.before`: a render will start.
  before: events.Event<Before>
  --- The event `render.finished`: what a render in the foreground wrote.
  finished: events.Event<types.RenderResult>
  --- The folder that renders go to when no place is named (defined below).
  renders_dir: function(): string
  --- `paw.render(path, opts)` is `paw.render.render(path, opts)`.
  metamethod __call: function(self: M, path: string, opts?: Options): types.RenderResult
end

M.before = events.event("render.before")
M.finished = events.event("render.finished")

M.ranges = {
  song = function(): number, number | string return 0, nil end,
  loop = function(): number, number | string
    local t = api.transport_get()
    if not (t.loop_end > t.loop_start) then
      return nil, "there is no loop"
    end
    return t.loop_start, t.loop_end
  end,
  selection = function(): number, number | string
    local sel = paw.keymap.selection()
    if not (sel and sel.c0 and sel.c1 and sel.c1 > sel.c0) then
      return nil, "nothing is selected: select a stretch of time first"
    end
    return sel.c0, sel.c1
  end,
}

--- A shallow copy of a record.
local function copy<T>(t: T): T
  local out: {string: Value} = {}
  for k, v in pairs(t as {string: Value}) do
    out[k] = v
  end
  return out as T
end

--- A shallow copy of a record with the fields of `extra` laid over it.
local function over<T>(base: T, extra: T): T
  return util.merge(base as {string: Value}, extra as {string: Value}) as T
end

--- The options as the kernel takes them: `range` turned into `start` and
--- `end`, and what only Lua knows taken out.
local function kernel_opts(opts: Options): types.RenderOptions
  local out = copy(opts or {})
  local range = out.range
  out.range, out.background, out.format = nil, nil, nil
  if out.channels == "mono" then
    out.channels = 1
  elseif out.channels == "stereo" then
    out.channels = 2
  end
  if out.rate then
    out.sample_rate, out.rate = out.rate, nil
  end
  local rate = out.sample_rate
  if rate ~= nil and not (type(rate) == "number" and rate % 1 == 0 and rate >= 8000 and rate <= 384000) then
    error("a sample rate is a whole number of Hz from 8000 to 384000, not " .. tostring(rate), 0)
  end
  out.ffmpeg = out.ffmpeg or options.opt.ffmpeg
  out.bitrate = tonumber(out.bitrate) as integer
  if out.tags and next(out.tags as {string: string}) == nil then
    out.tags = nil
  end
  if range and range ~= "song" then
    local resolve = M.ranges[range]
    if not resolve then
      local names: {string} = {}
      for name in pairs(M.ranges) do
        names[#names + 1] = name
      end
      table.sort(names)
      error(
        string.format(
          "no range `%s`: use %s, or start= and end= in beats", tostring(range), table.concat(names, ", ")
        ),
        0
      )
    end
    local start, finish = resolve()
    if not start then
      error(finish as string, 0)
    end
    out.start, out["end"] = start, finish as number
  end
  return out as types.RenderOptions
end

local function check(path: string)
  local why = api.render_check(path, options.opt.ffmpeg)
  if why then
    error(why, 0)
  end
end

--- A render waiting for the one running.
local record Queued
  path: string
  opts: types.RenderOptions
end

-- Renders waiting for the one running: stems are rendered one at a time.
local queue: {Queued} = {}

local function start(path: string, opts: types.RenderOptions)
  events.emit(M.before, {path = path, opts = opts})
  api.render_start(path, opts)
  paw.ui.poke()
end

--- Render the project to a file: WAV or FLAC, or MP3, Ogg Vorbis or Opus
--- when ffmpeg is installed (`paw.opt.ffmpeg` says where it is, if not on
--- the PATH), by the file's extension. A lossy file is rendered to a
--- temporary WAV, which ffmpeg then encodes.
--- `opts` (all optional):
---   range       "song" (the default), "loop", "selection", or a name in `paw.render_ranges`
---   start, end  beats, instead of a range (`end` defaults to the end of the last clip)
---   tail        seconds after the end, for reverbs and delays to ring out (1)
---   sample_rate (or rate) Hz; the engine's by default
---   bits        16, 24 or 32 (float; WAV only); 24 by default
---   channels    2 (or "stereo") or 1 (or "mono")
---   dither      true to add dither when writing 16 or 24 bits
---   quality     for MP3, Ogg Vorbis and Opus: "low", "medium", "high" (the
---               default) or "best"; `bitrate` (kbit/s) instead of it for a number
---   tags        { title, artist, album, track, year, genre, comment, cover } written into
---               the file, over the project's own (`paw.render_tags`); `cover` is a PNG or
---               JPEG file (a WAV holds no cover); the title of a lossy file is the project's name by default
---   normalize   bring the loudest sample to this level in dB, such as -1
---   loudness    bring the integrated loudness to this level in LUFS, such as -14;
---               with `normalize` too, the peak level is a ceiling
---   tracks      { id, ... }: only these, with what they pass through (a stem)
---   master      false to leave out the master track's devices, fader and pan
---   freeze      a track id: that track alone, before its fader, as a freeze renders it
---   block       a clip id of a block of a subproject: what the block plays into its row,
---               and nothing else, as a freeze of the block renders it
---   through     with `block` inside a subproject: the blocks that place it in the song,
---               outer first (`paw.api.block_path`); its first ones when left out
---   threads     threads to render on
---   background  true to return at once and render on a thread of its own:
---               `render.progress` ({ path, fraction, seconds }) follows now
---               and then, and `render.done` (what is returned below),
---               `render.failed` ({ path, error }) or `render.cancelled` at the end;
---               a render in the foreground emits `render.finished` with what it returns
--- When it is done, it returns `types.RenderResult`. The result has the path,
--- the frames, the seconds, the peak, the gain and the loudness. It also has
--- the format, the bits (nil for a lossy format) and the channels.
---
--- paw emits `render.before` first. Its handlers run before the render
--- starts, so an extension that makes audio of its own can complete it. paw refuses a file that it cannot
--- write before it renders. When a render fails or stops, no file has the
--- name that you gave.
function M.render(path: string, opts?: Options): types.RenderResult
  path = util.expand_path(path)
  check(path)
  -- The renders folder is made when the first render goes into it.
  local dir = M.renders_dir()
  if dir and path:match("^(.*)/[^/]+$") == dir then
    pcall(api.fs_mkdir, dir)
  end
  local background = opts and opts.background
  local kopts = kernel_opts(opts)
  if background then
    if api.render_status() then
      queue[#queue + 1] = {path = path, opts = kopts}
    else
      start(path, kopts)
    end
    return nil
  end
  events.emit(M.before, {path = path, opts = kopts})
  local info = api.render(path, kopts)
  -- What the render had to leave out (a plugin that stopped answering).
  for _, why in ipairs(info.left_out or {}) do
    paw.notify(why, "warn")
  end
  -- As `render.done` says of a render in the background.
  local finished = copy(info)
  finished.path = info.path or path
  events.emit(M.finished, finished)
  return info
end

M.tag_names = {"title", "artist", "album", "track", "year", "genre", "comment", "cover"}

--- What the project's rendered files are tagged with (`project.meta.tags`):
--- `paw.render_tags()` gives `{ title, artist, album, track, year, genre, comment, cover }`
--- as far as set; `paw.render_tags({ artist = "Me" })` sets those fields and keeps the others,
--- an empty string takes one out. A relative `cover` is from the project's directory.
function M.tags(set?: types.RenderTags): types.RenderTags
  local meta = api.project_get().meta
  local tags = (meta.tags or {}) as {string: string}
  local given = set as {string: string | number}
  local changed = false
  for _, key in ipairs(M.tag_names) do
    local value = given and given[key]
    if value ~= nil then
      local text = tostring(value) ~= "" and tostring(value) or nil
      changed = changed or tags[key] ~= text
      tags[key] = text
    end
  end
  -- The project is only touched when a tag is different.
  if changed then
    meta.tags = next(tags) ~= nil and tags or nil
    api.project_set({meta = meta})
  end
  return tags as types.RenderTags
end

--- The render in the background: `{ path, fraction, seconds, cancelling,
--- stage, queued }`, or nil. `stage` is "rendering", or "encoding" when
--- ffmpeg makes a lossy file from the render. Then `fraction` tells how
--- far the encoding is.
function M.status(): Status
  local s = api.render_status() as Status
  if s then
    s.queued = #queue
  end
  return s
end

--- Stop the render in the background, and the renders that wait after it.
--- paw does not write its file. Returns true if a render ran.
function M.cancel(): boolean
  queue = {}
  return api.render_cancel()
end

--- Render each track on its own into a directory, one file per track named
--- after it: stems. A track is rendered with what it passes through on the
--- way to the master, as when it is soloed, so that the stems add up to the
--- mix. `opts` is as for `paw.render`, plus `tracks` to choose which (all
--- that are not muted, by default) and `format` ("wav", "flac", "mp3", "ogg"
--- or "opus"). With
--- `background`, they are rendered one after another. Returns the files.
function M.stems(dir: string, opts?: Options): {string}
  dir = util.expand_path(dir)
  opts = opts or {}
  local ext = opts.format as string or "wav"
  check(dir .. "/stem." .. ext)
  pcall(api.fs_mkdir, dir)
  local out: {string} = {}
  local used: {string: integer} = {}
  local tracks = opts.tracks
  if not tracks then
    tracks = {}
    for _, track in ipairs(paw.tracks()) do
      if not track.mute and #track:clips() > 0 then
        tracks[#tracks + 1] = track.id
      end
    end
  end
  for _, given in ipairs(tracks) do
    -- A track as a table (from Lua) gives its id.
    local id = type(given) == "table" and (given as objects.Track).id or given
    local name = api.track_get(id).name:gsub("[^%w%-_ ]", "_")
    -- Two tracks of one name get a number each.
    used[name] = (used[name] or 0) + 1
    if used[name] > 1 then
      name = name .. " " .. used[name]
    end
    local path = string.format("%s/%s.%s", dir, name, ext)
    -- A lossy stem is titled after its track, unless the options say otherwise.
    local lossy = ext ~= "wav" and ext ~= "flac"
    local tags = over(lossy and {title = name} or {}, opts.tags or {})
    M.render(path, over(opts, {tracks = {id}, format = false, tags = tags}))
    out[#out + 1] = path
  end
  return out
end

local function next_in_queue()
  local nxt = table.remove(queue, 1)
  if nxt then
    local ok, err = pcall(start, nxt.path, nxt.opts) as (boolean, string)
    if not ok then
      paw.notify("could not render " .. nxt.path .. ": " .. tostring(err), "error")
      return next_in_queue()
    end
  end
end

local function name_of(path: string): string
  return tostring(path):match("([^/]+)$") or tostring(path)
end

--- Say what a render came to. The peak has its sign (`+6.2 dB` is over
--- full scale) and a peak over it is a warning, as it clips.
local function notify_rendered(path: string, info: types.RenderResult, more: string)
  local peak = 20 * math.log10(math.max(info.peak, 1e-6))
  paw.notify(
    string.format(
      "rendered %s: %.1f s, peak %+.1f dB%s%s", name_of(path), info.seconds, peak, more, peak > 0 and " (clips)" or ""
    ),
    peak > 0 and "warn" or "info"
  )
end

events.on(kernel.render_progress, function() api.ui_redraw() end)
events.on(
  kernel.render_done,
  function(info: types.RenderResult)
    notify_rendered(info.path, info, info.loudness and string.format(", %.1f LUFS", info.loudness) or "")
    for _, why in ipairs(info.left_out or {}) do
      paw.notify(why, "warn")
    end
    next_in_queue()
  end
)
events.on(
  kernel.render_failed,
  function(e: kernel.RenderEnd)
    paw.notify("render of " .. name_of(e.path) .. " failed: " .. tostring(e.error), "error")
    next_in_queue()
  end
)
events.on(
  kernel.render_cancelled,
  function(e: kernel.RenderEnd)
    queue = {}
    paw.notify("render of " .. name_of(e.path) .. " cancelled; no file written")
  end
)
-- `Esc` in normal mode, with nothing else to cancel, stops a render.
local escape: events.Event<events.Payload> = events.event("escape")
events.on(
  escape,
  function()
    if api.render_status() then
      M.cancel()
    end
  end
)

-- The command ------------------------------------------------------------------

M.options = {
  {"range=", {"song", "loop", "selection"}, "what to render"},
  {"start=", nil, "beat to start at"},
  {"end=", nil, "beat to end at"},
  {"tail=", {"0", "1", "2", "4"}, "seconds after the end"},
  {"rate=", {"44100", "48000", "96000"}, "sample rate"},
  {"bits=", {"16", "24", "32"}, "sample size; 32 is float"},
  {"quality=", {"low", "medium", "high", "best"}, "of an MP3, Ogg or Opus file"},
  {"bitrate=", {"128", "192", "256", "320"}, "kbit/s of an MP3, Ogg or Opus file"},
  {"channels=", {"stereo", "mono"}, ""},
  {"dither=", {"true"}, "dither at 16 or 24 bits"},
  {"normalize=", {"-1", "-0.3"}, "peak level in dB"},
  {"loudness=", {"-14", "-16", "-23"}, "integrated loudness in LUFS"},
  {"tracks=", {"selected", "all"}, "a stem of these tracks (ids, comma-separated)"},
  {"stems=", {"true"}, "one file per track, into a directory"},
  {"master=", {"false"}, "leave out the master's devices and fader"},
  {"wait=", {"true"}, "render in the foreground"},
  {"title=", nil, "tag; the project's name by default"},
  {"artist=", nil, "tag"},
  {"album=", nil, "tag"},
  {"track=", nil, "tag: a number, or 3/12"},
  {"year=", nil, "tag"},
  {"genre=", nil, "tag"},
  {"comment=", nil, "tag"},
  {"cover=", nil, "tag: a PNG or JPEG file"},
}

--- The folder that renders go to when no place is named: `renders/` in
--- the project's folder, apart from the files of the project; the folder
--- of a project kept in one file; nil before the first save.
function M.renders_dir(): string
  local p = api.project_get()
  local path = p.path and tostring(p.path)
  if not path or path == "" then
    return nil
  end
  local dir = path:match("^(.*)/[^/]+$") or "."
  if path:match("/project%.toml$") then
    return dir .. "/renders"
  end
  return dir
end

--- The file a render writes when no file is named: the project's name, in `renders_dir()`.
function M.default_path(): string
  local p = api.project_get()
  local name = (p.name and p.name ~= "" and p.name or "render"):gsub("[^%w%-_ ]", "_")
  local dir = M.renders_dir()
  return (dir and dir .. "/" or "") .. name .. ".wav"
end

local function track_list(spec: commands.Arg): {integer}
  if spec == nil or spec == "all" then
    return nil
  end
  if spec == "selected" then
    local id = paw.cursor.track_id()
    if not id then
      error("no track is selected", 0)
    end
    return {id}
  end
  local ids: {integer} = {}
  for n in tostring(spec):gmatch("[^,%s]+") do
    local id = tonumber(n) as integer
    if not id then
      error("not a track id: " .. n, 0)
    end
    ids[#ids + 1] = id
  end
  return ids
end

commands.define(
  "render",
  function(ctx: commands.Context): commands.Result
    local a = ctx.args
    local opts: Options = {
      range = a.range as string,
      start = tonumber(a.start),
      ["end"] = tonumber(a["end"]),
      tail = tonumber(a.tail),
      rate = tonumber(a.rate) as integer,
      bits = tonumber(a.bits) as integer,
      quality = a.quality and tostring(a.quality) or nil,
      bitrate = tonumber(a.bitrate) as integer,
      dither = a.dither == true or nil,
      channels = a.channels == "mono" and 1 or a.channels == "stereo" and 2 or tonumber(a.channels) as integer,
      normalize = tonumber(a.normalize),
      loudness = tonumber(a.loudness),
      master = a.master ~= false and nil or false,
      tracks = track_list(a.tracks),
      background = a.wait ~= true,
    }
    local tags: {string: string} = {}
    for _, key in ipairs(M.tag_names) do
      if a[key] ~= nil and a[key] ~= true then
        tags[key] = a[key] as string
      end
    end
    opts.tags = next(tags) ~= nil and tags as types.RenderTags or nil
    if opts.start or opts["end"] then
      opts.range = nil
    end
    -- `:render stems` and `:render Strings`: by group, the plan shown first.
    local stems = (require as function(string): Stems)("paw.stems")
    if a[1] == "stems" or stems.names_group(a[1]) then
      opts.tracks = nil
      return stems.command(ctx, opts)
    end
    if a.stems == true then
      local dir = a[1] and (paw.files as Files).path(tostring(a[1])) or ((M.renders_dir() or ".") .. "/stems")
      local made = M.stems(dir, over(opts, {format = a.format as string}))
      return paw.notify(string.format("rendering %d stem%s into %s", #made, #made == 1 and "" or "s", dir))
    end
    -- A relative name goes beside the project, or to the folder `:cd` set.
    local path = a[1] and (paw.files as Files).path(tostring(a[1])) or M.default_path()
    local info = M.render(path, opts)
    if info then
      notify_rendered(path, info, "")
    else
      paw.notify("rendering " .. name_of(path) .. " · Esc cancels")
    end
  end,
  {
    desc = "Render to WAV or FLAC by the file's extension, or MP3, Ogg or Opus with ffmpeg installed: `render mix.flac "
      .. "range=loop tail=2 bits=16 dither=true channels=mono rate=44100 normalize=-1 loudness=-14 tracks=selected master=false stems=true`; "
      .. "`render stems [dir]` one file per group (`render stems tracks` per track), `render Strings` one group",
    complete = function(rest: string): {string}
      local before, last = rest:match("^(.-)(%S*)$")
      local out: {string} = {}
      local key = last:match("^(%w+)=")
      if before == "" and not key then
        out[1] = "stems"
        for _, id in ipairs(api.track_list()) do
          if paw.groups.is_group(id) then
            out[#out + 1] = api.track_get(id).name
          end
        end
      end
      for _, o in ipairs(M.options) do
        local name = o[1] as string
        if key and name == key .. "=" then
          for _, v in ipairs(o[2] as {string} or {}) do
            out[#out + 1] = before .. name .. v
          end
        elseif not key then
          out[#out + 1] = before .. name
        end
      end
      return out
    end,
  }
)

commands.define(
  "render.tags",
  function(ctx: commands.Context): commands.Result
    local set: {string: string} = {}
    for _, key in ipairs(M.tag_names) do
      if ctx.args[key] ~= nil and ctx.args[key] ~= true then
        set[key] = ctx.args[key] as string
      end
    end
    local tags = M.tags(next(set) ~= nil and set as types.RenderTags or nil) as {string: string}
    local words: {string} = {}
    for _, key in ipairs(M.tag_names) do
      if tags[key] then
        words[#words + 1] = key .. "=" .. tostring(tags[key])
      end
    end
    paw.notify(
      #words > 0 and ("rendered files are tagged " .. table.concat(words, ", "))
        or "no tags: set some with `render.tags artist=Me album=First`"
    )
  end,
  {
    desc = "Show or set the tags of the project's rendered files: `render.tags artist=Me album=\"First one\" track=3 "
      .. "year=2026 genre=Ambient comment=\"a note\" cover=cover.png`; an empty value takes one out",
  }
)

commands.define(
  "render.cancel",
  function(): commands.Result
    if not M.cancel() then
      paw.notify("nothing is being rendered")
    end
  end,
  {desc = "Stop the render running in the background; it leaves no file"}
)

commands.define(
  "stems",
  function(ctx: commands.Context): commands.Result
    local dir = ctx.args[1] and (paw.files as Files).path(tostring(ctx.args[1]))
      or ((M.renders_dir() or ".") .. "/stems")
    local made = M.stems(
      dir,
      {
        tail = tonumber(ctx.args.tail),
        bits = tonumber(ctx.args.bits) as integer,
        format = ctx.args.format as string,
        quality = ctx.args.quality and tostring(ctx.args.quality) or nil,
        bitrate = tonumber(ctx.args.bitrate) as integer,
        master = ctx.args.master ~= false and nil or false,
        background = ctx.args.wait ~= true,
      }
    )
    paw.notify(string.format("rendering %d stem%s into %s", #made, #made == 1 and "" or "s", dir))
  end,
  {desc = "Render each track on its own into a directory: `stems out tail=2 bits=24 format=flac master=false`"}
)

return setmetatable(
  M,
  {
    __call = function(_: M, path: string, opts?: Options): types.RenderResult return M.render(path, opts) end,
  } as metatable<M>
)
