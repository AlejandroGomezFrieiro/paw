-- Tests of rendering to MP3, Ogg Vorbis and Opus through ffmpeg. They skip
-- when ffmpeg is not installed. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fails, fresh = T.test, T.eq, T.fails, T.fresh
local api = paw.api

local function have(program)
  local ok = os.execute("command -v " .. program .. " >/dev/null 2>&1")
  return ok == true or ok == 0
end

local function sh_quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

--- Seconds in a file, asked of ffprobe; nil without it.
local function duration(path)
  if not have("ffprobe") then return nil end
  local p = io.popen("ffprobe -v error -show_entries format=duration -of csv=p=0 " .. sh_quote(path))
  local out = p:read("*a")
  p:close()
  return tonumber(out)
end

--- The names in a directory, hidden ones too, sorted.
local function names(dir)
  local out = {}
  for _, e in ipairs(api.read_dir(dir)) do
    out[#out + 1] = e.name
  end
  table.sort(out)
  return table.concat(out, " ")
end

local function fresh_dir(name)
  local dir = T.scratch .. "/export-" .. name
  os.execute("rm -rf " .. sh_quote(dir) .. " && mkdir -p " .. sh_quote(dir))
  return dir
end

local function wait_idle()
  T.until_(function() return not paw.render_status() end, "the render to end")
end

local function missing()
  if not have("ffmpeg") then return "skipped: ffmpeg not found" end
end

test("a render to MP3, Ogg Vorbis and Opus has the length asked for and leaves nothing else", function()
  if missing() then return missing() end
  fresh()
  api.engine_restart({ backend = "null" })
  T.tone("Synth", 4)
  paw.project.tempo = 120
  local dir = fresh_dir("formats")
  for _, ext in ipairs({ "mp3", "ogg", "opus" }) do
    local path = dir .. "/song." .. ext
    local info = paw.render(path, { tail = 0 })
    eq(info.path, path, ext .. ": the file is the one asked for")
    local data = T.read_file(path)
    eq(#data > 1000, true, ext .. ": it has content")
    eq(data:sub(1, 4) ~= "RIFF", true, ext .. ": it is not a WAV")
    local seconds = duration(path)
    if seconds then T.near(seconds, 2, 0.15, ext .. ": two seconds long") end
  end
  eq(names(dir), "song.mp3 song.ogg song.opus", "no part file and no temporary WAV is left")
  paw.project.name = "Sunrise"
  paw.render(dir .. "/titled.mp3", { tail = 0 })
  if have("ffprobe") then
    local p =
      io.popen("ffprobe -v error -show_entries format_tags=title -of csv=p=0 " .. sh_quote(dir .. "/titled.mp3"))
    local title = p:read("*l")
    p:close()
    eq(title, "Sunrise", "the project's name is the title")
  end
end)

test("quality and bitrate change the size of a lossy file", function()
  if missing() then return missing() end
  fresh()
  api.engine_restart({ backend = "null" })
  T.tone("Synth", 8)
  local dir = fresh_dir("quality")
  local sizes = {}
  for _, q in ipairs({ "low", "best" }) do
    paw.render(dir .. "/" .. q .. ".opus", { tail = 0, quality = q })
    sizes[q] = #T.read_file(dir .. "/" .. q .. ".opus")
  end
  eq(sizes.low < sizes.best, true, "best is bigger than low")
  paw.render(dir .. "/num.mp3", { tail = 0, bitrate = 64 })
  paw.render(dir .. "/num320.mp3", { tail = 0, bitrate = 320 })
  eq(#T.read_file(dir .. "/num.mp3") < #T.read_file(dir .. "/num320.mp3"), true, "a bitrate in kbit/s is taken")
  fails(
    function() paw.render(dir .. "/x.mp3", { tail = 0, quality = "loud" }) end,
    "quality",
    "a quality that is not one is refused"
  )
  eq(names(dir):find("%.part") == nil, true, "nothing partial is left, even after a refusal")
end)

test("a background render to MP3 reports the final file once", function()
  if missing() then return missing() end
  fresh()
  api.engine_restart({ backend = "null" })
  T.tone("Synth", 4)
  local dir = fresh_dir("background")
  local events = {}
  local handles = {}
  for _, name in ipairs({ "render.progress", "render.done", "render.cancelled", "render.failed" }) do
    handles[#handles + 1] = paw.on(name, function(e) events[#events + 1] = { name = name, e = e } end)
  end
  local path = dir .. "/bg.mp3"
  eq(paw.render(path, { tail = 0, background = true }), nil, "it returns at once")
  wait_idle()
  for _, h in ipairs(handles) do
    paw.off(h)
  end
  local ends = {}
  for _, ev in ipairs(events) do
    if ev.name ~= "render.progress" then ends[#ends + 1] = ev.name .. " " .. ev.e.path end
  end
  eq(table.concat(ends, ","), "render.done " .. path, "one event at the end, for the final file")
  eq(#T.read_file(path) > 1000, true, "the file is there")
  eq(names(dir), "bg.mp3", "and nothing else")
end)

test("cancelling during the encode stops it and leaves nothing", function()
  if missing() then return missing() end
  fresh()
  api.engine_restart({ backend = "null" })
  local dir = fresh_dir("cancel")
  -- A long file to play, made by ffmpeg, so that the encode takes a while.
  local src = dir .. "/src.wav"
  os.execute("ffmpeg -v error -f lavfi -i 'sine=frequency=440:duration=1500:sample_rate=48000' -ac 2 " .. sh_quote(src))
  local t = paw.add_track()
  t:add_clip({ file = src, start = 0, length = 3000 })
  local out = fresh_dir("cancel-out")
  local events = {}
  local handles = {}
  for _, name in ipairs({ "render.done", "render.cancelled", "render.failed" }) do
    handles[#handles + 1] = paw.on(name, function() events[#events + 1] = name end)
  end
  local path = out .. "/long.mp3"
  paw.render(path, { tail = 0, background = true, quality = "best" })
  -- On a busy machine playing the long file can take a while before the
  -- encode starts, so wait by the clock; and cancel whatever happens, so
  -- that a failure here leaves no render running for the tests after it.
  local seen
  T.until_(function()
    local s = paw.render_status()
    if s and s.stage == "encoding" then seen = s end
    return seen or not s
  end, "the encode to start", 120000)
  if not seen then
    if paw.render_status() then
      paw.cmd("export.cancel")
      wait_idle()
    end
    for _, h in ipairs(handles) do
      paw.off(h)
    end
  end
  eq(seen ~= nil, true, "the status says it is encoding")
  eq(seen.fraction < 1, true, "and is not at 100%")
  paw.cmd("export.cancel")
  wait_idle()
  for _, h in ipairs(handles) do
    paw.off(h)
  end
  eq(table.concat(events, ","), "render.cancelled", "it says once that it was cancelled")
  eq(names(out), "", "no file, no part, no temporary WAV")
end, { live = "it watches the render while it runs, and a settle waits for its end" })

test("without ffmpeg a lossy format is refused before anything is rendered, and the formats say why", function()
  fresh()
  api.engine_restart({ backend = "null" })
  T.tone("Synth", 2)
  local dir = fresh_dir("missing")
  local was = paw.opt.ffmpeg
  paw.opt.ffmpeg = "/no/such/ffmpeg"
  -- Put ffmpeg back even if a check below fails, or every later lossy
  -- render in the suite fails with it.
  T.after(function() paw.opt.ffmpeg = was end)
  local heard = false
  local off = paw.on("render.before", function() heard = true end)
  fails(function() paw.render(dir .. "/a.mp3", { tail = 0 }) end, "ffmpeg", "the message says ffmpeg is needed")
  fails(
    function() paw.render(dir .. "/a.opus", { tail = 0, background = true }) end,
    "WAV %(%.wav%) or FLAC",
    "and how formats that need nothing are named"
  )
  fails(function() paw.cmd("export", { dir .. "/a.ogg" }) end, "ffmpeg", "the command too")
  fails(function() paw.export.plan(dir .. "/stems/ each=track format=mp3") end, "ffmpeg", "an export too")
  paw.off(off)
  eq(heard, false, "nothing was rendered")
  local by = {}
  for _, f in ipairs(api.render_formats(paw.opt.ffmpeg)) do
    by[f.name] = f
  end
  eq(by.MP3.available, false, "MP3 is not available")
  eq(type(by.MP3.why), "string", "and says why")
  eq(by.WAV.available, true, "WAV needs nothing")
  eq(paw.frontend.render_dialog().formats.mp3, false, "the window is not offered it")
  paw.render(dir .. "/ok.wav", { tail = 0 })
  paw.opt.ffmpeg = was
  eq(names(dir), "ok.wav", "only what was possible was written")
end)

test("stems and regions are rendered to a lossy format too", function()
  if missing() then return missing() end
  fresh()
  api.engine_restart({ backend = "null" })
  T.tone("Lead", 4)
  paw.project.tempo = 120
  paw.markers.add(0, "Intro", { length = 2 })
  local dir = fresh_dir("stems")
  paw.export.run(paw.export.plan(dir .. "/ each=track format=ogg tail=0 wait=true"))
  eq(names(dir), "Lead.ogg", "a stem is an Ogg file")
  paw.export.run(paw.export.plan(dir .. "/regions/ each=region format=opus tail=0 wait=true"))
  eq(#T.read_file(dir .. "/regions/01 Intro.opus") > 500, true, "a region is an Opus file")
  eq(names(dir .. "/regions"), "01 Intro.opus", "with nothing left over")
end)
