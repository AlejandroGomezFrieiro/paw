-- Rendering: `paw.render`, stems, the `:render` command, and the render
-- that runs in the background with its progress and cancelling. The work is
-- in the kernel (crates/paw-core/src/session/render.rs).
local api = paw.api
local M = {}

--- Named ranges a render can take besides beats: each a function giving
--- `start, end` in beats, or nil and why not. Extensions may add their own
--- (`paw.render_ranges.chorus = function() return 32, 48 end`).
M.ranges = {
  song = function() return 0, nil end,
  loop = function()
    local t = api.transport_get()
    if not (t.loop_end > t.loop_start) then return nil, "there is no loop" end
    return t.loop_start, t.loop_end
  end,
  selection = function()
    local sel = paw.keymap.selection()
    if not (sel and sel.c0 and sel.c1 and sel.c1 > sel.c0) then return nil, "nothing is selected: select a stretch of time first" end
    return sel.c0, sel.c1
  end,
}

--- The options as the kernel takes them: `range` turned into `start` and
--- `end`, and what only Lua knows taken out.
local function kernel_opts(opts)
  local out = {}
  for k, v in pairs(opts or {}) do out[k] = v end
  local range = out.range
  out.range, out.background, out.format = nil, nil, nil
  if out.channels == "mono" then out.channels = 1 elseif out.channels == "stereo" then out.channels = 2 end
  if out.rate then out.sample_rate, out.rate = out.rate, nil end
  local rate = out.sample_rate
  if rate ~= nil and not (type(rate) == "number" and rate % 1 == 0 and rate >= 8000 and rate <= 384000) then
    error("a sample rate is a whole number of Hz from 8000 to 384000, not " .. tostring(rate), 0)
  end
  out.ffmpeg = out.ffmpeg or paw.opt.ffmpeg
  out.bitrate = tonumber(out.bitrate)
  if out.tags and next(out.tags) == nil then out.tags = nil end
  if range and range ~= "song" then
    local resolve = M.ranges[range]
    if not resolve then
      local names = {}
      for name in pairs(M.ranges) do names[#names + 1] = name end
      table.sort(names)
      error(string.format("no range `%s`: use %s, or start= and end= in beats", tostring(range), table.concat(names, ", ")), 0)
    end
    local start, finish = resolve()
    if not start then error(finish, 0) end
    out.start, out["end"] = start, finish
  end
  return out
end

local function check(path)
  local why = api.render_check(path, paw.opt.ffmpeg)
  if why then error(why, 0) end
end

-- Renders waiting for the one running: stems are rendered one at a time.
local queue = {}

local function start(path, opts)
  paw.emit("render.before", { path = path, opts = opts })
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
---   threads     threads to render on
---   background  true to return at once and render on a thread of its own:
---               `render.progress` ({ path, fraction, seconds }) follows now
---               and then, and `render.done` (what is returned below),
---               `render.failed` ({ path, error }) or `render.cancelled` at the end;
---               a render in the foreground emits `render.finished` with what it returns
--- Returns { path, frames, seconds, sample_rate, peak, gain, loudness, format,
--- bits (nil for a lossy format), channels, ... } when done. `render.before` is emitted first, and its
--- handlers run before rendering starts, so an extension that makes audio of
--- its own can finish it. A file that cannot be written is refused before
--- anything is rendered; nothing is left under the name asked for when a
--- render fails or is cancelled.
function M.render(path, opts)
  path = paw.util.expand_path(path)
  check(path)
  local background = opts and opts.background
  opts = kernel_opts(opts)
  if background then
    if api.render_status() then
      queue[#queue + 1] = { path = path, opts = opts }
    else
      start(path, opts)
    end
    return nil
  end
  paw.emit("render.before", { path = path, opts = opts })
  local info = api.render(path, opts)
  -- What the render had to leave out (a plugin that stopped answering).
  for _, why in ipairs(info.left_out or {}) do paw.notify(why, "warn") end
  -- As `render.done` says of a render in the background.
  paw.emit("render.finished", paw.util.merge(info, { path = info.path or path }))
  return info
end

M.tag_names = { "title", "artist", "album", "track", "year", "genre", "comment", "cover" }

--- What the project's rendered files are tagged with (`project.meta.tags`):
--- `paw.render_tags()` gives `{ title, artist, album, track, year, genre, comment, cover }`
--- as far as set; `paw.render_tags({ artist = "Me" })` sets those fields and keeps the others,
--- an empty string takes one out. A relative `cover` is from the project's directory.
function M.tags(set)
  local meta = api.project_get().meta
  local tags = meta.tags or {}
  local changed = false
  for _, key in ipairs(M.tag_names) do
    local value = set and set[key]
    if value ~= nil then
      value = tostring(value) ~= "" and tostring(value) or nil
      changed = changed or tags[key] ~= value
      tags[key] = value
    end
  end
  -- The project is only touched when a tag is different.
  if changed then
    meta.tags = next(tags) ~= nil and tags or nil
    api.project_set("meta", meta)
  end
  return tags
end

--- The render running in the background: { path, fraction, seconds,
--- cancelling, stage, queued }, or nil. `stage` is "rendering", or "encoding"
--- when ffmpeg is making a lossy file from the render: `fraction` is then
--- the encode's.
function M.status()
  local s = api.render_status()
  if s then s.queued = #queue end
  return s
end

--- Stop the background render, and those waiting after it. Its file is not
--- written. Returns whether one was running.
function M.cancel()
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
function M.stems(dir, opts)
  dir = paw.util.expand_path(dir)
  opts = opts or {}
  local ext = opts.format or "wav"
  check(dir .. "/stem." .. ext)
  pcall(paw.api.fs_mkdir, dir)
  local out, used = {}, {}
  local tracks = opts.tracks
  if not tracks then
    tracks = {}
    for _, track in ipairs(paw.tracks()) do
      if not track.mute and #track:clips() > 0 then tracks[#tracks + 1] = track.id end
    end
  end
  for _, id in ipairs(tracks) do
    id = type(id) == "table" and id.id or id
    local name = api.track_get(id, "name"):gsub("[^%w%-_ ]", "_")
    -- Two tracks of one name get a number each.
    used[name] = (used[name] or 0) + 1
    if used[name] > 1 then name = name .. " " .. used[name] end
    local path = string.format("%s/%s.%s", dir, name, ext)
    -- A lossy stem is titled after its track, unless the options say otherwise.
    local lossy = ext ~= "wav" and ext ~= "flac"
    local tags = paw.util.merge(lossy and { title = name } or {}, opts.tags or {})
    M.render(path, paw.util.merge(opts, { tracks = { id }, format = false, tags = tags }))
    out[#out + 1] = path
  end
  return out
end

local function next_in_queue()
  local nxt = table.remove(queue, 1)
  if nxt then
    local ok, err = pcall(start, nxt.path, nxt.opts)
    if not ok then
      paw.notify("could not render " .. nxt.path .. ": " .. tostring(err), "error")
      return next_in_queue()
    end
  end
end

local function name_of(path) return tostring(path):match("([^/]+)$") or tostring(path) end

--- Say what a render came to. The peak has its sign (`+6.2 dB` is over
--- full scale) and a peak over it is a warning, as it clips.
local function notify_rendered(path, info, more)
  local peak = 20 * math.log10(math.max(info.peak, 1e-6))
  paw.notify(string.format("rendered %s: %.1f s, peak %+.1f dB%s%s", name_of(path), info.seconds, peak, more,
    peak > 0 and " (clips)" or ""), peak > 0 and "warn" or "info")
end

paw.on("render.progress", function() api.ui_redraw() end)
paw.on("render.done", function(info)
  notify_rendered(info.path, info, info.loudness and string.format(", %.1f LUFS", info.loudness) or "")
  for _, why in ipairs(info.left_out or {}) do paw.notify(why, "warn") end
  next_in_queue()
end)
paw.on("render.failed", function(e)
  paw.notify("render of " .. name_of(e.path) .. " failed: " .. tostring(e.error), "error")
  next_in_queue()
end)
paw.on("render.cancelled", function(e)
  queue = {}
  paw.notify("render of " .. name_of(e.path) .. " cancelled; no file written")
end)
-- `Esc` in normal mode, with nothing else to cancel, stops a render.
paw.on("escape", function()
  if api.render_status() then M.cancel() end
end)

-- The command ------------------------------------------------------------------

--- What `:render` takes, for its description and completion.
M.options = {
  { "range=", { "song", "loop", "selection" }, "what to render" },
  { "start=", nil, "beat to start at" },
  { "end=", nil, "beat to end at" },
  { "tail=", { "0", "1", "2", "4" }, "seconds after the end" },
  { "rate=", { "44100", "48000", "96000" }, "sample rate" },
  { "bits=", { "16", "24", "32" }, "sample size; 32 is float" },
  { "quality=", { "low", "medium", "high", "best" }, "of an MP3, Ogg or Opus file" },
  { "bitrate=", { "128", "192", "256", "320" }, "kbit/s of an MP3, Ogg or Opus file" },
  { "channels=", { "stereo", "mono" }, "" },
  { "dither=", { "true" }, "dither at 16 or 24 bits" },
  { "normalize=", { "-1", "-0.3" }, "peak level in dB" },
  { "loudness=", { "-14", "-16", "-23" }, "integrated loudness in LUFS" },
  { "tracks=", { "selected", "all" }, "a stem of these tracks (ids, comma-separated)" },
  { "stems=", { "true" }, "one file per track, into a directory" },
  { "master=", { "false" }, "leave out the master's devices and fader" },
  { "wait=", { "true" }, "render in the foreground" },
  { "title=", nil, "tag; the project's name by default" },
  { "artist=", nil, "tag" },
  { "album=", nil, "tag" },
  { "track=", nil, "tag: a number, or 3/12" },
  { "year=", nil, "tag" },
  { "genre=", nil, "tag" },
  { "comment=", nil, "tag" },
  { "cover=", nil, "tag: a PNG or JPEG file" },
}

local function default_path()
  local p = api.project_get()
  local name = (p.name and p.name ~= "" and p.name or "render"):gsub("[^%w%-_ ]", "_")
  local dir = p.path and tostring(p.path):match("^(.*)/[^/]+$")
  return (dir and dir .. "/" or "") .. name .. ".wav"
end

M.default_path = default_path

local function track_list(spec)
  if spec == nil or spec == "all" then return nil end
  if spec == "selected" then
    local id = paw.cursor.track_id()
    if not id then error("no track is selected", 0) end
    return { id }
  end
  local ids = {}
  for n in tostring(spec):gmatch("[^,%s]+") do ids[#ids + 1] = tonumber(n) or error("not a track id: " .. n, 0) end
  return ids
end

paw.command("render", function(ctx)
  local a = ctx.args
  local opts = {
    range = a.range, start = tonumber(a.start), ["end"] = tonumber(a["end"]), tail = tonumber(a.tail),
    rate = tonumber(a.rate), bits = tonumber(a.bits), quality = a.quality and tostring(a.quality) or nil,
    bitrate = tonumber(a.bitrate), dither = a.dither == true or nil,
    channels = a.channels == "mono" and 1 or a.channels == "stereo" and 2 or tonumber(a.channels),
    normalize = tonumber(a.normalize), loudness = tonumber(a.loudness),
    master = a.master ~= false and nil or false, tracks = track_list(a.tracks),
    background = a.wait ~= true,
  }
  local tags = {}
  for _, key in ipairs(M.tag_names) do
    if a[key] ~= nil and a[key] ~= true then tags[key] = a[key] end
  end
  opts.tags = next(tags) ~= nil and tags or nil
  if opts.start or opts["end"] then opts.range = nil end
  -- `:render stems` and `:render Strings`: by group, the plan shown first.
  local stems = require("paw.stems")
  if a[1] == "stems" or stems.names_group(a[1]) then
    opts.tracks = nil
    return stems.command(ctx, opts)
  end
  if a.stems == true then
    local dir = a[1] and paw.files.path(tostring(a[1])) or (default_path():gsub("%.wav$", "") .. " stems")
    local files = M.stems(dir, paw.util.merge(opts, { format = a.format }))
    return paw.notify(string.format("rendering %d stem%s into %s", #files, #files == 1 and "" or "s", dir))
  end
  -- A relative name goes beside the project, or to the folder `:cd` set.
  local path = a[1] and paw.files.path(tostring(a[1])) or default_path()
  local info = M.render(path, opts)
  if info then
    notify_rendered(path, info, "")
  else
    paw.notify("rendering " .. name_of(path) .. " · Esc cancels")
  end
end, {
  desc = "Render to WAV or FLAC by the file's extension, or MP3, Ogg or Opus with ffmpeg installed: `render mix.flac "
    .. "range=loop tail=2 bits=16 dither=true channels=mono rate=44100 normalize=-1 loudness=-14 tracks=selected master=false stems=true`; "
    .. "`render stems [dir]` one file per group (`render stems tracks` per track), `render Strings` one group",
  complete = function(rest)
    local before, last = rest:match("^(.-)(%S*)$")
    local out = {}
    local key = last:match("^(%w+)=")
    if before == "" and not key then
      out[1] = "stems"
      for _, id in ipairs(api.track_list()) do
        if paw.groups.is_group(id) then out[#out + 1] = api.track_get(id, "name") end
      end
    end
    for _, o in ipairs(M.options) do
      if key and o[1] == key .. "=" then
        for _, v in ipairs(o[2] or {}) do out[#out + 1] = before .. o[1] .. v end
      elseif not key then
        out[#out + 1] = before .. o[1]
      end
    end
    return out
  end,
})

paw.command("render.tags", function(ctx)
  local set = {}
  for _, key in ipairs(M.tag_names) do
    if ctx.args[key] ~= nil and ctx.args[key] ~= true then set[key] = ctx.args[key] end
  end
  local tags = M.tags(next(set) ~= nil and set or nil)
  local words = {}
  for _, key in ipairs(M.tag_names) do
    if tags[key] then words[#words + 1] = key .. "=" .. tostring(tags[key]) end
  end
  paw.notify(#words > 0 and ("rendered files are tagged " .. table.concat(words, ", "))
    or "no tags: set some with `render.tags artist=Me album=First`")
end, {
  desc = "Show or set the tags of the project's rendered files: `render.tags artist=Me album=\"First one\" track=3 "
    .. "year=2026 genre=Ambient comment=\"a note\" cover=cover.png`; an empty value takes one out",
})

paw.command("render.cancel", function()
  if not M.cancel() then paw.notify("nothing is being rendered") end
end, { desc = "Stop the render running in the background; it leaves no file" })

paw.command("stems", function(ctx)
  local dir = paw.files.path(tostring(ctx.args[1] or "stems"))
  local files = M.stems(dir, {
    tail = tonumber(ctx.args.tail), bits = tonumber(ctx.args.bits), format = ctx.args.format,
    quality = ctx.args.quality and tostring(ctx.args.quality) or nil, bitrate = tonumber(ctx.args.bitrate),
    master = ctx.args.master ~= false and nil or false, background = ctx.args.wait ~= true,
  })
  paw.notify(string.format("rendering %d stem%s into %s", #files, #files == 1 and "" or "s", dir))
end, { desc = "Render each track on its own into a directory: `stems out tail=2 bits=24 format=flac master=false`" })

return M
