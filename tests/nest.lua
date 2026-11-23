-- Tests of subprojects (nests, crates/paw-core/src/model/nest.rs) as the
-- user meets them: a subproject is a scope (paw/scope.tl), it plays into
-- its return row, and its devices see its own bars. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local L = paw.layout
local keys = T.keys

local W, H = 160, 48
local initial = L.capture()

local function reset()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  L.restore(initial)
  paw.ui.focus("arrange")
end

local function start()
  fresh()
  api.engine_restart({ backend = "null" })
  reset()
end

local function screen() return table.concat(api.ui_snapshot(W, H), "\n") end

local function names(ids)
  local out = {}
  for i, id in ipairs(ids) do
    out[i] = api.track_get(id, "name")
  end
  return table.concat(out, " ")
end

--- The name of the undo step the project is at.
local function step_name()
  local tree, at = api.undo_tree(), api.undo_current()
  for _, s in ipairs(tree.states) do
    if s.id == at then return s.label end
  end
end

--- A song with a Drums track and a return row Ballad, and a subproject
--- Ballad of two tracks (Piano, Strings) placed on the row at bar 9.
local function ballad()
  local drums = paw.add_track({ name = "Drums" })
  local row = paw.add_track({ name = "Ballad" })
  local nest = api.nest_add({ name = "Ballad", length = 32 })
  local piano = api.track_add({ name = "Piano", nest = nest })
  local strings = api.track_add({ name = "Strings", nest = nest })
  api.clip_add(piano, { start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
  local clip = api.clip_add(row.id, { nest = nest, start = 32 })
  paw.flush()
  api.undo_checkpoint()
  return { drums = drums.id, row = row.id, nest = nest, piano = piano, strings = strings, clip = clip }
end

-- A subproject is a scope ---------------------------------------------------------------

test(
  "znn on a subproject's clip enters it: its tracks, bars from 1, ⧉ in the path; zw leaves; <C-o> again",
  function()
    start()
    local b = ballad()
    eq(api.clip_get(b.clip).length, 32, "the clip is as long as the subproject")
    paw.cursor.set_track(b.row)
    paw.cursor.set_beat(33)
    keys("znn")
    eq(paw.scope.breadcrumb(), "Song › ⧉Ballad", "znn: the subproject of the clip")
    eq(names(paw.groups.rows()), "Piano Strings", "the arrange shows its two tracks")
    eq(paw.cursor.beat, 1, "the cursor keeps its place: beat 1 of the subproject")
    local text = screen()
    eq(
      text:find("Song › ⧉Ballad 1.2 (9.2)", 1, true) ~= nil,
      true,
      "the status line: its place and the song's\n" .. text
    )
    eq(paw.ruler.label(9, 0, "RulerBar", 1)[1][1], "1", "its bars count from 1: song bar 9 is its bar 1")
    keys("zw")
    eq(paw.scope.current(), nil, "zw: the song")
    eq(names(paw.groups.rows()), "Drums Ballad", "the song's tracks")
    eq(paw.cursor.beat, 33, "the cursor at the same place of the song")
    keys("<C-o>")
    eq(paw.scope.breadcrumb(), "Song › ⧉Ballad", "<C-o> enters it again")
    keys("zW")
    paw.cursor.set_track(b.row)
    paw.cursor.set_beat(40)
    keys("<CR>")
    eq(paw.scope.breadcrumb(), "Song › ⧉Ballad", "<CR> on the clip enters it too")
    reset()
  end
)

-- Inside a subproject, the ruler shows the song's regions that its block
-- covers, at their place in it, and the status line never gives a
-- negative bar for a playhead before the block.
test(
  "inside a subproject saved from a region, and one inside it, the ruler shows that region from bar 1, and the status line the song bar",
  function()
    start()
    paw.opt.zoom = 1
    local bass = paw.add_track({ name = "Bass" })
    bass:add_clip({ name = "Bass", start = 0, length = 96 })
    paw.markers.add(0, "Intro", { length = 32 })
    paw.markers.add(32, "Verse", { length = 32 })
    paw.markers.add(64, "Chorus", { length = 32 })
    paw.flush()
    api.undo_checkpoint()
    paw.ui.views:get("arrange").scroll = 0
    paw.cursor.set_track(bass)
    paw.cursor.set_beat(32)
    keys(":narrow Verse<CR>")
    keys(":scope.write! Bridge<CR>")
    eq(paw.scope.breadcrumb(), "Song › ⧉Bridge", "inside the subproject")
    -- The region Verse over its bars 1 to 8, no Intro at its bar 1, and the
    -- playhead at the song's start as `@1.1.00`, not as bar -7.
    T.expect_screen("subproject_regions", 72, 16, { styles = false })
    -- A subproject inside it, at its bar 3: the song's bar 11, and Verse
    -- still over it.
    paw.cursor.set_beat(8)
    keys(":nest.new Roll 2<CR>")
    eq(paw.scope.breadcrumb(), "Song › ⧉Bridge › ⧉Roll", "inside the subproject inside it")
    T.expect_screen("nested_subproject_regions", 72, 16, { styles = false })
    reset()
  end
)

test(
  "the song does not list a subproject's tracks: paw://tracks, the mixer, t*, the picker; all = true does",
  function()
    start()
    local b = ballad()
    eq(names(api.track_list()), "Drums Ballad", "api.track_list: the song's")
    eq(names(api.track_list({ all = true })), "Drums Ballad Master Piano Strings", "all = true: every track")
    eq(names(api.track_list({ nest = b.nest })), "Piano Strings", "nest = id: the subproject's")
    eq(names(paw.scope.tracks()), "Drums Ballad", "paw.scope.tracks of the song")
    eq(#paw.ex.range("t* mute").tracks, 2, "t*: the song's tracks")
    eq(#paw.pick.sources:get("tracks").items(), 2, "the track picker")
    paw.ui.show("mixer")
    eq(screen():find("Piano", 1, true), nil, "the mixer")
    paw.ui.hide("mixer")
    keys(":e paw://tracks<CR>")
    local lines = {}
    for i, l in ipairs(paw.textbuf.buf().state.text.lines) do
      lines[i] = l.text
    end
    eq(table.concat(lines, "\n"):find("Piano", 1, true), nil, "paw://tracks")
    for _, buf in ipairs(L.buffers_list()) do
      if buf.type == "textbuf" then L.buf_delete(buf) end
    end
    reset()
  end
)

test("<Space>zz lists a subproject, marked nest, and choosing it enters it", function()
  start()
  ballad()
  keys("<Space>zz")
  local text = screen()
  eq(text:find("nest%s+Ballad") ~= nil, true, "marked nest:\n" .. text)
  keys("Ballad<CR>")
  eq(paw.scope.breadcrumb(), "Song › ⧉Ballad", "entered")
  reset()
end)

test("an edit inside a subproject is one undo step named after it; u in the song undoes it", function()
  start()
  local b = ballad()
  paw.cursor.set_track(b.row)
  paw.cursor.set_beat(32)
  keys("znn")
  paw.cursor.set_track(b.strings)
  keys("o")
  eq(#paw.scope.tracks(), 3, "o adds a track in the subproject")
  eq(api.track_get(paw.cursor.track_id(), "nest"), b.nest, "it belongs to the subproject")
  eq(step_name():find("^Ballad: ") ~= nil, true, "the step names the subproject: " .. tostring(step_name()))
  keys("zW")
  keys("u")
  eq(#api.track_list({ nest = b.nest }), 2, "u in the song undoes it")
  reset()
end)

-- The transport inside ---------------------------------------------------------------

test("a Lua device in a subproject reads the subproject's bar; on a song track, the song's", function()
  start()
  -- A device whose sound is its bar: 0.01 for each bar, bar 1 is 0.01.
  local dir = T.scratch .. "/nest_luadev"
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(
    dir .. "/nest_bar_level.lua",
    [[
    local dev = require("paw.dsp").device {}
    function dev.process(b)
      local level = b.playing and (b.bar + 1) * 0.01 or 0
      for i = 0, b.frames - 1 do b.left[i], b.right[i] = level, level end
    end
    return dev
  ]]
  )
  paw.luadev.add_dir(dir)
  local b = ballad()
  -- Its second bar is the song's bar 10: beats 36 to 40, 18 to 20 s at 120 bpm.
  local function level()
    local info = T.render({ tail = 0, bits = 16, ["end"] = 40 })
    return (T.channel_peaks(info, 18.2, 19.8))
  end
  local inside = paw.track(b.piano):add_device("lua:nest_bar_level")
  T.near(level(), 0.02, 1e-3, "inside the subproject: its bar 2")
  inside:remove()
  paw.track(b.drums):add_device("lua:nest_bar_level")
  T.near(level(), 0.10, 1e-3, "on a song track: the song's bar 10")
end)

-- Adding one: <Space>za, :nest.new ----------------------------------------------------------

--- The song's signature changes as "beat:num/den" in order.
local function signatures()
  local out = {}
  for _, s in ipairs(paw.tempo.signatures()) do
    out[#out + 1] = string.format("%g:%d/%d", s.beat, s.num, s.den)
  end
  return table.concat(out, " ")
end

--- A metal song: 180 bpm in 4/4, a Drums track, the cursor on it.
local function metal()
  start()
  paw.project.tempo = 180
  local drums = paw.add_track({ name = "Drums" })
  paw.cursor.set_track(drums.id)
  paw.flush()
  api.undo_checkpoint()
  return drums.id
end

test(
  "the 6/8 piano section of nest.md: 33|, <Space>za Ballad 8 6/8, :tempo 60, a piano, zw; it plays in bars 33-40",
  function()
    metal()
    keys("33|")
    keys("<Space>za")
    keys("Ballad 8 6/8<CR>")
    eq(paw.scope.breadcrumb(), "Song › ⧉Ballad", "the window is inside it")
    eq(paw.ui.message.text:find("Ballad over bars 33-40 in 6/8", 1, true) ~= nil, true, paw.ui.message.text)
    eq(signatures(), "0:4/4 128:6/8 152:4/4", "the song's map: 6/8 at bar 33, 4/4 at bar 41")
    local row = api.track_list()[2]
    eq(names(api.track_list()), "Drums Ballad", "the return row is below the cursor's track")
    eq(api.clip_list(row)[1].start, 128, "its block starts at bar 33")
    eq(#paw.scope.tracks(), 1, "one empty track inside")
    local text = screen()
    eq(text:find("Song › ⧉Ballad 1.1 (33.1)", 1, true) ~= nil, true, "its bars and the song's\n" .. text)
    eq(paw.time.bar(0), 3, "its bars are 6/8: three beats")
    eq(paw.time.bar_start(34) - paw.time.bar_start(33), 3, "bar 2 of it starts 3 beats in")
    keys(":tempo 60<CR>")
    eq(paw.ui.message.text, "60 bpm: the song's tempo at bar 33", "the message names the song's bar")
    keys(":tempo 180 at 9<CR>")
    eq(paw.ui.message.text, "180 bpm: the song's tempo at bar 41", "bar 9 inside is bar 41")
    keys("a")
    keys("synth<CR>")
    keys("i")
    keys("<CR>")
    keys("<Esc>")
    keys("<CR>")
    keys("<C-w>p")
    local piano = paw.scope.tracks()[1]
    eq(#api.clip_notes(api.clip_list(piano)[1].id), 1, "a clip with a note inside")
    keys("zw")
    eq(paw.scope.current(), nil, "zw: the song")
    eq(paw.cursor.track_id() ~= nil, true, "the cursor in the song")
    -- From bar 31 to bar 43: 2.67 s of 180 bpm before bar 33.
    local info = T.render({ tail = 0, bits = 16, start = 120, ["end"] = 160 })
    eq(T.channel_peaks(info, 0, 2.6) < 1e-3, true, "nothing before bar 33")
    eq(T.channel_peaks(info, 2.7, 3.5) > 0.01, true, "the piano at bar 33")
  end
)

test("<Space>za adds a subproject in one undo step: u takes its row, the subproject and the meter away", function()
  metal()
  keys("33|")
  keys("<Space>za")
  keys("Ballad 8 6/8<CR>")
  eq(#api.nest_list(), 1, "one subproject")
  keys("u")
  eq(#api.nest_list(), 0, "no subproject")
  eq(names(api.track_list({ all = true })), "Drums", "no row, no track inside")
  eq(signatures(), "0:4/4", "the song's meter as it was")
  eq(paw.scope.current(), nil, "the window shows the song")
end)

-- The return row: blocks, in place, K, the list, stems ---------------------------------------

test("a block on its return row: a frame, ⧉ and its name, and the notes that the subproject plays", function()
  start()
  local b = ballad()
  local text = screen()
  eq(text:find("⧉ Ballad", 1, true) ~= nil, true, "the block's name after ⧉\n" .. text)
  paw.ui.render_scene("arrange", W, H, { w = 8, h = 16 })
  api.scene_forget(0)
  api.scene_roles(0, { "clip" })
  paw.ui.render_scene("arrange", W, H, { w = 8, h = 16 })
  local patch = api.json_decode(api.scene_end(0, "arr"))
  local props
  for _, n in ipairs(patch.set) do
    if n.role == "clip" and n.props.id == b.clip then props = n.props end
  end
  api.scene_forget(0)
  eq(props.nest and props.midi and props.label, "⧉ Ballad", "in the scene: a block, drawn in a frame")
  eq(props.content:find("^nest|") ~= nil, true, "with the key of what it plays")
  local flat = paw.frontend.preview(b.clip)
  eq(flat[1] .. " " .. flat[3], "0 60", "a window's picture: the piano's note at the block's start")
end)

test(
  "za on the return row shows the subproject's tracks under it, in the song's time; an edit there changes it",
  function()
    start()
    local b = ballad()
    paw.cursor.set_track(b.row)
    paw.cursor.set_beat(32)
    keys("za")
    eq(names(paw.groups.rows()), "Drums Ballad Piano Strings", "its tracks under the row")
    eq(paw.scope.current(), nil, "the window still shows the song")
    keys("j")
    eq(paw.cursor.track_id(), b.piano, "the cursor on the piano, in place")
    local clip = paw.cursor.clip()
    eq(clip and clip.id, api.clip_list(b.piano)[1].id, "its clip at bar 9 of the song: its beat 0")
    keys("~")
    eq(api.clip_get(clip.id).muted, true, "~ mutes the clip of the subproject")
    keys("za")
    eq(names(paw.groups.rows()), "Drums Ballad", "za again: one row")
    eq(paw.cursor.track_id(), b.row, "the cursor back on the row")
  end
)

test("K on a block: its meter, bars, tempo, tracks, instances", function()
  metal()
  keys("33|")
  keys(":nest.new Ballad 8 6/8<CR>")
  keys(":track.add Strings<CR>")
  keys("zw")
  paw.cursor.set_track(api.track_list()[2])
  paw.cursor.set_beat(129)
  keys("K")
  local lines = {}
  for _, line in ipairs(paw.ui.views:get("pager").lines) do
    lines[#lines + 1] = line.text
  end
  local text = table.concat(lines, "\n")
  eq(
    text:find("nest Ballad · 6/8 · 8 bars · follows the tempo · 2 tracks · 1 instance · live", 1, true) ~= nil,
    true,
    text
  )
  paw.ui.close()
end)

test(":nest.list lists the blocks and the unused subprojects; choosing one enters it", function()
  start()
  ballad()
  api.nest_add({ name = "Spare" })
  keys(":nest.list<CR>")
  local text = screen()
  eq(text:find("Ballad · bar 9 on Ballad", 1, true) ~= nil, true, "the block\n" .. text)
  eq(text:find("Spare · unused", 1, true) ~= nil, true, "the unused one\n" .. text)
  keys("bar 9<CR>")
  eq(paw.scope.breadcrumb(), "Song › ⧉Ballad", "entered")
end)

test(
  ":nest.outputs stems: a row for each track under the subproject's row, the same sound; master and u give one row",
  function()
    start()
    local b = ballad()
    api.clip_add(b.strings, { start = 0, length = 4, notes = { { pitch = 67, start = 0, length = 1 } } })
    paw.track(b.piano):add_device("synth", { attack = 0.001, release = 0.01 })
    paw.track(b.strings):add_device("synth", { attack = 0.001, release = 0.01 })
    paw.flush()
    api.undo_checkpoint()
    local function level()
      local info = T.render({ tail = 0, bits = 16, ["end"] = 40 })
      return { T.channel_peaks(info, 16, 18) }
    end
    local before = level()
    eq(before[1] > 0.01, true, "the stereo return plays")
    paw.cursor.set_track(b.row)
    keys(":nest.outputs stems<CR>")
    eq(names(api.track_list()), "Drums Ballad Piano Strings", "a stem row for each track, under the row")
    eq(paw.groups.is_group(b.row) and #paw.groups.members(b.row), 2, "the row is the group of the stems")
    local stems = level()
    T.near(stems[1], before[1], 2e-3, "the sum of the stems sounds as the return did (left)")
    T.near(stems[2], before[2], 2e-3, "and right")
    keys(":nest.outputs master<CR>")
    eq(names(api.track_list()), "Drums Ballad", "one row again")
    eq(#api.clip_list(b.row), 1, "with its block")
    keys("u")
    eq(names(api.track_list()), "Drums Ballad Piano Strings", "u: the stems again")
    keys("u")
    eq(names(api.track_list()), "Drums Ballad", "u: one row")
    eq(paw.groups.is_group(b.row), false, "not a group")
  end
)

-- Promote: <Space>zp ------------------------------------------------------------------------

--- The project as its file says it, for comparing two states.
local function project_text() return api.json_encode(api.undo_project()) end

--- The keys whose numbers are ids.
local ID_KEYS = {
  id = true,
  nest = true,
  master = true,
  output = true,
  target = true,
  group = true,
  track = true,
  sidechain = true,
  device = true,
  vcas = true,
}

--- The project as its file says it, with each id numbered in the order it
--- comes: two states that differ only in their ids give the same text.
local function canonical()
  local seen, count = {}, 0
  local function walk(v, key)
    if type(v) == "number" and ID_KEYS[key] then
      if not seen[v] then
        count = count + 1
        seen[v] = count
      end
      return "#" .. seen[v]
    elseif type(v) ~= "table" then
      return tostring(v)
    end
    local names = {}
    for k in pairs(v) do
      names[#names + 1] = k
    end
    table.sort(names, function(a, b)
      if type(a) == type(b) then return a < b end
      return type(a) == "number"
    end)
    local parts = {}
    for _, k in ipairs(names) do
      -- The items of a list are of the list's key.
      parts[#parts + 1] = tostring(k) .. "=" .. walk(v[k], type(k) == "number" and key or k)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return walk(api.undo_project())
end

--- A render of the song from `from` to `to` (beats), as the bytes of its file.
local function sound(from, to)
  local info = T.render({ tail = 0, bits = 16, start = from, ["end"] = to })
  return T.read_file(info.path)
end

--- The largest difference of two 16-bit renders, in steps of the last bit.
local function apart(a, b)
  if #a ~= #b then return math.huge end
  local worst = 0
  for i = 45, #a - 1, 2 do
    local x, y = a:byte(i) + a:byte(i + 1) * 256, b:byte(i) + b:byte(i + 1) * 256
    if x >= 32768 then x = x - 65536 end
    if y >= 32768 then y = y - 65536 end
    worst = math.max(worst, math.abs(x - y))
  end
  return worst
end

--- The 6/8 Ballad of nest.md made with keys at bar 33 of a metal song,
--- with two tracks (Piano, Strings) that each have a synth and a note, two
--- regions inside it, a volume lane on its row, and one on its master
--- unless `plain`.
local function ballad_68(plain)
  metal()
  keys("33|")
  keys(":nest.new Ballad 8 6/8<CR>")
  local nest = paw.scope.nest().id
  local piano = paw.scope.tracks()[1]
  api.track_set(piano, { name = "Piano" })
  local strings = paw.add_track({ name = "Strings" }).id
  for i, id in ipairs({ piano, strings }) do
    paw.track(id):add_device("synth", { attack = 0.001, release = 0.01 })
    api.clip_add(id, { start = 3 * (i - 1), length = 6, notes = { { pitch = 60 + 7 * i, start = 0, length = 2 } } })
  end
  local master = api.nest_get(nest, "master")
  if not plain then paw.track(master):automate("volume"):set_points({ { 0, -6 }, { 12, 0 } }) end
  local meta = api.nest_get(nest).meta
  meta.markers = {
    { id = 1, beat = 0, name = "Intro", length = 6 },
    { id = 2, beat = 12, name = "Theme", length = 12 },
  }
  api.nest_set(nest, { meta = meta })
  keys("zw")
  local row = api.track_list()[2]
  paw.track(row):automate("volume"):set_points({ { 128, -3 } })
  paw.flush()
  api.undo_checkpoint()
  return { nest = nest, row = row, piano = piano, strings = strings, master = master }
end

--- The regions as "name@beat+length", in order.
local function regions()
  local out = {}
  for _, m in ipairs(paw.markers.regions()) do
    out[#out + 1] = string.format("%s@%g+%g", m.name, m.beat, m.length)
  end
  return table.concat(out, " ")
end

test(
  "<Space>zp promotes the subproject to a view: its tracks in a group at the row's place, regions, the lane, 6/8; the window is in Song › Ballad",
  function()
    local b = ballad_68()
    -- The song's map without the 6/8, as for a subproject in a meter of its own.
    api.signature_remove(152)
    api.signature_remove(128)
    api.undo_checkpoint()
    paw.cursor.set_track(b.row)
    keys("znn")
    paw.cursor.set_track(b.strings)
    paw.cursor.set_beat(4)
    keys("<Space>zp")
    eq(#api.nest_list(), 0, "no subproject left")
    eq(names(api.track_list()), "Drums Ballad Piano Strings", "a group Ballad at the row's place, its tracks under it")
    local group = api.track_list()[2]
    eq(
      paw.groups.is_group(group) and table.concat(paw.groups.members(group), " "),
      b.piano .. " " .. b.strings,
      "the group"
    )
    eq(
      api.clip_list(b.piano)[1].start .. " " .. api.clip_list(b.strings)[1].start,
      "128 131",
      "the clips at song beats"
    )
    eq(regions(), "Ballad@128+24 Intro@128+6 Theme@140+12", "the regions inside a region named after it")
    local lanes = paw.track(group):lanes()
    local points = {}
    for _, p in ipairs(lanes[1]:points()) do
      points[#points + 1] = string.format("%g:%g", p[1], p[2])
    end
    eq(
      #lanes .. " " .. table.concat(points, " "),
      "1 128:-9 140:-3 152:-3",
      "the row's lane and the master's, one lane in dB"
    )
    eq(signatures(), "0:4/4 128:6/8 152:4/4", "6/8 in the song's map")
    eq(paw.scope.breadcrumb(), "Song › Ballad", "the window in the view that took its place")
    eq(paw.cursor.track_id() .. " " .. paw.cursor.beat, b.strings .. " 132", "at the same place")
    eq(
      paw.ui.message.text:find("promoted Ballad: 2 tracks in the group Ballad, bars 33-40", 1, true) ~= nil,
      true,
      paw.ui.message.text
    )
  end
)

test("promote: the same sound, u gives back the project as it was, and a plugin inside keeps its instance", function()
  local b = ballad_68()
  local dir = (function()
    local built = os.getenv("PAW_TEST_STUB") or "target/release/examples/libstub_clap.so"
    if not io.open(built) then return nil end
    local d = T.scratch .. "/nest-stub"
    os.execute("mkdir -p '" .. d .. "' && cp '" .. built .. "' '" .. d .. "/stub.clap'")
    return d
  end)()
  local plugin
  if dir then
    paw.plugins.add_dir(dir, "stubs")
    T.after(function() paw.plugins.remove_dir(dir) end)
    plugin = paw.track(b.piano):add_device("clap:dev.paw.stub")
  end
  paw.flush()
  api.undo_checkpoint()
  local before = project_text()
  local heard = sound(120, 160)
  paw.cursor.set_track(b.row)
  paw.cursor.set_beat(130)
  keys(":nest.promote<CR>")
  eq(apart(sound(120, 160), heard) <= 1, true, "a render after promote is the same, to the last bit of rounding")
  if plugin then
    local d = api.device_get(plugin.id)
    eq(d.track .. " " .. d.status, b.piano .. " running", "the plugin on the same track, its instance running")
  end
  keys("u")
  eq(project_text(), before, "u: the project before promote")
end)

-- Save a view: <Space>zw and <Space>zW --------------------------------------------------

--- A song in 4/4 with Bass and Keys, each with a synth, a clip in the
--- region Bridge (bars 5-10, in 6/8 in the song's map) and one after it,
--- and a marker and a region inside Bridge. The cursor on Bass.
local function bridge()
  start()
  local ids = {}
  for i, name in ipairs({ "Bass", "Keys" }) do
    local t = paw.add_track({ name = name })
    t:add_device("synth", { attack = 0.001, release = 0.01 })
    api.clip_add(t.id, { start = 16 + i, length = 6, notes = { { pitch = 40 + 12 * i, start = 0, length = 2 } } })
    api.clip_add(t.id, { start = 40, length = 4, notes = { { pitch = 45 + 12 * i, start = 0, length = 1 } } })
    ids[name] = t.id
  end
  api.signature_set(16, 6, 8)
  api.signature_set(34, 4, 4)
  paw.markers.add(16, "Bridge", { length = 18 })
  paw.markers.add(20, "Hit")
  paw.markers.add(28, "Fill", { length = 4 })
  paw.cursor.set_track(ids.Bass)
  paw.flush()
  api.undo_checkpoint()
  return ids
end

--- The markers of a subproject as "name@beat+length", in order.
local function nest_markers(nest)
  local out = {}
  for _, m in ipairs(api.nest_get(nest).meta.markers or {}) do
    out[#out + 1] = string.format("%s@%g%s", m.name, m.beat, m.length and ("+" .. m.length) or "")
  end
  return table.concat(out, " ")
end

test(
  "znar in Bridge, <Space>zw: blocks on the rows, the same render to the bit, its meter, the markers inside moved in; u",
  function()
    local t = bridge()
    local before, heard = project_text(), sound(0, 48)
    keys("6|")
    keys("znar")
    keys("<Space>zw")
    local nest = api.nest_list()[1]
    local n = api.nest_get(nest)
    eq(n.name .. " " .. #n.tracks, "Bridge 2", "a subproject Bridge with a track for each row")
    for _, id in ipairs({ t.Bass, t.Keys }) do
      local clips = api.clip_list(id)
      eq(#clips, 2, "the row keeps its clip after Bridge and gets a block")
      eq(
        string.format("%g+%g %s", clips[1].start, clips[1].length, clips[1].nest == nest and "block" or "clip"),
        "16+18 block",
        "a block over Bridge"
      )
      eq(api.track_get(id, "nest") == nil and #api.track_get(id).devices, 1, "the row keeps its synth")
    end
    eq(sound(0, 48) == heard, true, "the render is the same to the bit")
    eq(n.meter.mode .. " " .. n.meter.changes[1].num .. "/" .. n.meter.changes[1].den, "own 6/8", "the meter of Bridge")
    eq(nest_markers(nest), "Hit@4 Fill@12+4", "the marker and the region inside moved in")
    eq(regions(), "Bridge@16+18", "the region of the view stayed in the song")
    eq(
      paw.ui.message.text:find("nested 2 tracks, bars 5-10, as Bridge (6/8)", 1, true) ~= nil,
      true,
      paw.ui.message.text
    )
    keys("u")
    eq(project_text(), before, "u: the project before <Space>zw")
  end
)

test("<Space>zw then <Space>zp gives the same project, ids aside", function()
  local t = bridge()
  local before = canonical()
  keys("6|")
  keys("znar")
  keys("<Space>zw")
  paw.cursor.set_track(t.Bass)
  paw.cursor.set_beat(17)
  keys("<Space>zp")
  eq(#api.nest_list(), 0, "no subproject left")
  eq(canonical(), before, "the project as it was before <Space>zw")
end)

test(
  ":scope.write with a slash writes the view as a project that opens alone and sounds the same, the song as it was; with a name it saves a subproject",
  function()
    bridge()
    local home = T.home()
    local before, step, heard = project_text(), step_name(), sound(16, 34)
    keys("6|")
    keys("znar")
    keys(":scope.write ~/lib/bridge<CR>")
    eq(
      paw.ui.message.text:find("wrote the view Bridge to ~/lib/bridge: 2 tracks", 1, true) ~= nil,
      true,
      paw.ui.message.text
    )
    eq(project_text(), before, "the song did not change")
    eq(step_name(), step, "no undo step")
    T.expect_error("has files in it already")
    keys(":scope.write ~/lib/bridge<CR>")
    eq(
      paw.ui.message.text:find(home .. "/lib/bridge has files in it already", 1, true) ~= nil,
      true,
      paw.ui.message.text
    )
    keys(":scope.write Middle eight<CR>")
    eq(api.nest_get(api.nest_list()[1]).name, "Middle eight", "a name saves a subproject, as typed")
    paw.scope.widen(true)
    api.project_new()
    api.project_load(home .. "/lib/bridge")
    paw.flush()
    eq(names(api.track_list()), "Bass Keys", "the view's tracks")
    eq(api.device_get(api.track_get(api.track_list()[1]).devices[1]).kind, "synth", "with their devices")
    eq(signatures(), "0:6/8", "the meter of the view's time")
    eq(regions(), "Bridge@0+18 Fill@12+4", "its regions, from beat 0")
    eq(apart(sound(0, 18), heard) <= 1, true, "the same render as the view in the song")
  end
)

test(
  ":nest.export writes the subproject as a project that opens alone and renders the same as its block; the song does not change",
  function()
    local b = ballad_68()
    -- The block alone: no lane on its row, and a slower song over it,
    -- which the subproject follows.
    for _, lane in ipairs(api.lane_list(b.row)) do
      api.lane_remove(lane.id)
    end
    api.tempo_set(128, 90)
    api.tempo_set(152, 180)
    os.execute("mkdir -p '" .. T.scratch .. "/nest-export'")
    local samples = {}
    for i = 1, 12000 do
      samples[i] = 0.25
    end
    api.clip_add(b.piano, { start = 6, file = T.write_wav(T.scratch .. "/nest-export/hit.wav", samples) })
    paw.flush()
    api.undo_checkpoint()
    local before, heard = project_text(), sound(128, 152)
    paw.cursor.set_track(b.row)
    paw.cursor.set_beat(130)
    local dir = T.scratch .. "/nest-export/Ballad"
    keys(":nest.export " .. dir .. "<CR>")
    eq(
      paw.ui.message.text:find("wrote the subproject Ballad to " .. dir .. ": 2 tracks, 1 media file", 1, true) ~= nil,
      true,
      paw.ui.message.text
    )
    eq(project_text(), before, "the song did not change")
    eq(
      #T.read_file(dir .. "/media/hit.wav"),
      #T.read_file(T.scratch .. "/nest-export/hit.wav"),
      "its sound file copied in"
    )
    api.project_new()
    api.project_load(dir)
    paw.flush()
    eq(names(api.track_list()), "Piano Strings", "its tracks are the project's")
    eq(api.project_get().tempo, 90, "the song's tempo over its block")
    eq(signatures(), "0:6/8", "its own meter")
    eq(regions(), "Intro@0+6 Theme@12+12", "its regions")
    eq(apart(sound(0, 24), heard) <= 1, true, "the same render as its block, its master's lane included")
  end
)

-- Into the song: :import of a project folder ---------------------------------------------

--- A project folder of its own: the 6/8 Ballad of `ballad_68` written
--- with `:nest.export` to `<scratch>/<name>/Ballad`. Returns the folder
--- and a render of it alone, 24 beats at 180 bpm.
local function ballad_folder(name)
  local b = ballad_68(true)
  paw.cursor.set_track(b.row)
  paw.cursor.set_beat(130)
  local dir = T.scratch .. "/" .. name .. "/Ballad"
  keys(":nest.export " .. dir .. "<CR>")
  api.project_new()
  api.project_load(dir)
  paw.flush()
  return dir, sound(0, 24)
end

--- The message line has `text` in it.
local function said(text) eq(paw.ui.message.text:find(text, 1, true) ~= nil, true, paw.ui.message.text) end

test(
  ":import of a project folder plays it at once on a row of its own; its first edit makes it the song's own copy, said once",
  function()
    local dir, heard = ballad_folder("import")
    metal()
    keys(":import " .. dir .. "<CR>")
    said(
      "the subproject Ballad from "
        .. dir
        .. " at bar 1, on its own row: 2 tracks; it refers to the folder until you edit it"
    )
    local nest = api.nest_list()[1]
    eq(api.nest_get(nest).source, dir, "it refers to the folder")
    eq(apart(sound(0, 24), heard) <= 1, true, "it plays as the folder does alone")
    local copies = 0
    local handler = paw.on("nest.copied", function() copies = copies + 1 end)
    T.after(function() paw.off(handler) end)
    local piano = api.nest_get(nest).tracks[1]
    for _, name in ipairs({ "Keys", "Organ" }) do
      api.track_set(piano, { name = name })
      paw.flush()
      api.undo_checkpoint()
    end
    paw.flush()
    eq(copies, 1, "the first edit is told, the next is not")
    said("the subproject Ballad is now the song's own copy (was ")
    local n = api.nest_get(nest)
    eq({ n.source, n.origin }, { nil, dir }, "origin keeps the folder")
  end
)

test(
  ":nest.own makes the subproject at the cursor the song's own copy now; u makes it refer to the folder again",
  function()
    local dir = ballad_folder("own")
    metal()
    keys(":import " .. dir .. "<CR>")
    local nest = api.nest_list()[1]
    keys(":nest.own<CR>")
    said("the subproject Ballad is now the song's own copy (was ")
    local n = api.nest_get(nest)
    eq({ n.source, n.origin }, { nil, dir }, "the copy keeps the folder in origin")
    T.expect_error("is the song's own already")
    keys(":nest.own<CR>")
    keys("u")
    n = api.nest_get(nest)
    eq({ n.source, n.origin }, { dir, nil }, "u: it refers to the folder again")
  end
)

test(":e of a subproject's folder in a song opens the song inside it; the song keeps a path, no copy", function()
  local dir = ballad_folder("open")
  metal()
  keys(":import " .. dir .. "<CR>")
  local song = T.scratch .. "/open/song"
  keys(":w " .. song .. "<CR>")
  eq(
    T.read_file(song .. "/nests/Ballad/nest.toml"):find("\nsource = ", 1, true) ~= nil,
    true,
    "nest.toml names the folder"
  )
  eq(io.open(song .. "/nests/Ballad/master/track.json"), nil, "and the song has no copy of it")
  api.project_new()
  paw.flush()
  keys(":e " .. song .. "/nests/Ballad<CR>")
  local here = paw.scope.nest()
  eq(here and api.nest_get(here.id).name, "Ballad", "the window is inside Ballad")
  eq(api.nest_get(here.id).source, dir, "read from the folder")
  eq(names(paw.scope.tracks()), "Piano Strings", "its tracks")
end)

test(". after <Space>zw saves the next view beside it", function()
  bridge()
  paw.markers.add(34, "Outro", { length = 12 })
  api.undo_checkpoint()
  keys("6|")
  keys("znar")
  keys("<Space>zw")
  keys(".")
  local made = {}
  for _, n in ipairs(paw.nest.list()) do
    made[#made + 1] = n.name
  end
  eq(table.concat(made, " "), "Bridge Outro", "a subproject for Bridge, then one for Outro")
end)

test("<Space>zW on two tracks with devices: one return row, the devices inside, the same render", function()
  local t = bridge()
  local heard = sound(0, 48)
  keys("6|")
  keys("znar")
  keys("<Space>zW")
  eq(names(api.track_list()), "Bridge Bass Keys", "one return row, at the place of the first track")
  eq(paw.scope.breadcrumb(), "Song › ⧉Bridge", "the window inside it")
  local inside = paw.scope.tracks()
  eq(names(inside), "Bass Keys", "a copy of each track inside")
  for _, id in ipairs(inside) do
    eq(api.device_get(api.track_get(id).devices[1]).kind, "synth", "with a copy of its synth")
  end
  eq(#api.clip_list(t.Bass), 1, "the song's Bass keeps its clip after Bridge")
  eq(apart(sound(0, 48), heard) <= 1, true, "the same render, to the last bit of rounding")
end)

test(
  "<Space>zW: a send to a bus outside becomes the return row's, said; a side-chain from outside is refused",
  function()
    local t = bridge()
    local verb = paw.add_track({ name = "Verb" })
    local kick = paw.add_track({ name = "Kick" })
    paw.track(t.Bass):send(verb.id, -6)
    paw.flush()
    api.undo_checkpoint()
    paw.scope.enter({ kind = "range", tracks = { t.Bass }, from = 16, to = 34, name = "Bridge" })
    keys("<Space>zW")
    local row = api.track_list()[1]
    eq(names({ row }), "Bridge", "the return row")
    local sends = api.track_get(row).sends
    eq(#sends == 1 and sends[1].target == verb.id and sends[1].level, -6, "the row sends to Verb as Bass did")
    eq(
      paw.ui.message.text:find("the send Bass → Verb (-6 dB) is now Bridge's", 1, true) ~= nil,
      true,
      paw.ui.message.text
    )
    keys("u")
    paw.scope.widen(true)
    local comp = paw.track(t.Bass):add_device("compressor")
    comp:set_sidechain(kick)
    paw.flush()
    api.undo_checkpoint()
    paw.scope.enter({ kind = "range", tracks = { t.Bass }, from = 16, to = 34, name = "Bridge" })
    T.expect_error("^compressor on Bass listens to Kick")
    keys("<Space>zW")
    eq(paw.ui.message.text, "compressor on Bass listens to Kick: take Kick in too, or use <Space>zw", "refused")
    eq(#api.nest_list(), 0, "nothing saved")
  end
)

--- A song of groups: Drums (Kick, Snare) and Keys (Piano, Pad), Bass and
--- Reverb, each with a synth and a clip over the whole song but Reverb,
--- and the regions Intro, Verse and Chorus of 2 bars each. With `send`,
--- Piano sends to Reverb at -14 dB. The cursor on Kick at the start.
local function groups_song(send)
  start()
  paw.opt.zoom = 1
  local t = {}
  for i, name in ipairs({ "Kick", "Snare", "Piano", "Pad", "Bass", "Reverb" }) do
    local track = paw.add_track({ name = name })
    track:add_device("synth", { attack = 0.001, release = 0.01 })
    if name ~= "Reverb" then
      local notes = {}
      for beat = 0, 20, 4 do
        notes[#notes + 1] = { pitch = 40 + 3 * i, start = beat, length = 2 }
      end
      track:add_clip({ name = name, start = 0, length = 24, notes = notes })
    end
    t[name] = track.id
  end
  t.Drums = paw.groups.make({ t.Kick, t.Snare }, "Drums").id
  t.Keys = paw.groups.make({ t.Piano, t.Pad }, "Keys").id
  if send then paw.track(t.Piano):send(t.Reverb, -14) end
  paw.markers.add(0, "Intro", { length = 8 })
  paw.markers.add(8, "Verse", { length = 8 })
  paw.markers.add(16, "Chorus", { length = 8 })
  paw.ui.views:get("arrange").scroll = 0
  paw.cursor.set_track(t.Kick)
  paw.cursor.set_beat(0)
  paw.flush()
  api.undo_checkpoint()
  return t
end

--- The output of each track named, as "name>output" ("-" the master).
local function outputs(t, list)
  local out = {}
  for i, name in ipairs(list) do
    local to = api.track_get(t[name] or name, "output")
    out[i] = name .. ">" .. (to and api.track_get(to, "name") or "-")
  end
  return table.concat(out, " ")
end

--- The song's track called `name`.
local function song_track(name)
  for _, id in ipairs(api.track_list()) do
    if api.track_get(id, "name") == name then return id end
  end
end

test(":scope.write! of a group with no time leaves every marker and region in the song, and says what moved", function()
  local t = groups_song()
  paw.cursor.set_track(t.Piano)
  keys(":narrow Keys<CR>")
  keys(":scope.write! Keys2<CR>")
  said("made the subproject ⧉Keys2 from Piano and Pad, bars 1-6")
  eq(paw.ui.message.text:find("moved in", 1, true), nil, "no marker moved in: " .. paw.ui.message.text)
  eq(regions(), "Intro@0+8 Verse@8+8 Chorus@16+8", "the song keeps its regions")
  eq(api.nest_get(api.nest_list()[1]).meta.markers, nil, "the subproject has none")
end)

test(
  ":scope.write! of a group over some bars keeps the group: the row goes into it, nothing else is routed again, the same render",
  function()
    local t = groups_song()
    local heard = sound(0, 24)
    paw.cursor.set_track(t.Piano)
    paw.cursor.set_beat(8)
    keys(":narrow Verse<CR>:narrow Keys<CR>")
    keys(":scope.write! Bridge<CR>")
    said(
      "made the subproject ⧉Bridge from Piano and Pad, bars 3-4 (4/4); its row is in the group Keys, so it plays as before"
    )
    keys("zW")
    local row = song_track("Bridge")
    eq(
      names(api.track_list()),
      "Drums Kick Snare Keys Piano Pad Bridge Bass Reverb",
      "the groups stay; the row is the last of Keys"
    )
    eq(paw.groups.of(row), t.Keys, "the row is in the group Keys")
    eq(outputs(t, { "Piano", "Pad", "Bridge" }), "Piano>Keys Pad>Keys Bridge>Keys", "the routes of the song")
    eq(apart(sound(0, 24), heard) <= 1, true, "the same render, to the last bit of rounding")
    paw.cursor.set_track(t.Keys)
    T.expect_screen("write_keeps_the_group", 100, 30, { styles = false, rows = { 1, 28 } })
  end
)

test(
  ":scope.write! over several buses: one row to the master, the buses named; a bus the song sends to stays; stems keep the buses",
  function()
    local t = groups_song(true)
    keys(":narrow Verse<CR>")
    keys(":scope.write! Bridge<CR>")
    said("the Drums bus and the Keys bus no longer process bars 3-4: `:scope.write! Bridge stems` keeps them")
    said("the send Piano → Reverb (-14 dB) is now Bridge's")
    keys("zW")
    eq(
      outputs(t, { "Kick", "Piano", "Bridge" }),
      "Kick>Drums Piano>Keys Bridge>-",
      "the song's routes; the row to the master"
    )
    local sends = api.track_get(t.Piano).sends
    eq(#sends == 1 and sends[1].target, t.Reverb, "the song's Piano still sends to Reverb, which stays in the song")
    eq(paw.groups.members(t.Drums), { t.Kick, t.Snare }, "the group Drums stays")
    -- Stems, in a song without the send: the same sound.
    t = groups_song()
    local heard = sound(0, 24)
    paw.cursor.set_beat(8)
    keys(":narrow Verse<CR>")
    keys(":scope.write! Bridge stems<CR>")
    said("a stem row for each track, so the Drums bus and the Keys bus still process bars 3-4")
    keys("zW")
    local stems = {}
    for _, id in ipairs(paw.groups.members(song_track("Bridge"))) do
      local to = api.track_get(id, "output")
      stems[#stems + 1] = api.track_get(id, "name") .. ">" .. api.track_get(to, "name")
    end
    eq(
      table.concat(stems, " "),
      "Kick>Drums Snare>Drums Piano>Keys Pad>Keys Bass>Bridge",
      "each stem plays into its bus"
    )
    eq(apart(sound(0, 24), heard) <= 1, true, "the same render, to the last bit of rounding")
  end
)

test("a split with one window inside a subproject: moving in the song's window leaves the other in its bars", function()
  start()
  paw.opt.zoom = 4
  local bass = paw.add_track({ name = "Bass" })
  bass:add_clip({ name = "Bass", start = 0, length = 24 })
  paw.markers.add(8, "Verse", { length = 8 })
  paw.ui.views:get("arrange").scroll = 0
  paw.cursor.set_track(bass)
  paw.cursor.set_beat(8)
  paw.flush()
  api.undo_checkpoint()
  keys(":narrow Verse<CR>")
  keys(":scope.write! Bridge<CR>")
  keys("<C-w>v")
  keys("zW")
  keys("6|")
  T.expect_screen("split_keeps_its_bars", 100, 30, { styles = false, rows = { 1, 28 } })
  reset()
end)

test("the round trip of nest.md 3.9: <Space>zp then <Space>zW gives the same project, ids aside, and render", function()
  local b = ballad_68(true)
  paw.markers.add(128, "Ballad", { length = 24 })
  paw.flush()
  api.undo_checkpoint()
  local before, heard = canonical(), sound(120, 160)
  paw.cursor.set_track(b.row)
  paw.cursor.set_beat(130)
  keys("<Space>zp")
  eq(paw.scope.breadcrumb(), "Song › Ballad", "in the view that took its place")
  keys("<Space>zW")
  eq(canonical(), before, "the subproject as it was")
  eq(apart(sound(120, 160), heard) <= 1, true, "the same render, to the last bit of rounding")
end)

test(
  "<Space>za with a meter of 8 shorter beats moves the rest of the song: a clip at bar 41 stays at bar 41; u puts all back",
  function()
    local drums = metal()
    api.clip_add(drums, { start = 160, length = 4, notes = { { pitch = 36, start = 0, length = 1 } } })
    paw.markers.add(160, "Outro", { length = 16 })
    api.undo_checkpoint()
    keys("33|")
    keys("<Space>za")
    keys("Ballad 8 6/8<CR>")
    eq(
      paw.ui.message.text:find("the rest of the song moved 8 beats earlier", 1, true) ~= nil,
      true,
      paw.ui.message.text
    )
    keys("zw")
    local clip = api.clip_list(drums)[1]
    eq(clip.start .. " " .. paw.time.bar_of(clip.start), "152 41", "the clip still starts at bar 41")
    eq(paw.markers.regions()[1].beat, 152, "the region Outro moved with it")
    keys("u")
    eq(api.clip_list(drums)[1].start, 160, "u: the clip where it was")
    eq(paw.markers.regions()[1].beat .. " " .. signatures(), "160 0:4/4", "the region and the meter as they were")
  end
)

test("promote keeps the subproject's key on its region, as a key over its time", function()
  local b = ballad_68()
  local meta = api.nest_get(b.nest).meta
  meta.key = "D minor"
  api.nest_set(b.nest, { meta = meta })
  api.undo_checkpoint()
  paw.cursor.set_track(b.row)
  paw.cursor.set_beat(130)
  keys("<Space>zp")
  local region = paw.markers.regions()[1]
  eq(region.name .. " " .. tostring(region.key), "Ballad D minor", "the region has its key")
  eq(paw.ui.message.text:find("the region Ballad is in D minor", 1, true) ~= nil, true, paw.ui.message.text)
end)

-- Its own tempo and meter ------------------------------------------------------------------

--- A song at 120 bpm with a return row Cue, and a subproject Cue of 16
--- beats whose synth plays a short note on its beats 0, 4, 8 and 12. Its
--- block starts at bar 5 (beat 16, 8 s).
local function cue()
  start()
  local row = paw.add_track({ name = "Cue" })
  local nest = api.nest_add({ name = "Cue", length = 16 })
  local synth = api.track_add({ name = "Synth", nest = nest })
  paw.track(synth):add_device("synth", { attack = 0.001, release = 0.01 })
  local notes = {}
  for i = 0, 3 do
    notes[#notes + 1] = { pitch = 69, start = i * 4, length = 0.25 }
  end
  api.clip_add(synth, { start = 0, length = 16, notes = notes })
  local clip = api.clip_add(row.id, { nest = nest, start = 16 })
  paw.flush()
  api.undo_checkpoint()
  return { row = row.id, nest = nest, clip = clip }
end

--- Where sound starts after a silence in a 16-bit render, in seconds with
--- two decimals ("8.00 10.00"), or with `digits` decimals.
local function onsets(info, digits)
  local data = T.read_file(info.path)
  local at = data:find("data", 1, true) + 8
  local out, quiet, gap = {}, 0, math.floor(info.sample_rate * 0.05)
  for i = at, #data - 3, 4 do
    local v = data:byte(i) + data:byte(i + 1) * 256
    if v >= 32768 then v = v - 65536 end
    if math.abs(v) > 300 then
      if quiet >= gap then
        out[#out + 1] = string.format("%." .. (digits or 2) .. "f", (i - at) / 4 / info.sample_rate)
      end
      quiet = 0
    else
      quiet = quiet + 1
    end
  end
  return table.concat(out, " ")
end

test(
  "a ritardando of the song over a block moves the notes of a subproject that follows the tempo, not those of one with its own",
  function()
    local b = cue()
    local function heard() return onsets(T.render({ tail = 0, bits = 16, ["end"] = 40 })) end
    paw.cursor.set_track(b.row)
    paw.cursor.set_beat(17)
    keys(":nest.time own<CR>")
    eq(paw.ui.message.text:find("Cue has its own tempo, 120 bpm", 1, true) ~= nil, true, paw.ui.message.text)
    eq(heard(), "8.00 10.00 12.00 14.00", "at 120 bpm, a note each 2 s from 8 s")
    -- From bar 5 the song slows down to 60 bpm at bar 9.
    paw.tempo.set(16, 120, { ramp = true })
    paw.tempo.set(32, 60)
    eq(heard(), "8.00 10.00 12.00 14.00", "its own tempo: the same seconds")
    local c = api.clip_get(b.clip)
    T.near(api.tempo_seconds(c.start + c.length), 16, 1e-6, "the block still lasts 8 s")
    keys(":nest.time follow<CR>")
    local follows = {}
    for t in heard():gmatch("%S+") do
      follows[#follows + 1] = tonumber(t)
    end
    eq(follows[1], 8, "the first note on the block's start")
    eq(follows[2] > 10.05 and follows[3] > 12.05 and follows[4] > 14.05, true, "the song's tempo: later notes")
    keys("u")
    eq(api.nest_get(b.nest).tempo.mode, "own", "u: its own tempo again")
  end
)

test(":nest.new Ballad 8 6/8 meter=own keeps the song's map; inside it, its bars are 6/8 and K says 6/8", function()
  metal()
  keys("33|")
  keys(":nest.new Ballad 8 6/8 meter=own<CR>")
  eq(signatures(), "0:4/4", "the song's map as it was")
  eq(
    paw.ui.message.text:find("over bars 33-38 in 6/8 (the song's meter stays)", 1, true) ~= nil,
    true,
    paw.ui.message.text
  )
  local lines = {}
  for _, l in ipairs(paw.time.bars(0, 10)) do
    lines[#lines + 1] = l.beat .. ":" .. l.bar
  end
  eq(table.concat(lines, " "), "0:1 3:2 6:3 9:4", "its bars: three beats each, from 1")
  eq(paw.ruler.label(2, 3, "RulerBar", 0)[1][1], "2", "the ruler numbers its bar 2 at beat 3")
  local text = screen()
  eq(text:find("Song › ⧉Ballad 1.1 (33.1)", 1, true) ~= nil, true, "its place and the song's\n" .. text)
  keys("zw")
  paw.cursor.set_track(api.track_list()[2])
  paw.cursor.set_beat(129)
  keys("K")
  local said = {}
  for _, line in ipairs(paw.ui.views:get("pager").lines) do
    said[#said + 1] = line.text
  end
  paw.ui.close()
  eq(table.concat(said, "\n"):find("nest Ballad · 6/8 · 8 bars", 1, true) ~= nil, true, table.concat(said, "\n"))
end)

test(
  "inside a meter=own 6/8 subproject, the ruler, the grid and the status line count 6/8; the song's stay 4/4",
  function()
    metal()
    paw.opt.zoom = 2
    -- The columns between the bar numbers of the ruler, and between the grid's
    -- bar lines on the track's row, and the meter in the status line.
    local function counted()
      local rows = api.ui_snapshot(W, H)
      local ruler = rows[1]:match("│(.*)$"):gsub("▏", "'")
      local lane = rows[3]:match("│(.*)$"):gsub("▏", "|")
      local function gaps(row, pattern)
        local at, out = {}, {}
        for x in row:gmatch("()" .. pattern) do
          at[#at + 1] = x
        end
        for i = 2, math.min(#at, 4) do
          out[#out + 1] = at[i] - at[i - 1]
        end
        return table.concat(out, " ")
      end
      local meter = table.concat(rows, "\n"):match("bpm (%d+/%d+)")
      return gaps(ruler, "%f[%d]%d+") .. " | " .. gaps(lane, "|") .. " | " .. meter
    end
    keys("33|")
    keys(":nest.new Ballad 8 6/8 meter=own<CR>")
    eq(counted(), "6 6 6 | 6 6 6 | 6/8", "inside: a bar every 3 beats (6 eighths)")
    keys("zw")
    eq(counted(), "8 8 8 | 8 8 8 | 4/4", "the song outside: a bar every 4 beats")
  end
)

test("<Space>zw on a view inside a meter=own 6/8 subproject saves it in 6/8", function()
  metal()
  keys("33|")
  keys(":nest.new Ballad 8 6/8 meter=own<CR>")
  local inside = paw.scope.tracks()
  api.clip_add(inside[1], { start = 3, length = 6, notes = { { pitch = 60, start = 0, length = 1 } } })
  paw.flush()
  api.undo_checkpoint()
  -- Bars 2-3 of Ballad: three beats each.
  paw.scope.enter({ kind = "range", tracks = inside, from = 3, to = 9, name = "Verse" })
  keys("<Space>zw")
  local verse = api.nest_get(api.nest_list()[2])
  local changes = {}
  for _, c in ipairs(verse.meter.changes) do
    changes[#changes + 1] = string.format("%g:%d/%d", c.beat, c.num, c.den)
  end
  eq(verse.name .. " " .. verse.meter.mode .. " " .. table.concat(changes, " "), "Verse own 0:6/8", "Ballad's meter")
  eq(paw.ui.message.text:find("as Verse (6/8)", 1, true) ~= nil, true, paw.ui.message.text)
  eq(signatures(), "0:4/4", "the song's map as it was")
end)

test("inside a subproject with its own tempo, :tempo sets its tempo and the status line says own tempo", function()
  local b = cue()
  paw.cursor.set_track(b.row)
  paw.cursor.set_beat(17)
  keys(":nest.time own<CR>")
  keys("znn")
  keys(":tempo 90<CR>")
  eq(paw.ui.message.text, "90 bpm: the subproject's own tempo", "the message")
  eq(api.nest_get(b.nest).tempo.points[1].bpm .. " " .. paw.project.tempo, "90 120", "its tempo, not the song's")
  eq(screen():find("own tempo", 1, true) ~= nil, true, "the status line")
end)

test("inside a subproject with its own tempo, the tempo lane shows its tempo, not the song's", function()
  local b = cue()
  paw.cursor.set_track(b.row)
  paw.cursor.set_beat(17)
  keys(":nest.time own<CR>")
  keys("znn")
  keys(":tempo 90<CR>")
  keys("zT")
  T.after(function() paw.tempolane.show(false) end)
  local rows = api.ui_snapshot(120, 24)
  local header
  for i, row in ipairs(rows) do
    if row:find("^%s*tempo%s") and rows[i + 1] then header = rows[i + 1]:match("^%s*(%d+ bpm)") end
  end
  eq(header, "90 bpm", "the lane's header: its tempo at the cursor\n" .. table.concat(rows, "\n"))
  local lo, hi = paw.tempolane.range()
  eq(lo .. " " .. hi, "50 130", "the lane's range round 90")
end)

test("inside a subproject with its own tempo, grt types its tempo, not the song's, and u takes it back", function()
  local b = cue()
  paw.cursor.set_track(b.row)
  paw.cursor.set_beat(17)
  keys(":nest.time own<CR>")
  keys("znn")
  api.undo_checkpoint()
  keys("grt96<CR>")
  local function tempos() return api.nest_get(b.nest).tempo.points[1].bpm .. " " .. paw.project.tempo end
  eq(tempos(), "96 120", "its tempo, not the song's")
  api.undo_checkpoint()
  keys("u")
  eq(tempos(), "120 120", "one step back")
end)

test(
  "<Space>zp of a subproject with its own tempo writes its tempo into the song's map: the same render, and the message says so",
  function()
    local b = cue()
    local drums = paw.add_track({ name = "Drums" })
    drums:add_device("synth", { attack = 0.001, release = 0.01 })
    drums:add_clip({ start = 40, length = 1, notes = { { pitch = 57, start = 0, length = 0.25 } } })
    paw.cursor.set_track(b.row)
    paw.cursor.set_beat(17)
    keys(":nest.time own 90<CR>")
    T.near(api.clip_get(b.clip).length, 64 / 3, 1e-9, "16 of its beats at 90 are 21.33 of the song's at 120")
    -- The same sound: each note at the same millisecond, as loud. A note
    -- can start one frame apart, as its beat in the song is another.
    local function heard()
      local info = T.render({ tail = 0, bits = 16 })
      local peak = T.channel_peaks(info)
      return onsets(info, 3) .. string.format(" peak %.3f", peak)
    end
    local before = heard()
    keys("<Space>zp")
    eq(heard(), before, "the same render")
    local tempos = {}
    for _, p in ipairs(paw.tempo.points()) do
      tempos[#tempos + 1] = string.format("%g:%g", p.beat, p.bpm)
    end
    eq(table.concat(tempos, " "), "0:120 16:90 32:120", "90 over its 16 beats, 120 back after")
    T.near(api.clip_list(drums.id)[1].start, 40 - 16 / 3, 1e-9, "the song after it moved with its beats")
    eq(
      paw.ui.message.text:find(
        "its own tempo, 90 bpm, in the song's map over bars 5-8, and 120 bpm back after it",
        1,
        true
      ) ~= nil,
      true,
      paw.ui.message.text
    )
  end
)

test(
  "a drag of a song's marker inside a subproject with its own tempo moves it to the song's beat under the mouse",
  function()
    local b = cue()
    paw.markers.add(20, "Hit")
    paw.opt.zoom, paw.opt.grid = 4, 1
    paw.cursor.set_track(b.row)
    paw.cursor.set_beat(17)
    keys(":nest.time own 90<CR>")
    keys("znn")
    paw.ui.views:get("arrange").scroll = 0
    -- Its beat 3 is the song's beat 20: 16 of its beats at 90 are 21.33 of
    -- the song's at 120.
    local x, y
    for row, line in ipairs(api.ui_snapshot(W, H)) do
      local i = line:find("Hit", 1, true)
      if i then
        x, y = api.str_width(line:sub(1, i - 1)), row - 1
        break
      end
    end
    eq(x ~= nil, true, "the marker shows inside")
    paw.mouse.forget()
    -- Three of its beats to the right: its beat 6, the song's beat 24.
    for _, e in ipairs({ { "down", x }, { "drag", x + 1 }, { "drag", x + 12 }, { "up", x + 12 } }) do
      paw.ui.mouse({ kind = e[1], x = e[2], y = y, button = "left", mods = "" })
    end
    T.near(paw.markers.find("Hit").beat, 24, 1e-9, "the song's beat under the mouse")
    keys("u")
    eq(paw.markers.find("Hit").beat, 20, "u puts it back")
  end
)

-- Tempo and meter edits inside one ----------------------------------------------------------

--- Tempo points as text: "120@0 90@8", a ramp marked ">".
local function tempo_text(points)
  local out = {}
  for i, p in ipairs(points or {}) do
    out[i] = string.format("%g@%g%s", p.bpm, p.beat, p.ramp and ">" or "")
  end
  return table.concat(out, " ")
end

--- Signature changes as text: "0:4/4 8:6/8".
local function meter_text(changes)
  local out = {}
  for i, s in ipairs(changes or {}) do
    out[i] = string.format("%g:%d/%d", s.beat, s.num, s.den)
  end
  return table.concat(out, " ")
end

--- The Cue of `cue`, its time set with the keys `how` on its block (none
--- to follow the song), then entered with znn, the cursor at its beat 10.
--- Gives the tempo and the meter of the song and of the subproject as text.
local function inside_cue(how)
  local b = cue()
  paw.cursor.set_track(b.row)
  paw.cursor.set_beat(17)
  if how then keys(how) end
  keys("znn")
  paw.cursor.set_beat(10)
  api.undo_checkpoint()
  return function()
    local n = api.nest_get(b.nest)
    return {
      song = tempo_text(paw.tempo.points()) .. " | " .. signatures(),
      own = tempo_text(n.tempo.mode == "own" and n.tempo.points) .. " | " .. meter_text(
        n.meter.mode == "own" and n.meter.changes
      ),
    }
  end
end

-- Each row: how the subproject keeps time, and where its beat 8 is in
-- the map that an edit changes: its own map, or the song's at beat 24.
local tempo_cases = {
  { name = "its own tempo", how = ":nest.time own<CR>", own = true },
  { name = "the song's tempo", how = nil, own = false },
}

test(
  "inside a subproject, :tempo.ramp, :tempo.tap and :tempo.remove edit the window's map, one undo step each",
  function()
    -- A clock that the test steps, far after the taps of other tests.
    local clock = 1e12
    local now = api.now
    api.now = function() return clock end
    T.after(function() api.now = now end)
    for _, case in ipairs(tempo_cases) do
      local maps = inside_cue(case.how)
      local before = maps()
      local name, other = case.own and "own" or "song", case.own and "song" or "own"
      local function map() return maps()[name] end
      -- Its beat 8: in its own map, or at the song's beat 24, in 4/4.
      local function with(bpm, ramp)
        local change = string.format("%d@%d%s", bpm, case.own and 8 or 24, ramp or "")
        return "120@0 " .. change .. (case.own and " | " or " | 0:4/4")
      end
      keys(":tempo 90 at 3<CR>")
      eq(map(), with(90), case.name .. ": a change at its bar 3")
      keys(":tempo.ramp<CR>")
      eq(map(), with(90, ">"), case.name .. ": the change before the cursor ramps")
      keys("u")
      eq(map(), with(90), case.name .. ": u takes the ramp back")
      keys(":tempo.tap<CR>")
      clock = clock + 600
      keys(":tempo.tap<CR>")
      clock = clock + 5000
      eq(map(), with(100), case.name .. ": a tap each 0.6 s is 100 bpm")
      keys("u")
      eq(map(), with(90), case.name .. ": u takes the tap back")
      keys(":tempo.remove<CR>")
      eq(map(), case.own and "120@0 | " or "120@0 | 0:4/4", case.name .. ": the change goes")
      keys("u")
      eq(map(), with(90), case.name .. ": u brings it back")
      eq(maps()[other], before[other], case.name .. ": the other map as it was")
    end
  end
)

test("inside a subproject, :timesig and :timesig.remove edit the window's meter, one undo step each", function()
  local cases = {
    -- Its own meter of 3/4: its bar 3 is its beat 6.
    { name = "its own meter", how = ":nest.meter 3/4<CR>", map = "own", set = "0:3/4 6:6/8", was = "0:3/4" },
    -- Its own tempo, the song's meter: the 4/4 it shows becomes its own.
    { name = "its own tempo", how = ":nest.time own<CR>", map = "own", set = "0:4/4 8:6/8", was = "" },
    -- The song's tempo and meter: its bar 3 is the song's bar 7, beat 24.
    { name = "the song's time", how = nil, map = "song", set = "0:4/4 24:6/8", was = "0:4/4" },
  }
  for _, case in ipairs(cases) do
    local maps = inside_cue(case.how)
    local function meter() return maps()[case.map]:match("| (.*)$") end
    local other = case.map == "own" and "song" or "own"
    local before = maps()[other]
    keys(":timesig 6/8 at 3<CR>")
    eq(meter(), case.set, case.name .. ": 6/8 from its bar 3")
    eq(paw.ui.message.text, "6/8 from bar 3", case.name .. ": the message")
    keys("u")
    eq(meter(), case.was, case.name .. ": u takes it back")
    keys(":timesig 6/8 at 3<CR>")
    api.undo_checkpoint()
    keys(":timesig.remove 3<CR>")
    eq(paw.ui.message.text, "removed the signature change at bar 3", case.name .. ": the message of the removal")
    eq(meter() == case.set, false, case.name .. ": the change goes")
    keys("u")
    eq(meter(), case.set, case.name .. ": u brings it back")
    eq(maps()[other], before, case.name .. ": the other map as it was")
  end
end)

test(
  "inside a subproject, o in the curve editor of paw://tempo adds a change to the window's map at its beat",
  function()
    for _, case in ipairs(tempo_cases) do
      local maps = inside_cue(case.how)
      local before = maps()
      paw.cursor.set_beat(8)
      keys(":sp paw://tempo<CR>")
      keys("o")
      local m = maps()
      local map, other = m.song, "own"
      if case.own then
        map, other = m.own, "song"
      end
      eq(map:match("^120@0 120@(%d+)"), case.own and "8" or "24", case.name .. ": a change at its beat 8: " .. map)
      eq(m[other], before[other], case.name .. ": the other map as it was")
      keys("u")
      eq(maps().song .. maps().own, before.song .. before.own, case.name .. ": one undo step")
      reset()
    end
  end
)

-- One subproject placed twice ---------------------------------------------------------------

--- The Ballad of `ballad` with a synth on its Piano, and a second block
--- pasted with keys: `yic` on the block at bar 9, then `p` at bar 97.
local function linked()
  start()
  local b = ballad()
  paw.track(b.piano):add_device("synth", { attack = 0.001, release = 0.01 })
  api.undo_checkpoint()
  paw.cursor.set_track(b.row)
  paw.cursor.set_beat(32)
  keys("yic")
  keys("97|")
  keys("p")
  local blocks = api.clip_list(b.row)
  b.second = blocks[#blocks].id
  return b
end

--- The peak of the song over two beats from `from`.
local function level(from) return (T.channel_peaks(T.render({ tail = 0, bits = 16, start = from, ["end"] = from + 2 }))) end

--- Mute the Piano clip of the subproject of the block at `beat` of the row, with keys from inside it.
local function mute_inside(b, beat)
  paw.cursor.set_track(b.row)
  paw.cursor.set_beat(beat)
  keys("znn")
  paw.cursor.set_track(paw.scope.tracks()[1])
  paw.cursor.set_beat(0)
  keys("~")
  keys("zw")
end

test(
  "y on a block and p at bar 97 make a second block of the same subproject: an edit inside is heard in both",
  function()
    local b = linked()
    eq(
      api.clip_get(b.second).start .. " " .. api.clip_get(b.second).nest,
      "384 " .. b.nest,
      "a block of Ballad at bar 97"
    )
    eq(#api.nest_list(), 1, "one subproject")
    eq(level(32) > 0.01 and level(384) > 0.01, true, "both blocks play the piano")
    mute_inside(b, 33)
    eq(level(32) < 1e-3, true, "the piano muted at bar 9")
    eq(level(384) < 1e-3, true, "and at bar 97")
  end
)

test(":nest.unique on the second block: an edit inside it leaves the first as it was; u links them again", function()
  local b = linked()
  paw.cursor.set_track(b.row)
  paw.cursor.set_beat(385)
  keys(":nest.unique<CR>")
  eq(
    paw.ui.message.text,
    "Ballad 2: the block at bar 97 is a subproject of its own; Ballad still plays at bar 9",
    "the message"
  )
  keys("u")
  eq(api.clip_get(b.second).nest, b.nest, "u: the same subproject again")
  keys("<C-r>")
  local copy = api.clip_get(b.second).nest
  eq(copy ~= b.nest and api.nest_get(copy).name, "Ballad 2", "a copy of its own")
  mute_inside(b, 385)
  eq(level(32) > 0.01, true, "the first block plays as it did")
  eq(level(384) < 1e-3, true, "the second is muted")
end)

test(
  "K on a block placed twice says 2 instances; <Space>zp on one says that the subproject still plays at the other",
  function()
    local b = linked()
    paw.cursor.set_track(b.row)
    paw.cursor.set_beat(33)
    keys("K")
    local said = {}
    for _, line in ipairs(paw.ui.views:get("pager").lines) do
      said[#said + 1] = line.text
    end
    paw.ui.close()
    eq(table.concat(said, "\n"):find("· 2 instances ·", 1, true) ~= nil, true, table.concat(said, "\n"))
    paw.cursor.set_track(b.row)
    paw.cursor.set_beat(33)
    keys("<Space>zp")
    eq(paw.ui.message.text:find("Ballad still plays at bar 97", 1, true) ~= nil, true, paw.ui.message.text)
    eq(api.clip_get(b.second).nest .. " " .. #api.nest_list(), b.nest .. " 1", "the block at bar 97 keeps Ballad")
    eq(level(32) > 0.01 and level(384) > 0.01, true, "both play as before")
  end
)
