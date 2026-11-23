-- Tests of the tags a rendered file carries: title, artist, album, track,
-- year, genre, comment and a cover, in WAV, FLAC (read back by parsing the
-- chunks and blocks) and in MP3, Ogg and Opus (read back with ffprobe, and
-- skipped without ffmpeg). Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fails, fresh = T.test, T.eq, T.fails, T.fresh
local api = paw.api

local function have(program)
  local ok = os.execute("command -v " .. program .. " >/dev/null 2>&1")
  return ok == true or ok == 0
end

local function sh_quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function fresh_dir(name)
  local dir = T.scratch .. "/tags-" .. name
  os.execute("rm -rf " .. sh_quote(dir) .. " && mkdir -p " .. sh_quote(dir))
  return dir
end

local function le(s, at, n)
  local v = 0
  for i = n, 1, -1 do
    v = v * 256 + s:byte(at + i - 1)
  end
  return v
end

local function be(s, at, n)
  local v = 0
  for i = 1, n do
    v = v * 256 + s:byte(at + i - 1)
  end
  return v
end

--- The INFO entries of a WAV file: { INAM = "title", ... }, and whether the RIFF size is right.
local function wav_info(data)
  local out = {}
  local at = 13
  while at + 8 <= #data + 1 do
    local id, size = data:sub(at, at + 3), le(data, at + 4, 4)
    if id == "LIST" and data:sub(at + 8, at + 11) == "INFO" then
      local p, stop = at + 12, at + 8 + size
      while p < stop do
        local sub, n = data:sub(p, p + 3), le(data, p + 4, 4)
        out[sub] = data:sub(p + 8, p + 8 + n - 2)
        p = p + 8 + n + n % 2
      end
    end
    at = at + 8 + size + size % 2
  end
  return out, le(data, 5, 4) == #data - 8
end

--- The comments and the picture of a FLAC file: { comments = { KEY = value }, picture = { mime, data } }.
local function flac_blocks(data)
  assert(data:sub(1, 4) == "fLaC", "not a FLAC file")
  local out, at = { comments = {} }, 5
  while true do
    local head = data:byte(at)
    local kind, size = head % 128, be(data, at + 1, 3)
    local body = data:sub(at + 4, at + 3 + size)
    if kind == 4 then
      local vendor = le(body, 1, 4)
      local p = 5 + vendor
      local count = le(body, p, 4)
      p = p + 4
      for _ = 1, count do
        local n = le(body, p, 4)
        local pair = body:sub(p + 4, p + 3 + n)
        out.comments[pair:match("^([^=]+)")] = pair:match("=(.*)$")
        p = p + 4 + n
      end
    elseif kind == 6 then
      local mime_len = be(body, 5, 4)
      local p = 9 + mime_len
      p = p + 4 + be(body, p, 4) + 16
      out.picture = { mime = body:sub(9, 8 + mime_len), data = body:sub(p + 4, p + 3 + be(body, p, 4)) }
    end
    if head >= 128 then break end
    at = at + 4 + size
  end
  return out
end

local function setup(name)
  fresh()
  api.engine_restart({ backend = "null" })
  T.tone("Synth", 2)
  paw.project.tempo = 120
  return fresh_dir(name)
end

local cover = "tests/fixtures/cover.png"

test("a WAV carries the project's tags in an INFO chunk and is still a WAV", function()
  local dir = setup("wav")
  eq(next(paw.render_tags()), nil, "a new project has no tags")
  paw.render_tags({ artist = "Ana", album = "First", track = 3, year = 2026, genre = "Ambient", comment = "a note" })
  eq(paw.render_tags().track, "3", "a number is kept as text")
  paw.project.name = "Sunrise"
  local path = dir .. "/a.wav"
  paw.render(path, { tail = 0, bits = 16 })
  local info, size_ok = wav_info(T.read_file(path))
  eq(info.INAM, nil, "a WAV is not titled with the project's name unless asked")
  eq(
    info.IART .. "|" .. info.IPRD .. "|" .. info.ITRK .. "|" .. info.ICRD .. "|" .. info.IGNR .. "|" .. info.ICMT,
    "Ana|First|3|2026|Ambient|a note",
    "every tag is there"
  )
  eq(size_ok, true, "the RIFF size covers the chunk")
  local again = paw.render(dir .. "/b.wav", { tail = 0, bits = 16, tags = { artist = "Bo", title = "Other" } })
  local info2 = wav_info(T.read_file(dir .. "/b.wav"))
  eq(
    info2.IART .. "|" .. info2.INAM .. "|" .. info2.IPRD,
    "Bo|Other|First",
    "a render's own tags go over the project's"
  )
  eq(again.frames, 48000, "and the audio is as long as it was")
  fails(
    function() paw.render(dir .. "/c.wav", { tail = 0, tags = { artsit = "x" } }) end,
    "artsit",
    "a tag that does not exist is refused"
  )
  paw.render_tags({ artist = "", album = "", track = "", year = "", genre = "", comment = "" })
  eq(next(paw.render_tags()), nil, "empty values take tags out")
end)

test("a FLAC carries Vorbis comments and a cover picture", function()
  local dir = setup("flac")
  paw.render_tags({ artist = "Ana", album = "First", track = "3/12", year = 2026, cover = cover })
  local path = dir .. "/a.flac"
  paw.render(path, { tail = 0, bits = 16, tags = { title = "Song", comment = "x=y" } })
  local blocks = flac_blocks(T.read_file(path))
  eq(
    blocks.comments.TITLE
      .. "|"
      .. blocks.comments.ARTIST
      .. "|"
      .. blocks.comments.TRACKNUMBER
      .. "|"
      .. blocks.comments.DATE
      .. "|"
      .. blocks.comments.COMMENT,
    "Song|Ana|3/12|2026|x=y",
    "the comments are there"
  )
  eq(blocks.picture and blocks.picture.mime, "image/png", "the cover is a PNG")
  eq(blocks.picture and blocks.picture.data, T.read_file(cover), "and is the file's bytes")
  if have("ffmpeg") then
    local ok = os.execute("ffmpeg -v error -i " .. sh_quote(path) .. " -f null - 2>/dev/null")
    eq(ok == true or ok == 0, true, "ffmpeg decodes the file, tags and cover included")
  end
  fails(
    function() paw.render(dir .. "/b.flac", { tail = 0, tags = { cover = "/no/such.png" } }) end,
    "cover",
    "a cover that cannot be read is refused"
  )
  eq(#api.read_dir(dir), 1, "and leaves nothing")
  fails(
    function() paw.render(dir .. "/c.flac", { tail = 0, tags = { cover = "tests/fixtures/shape.wav" } }) end,
    "PNG or JPEG",
    "a cover that is no picture is refused"
  )
end)

--- What ffprobe says of a file: tags (lowercase) and the kinds of its streams.
local function probe(path)
  local function ask(what)
    local p = io.popen("ffprobe -v error " .. what .. " -of default=nw=1 " .. sh_quote(path))
    local out = p:read("*a")
    p:close()
    return out
  end
  local tags, streams = {}, {}
  -- The sound's own tags (Ogg and Opus keep them there) and the file's.
  for _, what in ipairs({ "-select_streams a -show_entries stream_tags", "-show_entries format_tags" }) do
    for line in ask(what):gmatch("[^\n]+") do
      local key, value = line:match("^TAG:([^=]+)=(.*)$")
      if key then tags[key:lower()] = value end
    end
  end
  for line in ask("-show_entries stream=codec_type"):gmatch("[^\n]+") do
    streams[#streams + 1] = line:match("^codec_type=(.*)$")
  end
  return tags, table.concat(streams, ",")
end

test("MP3, Ogg and Opus carry the tags and the cover, read back with ffprobe", function()
  if not (have("ffmpeg") and have("ffprobe")) then return "skipped: ffmpeg and ffprobe not found" end
  local dir = setup("lossy")
  paw.render_tags({
    title = "Song",
    artist = "Ana",
    album = "First",
    track = "3",
    year = 2026,
    genre = "Ambient",
    comment = "a=b; c",
    cover = cover,
  })
  for _, ext in ipairs({ "mp3", "ogg", "opus" }) do
    local path = dir .. "/a." .. ext
    paw.render(path, { tail = 0 })
    local tags, streams = probe(path)
    eq(
      tags.title .. "|" .. tags.artist .. "|" .. tags.album .. "|" .. tags.genre,
      "Song|Ana|First|Ambient",
      ext .. ": the text tags are there"
    )
    eq(tags.track, "3", ext .. ": the track")
    eq((tags.date or tags.year or ""):sub(1, 4), "2026", ext .. ": the year")
    eq(tags.comment, "a=b; c", ext .. ": the comment, with what ffmpeg reads specially")
    eq(streams:find("video", 1, true) ~= nil, true, ext .. ": a picture is attached (" .. streams .. ")")
  end
  eq(#api.read_dir(dir), 3, "no metadata, picture or part file is left")
  paw.render(dir .. "/plain.mp3", { tail = 0, tags = { cover = "" } })
  paw.render_tags({ cover = "" })
  paw.render(dir .. "/nocover.mp3", { tail = 0 })
  local _, streams = probe(dir .. "/nocover.mp3")
  eq(streams, "audio", "without a cover there is only the sound")
end)

test("the tags are given to :export, :export.tags and the window's dialog, and kept with the project", function()
  local dir = setup("command")
  paw.cmd("export.tags", { artist = "Ana", album = "Two words" })
  eq(paw.render_tags().album, "Two words", "the command sets them")
  eq(paw.frontend.render_dialog().tags.artist, "Ana", "the window's dialog starts from them")
  paw.cmd("export", { dir .. "/a.wav", wait = true, tail = 0, title = "Mine", artist = "Bo" })
  local info = wav_info(T.read_file(dir .. "/a.wav"))
  eq(
    info.INAM .. "|" .. info.IART .. "|" .. info.IPRD,
    "Mine|Bo|Two words",
    "the words of an export go over the project's"
  )
  eq(paw.render_tags().artist, "Ana", "and do not change them")
  paw.frontend.act.render({ path = dir .. "/b.wav", tail = 0, tags = { artist = "Cy", year = "1999" } })
  while paw.render_status() do
    paw.wait(10)
  end
  info = wav_info(T.read_file(dir .. "/b.wav"))
  eq(info.IART .. "|" .. info.ICRD, "Cy|1999", "the dialog's tags are written")
  eq(paw.render_tags().artist, "Cy", "and become the project's")
  local project = dir .. "/p.json"
  api.project_save(project)
  api.project_load(project)
  eq(paw.render_tags().year, "1999", "they are saved with the project")
  paw.export.run(paw.export.plan(dir .. "/stems/ each=track tail=0 wait=true"))
  eq(wav_info(T.read_file(dir .. "/stems/Synth.wav")).IART, "Cy", "a stem has the project's tags")
end)
