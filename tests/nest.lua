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
    eq(paw.ruler.label(1, 0, "RulerBar", 1)[1][1], "1", "its bars count from 1")
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
