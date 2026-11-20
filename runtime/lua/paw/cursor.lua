-- The edit cursor: a track and a position in beats. Commands act on it and
-- views draw it. It survives a reload.
local api = paw.api
local M = { beat = 0 }

local track_id
local lane_id    -- the automation lane row the cursor is on, if any
do
  local saved = api.state_get("cursor")
  if saved then track_id, M.beat, lane_id = saved.track, saved.beat or 0, saved.lane end
end

-- Each seat has a cursor of its own, starting where the instance's is.
paw.seats.keep("cursor",
  function() return track_id, M.beat, lane_id end,
  function(track, beat, lane) track_id, M.beat, lane_id = track, beat, lane end,
  function(track, beat, lane) return track, beat or 0, lane end)

local function save()
  -- The instance's own is the one that outlives a reload.
  if paw.seats.current == 0 then api.state_set("cursor", { track = track_id, beat = M.beat, lane = lane_id }) end
  paw.emit("cursor.changed", { track = track_id, beat = M.beat, lane = lane_id })
  api.ui_redraw()
end

--- A function that gives the track that keys and commands act on in
--- place of the cursor's, or nil: a device panel pinned to a track
--- (paw/views/devices.lua) sets it, for while its window has the keyboard.
M.lens = nil

--- The id of the track of the cursor, or of the first track when that track
--- does not exist now. Nil when the project has no tracks. 0 when the
--- cursor is on the master track (`on_master`).
function M.track_id()
  local lens = M.lens and M.lens()
  if lens then return lens end
  if track_id == 0 then return 0 end
  if track_id and pcall(api.track_get, track_id) then return track_id end
  track_id = api.track_list()[1]
  return track_id
end

--- True if the cursor is on the master track: the row after the last
--- track in the arrange view, the strip after the last in the mixer.
function M.on_master()
  return track_id == 0
end

--- True if a move of the cursor can go on from the last track to the
--- master: a move of its own in normal mode, in the views that draw the
--- master after the tracks. After an operator or in a selection, only
--- tracks count.
local function master_reachable()
  local keymap = paw.keymap
  return keymap.mode == "n" and not keymap.motion_for
    and (paw.ui.focused == "arrange" or paw.ui.focused == "mixer")
end
M.master_reachable = master_reachable

--- The track the cursor is on, as a `paw.Track`, or nil.
--- @type function(): contracts.TrackHandle
function M.track()
  local id = M.track_id()
  return id and paw.track(id) or nil
end

--- 1-based position of the cursor track in the track list.
function M.index()
  local id = M.track_id()
  for i, other in ipairs(api.track_list()) do
    if other == id then return i end
  end
end

--- 1-based row of the cursor track among the tracks that are drawn: the
--- same as `index` until a group is folded. On the master, the row after
--- the last track.
function M.row()
  local id = M.track_id()
  if id == 0 then return #paw.groups.rows() + 1 end
  for i, other in ipairs(paw.groups.rows()) do
    if other == id then return i end
  end
end

--- The automation lane row of the cursor: a lane of the cursor track that
--- shows as a row (see `paw.lanes`). Nil when the cursor is on the track.
function M.lane_id()
  if not lane_id then return nil end
  local id = M.track_id()
  for _, lane in ipairs(id and paw.lanes.shown(id) or {}) do
    if lane.id == lane_id then return lane_id end
  end
end

--- 1-based row of the cursor among every row drawn, lanes included.
function M.line()
  local id, lane = M.track_id(), M.lane_id()
  for i, line in ipairs(paw.groups.rows({ lanes = true })) do
    if line.track == id and line.lane == lane then return i end
  end
end

--- Put the cursor on a track, or with `lane` on one of its lane rows.
function M.set_track(track, lane)
  track_id = type(track) == "table" and track.id or track
  lane_id = lane
  save()
end

--- Move by rows. In normal mode, the rows of open automation lanes count.
--- After an operator or in a selection, only tracks count, as for `dj`.
--- From the last track, a move down goes on to the master, and from the
--- master a move up returns to the tracks.
function M.move_track(delta)
  local reach = master_reachable()
  if paw.lanes.any_open() and paw.keymap.mode == "n" then
    local lines = paw.groups.rows({ lanes = true })
    if #lines == 0 then return end
    local at = M.on_master() and #lines + 1 or (M.line() or 1)
    if reach and at + delta > #lines then return M.set_track(0) end
    local to = lines[paw.util.clamp(at + delta, 1, #lines)]
    return M.set_track(to.track, to.lane)
  end
  local list = paw.groups.rows()
  if #list == 0 then return end
  local at = M.row() or 1
  if reach and at + delta > #list then return M.set_track(0) end
  M.set_track(list[paw.util.clamp(at + delta, 1, #list)])
end

--- Put the cursor at a beat (not before 0).
function M.set_beat(beat)
  M.beat = math.max(0, beat)
  save()
end

-- Another project starts at its start, on its first track.
paw.on("project.loaded", function()
  track_id, lane_id, M.beat = nil, nil, 0
  save()
end)

--- Round a position to the arrange grid.
function M.snap(beat)
  return paw.util.round(beat, paw.opt.grid)
end

--- The clip under the cursor, if any.
function M.clip()
  local track = M.track()
  return track and track:clip_at(M.beat) or nil
end

return M
