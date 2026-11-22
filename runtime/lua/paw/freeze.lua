-- Freezing: a track or a group rendered in place to a sound file, which the
-- engine then plays instead of the track's clips and devices, so that they
-- cost nothing while it is frozen.
--
--   paw.freeze.freeze(strings)     -- render it, and play the file
--   paw.freeze.unfreeze(strings)   -- play the clips and devices again
--   paw.freeze.state(violins)      -- "frozen", "held" (inside a frozen group) or nil
--
-- The file is what comes out of the track before its fader: its clips, its
-- devices, and every track that sounds through it (a group's members). The
-- fader, pan, mute and sends stay live, so the mix can still be changed. A
-- frozen track's meta holds `frozen = { file }`, so a freeze is saved with
-- the project and undone like any edit; the clips, notes and devices are
-- not touched. The engine holds the devices of a frozen track and of the
-- tracks inside it (bypassed there, not in the project) and plays nothing
-- of those tracks: crates/paw-core/src/freeze.rs.
--
-- Editing what a frozen track plays asks whether to unfreeze it: the edit
-- is not heard until it is.
local api = paw.api
local M = {}

local function id_of(track) return type(track) == "table" and track.id or track end

local function meta(id)
  local ok, m = pcall(api.track_get, id, "meta")
  return ok and m or {}
end

--- What a frozen track was frozen to, `{ file }`, or nil.
function M.frozen(track)
  local f = meta(id_of(track)).frozen
  if type(f) == "table" and f.file then return f end
end

--- The frozen track a track sounds through, if any: the one whose file
--- holds its sound.
function M.holder(track)
  local ok, out = pcall(api.track_get, id_of(track), "output")
  local at, steps = ok and out, 0
  while at and at ~= 0 and steps < 64 do
    if M.frozen(at) then return at end
    local ok, out = pcall(api.track_get, at, "output")
    at, steps = ok and out or nil, steps + 1
  end
end

--- "frozen", "held" (its sound is in a frozen track it feeds), or nil.
function M.state(track)
  track = id_of(track)
  if M.holder(track) then return "held" end
  if M.frozen(track) then return "frozen" end
end

--- The file a freeze of `track` is rendered to: in the project's media
--- folder, so that saving keeps it with the project.
local function file_for(track)
  local dir = api.media_dir()
  pcall(paw.api.fs_mkdir, dir)
  local name = api.track_get(track, "name"):gsub("[^%w%-_]", "_")
  return string.format("%s/%s-frozen-%d-%d.wav", dir, name, os.time(), track)
end

--- The render options of a freeze: the whole song from its start, the
--- track alone before its fader, as 32-bit float. So the file plays
--- what the track did.
function M.render_opts(track, opts)
  opts = opts or {}
  return { freeze = track, start = 0, tail = opts.tail or 2, bits = 32, master = false, background = opts.background }
end

--- Freeze a track or a group: render it, and play the file from now on.
--- `opts.tail` is the seconds rendered after the song's end (2). One undo
--- step. Returns the file.
function M.freeze(track, opts)
  track = id_of(track)
  if track == 0 then error("the master track cannot be frozen", 0) end
  local name = api.track_get(track, "name")
  if M.frozen(track) then error(name .. " is frozen already", 0) end
  local holder = M.holder(track)
  if holder then
    error(
      string.format("%s sounds through %s, which is frozen: unfreeze that first", name, api.track_get(holder, "name")),
      0
    )
  end
  local path = file_for(track)
  paw.render(path, M.render_opts(track, opts))
  local m = meta(track)
  m.frozen = { file = path }
  api.track_set(track, "meta", m)
  paw.emit("track.frozen", { id = track, file = path })
  return path
end

--- Play a frozen track's clips and devices again. The file stays where it
--- is, as undo can bring the freeze back.
function M.unfreeze(track)
  track = id_of(track)
  if not M.frozen(track) then error(api.track_get(track, "name") .. " is not frozen", 0) end
  local m = meta(track)
  m.frozen = nil
  api.track_set(track, "meta", m)
  paw.emit("track.thawed", { id = track })
end

-- Editing what a frozen track plays -----------------------------------------------

-- Frozen tracks already asked about since they were frozen: one question
-- each, not one per note.
local asked = {}

local function ask(track)
  local frozen = M.frozen(track) and track or M.holder(track)
  if not frozen or asked[frozen] then return end
  asked[frozen] = true
  local name = api.track_get(frozen, "name")
  paw.ui.input({ prompt = name .. " is frozen: unfreeze it to hear this edit? (y/n) " }, function(answer)
    if tostring(answer):lower():match("^y") then
      M.unfreeze(frozen)
      api.undo_checkpoint()
      paw.notify(name .. " is unfrozen")
    else
      paw.notify(name .. " stays frozen: the edit is heard once it is unfrozen (`:unfreeze`)")
    end
  end)
end

local function edited(event)
  if event.restored or not event.track then return end
  if M.state(event.track) then ask(event.track) end
end
for _, name in ipairs({
  "clip.added",
  "clip.changed",
  "clip.removed",
  "device.added",
  "device.changed",
  "device.removed",
}) do
  paw.on(name, edited)
end
paw.on("track.changed", function(event)
  if event.id and not M.frozen(event.id) then asked[event.id] = nil end
end)

-- Commands -------------------------------------------------------------------------

--- The tracks a freeze command is about: a range of tracks, those named,
--- or the cursor's track.
local function chosen(ctx)
  if ctx.range and ctx.range.tracks then return ctx.range.tracks end
  local name = ctx.args[1]
  if name and name ~= true then
    local wanted = tostring(name):lower()
    for _, id in ipairs(paw.scope.tracks()) do
      if api.track_get(id, "name"):lower() == wanted then return { id } end
    end
    for _, id in ipairs(paw.scope.tracks()) do
      if api.track_get(id, "name"):lower():find(wanted, 1, true) then return { id } end
    end
    error("no track `" .. tostring(name) .. "`", 0)
  end
  local id = paw.cursor.track_id()
  if not id then error("no track selected", 0) end
  return { id }
end

local function track_names()
  local out = {}
  for _, id in ipairs(paw.scope.tracks()) do
    out[#out + 1] = api.track_get(id, "name")
  end
  return out
end

paw.command("freeze", function(ctx)
  local done = {}
  for _, id in ipairs(chosen(ctx)) do
    M.freeze(id, { tail = tonumber(ctx.args.tail) })
    done[#done + 1] = api.track_get(id, "name")
  end
  paw.notify(string.format("frozen: %s · its devices rest; `:unfreeze` plays them again", table.concat(done, ", ")))
end, {
  desc = "Render the track or group in place and play that, its devices at rest: `freeze`, `freeze Strings`, `:t2,t4freeze`, `freeze tail=4`",
  range = true,
  complete = track_names,
})

paw.command(
  "unfreeze",
  function(ctx)
    local done = {}
    for _, id in ipairs(chosen(ctx)) do
      -- A track inside a frozen group thaws that group.
      local which = M.frozen(id) and id or M.holder(id) or id
      M.unfreeze(which)
      done[#done + 1] = api.track_get(which, "name")
    end
    paw.notify("unfrozen: " .. table.concat(done, ", "))
  end,
  {
    desc = "Play a frozen track's clips and devices again: `unfreeze`, `unfreeze Strings`",
    range = true,
    complete = track_names,
  }
)

return M
