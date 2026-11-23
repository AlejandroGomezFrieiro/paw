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
      "an Ex range of parts",
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
      "each=group: the groups at the top, and the parts outside a group",
    },
    {
      "each=part",
      nil,
      {
        "renders/song Kick.wav | Kick | song | nil-nil | master | stereo",
        "renders/song Snare.wav | Snare | song | nil-nil | master | stereo",
        "renders/song Bass.wav | Bass | song | nil-nil | master | stereo",
      },
      "each=part",
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
      "parts format=flac channels=stereo tap=groups",
      nil,
      {
        "renders/parts/Kick.flac | Kick | song | nil-nil | groups | stereo",
        "renders/parts/Snare.flac | Snare | song | nil-nil | groups | stereo",
        "renders/parts/Bass.flac | Bass | song | nil-nil | groups | stereo",
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
  T.fails(function() plan("tap=pre") end, "tap=pre is the sound of parts", "the mix has no tap before its fader")
  T.fails(function() plan("each=bar") end, "each=bar: use group, part, region or clip", "each= of a wrong word")
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
  eq(files('"{project} - {parts}.wav"', "t/Bass/"), "renders/song - Bass.wav", "{project} and {parts}")
  eq(
    files('"{n} {group}.flac" each=group'),
    "renders/01 Drums.flac, renders/02 Bass.flac",
    "{n} and {group}, the ending gives the format"
  )
  eq(files("{part}.wav each=part", "t/Drums/"), "renders/Kick.wav, renders/Snare.wav", "{part}")
  eq(files('"{region}.wav" each=region'), "renders/Verse.wav, renders/Chorus.wav", "{region}")
  eq(files('"{date}.wav"'):match("^renders/%d%d%d%d%-%d%d%-%d%d%.wav$") ~= nil, true, "{date}")
  eq(files("all each=group"), "renders/all Drums.wav, renders/all Bass.wav", "each= adds its field to a name")
  eq(files("out/ each=part", "t/Drums/"), "out/Kick.wav, out/Snare.wav", "and to a folder, which is beside the project")
  T.tone("Bass", 8, "A2")
  eq(
    files("each=part", "t/Bass/"),
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
  "export plan: a muted part is left out and named, a range of only muted parts says so, a compressor gives a note",
  function()
    local s = song()
    local p = plan("stems")
    eq(p.left_out, { "Keys, muted" }, "the muted part is named")
    eq(paw.export.lines(p)[4], "left out: Keys, muted", "in the plan")
    T.fails(function() plan("", "t/Keys/") end, "t/Keys/ holds only muted parts: nothing to export", "only muted parts")
    eq(plan("each=part").notes, {}, "no note without a compressor")
    s.drums:add_device("compressor")
    eq(
      plan("each=part").notes,
      { "Drums has Compressor: it hears each file alone, so the files differ a little from the mix" },
      "a compressor on a group that two files pass"
    )
    eq(plan("stems").notes, {}, "a group that one file holds whole needs no note")
    paw.part(0):add_device("limiter")
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

  paw.part(0).volume = -6
  paw.flush()
  keys(":t/Drums/export drums.wav bits=16<CR>")
  done = exported(done)
  local drums = done.results[1]
  T.near(T.frequency(drums, 0.5, 1.5), 440, 5, "the drums alone: no bass in it")
  local groups = T.render({ parts = { s.drums.id }, tap = "groups", bits = 16 })
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
    keys(":export! parts channels=stereo tail=600<CR>")
    eq(paw.export.running(), true, "the export runs")
    keys(":export mix.wav<CR>")
    eq(
      T.screen(140, 10):find("exporting 1/4 Kick.wav %d+%% · Esc cancels") ~= nil,
      true,
      "a second export waits in the same queue, and the status line says which file"
    )
    keys(cancel)
    local done = exported(before)
    eq(done.cancelled, true, cancel .. " cancels the queue")
    eq(io.open(s.dir .. "/renders/mix.wav"), nil, "the last file is not written")
    eq(done.message:match("^export cancelled; %d of 4 files written$") ~= nil, true, done.message)
  end
end)

test("<Space>e exports the mix, stems, parts and regions, and again; in visual mode for the selection", function()
  local s = song()
  local before = paw.export.last()
  keys("<Space>em")
  local done = exported(before)
  eq(done.results[1].path, s.dir .. "/renders/song.wav", "<Space>em: the mix")
  keys("<Space>ee")
  done = exported(done)
  eq(done.results[1].path, s.dir .. "/renders/song.wav", "<Space>ee: the last export again")
  for _, k in ipairs({ { "es", "stems/Drums.wav" }, { "et", "parts/Kick.wav" }, { "er", "regions/01 Verse.wav" } }) do
    keys("<Space>" .. k[1])
    eq(paw.ui.float and paw.ui.float.name, "export.plan", "<Space>" .. k[1] .. " shows the plan")
    eq(T.screen(120, 20):find(k[2], 1, true) ~= nil, true, "<Space>" .. k[1] .. " plans " .. k[2])
    keys("<Esc>")
  end
  paw.cursor.set_part(s.bass)
  keys("V<Space>em")
  done = exported(done)
  eq(done.results[1].path, s.dir .. "/renders/Bass.wav", "visual <Space>em: the selected part")
end)

-- Presets ------------------------------------------------------------------------------

--- Set the presets of the project, as `[export.presets]` of project.toml holds them.
local function project_presets(presets) paw.api.project_set({ export = { presets = presets } }) end

test("export presets: paw's have their words, by the plan of each", function()
  local s = song()
  local rows = {
    { "mix", { "renders/song.wav | the mix | song | nil-nil | master | stereo" }, {} },
    {
      "review",
      { "renders/song.mp3 | the mix | song | nil-nil | master | stereo" },
      { quality = "high", loudness = -14 },
    },
    {
      "stems",
      {
        "renders/stems/Drums.wav | Kick, Snare | song | nil-nil | master | auto",
        "renders/stems/Bass.wav | Bass | song | nil-nil | master | auto",
      },
      {},
    },
    {
      "parts",
      {
        "renders/parts/Kick.wav | Kick | song | nil-nil | post | auto",
        "renders/parts/Snare.wav | Snare | song | nil-nil | post | auto",
        "renders/parts/Bass.wav | Bass | song | nil-nil | post | auto",
      },
      {},
    },
    {
      "regions",
      {
        "renders/regions/01 Verse.wav | the mix | Verse | 0-4 | master | stereo",
        "renders/regions/02 Chorus.wav | the mix | Chorus | 4-8 | master | stereo",
      },
      {},
    },
  }
  for _, row in ipairs(rows) do
    local name, want, words = row[1], row[2], row[3]
    local p = plan(name)
    eq(shown(p, s), want, name)
    for key, value in pairs(words) do
      eq(p.renders[1].options[key], value, name .. " " .. key)
    end
  end
  local project = paw.export.find("project")
  eq({ project.source, project.preset.target, project.preset.words }, {
    "built-in",
    "{project}-export/",
    { format = "project" },
  }, "project: a project folder")
  T.fails(function() plan("project") end, "writes a project folder, which has no plan", "it has no plan of files")
  keys(":export project<CR>")
  eq(io.open(s.dir .. "/renders/song-export/project.toml") ~= nil, true, ":export project writes it in renders/")
end)

test("export presets: the project's wins, then the one of init.lua, then paw's", function()
  local s = song()
  T.after(function() paw.export.presets.stems = nil end)
  local function files(words)
    local out = {}
    for i, r in ipairs(plan(words).renders) do
      out[i] = r.file:sub(#s.dir + 2)
    end
    return table.concat(out, ", ")
  end
  eq(files("stems"), "renders/stems/Drums.wav, renders/stems/Bass.wav", "paw's")
  paw.export.presets.stems = { target = "mine/{group}.wav", words = { each = "group" } }
  eq(files("stems"), "renders/mine/Drums.wav, renders/mine/Bass.wav", "init.lua's comes before paw's")
  eq(paw.export.find("stems").source, "init.lua", "and says where it comes from")
  -- The project's preset names `stems`: that one is the next one, of init.lua.
  project_presets({ stems = "stems format=flac" })
  eq(files("stems"), "renders/mine/Drums.flac, renders/mine/Bass.flac", "the project's comes first")
  eq(files("stems out/"), "out/Drums.flac, out/Bass.flac", "a target typed after it takes the place of the preset's")
  eq(paw.export.find("stems").source, "project", "and says where it comes from")
  paw.export.presets.stems = nil
  eq(files("stems"), "renders/stems/Drums.flac, renders/stems/Bass.flac", "then paw's under it")
end)

test(":export.preset saves the words of the last export in the project, ! replaces, alone lists, u undoes", function()
  local s = song()
  local function saved() return (paw.api.project_get().export.presets or {}).mine end
  keys(":export stems format=flac<CR><Esc>")
  keys(":export.preset mine<CR>")
  eq(saved(), "stems format=flac", ":export.preset saves the words")
  eq(paw.ui.messages[#paw.ui.messages].text, "saved the preset mine in the project: stems format=flac", "and says so")
  T.expect_error("the project has a preset mine")
  keys(":export.preset mine<CR>")
  eq(saved(), "stems format=flac", "a preset of that name stays")
  keys(":export parts<CR><Esc>:export.preset! mine<CR>")
  eq(saved(), "parts", "! replaces it")
  keys(":export.preset<CR>")
  T.expect_screen("preset_list", 90, 24, { styles = false, rows = { 7, 17 }, cols = { 10, 81 } })
  keys("q")
  keys("u")
  eq(saved(), "stems format=flac", "u takes the replace back")
  keys("u")
  eq(saved(), nil, "and the save")
  keys(":export.preset mine<CR>:w<CR>")
  local toml = T.read_file(s.dir .. "/project.toml")
  eq(toml:find('[export.presets]\nmine = "parts"', 1, true) ~= nil, true, "project.toml keeps it: " .. toml)
end)

test("a preset that is a list of exports gives one plan, one confirm and one queue", function()
  local s = song()
  project_presets({ delivery = { "mix format=flac", "stems channels=stereo" } })
  eq(shown(plan("delivery tail=0"), s), {
    "renders/song.flac | the mix | song | nil-nil | master | stereo",
    "renders/stems/Drums.wav | Kick, Snare | song | nil-nil | master | stereo",
    "renders/stems/Bass.wav | Bass | song | nil-nil | master | stereo",
  }, "one plan of the files of each export")
  local before = paw.export.last()
  keys(":export delivery tail=0<CR>")
  eq(paw.ui.float and paw.ui.float.name, "export.plan", "one plan to confirm")
  eq(T.screen(120, 30):find("Export 3 files", 1, true) ~= nil, true, "of the three files")
  keys("y")
  local done = exported(before)
  eq(#done.results, 3, "one queue writes them all")
  eq(done.message:match("^wrote 3 files %(0:04 each, peak [-+]%d+%.%d dB%)$") ~= nil, true, done.message)
  T.fails(
    function() plan("delivery out/") end,
    "delivery is a list of exports: it takes words, not a target",
    "a target"
  )
end)

test("<Space>ep picks a preset, shows its plan, and exports it", function()
  local s = song()
  local before = paw.export.last()
  keys("<Space>ep")
  keys("stems")
  T.expect_screen("preset_picker", 80, 24, { styles = false, rows = { 3, 22 } })
  keys("<CR>")
  eq(paw.ui.float and paw.ui.float.name, "export.plan", "Enter shows the plan of its files")
  keys("y")
  local done = exported(before)
  eq(done.results[1].path, s.dir .. "/renders/stems/Drums.wav", "and y exports them")
end)

--- The samples of a 32-bit float WAV file.
local function samples(path)
  local ffi = require("ffi")
  local data = T.read_file(path)
  local at = data:find("data", 1, true) + 8
  local n = math.floor((#data - at + 1) / 4)
  local buf = ffi.new("float[?]", n)
  ffi.copy(buf, data:sub(at, at + n * 4 - 1), n * 4)
  return buf, n
end

test("normalize= on stems gives each file the gain of the mix, so they still add up to the mix", function()
  local s = song()
  local before = paw.export.last()
  keys(":export stems channels=stereo bits=32 tail=0 normalize=-1 wait=true<CR>")
  T.expect_screen("stems_gain_plan", 90, 24, { styles = false, rows = { 9, 16 } })
  keys("y")
  local done = exported(before)
  local mix = T.render({ bits = 32, tail = 0, normalize = -1 })
  eq(#done.results, 2, "the two stems, and no file of the mix")
  eq(io.open(s.dir .. "/renders/.mix for the gain.wav"), nil, "paw removes the mix that it measured")
  for _, r in ipairs(done.results) do
    T.near(r.gain, mix.gain, 1e-4, r.path:match("[^/]+$") .. " has the gain of the mix")
  end
  local m, n = samples(mix.path)
  local x, k = samples(done.results[1].path)
  local y = samples(done.results[2].path)
  local worst = 0
  for i = 0, math.min(n, k) - 1 do
    worst = math.max(worst, math.abs(x[i] + y[i] - m[i]))
  end
  eq(worst < 1e-5, true, "the stems add up to the normalized mix: " .. worst)
  eq(plan("stems loudness=-14").renders[2].set ~= nil, true, "loudness= makes a set too")
  eq(plan("in=Verse normalize=-1").renders[1].set, nil, "one file keeps its own gain")
end)

test("<Space>tf freezes the part at the cursor and <Space>tF unfreezes it, one undo step each", function()
  local s = song()
  paw.cursor.set_part(s.bass)
  keys("<Space>tf")
  eq(paw.freeze.frozen(s.bass.id) ~= nil, true, "<Space>tf freezes")
  keys("<Space>tF")
  eq(paw.freeze.frozen(s.bass.id), nil, "<Space>tF unfreezes")
  keys("u")
  eq(paw.freeze.frozen(s.bass.id) ~= nil, true, "u gives the freeze back")
end)
