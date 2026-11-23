-- `:export` of sound (paw/export.tl): the words turned into a plan of
-- files, their names, what a plan leaves out, the plan float, the queue,
-- the message at the end, and the <Space>e keys. Loaded by tests/suite.lua.
local T = ...
local test, eq, keys = T.test, T.eq, T.keys

local folders = 0

--- A saved song at 120 BPM, two bars long: Drums (a group of Kick and
--- Snare), Bass, and Keys, which is muted. Two regions, Verse (bar 1) and
--- Chorus (bar 2).
local function song()
  T.start()
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
  folders = folders + 1
  local dir = T.scratch .. "/export" .. folders
  paw.project.tempo = 120
  local kick = T.tone("Kick", 8, "A4")
  local snare = T.tone("Snare", 8, "A4")
  local drums = paw.groups.make({ kick, snare }, "Drums")
  local bass = T.tone("Bass", 8, "A2")
  local keys_ = T.tone("Keys", 8, "C4")
  keys_.mute = true
  paw.markers.add(0, "Verse", { length = 4 })
  paw.markers.add(4, "Chorus", { length = 4 })
  paw.project.save(dir .. "/song")
  paw.flush()
  return { dir = dir .. "/song", drums = drums, kick = kick, snare = snare, bass = bass, keys = keys_ }
end

--- A plan in a line for each file: its name from the project's folder,
--- what it holds, when, where it listens and its channels.
local function shown(plan, s)
  local out = {}
  for i, r in ipairs(plan.renders) do
    out[i] = table.concat({
      (r.file:gsub("^" .. s.dir:gsub("%p", "%%%0") .. "/", "")),
      r.holds,
      r.when,
      tostring(r.from) .. "-" .. tostring(r.to),
      r.tap,
      r.channels,
    }, " | ")
  end
  return out
end

local function plan(words, range) return paw.export.plan(words, range and paw.ex.range(range)) end

test("export plan: the range, in= and each= give the files, their time, tap and channels", function()
  local s = song()
  paw.transport.loop_start, paw.transport.loop_end = 2, 6
  local rows = {
    {
      "",
      nil,
      { "renders/song.wav | the mix | song | nil-nil | master | stereo" },
      "no words: the mix of the song",
    },
    {
      "",
      "t/Bass/",
      { "renders/Bass.wav | Bass | song | nil-nil | master | stereo" },
      "an Ex range of tracks",
    },
    {
      "bridge.wav",
      "2,2",
      { "renders/bridge.wav | the mix | bar 2 | 4-8 | master | stereo" },
      "an Ex range of time",
    },
    { "in=loop", nil, { "renders/song.wav | the mix | loop | 2-6 | master | stereo" }, "in=loop" },
    { "in=Chorus", nil, { "renders/song.wav | the mix | Chorus | 4-8 | master | stereo" }, "in=<region>" },
    {
      "each=group",
      nil,
      {
        "renders/song Drums.wav | Kick, Snare | song | nil-nil | master | stereo",
        "renders/song Bass.wav | Bass | song | nil-nil | master | stereo",
      },
      "each=group: the groups at the top, and the tracks outside a group",
    },
    {
      "each=track",
      nil,
      {
        "renders/song Kick.wav | Kick | song | nil-nil | master | stereo",
        "renders/song Snare.wav | Snare | song | nil-nil | master | stereo",
        "renders/song Bass.wav | Bass | song | nil-nil | master | stereo",
      },
      "each=track",
    },
    {
      "each=region",
      "t/Bass/",
      {
        "renders/Bass 01 Verse.wav | Bass | Verse | 0-4 | master | stereo",
        "renders/Bass 02 Chorus.wav | Bass | Chorus | 4-8 | master | stereo",
      },
      "each=region",
    },
    {
      "each=clip",
      "t/Bass/",
      { "renders/Bass Bass 01.wav | Bass | midi | 0-8 | master | stereo" },
      "each=clip",
    },
    {
      "each=region,group",
      nil,
      {
        "renders/song 01 Verse - Drums.wav | Kick, Snare | Verse | 0-4 | master | stereo",
        "renders/song 01 Verse - Bass.wav | Bass | Verse | 0-4 | master | stereo",
        "renders/song 02 Chorus - Drums.wav | Kick, Snare | Chorus | 4-8 | master | stereo",
        "renders/song 02 Chorus - Bass.wav | Bass | Chorus | 4-8 | master | stereo",
      },
      "two each= joined: the region matrix",
    },
    {
      "stems",
      nil,
      {
        "renders/stems/Drums.wav | Kick, Snare | song | nil-nil | master | auto",
        "renders/stems/Bass.wav | Bass | song | nil-nil | master | auto",
      },
      "a preset",
    },
    {
      "tracks format=flac channels=stereo tap=groups",
      nil,
      {
        "renders/tracks/Kick.flac | Kick | song | nil-nil | groups | stereo",
        "renders/tracks/Snare.flac | Snare | song | nil-nil | groups | stereo",
        "renders/tracks/Bass.flac | Bass | song | nil-nil | groups | stereo",
      },
      "the words after a preset win",
    },
  }
  for _, row in ipairs(rows) do
    local words, range, want, what = row[1], row[2], row[3], row[4]
    local p = plan(words, range)
    local got = shown(p, s)
    eq(got, want, what)
  end
  T.fails(function() plan("in=Verse", "2,2") end, "in= and a range of time say the same", "in= and a range")
  T.fails(function() plan("tap=pre") end, "tap=pre is the sound of tracks", "the mix has no tap before its fader")
  T.fails(function() plan("each=bar") end, "each=bar: use group, track, region or clip", "each= of a wrong word")
  T.fails(function() plan("loud=yes") end, "loud=: not a word of :export", "a word that :export does not know")
end)

test("export plan: names take fields, each= adds one, two of one name get a number, no folder is renders/", function()
  local s = song()
  local function files(words, range)
    local out = {}
    for i, r in ipairs(plan(words, range).renders) do
      out[i] = r.file:sub(#s.dir + 2)
    end
    return table.concat(out, ", ")
  end
  eq(files('"{project} - {tracks}.wav"', "t/Bass/"), "renders/song - Bass.wav", "{project} and {tracks}")
  eq(
    files('"{n} {group}.flac" each=group'),
    "renders/01 Drums.flac, renders/02 Bass.flac",
    "{n} and {group}, the ending gives the format"
  )
  eq(files("{track}.wav each=track", "t/Drums/"), "renders/Kick.wav, renders/Snare.wav", "{track}")
  eq(files('"{region}.wav" each=region'), "renders/Verse.wav, renders/Chorus.wav", "{region}")
  eq(files('"{date}.wav"'):match("^renders/%d%d%d%d%-%d%d%-%d%d%.wav$") ~= nil, true, "{date}")
  eq(files("all each=group"), "renders/all Drums.wav, renders/all Bass.wav", "each= adds its field to a name")
  eq(
    files("out/ each=track", "t/Drums/"),
    "out/Kick.wav, out/Snare.wav",
    "and to a folder, which is beside the project"
  )
  T.tone("Bass", 8, "A2")
  eq(
    files("each=track", "t/Bass/"),
    "renders/Bass+Bass Bass.wav, renders/Bass+Bass Bass 2.wav",
    "two files of one name get a number"
  )
  eq(files("mix.mp3"), "renders/mix.mp3", "a name with no folder goes into renders/")
  eq(
    files("stems format=flac"),
    "renders/stems/Drums.flac, renders/stems/Bass.flac, renders/stems/Bass 2.flac",
    "format= changes the ending of a preset"
  )
  T.fails(function() plan("song.flac format=mp3") end, "song.flac and format=mp3 say two formats", "two formats")
  T.fails(function() plan("{who}.wav") end, "{who}: not a field of a name", "a field that is not one")
end)

test(
  "export plan: a muted track is left out and named, a range of only muted tracks says so, a compressor gives a note",
  function()
    local s = song()
    local p = plan("stems")
    eq(p.left_out, { "Keys, muted" }, "the muted track is named")
    eq(paw.export.lines(p)[4], "left out: Keys, muted", "in the plan")
    T.fails(
      function() plan("", "t/Keys/") end,
      "t/Keys/: every track of the range is muted, so there is nothing to export",
      "only muted tracks"
    )
    eq(plan("each=track").notes, {}, "no note without a compressor")
    s.drums:add_device("compressor")
    eq(
      plan("each=track").notes,
      { "Drums has Compressor: it hears each file alone, so the files differ a little from the mix" },
      "a compressor on a group that two files pass"
    )
    eq(plan("stems").notes, {}, "a group that one file holds whole needs no note")
    paw.track(0):add_device("limiter")
    eq(
      plan("stems").notes,
      { "the master has Limiter: it hears each file alone, so the files differ a little from the mix" },
      "a limiter on the master"
    )
    eq(plan("stems tap=groups").notes, {}, "not when the files leave out the master")
  end
)

--- Wait for the export that the keys started to end, and give what it did.
local function exported(before)
  return T.until_(function()
    local last = paw.export.last()
    return last ~= before and not paw.export.running() and last
  end, "the export to end")
end

--- The length of a WAV file in seconds.
local function seconds(path)
  local data = T.read_file(path)
  local function u32(at)
    local a, b, c, d = data:byte(at, at + 3)
    return a + b * 256 + c * 65536 + d * 16777216
  end
  local bytes = u32(29)
  local at = data:find("data", 37, true)
  return u32(at + 4) / bytes
end

test(":export writes renders/<project>.wav, :2export a bar, :t/Drums/export the group through the master", function()
  local s = song()
  local before = paw.export.last()
  keys(":export<CR>")
  local done = exported(before)
  eq(done.results[1].path, s.dir .. "/renders/song.wav", ":export writes the mix into renders/")
  T.near(seconds(s.dir .. "/renders/song.wav"), 6, 0.01, "the song and a tail of 2 s")
  eq(done.message:match("^wrote renders/song.wav %(0:06, peak [-+]%d+%.%d dB%)$") ~= nil, true, done.message)
  eq(paw.ui.messages[#paw.ui.messages].text, done.message, ":messages keeps the message")

  keys(":2export bridge.wav tail=0<CR>")
  done = exported(done)
  T.near(seconds(s.dir .. "/renders/bridge.wav"), 2, 0.01, ":2export: bar 2 alone")

  paw.track(0).volume = -6
  paw.flush()
  keys(":t/Drums/export drums.wav bits=16<CR>")
  done = exported(done)
  local drums = done.results[1]
  T.near(T.frequency(drums, 0.5, 1.5), 440, 5, "the drums alone: no bass in it")
  local groups = T.render({ tracks = { s.drums.id }, tap = "groups", bits = 16 })
  T.near(drums.peak / groups.peak, 0.5, 0.01, "through the master's fader")
end)

test(":export shows the plan before several files or a file it replaces outside renders/; :export! does not", function()
  local s = song()
  keys(":export stems channels=stereo<CR>")
  eq(paw.ui.float and paw.ui.float.name, "export.plan", "several files: the plan first")
  T.expect_screen("stems_plan", 90, 24, { styles = false, rows = { 9, 15 }, cols = { 14, 77 } })
  keys("n")
  eq(paw.ui.float, nil, "n goes back")
  eq(io.open(s.dir .. "/renders/stems/Bass.wav"), nil, "and writes nothing")
  keys(":export stems channels=stereo<CR><Esc>")
  eq(paw.ui.float, nil, "Esc goes back")
  local before = paw.export.last()
  keys(":export stems channels=stereo<CR>y")
  local done = exported(before)
  eq(#done.results, 2, "y writes the files")
  eq(
    done.message:match("^wrote 2 files to renders/stems %(0:06 each, peak [-+]%d+%.%d dB%)$") ~= nil,
    true,
    done.message
  )

  local outside = s.dir .. "/mix.wav"
  T.write_file(outside, "old")
  keys(":export " .. outside .. "<CR>")
  eq(paw.ui.float and paw.ui.float.name, "export.plan", "a file outside renders/ that is there: the plan first")
  keys("<CR>")
  done = exported(done)
  eq(T.read_file(outside) ~= "old", true, "Enter replaces it")
  T.write_file(outside, "old")
  keys(":export! " .. outside .. "<CR>")
  eq(paw.ui.float, nil, ":export! shows no plan")
  exported(done)
  eq(T.read_file(outside) ~= "old", true, "and replaces the file")
end)

test("exports run in one queue with their progress on the status line; Esc and :export.cancel stop it all", function()
  local s = song()
  for _, cancel in ipairs({ "<Esc>", ":export.cancel<CR>" }) do
    local before = paw.export.last()
    keys(":export! tracks channels=stereo tail=600<CR>")
    eq(paw.export.running(), true, "the export runs: " .. tostring(paw.export.last() and paw.export.last().message))
    eq(
      T.screen(140, 10):find("exporting 1/3 Kick.wav %d+%% · Esc cancels") ~= nil,
      true,
      "the status line says which file"
    )
    keys(cancel)
    local done = exported(before)
    eq(done.cancelled, true, cancel .. " cancels the queue")
    eq(io.open(s.dir .. "/renders/tracks/Bass.wav"), nil, "the last file is not written")
    eq(done.message:match("^export cancelled; %d of 3 files written$") ~= nil, true, done.message)
  end
end)

test("<Space>e exports the mix, stems, tracks and regions, and again; in visual mode for the selection", function()
  local s = song()
  local before = paw.export.last()
  keys("<Space>em")
  local done = exported(before)
  eq(done.results[1].path, s.dir .. "/renders/song.wav", "<Space>em: the mix")
  keys("<Space>ee")
  done = exported(done)
  eq(done.results[1].path, s.dir .. "/renders/song.wav", "<Space>ee: the last export again")
  for _, k in ipairs({ { "es", "stems/Drums.wav" }, { "et", "tracks/Kick.wav" }, { "er", "regions/01 Verse.wav" } }) do
    keys("<Space>" .. k[1])
    eq(paw.ui.float and paw.ui.float.name, "export.plan", "<Space>" .. k[1] .. " shows the plan")
    eq(T.screen(120, 20):find(k[2], 1, true) ~= nil, true, "<Space>" .. k[1] .. " plans " .. k[2])
    keys("<Esc>")
  end
  paw.cursor.set_track(s.bass)
  keys("V<Space>em")
  done = exported(done)
  eq(done.results[1].path, s.dir .. "/renders/Bass.wav", "visual <Space>em: the selected track")
end)
