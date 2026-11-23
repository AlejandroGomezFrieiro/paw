-- Rendering: `paw.render`, the tags, and the render
-- that runs in the background with its progress and cancelling. The work is
-- in the kernel (crates/paw-core/src/session/render.rs).
--
-- `paw.render` is this module, and a call of it renders:
-- `paw.render(path, opts)` is `paw.render.render(path, opts)`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local util = require("paw.util")
local type types = require("paw.types")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")

--- A range that a render can take: where it starts and ends, in beats (no
--- end: the end of the last clip), or nil and why not.
local type Range = function(): number, number | string

--- The options of `paw.render` (see `M.render`): what the kernel takes
--- (`types.RenderOptions`), and what only Lua knows: `range`, `rate`,
--- `background`, `quiet`, and `format` (false takes it out).
local record Options
  range: string
  start: number
  ["end"]: number
  tail: number
  sample_rate: integer
  rate: integer
  bits: integer
  channels: types.RenderChannels
  dither: boolean
  quality: string
  bitrate: integer | string
  tags: types.RenderTags
  normalize: number
  loudness: number
  gain: number
  tracks: {integer}
  tap: types.RenderTap
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
  quiet: boolean
end

--- The export that renders its files one by one (paw/export.tl): which
--- file of how many runs now. The status line shows it.
local record Batch
  index: integer
  total: integer
  --- What the status line says in place of the name of the file.
  label: string
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

--- A value that a copy passes on and never reads.
local record Value
end

-- What this module reads of `paw`, which paw/init.lua makes, and of the
-- modules that it calls: their parts that it uses.
local type UiModule = require("paw.ui")
local record Paw is partial.Paw
  keymap: KeymapModule
  ui: UiModule
end
local paw = (_G as {string: Paw}).paw

local record M
  type Range = Range
  type Options = Options
  type Status = Status
  type Before = Before
  type Batch = Batch
  --- Named ranges a render can take besides beats: each a function giving
  --- `start, end` in beats, or nil and why not. Extensions may add their own
  --- (`paw.render_ranges.chorus = function() return 32, 48 end`).
  ranges: {string: Range}
  --- The tags that `paw.render_tags` reads and sets, in order.
  tag_names: {string}
  --- The event `render.before`: a render will start.
  before: events.Event<Before>
  --- The event `render.finished`: what a render in the foreground wrote.
  finished: events.Event<types.RenderResult>
  --- The folder that renders go to when no place is named (defined below).
  renders_dir: function(): string
  --- The export that runs, while it runs (paw/export.tl sets it).
  batch: Batch
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

--- The options as the kernel takes them: `range` turned into `start` and
--- `end`, and what only Lua knows taken out.
local function kernel_opts(opts: Options): types.RenderOptions
  local out = copy(opts or {})
  local range = out.range
  out.range, out.background, out.format, out.quiet = nil, nil, nil, nil
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

-- Renders waiting for the one running: one render runs at a time.
local queue: {Queued} = {}
-- The files of renders in the background that say nothing when they end:
-- the export that started them says what they came to.
local quiet: {string: boolean} = {}

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
---   channels    "stereo" (the default), "mono" (one channel: (left + right) / 2) or
---               "auto" (one channel when the two sides are equal to the bit, else two)
---   dither      true to add dither when writing 16 or 24 bits
---   quality     for MP3, Ogg Vorbis and Opus: "low", "medium", "high" (the
---               default) or "best"; `bitrate` (kbit/s) instead of it for a number
---   tags        { title, artist, album, track, year, genre, comment, cover } written into
---               the file, over the project's own (`paw.render_tags`); `cover` is a PNG or
---               JPEG file (a WAV holds no cover); the title of a lossy file is the project's name by default
---   normalize   bring the loudest sample to this level in dB, such as -1
---   loudness    bring the integrated loudness to this level in LUFS, such as -14;
---               with `normalize` too, the peak level is a ceiling
---   gain        raise or lower the whole file by this many dB, such as -3.5; not with
---               `normalize` or `loudness` (an export of stems gives each stem the gain of the mix)
---   tracks      { id, ... }: only these, with what they pass through (a stem)
---   tap         where in the sound of the tracks the render listens:
---               "pre"     their clips and devices, without the fader, pan or mute
---               "post"    with the fader, pan and mute, without the groups, sends or master
---               "groups"  as when they are soloed, through their groups and the
---                         returns of their sends, without the master
---               "master"  through the master as well (the default)
---               "pre" and "post" need `tracks`. The files of "groups" and
---               "master" add up to the mix.
---   master      false is the same as tap = "groups"
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
---   quiet       with `background`: no message when it ends, for a caller that
---               says itself what it rendered
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
    quiet[path] = opts.quiet or nil
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
    if not quiet[info.path] then
      notify_rendered(info.path, info, info.loudness and string.format(", %.1f LUFS", info.loudness) or "")
    end
    quiet[info.path] = nil
    for _, why in ipairs(info.left_out or {}) do
      paw.notify(why, "warn")
    end
    next_in_queue()
  end
)
events.on(
  kernel.render_failed,
  function(e: kernel.RenderEnd)
    if not quiet[e.path] then
      paw.notify("render of " .. name_of(e.path) .. " failed: " .. tostring(e.error), "error")
    end
    quiet[e.path] = nil
    next_in_queue()
  end
)
events.on(
  kernel.render_cancelled,
  function(e: kernel.RenderEnd)
    queue = {}
    if not quiet[e.path] then
      paw.notify("render of " .. name_of(e.path) .. " cancelled; no file written")
    end
    quiet = {}
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

return setmetatable(
  M,
  {
    __call = function(_: M, path: string, opts?: Options): types.RenderResult return M.render(path, opts) end,
  } as metatable<M>
)
