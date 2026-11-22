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
    eq(text:find("9%s+10%s+11") ~= nil, true, "a second row has the song's bars")
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
    eq(#paw.pick.sources.tracks.items(), 2, "the track picker")
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
  for _, line in ipairs(paw.ui.views.pager.lines) do
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
