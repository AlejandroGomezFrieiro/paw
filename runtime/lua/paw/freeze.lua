-- Freezing: a part or a group rendered in place to a sound file, which the
-- engine then plays instead of the part's clips and devices, so that they
-- cost nothing while it is frozen.
--
--   paw.freeze.freeze(strings)     -- render it, and play the file
--   paw.freeze.unfreeze(strings)   -- play the clips and devices again
--   paw.freeze.state(violins)      -- "frozen", "held" (inside a frozen group) or nil
--
-- The file is what comes out of the part before its fader: its clips, its
-- devices, and every part that sounds through it (a group's members). The
-- fader, pan, mute and sends stay live, so the mix can still be changed. A
-- frozen part's meta holds `frozen = { file, key }`, so a freeze is saved
-- with the project and undone like any edit; the clips, notes and devices
-- are not touched. The `key` says what the file was made from
-- (paw/bake_state.tl): `K` compares it with the part as it is now, and
-- says whether the file is up to date or stale, and why. The engine holds
-- the devices of a frozen part and of the parts inside it (bypassed
-- there, not in the project) and plays nothing of those parts:
-- crates/paw-core/src/freeze.rs.
--
-- Editing what a frozen part plays asks whether to unfreeze it: the edit
-- is not heard until it is.
--
-- `:freeze` and `:unfreeze` on a block of a subproject freeze the block
-- instead (paw/freeze_block.tl).
local api = paw.api
local bake_state = require("paw.bake_state")
local derived = require("paw.derived")
local freeze_block = require("paw.freeze_block")
local M = {}

local function id_of(part) return type(part) == "table" and part.id or part end

local function meta(id)
  local ok, m = pcall(api.part_get, id, "meta")
  return ok and m or {}
end

--- What a frozen part was frozen to, `{ file, key }`, or nil. The `key`
--- says what the file was made from.
function M.frozen(part)
  local f = meta(id_of(part)).frozen
  if type(f) == "table" and f.file then return f end
end

--- The frozen part a part sounds through, if any: the one whose file
--- holds its sound.
function M.holder(part)
  local ok, out = pcall(api.part_get, id_of(part), "output")
  local at, steps = ok and out, 0
  while at and at ~= 0 and steps < 64 do
    if M.frozen(at) then return at end
    local ok, out = pcall(api.part_get, at, "output")
    at, steps = ok and out or nil, steps + 1
  end
end

--- "frozen", "held" (its sound is in a frozen part it feeds), or nil.
function M.state(part)
  part = id_of(part)
  if M.holder(part) then return "held" end
  if M.frozen(part) then return "frozen" end
end

--- The parts a freeze of `part` plays: the part, and each part whose
--- outputs lead into it. With `ctx` (a node of paw.derived), the routing
--- that it reads is recorded.
local function members(part, ctx)
  if ctx then ctx:source("parts") end
  local ids = api.part_list({ all = true })
  local output = {}
  for _, id in ipairs(ids) do
    if ctx then ctx:source("part:" .. id .. ":output") end
    output[id] = api.part_get(id, "output")
  end
  local list = { part }
  for _, id in ipairs(ids) do
    -- Routing has no loops (the kernel refuses them); the bound is a guard.
    local at, steps = output[id], 0
    while at and at ~= 0 and at ~= part and steps < 64 do
      at, steps = output[at], steps + 1
    end
    if at == part and id ~= part then list[#list + 1] = id end
  end
  return list
end

local function same_list(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

-- The parts that each frozen part plays. A change of the routing makes
-- it again; when the list stays the same, the key stays fresh.
local members_node = derived.node({
  name = "freeze.members",
  kind = "memo",
  make = function(ctx, part) return members(part, ctx) end,
  same = same_list,
  limit = 64,
})

-- The key of what a freeze of each frozen part plays now. An edit of a
-- part that the freeze does not play leaves it fresh: then the check is a
-- compare of the key.
local key_node = derived.node({
  name = "freeze.key",
  kind = "memo",
  make = function(ctx, part) return bake_state.make({ parts = ctx:get(members_node, part), own = part }, ctx) end,
  limit = 64,
})

--- What `K` says of a frozen part, or of a part held in one: "frozen, up
--- to date", "frozen, stale: Drums changed since: devices", "held in
--- Drums, which is frozen, up to date". Nil for a part that plays live.
function M.describe(part)
  part = id_of(part)
  local holder = M.holder(part)
  local frozen = holder or (M.frozen(part) and part)
  if not frozen then return end
  local name = api.part_get(frozen, "name")
  local saved = M.frozen(frozen).key
  -- A freeze made before paw kept its key: nothing to compare.
  local state = saved and bake_state.describe(name, saved, key_node:get(frozen, true))
  local text = holder and string.format("held in %s, which is frozen", name) or "frozen"
  return state and text .. ", " .. state or text
end

--- The file a freeze of `part` is rendered to: in the project's media
--- folder, so that saving keeps it with the project.
local function file_for(part)
  local dir = api.media_dir()
  pcall(paw.api.fs_mkdir, dir)
  local name = api.part_get(part, "name"):gsub("[^%w%-_]", "_")
  return string.format("%s/%s-frozen-%d-%d.wav", dir, name, os.time(), part)
end

--- The render options of a freeze: the whole song from its start, the
--- part alone before its fader, as 32-bit float. So the file plays
--- what the part did.
function M.render_opts(part, opts)
  opts = opts or {}
  return { freeze = part, start = 0, tail = opts.tail or 2, bits = 32, master = false, background = opts.background }
end

--- Freeze a part or a group: render it, and play the file from now on.
--- `opts.tail` is the seconds rendered after the song's end (2). One undo
--- step. Returns the file.
function M.freeze(part, opts)
  part = id_of(part)
  if part == 0 then error("the master part cannot be frozen", 0) end
  local name = api.part_get(part, "name")
  if M.frozen(part) then error(name .. " is frozen already", 0) end
  local holder = M.holder(part)
  if holder then
    error(
      string.format("%s sounds through %s, which is frozen: unfreeze that first", name, api.part_get(holder, "name")),
      0
    )
  end
  local path = file_for(part)
  paw.render(path, M.render_opts(part, opts))
  local m = meta(part)
  m.frozen = { file = path, key = bake_state.make({ parts = members(part), own = part }) }
  api.part_set(part, "meta", m)
  paw.emit("part.frozen", { id = part, file = path })
  return path
end

--- Play a frozen part's clips and devices again. The file stays where it
--- is, as undo can bring the freeze back.
function M.unfreeze(part)
  part = id_of(part)
  if not M.frozen(part) then error(api.part_get(part, "name") .. " is not frozen", 0) end
  local m = meta(part)
  m.frozen = nil
  api.part_set(part, "meta", m)
  paw.emit("part.thawed", { id = part })
end

-- Editing what a frozen part plays -----------------------------------------------

-- Frozen parts already asked about since they were frozen: one question
-- each, not one per note.
local asked = {}

local function ask(part)
  local frozen = M.frozen(part) and part or M.holder(part)
  if not frozen or asked[frozen] then return end
  asked[frozen] = true
  local name = api.part_get(frozen, "name")
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

-- A clip or device removed with its part: the part is gone, and the
-- reads of `M.state` would fail, which costs much more than a list.
local function gone(part)
  local ids = api.part_list({ all = true })
  for i = 1, #ids do
    if ids[i] == part then return false end
  end
  return true
end

local function edited(event, name)
  if event.restored or not event.part then return end
  if name:match("%.removed$") and gone(event.part) then return end
  if M.state(event.part) then ask(event.part) end
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
paw.on("part.changed", function(event)
  if event.id and not M.frozen(event.id) then asked[event.id] = nil end
end)

-- Commands -------------------------------------------------------------------------

--- The parts a freeze command is about: a range of parts, those named,
--- or the cursor's part.
local function chosen(ctx)
  if ctx.range and ctx.range.parts then return ctx.range.parts end
  local name = ctx.args[1]
  if name and name ~= true then
    local wanted = tostring(name):lower()
    for _, id in ipairs(paw.scope.parts()) do
      if api.part_get(id, "name"):lower() == wanted then return { id } end
    end
    for _, id in ipairs(paw.scope.parts()) do
      if api.part_get(id, "name"):lower():find(wanted, 1, true) then return { id } end
    end
    error("no part `" .. tostring(name) .. "`", 0)
  end
  local id = paw.cursor.part_id()
  if not id then error("no part selected", 0) end
  return { id }
end

local function part_names()
  local out = {}
  for _, id in ipairs(paw.scope.parts()) do
    out[#out + 1] = api.part_get(id, "name")
  end
  return out
end

--- The block of a subproject under the cursor, when a freeze command names
--- no part: the clip's id, or nil.
local function chosen_block(ctx)
  local name = ctx.args[1]
  if ctx.range or (name and name ~= true) then return end
  local clip = paw.cursor.clip()
  local c = clip and clip:get()
  return c and c.kind == "nest" and c.id or nil
end

--- The blocks that the window went into subprojects through, outer first:
--- where a block inside a subproject is rendered.
local function way_in()
  local out = {}
  local s = paw.scope.current()
  while s do
    if s.kind == "nest" and s.clip then table.insert(out, 1, s.clip) end
    s = s.parent
  end
  return out
end

paw.command("freeze", function(ctx)
  local block = chosen_block(ctx)
  if block then
    local name = api.nest_get(api.clip_get(block).nest, "name")
    local current = freeze_block.describe(block) == "frozen, up to date"
    if not current then freeze_block.freeze(block, { tail = tonumber(ctx.args.tail), through = way_in() }) end
    return paw.notify(
      current and string.format("%s is frozen and up to date", name)
        or string.format("frozen: the block of %s · its devices rest; `:unfreeze` plays them again", name)
    )
  end
  local done = {}
  for _, id in ipairs(chosen(ctx)) do
    M.freeze(id, { tail = tonumber(ctx.args.tail) })
    done[#done + 1] = api.part_get(id, "name")
  end
  paw.notify(string.format("frozen: %s · its devices rest; `:unfreeze` plays them again", table.concat(done, ", ")))
end, {
  desc = "Render the part or group in place, or the block of a subproject at the cursor, and play that, its devices at rest: `freeze`, `freeze Strings`, `:t2,t4freeze`, `freeze tail=4`",
  range = true,
  complete = part_names,
})

paw.command("unfreeze", function(ctx)
  local block = chosen_block(ctx)
  if block then
    freeze_block.unfreeze(block)
    return paw.notify("unfrozen: the block of " .. api.nest_get(api.clip_get(block).nest, "name"))
  end
  local done = {}
  for _, id in ipairs(chosen(ctx)) do
    -- A part inside a frozen group thaws that group.
    local which = M.frozen(id) and id or M.holder(id) or id
    M.unfreeze(which)
    done[#done + 1] = api.part_get(which, "name")
  end
  paw.notify("unfrozen: " .. table.concat(done, ", "))
end, {
  desc = "Play a frozen part's clips and devices again, or the subproject of a frozen block at the cursor: `unfreeze`, `unfreeze Strings`",
  range = true,
  complete = part_names,
})

return M
