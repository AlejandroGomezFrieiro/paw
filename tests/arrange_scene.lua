-- Tests of the arrange view as a window shows it: from its scene (its
-- timeline a plane of beats and lines, each clip on it a role a window
-- paints between cells, its headers' switches and levels widgets), with
-- the pointer coming back in fractions of a cell (`scene.input`) to the
-- same gestures the terminal's mouse reaches. Loaded by tests/suite.lua
-- with its helpers.
local T = ...
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh
local api = paw.api
local view = paw.ui.views:get("arrange")

local W, H, CELL = 160, 40, { w = 8, h = 17 }
local ROLES = {
  "clip",
  "beats",
  "curve",
  "hmeter",
  "switch",
  "playhead",
  "trackhead",
  "recording",
  "label",
  "button",
  "knob",
}

-- What the window's watcher keeps of a drag under way.
local held = {}

--- Draw the arrange view's scene for a window that paints its roles, as
--- the kernel sends it.
local function redraw()
  paw.ui.render_scene("arrange", W, H, CELL)
  local patch = api.scene_end(0, "arr")
  return patch and api.json_decode(patch)
end

--- Two tracks, a MIDI clip on the first from beat 4 to 8, an audio clip
--- on the second from 8 to 12, at three columns a beat; and where a beat
--- is on a track's row in the window's units (`dy` lines under its top).
local function song()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  local saved = { zoom = paw.opt.zoom, grid = paw.opt.grid, height = paw.opt.track_height }
  T.after(function()
    paw.opt.zoom, paw.opt.grid, paw.opt.track_height = saved.zoom, saved.grid, saved.height
    paw.mouse.forget()
    api.scene_forget(0)
  end)
  paw.opt.zoom, paw.opt.grid, paw.opt.track_height = 3, 1, 4
  local a, b = paw.add_track({ name = "keys" }), paw.add_track({ name = "loop" })
  local riff = a:add_clip({ name = "riff", start = 4, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
  local samples = {}
  for i = 1, 48000 * 4 do
    samples[i] = 0.25 * math.sin(i / 20)
  end
  local wav =
    b:add_clip({ name = "wav", file = T.write_wav(T.scratch .. "/arrange-scene.wav", samples), start = 8, length = 4 })
  paw.flush()
  view.scroll, view.top = 0, 1
  api.undo_checkpoint()
  api.scene_forget(0)
  api.scene_roles(0, ROLES)
  redraw()
  local function at(track, beat, dy)
    local g = view.geometry
    for _, row in ipairs(g.layout.rows) do
      if row.kind == "track" and row.id == track.id then
        return g.hw + (beat - view.scroll) * g.zoom, row.y + (dy or 1.5)
      end
    end
  end
  return a, b, riff, wav, at
end

--- A pointer event from the window, in units of the arrange view's window;
--- then the view drawn again, as the kernel does after a turn.
local function input(kind, x, y, extra)
  local e = { kind = kind, x = x, y = y, button = "left" }
  for k, v in pairs(extra or {}) do
    e[k] = v
  end
  local taken = paw.roles.input(0, "arr", view, nil, e, held)
  api.undo_checkpoint()
  redraw()
  return taken
end

local function drag(x0, y0, x1, y1, extra)
  input("down", x0, y0, extra)
  for i = 1, 4 do
    input("move", x0 + (x1 - x0) * i / 4, y0 + (y1 - y0) * i / 4, extra)
  end
  input("up", x1, y1, extra)
end

--- The nodes of the scene a window that paints the arrange view's roles
--- is sent, by role.
local function nodes_of(role)
  api.scene_forget(0)
  local patch = redraw()
  local out = {}
  for _, n in ipairs(patch.set) do
    if n.role == role then out[#out + 1] = n end
  end
  return out
end

test(
  "the arrange view's scene: its timeline a plane, each clip on it a role between cells, its headers' controls widgets",
  function()
    local a, _, riff, wav = song()
    api.scene_forget(0)
    local patch = redraw()
    local plane
    for _, n in ipairs(patch.set) do
      if n.t == "plane" then plane = n end
    end
    eq(
      plane ~= nil and plane.x.domain .. " " .. plane.y.domain,
      "beat line",
      "the timeline, a plane of beats along and the view's lines down"
    )
    eq(plane.x.per .. " " .. plane.x.from, "3 0", "three units a beat from the left edge")
    local clips = {}
    for _, n in ipairs(nodes_of("clip")) do
      clips[n.props.id] = n
    end
    local row = view.geometry.layout.rows[1]
    eq(
      api.json_encode(clips[riff.id].r),
      api.json_encode({ 4, row.y, 4, row.h }),
      "a clip where it is in the plane's domain"
    )
    eq(clips[riff.id].props.midi and clips[riff.id].props.content ~= nil, true, "with the key of what it shows")
    eq(clips[wav.id].props.midi, false, "an audio clip")
    eq(clips[wav.id].props.fade_in .. " " .. clips[wav.id].props.gain, "0 0", "with its fades and gain")
    local letters = {}
    for _, n in ipairs(nodes_of("switch")) do
      letters[#letters + 1] = n.props.letter
    end
    eq(table.concat(letters):sub(1, 4), "MSRI", "a header's switches")
    local bound = {}
    for _, n in ipairs(nodes_of("hmeter")) do
      bound[#bound + 1] = n.bind
    end
    eq(
      table.concat(bound, " "):find("meter:" .. a.id, 1, true) ~= nil,
      true,
      "a header's level, bound to the track's meter: " .. table.concat(bound, " ")
    )
    eq(nodes_of("playhead")[1].bind, "position", "the playhead, bound to the position")
    eq(#nodes_of("beats") >= 2, true, "each row's ground with its lines")
  end
)

test("in a scope a clip across its edges is in the scene with the cuts, for a window to draw ‹ and ›", function()
  local a, b, riff = song()
  T.after(function() paw.scope.widen(true) end)
  paw.scope.enter({ kind = "range", tracks = { a.id, b.id }, from = 5, to = 7 })
  local props
  for _, n in ipairs(nodes_of("clip")) do
    if n.props.id == riff.id then props = n.props end
  end
  eq(
    props.cut_in .. " " .. props.cut_out .. " " .. props.length,
    "1 3 4",
    "cut at beats 1 and 3 of the clip, all of it there"
  )
end)

test(
  "a time fold is in the scene: its column on the ruler, a clip across it in two cut pieces, the playhead's jumps",
  function()
    local _, _, riff = song()
    T.after(function() paw.folds.clear() end)
    paw.folds.make({ kind = "range", from = 5, to = 7 })
    local pieces = {}
    for _, n in ipairs(nodes_of("clip")) do
      if n.props.id == riff.id then pieces[#pieces + 1] = n end
    end
    table.sort(pieces, function(x, y) return x.r[1] < y.r[1] end)
    -- "Fold 1 ▸ 1" and a cell on each side: 12 cells, 4 beats of the view at 3 a beat.
    eq(#pieces, 2, "two pieces")
    eq(
      pieces[1].r[1] .. " " .. tostring(pieces[1].props.cut_in) .. " " .. pieces[1].props.cut_out,
      "4 nil 1",
      "the first cut at the fold"
    )
    eq(
      pieces[2].r[1] .. " " .. pieces[2].props.cut_in .. " " .. tostring(pieces[2].props.cut_out),
      "6 3 nil",
      "the second after its column"
    )
    local playhead = nodes_of("playhead")[1]
    eq(api.json_encode(playhead.props.jumps), "[[5,7,4]]", "the playhead jumps the fold")
    api.scene_forget(0)
    local text = api.json_encode(redraw())
    eq(text:find("Fold 1", 1, true) ~= nil, true, "the column's name is in the scene's cells")
  end
)

test(
  "in a window a clip dragged by fractions of a cell moves on the grid by the beats it went, and to another track",
  function()
    local _, b, riff, _, at = song()
    local x, y = at(riff:track(), 5.2)
    drag(x, y, x + 0.4, y)
    eq(riff:get().start, 4, "a click that wavers moves nothing")
    eq(paw.frontend.chosen_clips()[1], riff.id, "and chooses it")
    -- Not the second press of a double click.
    paw.mouse.forget()
    drag(x, y, x + 2.4 * 3, y)
    eq(riff:get().start, 6, "two beats and a bit on, on the grid")
    x, y = at(riff:track(), 7.2)
    local _, y1 = at(b, 7.2)
    paw.mouse.forget()
    drag(x, y, x, y1)
    eq(paw.clip(riff.id):get().track, b.id, "a row down, onto the next track")
  end
)

test("in a window either end of a clip is trimmed from within a cell of it", function()
  local _, _, riff, _, at = song()
  local x, y = at(riff:track(), 4)
  drag(x + 0.3, y, x + 0.3 + 3, y)
  eq(riff:get().start .. "+" .. riff:get().length, "5+3", "its start, a beat on")
  x = at(riff:track(), 8)
  drag(x - 0.3, y, x - 0.3 + 6, y)
  eq(riff:get().start .. "+" .. riff:get().length, "5+5", "its end, two beats on")
end)

test(
  "in a window an audio clip's fade handle and gain line take the pointer, which a terminal cell is too big for",
  function()
    local _, b, _, wav, at = song()
    local x, y = at(b, 8, 0.2)
    drag(x + 0.2, y, x + 0.2 + 3, y)
    near(wav:get().fade_in, 1, 0.05, "the fade in, a beat long")
    eq(wav:get().start, 8, "and the clip where it was")
    x = at(b, 12)
    drag(x - 0.2, y, x - 0.2 - 1.5, y)
    near(wav:get().fade_out, 0.5, 0.05, "the fade out, half a beat")
    x = at(b, 10)
    y = select(2, at(b, 10, 0.15))
    drag(x, y, x, y - 1)
    near(wav:get().gain, 4, 0.01, "the gain up four dB, a line")
  end
)

test("in a window the header's switches and its volume take the pointer", function()
  local a, _, _, _, at = song()
  local _, y = at(a, 0, 0.5)
  input("down", view.flags.mute + 0.4, y)
  input("up", view.flags.mute + 0.4, y)
  eq(a:get().mute, true, "M mutes it")
  local x = view.geometry.hw - 6
  drag(x, y + 1, x + 3.5, y + 1)
  near(a:get().volume, 3.5, 0.01, "the volume, a dB a column")
end)

test(
  "in a window the ruler puts the playhead on the step under the pointer, a drag loops, and Ctrl and the wheel zoom about the pointer",
  function()
    local a, _, _, _, at = song()
    local x = at(a, 6.5)
    input("down", x, 0.5)
    input("up", x, 0.5)
    eq(api.transport_get().position, 6, "the playhead on the step under the pointer")
    -- On a grid of quarter beats: where the pointer was, not the cells it
    -- was in (which would be 2 to 5.75).
    paw.opt.grid = 0.25
    paw.mouse.forget()
    drag(at(a, 2.2), 0.5, at(a, 5.6), 0.5)
    local t = api.transport_get()
    eq(
      t.loop_start .. " " .. t.loop_end,
      "2.25 5.5",
      "the loop from where the drag began to where it ended, on the grid"
    )
    x = at(a, 8)
    input("wheel", x, 10, { dy = 1, ctrl = true })
    eq(paw.opt.zoom > 3, true, "zoomed in")
    near(view.scroll + (x - view.geometry.hw) / paw.opt.zoom, 8, 0.01, "the beat under the pointer where it was")
  end
)

test("the arrange view does not move on its own while the song is stopped", function()
  song()
  eq(view:moving(), false, "stopped, it does not move")
end)

test(
  "a header in a window: its ground and stripe, its name in words, a knob for the pan, the input and the monitor as buttons",
  function()
    local a = song()
    local heads, names, knobs, mics, speakers = 0, {}, 0, 0, 0
    for _, n in ipairs(nodes_of("trackhead")) do
      if n.props.color == paw.draw.track_colour(a:get(), 1) then heads = heads + 1 end
    end
    for _, n in ipairs(nodes_of("label")) do
      names[#names + 1] = n.props.text
    end
    for _, n in ipairs(nodes_of("knob")) do
      if n.props.round then knobs = knobs + 1 end
    end
    for _, n in ipairs(nodes_of("button")) do
      if n.props.icon == "mic" then mics = mics + 1 end
    end
    for _, n in ipairs(nodes_of("switch")) do
      if n.props.icon == "speaker" then speakers = speakers + 1 end
    end
    eq(heads, 1, "the header's ground, in the track's colour")
    eq(
      table.concat(names, " "):find("keys", 1, true) ~= nil,
      true,
      "the name, as a label: " .. table.concat(names, " ")
    )
    eq(knobs >= 2 and mics == 2 and speakers == 2, true, "a pan knob, an input button and a monitor switch a track")
  end
)

test("the master is a header like the others, its level on both sides; the timeline beside it is empty", function()
  song()
  local master
  for _, n in ipairs(nodes_of("hmeter")) do
    if n.bind == "meter:0" then master = n end
  end
  eq(master ~= nil and master.props.stereo, true, "the master's level, both sides, bound to its meter")
  eq(master.r[1] < view.geometry.hw, true, "in the header's column")
end)

test("a header's bottom edge dragged in a window makes its track taller, the others keeping theirs", function()
  local a, b = song()
  local row
  for _, r in ipairs(view.geometry.layout.rows) do
    if r.id == a.id then row = r end
  end
  local x = 6
  local y = row.y + row.h - 0.1
  drag(x, y, x, y + 2)
  near(a:get().height, (row.h + 2) / view.geometry.th, 0.01, "two lines taller")
  local rows = {}
  for _, r in ipairs(view.geometry.layout.rows) do
    rows[r.id] = r.h
  end
  eq(rows[a.id] .. " " .. rows[b.id], (row.h + 2) .. " " .. row.h, "drawn so, the other as it was")
  paw.mouse.forget()
  input("down", x, rows[a.id] + row.y - 0.1)
  input("up", x, rows[a.id] + row.y - 0.1)
  input("down", x, rows[a.id] + row.y - 0.1)
  input("up", x, rows[a.id] + row.y - 0.1)
  eq(a:get().height or 1, 1, "a double click gives it the others' height")
end)

test("over a clip's edge the pointer says it trims, with a shape for a window to show", function()
  local _, _, riff, _, at = song()
  local x, y = at(riff:track(), 4)
  input("hover", x + 0.2, y)
  local text, shape = paw.mouse.hint_text()
  eq(shape, "resize_h", "a shape for an edge dragged sideways: " .. tostring(text))
  eq(paw.frontend.state(-1).modal.pointer, "resize_h", "told to the window")
end)

test("a take lane in a window: each take a clip of its own, with the take's key for what it shows", function()
  local a, _, riff = song()
  paw.takes.new(riff.id)
  paw.cursor.set_track(a.id)
  paw.commands.exec("take.lanes")
  local takes = {}
  for _, n in ipairs(nodes_of("clip")) do
    if n.props.take then
      takes[#takes + 1] = n.props.take .. (n.props.active and "*" or "") .. ":" .. tostring(n.props.content ~= nil)
    end
  end
  table.sort(takes)
  eq(table.concat(takes, " "), "1:true 2*:true", "both takes, the second playing, each with its key")
  paw.commands.exec("take.lanes")
end)

test("in a window the new track button under the tracks offers the kinds of track", function()
  song()
  local L = view.geometry.layout
  input("down", 8.5, L.used + 0.5)
  input("up", 8.5, L.used + 0.5)
  local items = require("paw.menu").shown()
  eq(items ~= nil and items[1].label, "Empty track", "the menu of new tracks")
  paw.frontend.act.menu_dismiss()
end)

test("a jump to a marker off screen puts it at the left margin, or in the middle with jumpview center", function()
  song()
  local saved = { view = paw.opt.jumpview, margin = paw.opt.jumpmargin }
  T.after(function()
    paw.opt.jumpview, paw.opt.jumpmargin = saved.view, saved.margin
  end)
  paw.markers.add(200, "far")
  paw.markers.add(210, "farther")
  paw.opt.jumpview, paw.opt.jumpmargin = "left", 6
  paw.keymap.feed("]'")
  redraw()
  near(view.scroll, 200 - 6 / 3, 0.01, "the marker 6 columns from the left edge")
  paw.keymap.feed("]'")
  redraw()
  near(view.scroll, 200 - 2, 0.01, "a marker on screen does not scroll")
  paw.keymap.feed("0")
  redraw()
  eq(view.scroll, 0, "back at the start")
  paw.opt.jumpview = "center"
  paw.keymap.feed("]'")
  redraw()
  near(view.scroll + view.geometry.span / 2, 200, 0.01, "in the middle")
  paw.keymap.feed("zs")
  redraw()
  near(view.scroll, 200 - 2, 0.01, "zs puts the cursor at the left margin")
  paw.keymap.feed("zz")
  redraw()
  near(view.scroll + view.geometry.span / 2, 200, 0.01, "zz puts it in the middle")
end)

test("a jump just past the right edge aligns the target at the left margin; a step scrolls just enough", function()
  song()
  local saved = { view = paw.opt.jumpview, margin = paw.opt.jumpmargin }
  T.after(function()
    paw.opt.jumpview, paw.opt.jumpmargin = saved.view, saved.margin
  end)
  paw.opt.jumpview, paw.opt.jumpmargin = "left", 6
  local span = view.geometry.span
  local edge = math.ceil(span - 1 / 3) + 2
  paw.markers.add(edge, "just past")
  paw.keymap.feed("]'")
  redraw()
  near(view.scroll, edge - 2, 0.01, "2 beats past the edge: at the left margin")
  paw.keymap.feed("<Esc>0")
  redraw()
  eq(view.scroll, 0, "back at the start")
  paw.cursor.set_beat(math.floor(span - 1 / 3))
  redraw()
  paw.keymap.feed("l")
  redraw()
  eq(paw.cursor.beat - view.scroll > span * 0.75, true, "a step past the edge scrolls just enough")
  paw.keymap.feed("ze")
  redraw()
  near(view.scroll + span - 1 / 3, paw.cursor.beat, 0.01, "ze puts the cursor at the right edge")
end)
