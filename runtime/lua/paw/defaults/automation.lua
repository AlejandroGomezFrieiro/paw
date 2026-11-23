-- The default commands and keys: automation. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local command = paw.command
local cursor = paw.cursor
local common = require("paw.defaults.common")
local need_part = common.need_part

--- What a lane command acts on: the cursor part's volume, or what
--- `target=pan` or `target=<param> device=<kind>` names. Returns the part or
--- device that owns the lane, and the target.
local function lane_owner(ctx)
  local part = need_part()
  if not part then return end
  local target = tostring(ctx.args.target or "volume")
  if not ctx.args.device then return part, target end
  local device = part:device(ctx.args.device)
  if not device then paw.notify("no device `" .. tostring(ctx.args.device) .. "` on the part", "warn") end
  return device, target
end

local function need_lane(ctx)
  -- On a lane's row, that lane.
  if not ctx.args.target and not ctx.args.device and cursor.lane_id() then return paw.lane(cursor.lane_id()) end
  local owner, target = lane_owner(ctx)
  local lane = owner and owner:lane(target)
  if owner and not lane then paw.notify("no " .. target .. " automation on the part", "warn") end
  return lane
end

command("lane.add", function(ctx)
  local owner, target = lane_owner(ctx)
  if not owner then return end
  local beat = cursor.beat
  local function add(value) owner:automate(target):add(beat, value) end
  local current = owner:value_at(target, beat)
  if tonumber(ctx.args[1]) then return add(tonumber(ctx.args[1])) end
  if ctx.args.by then return add(current + ctx.args.by * (ctx.count or 1)) end
  paw.ui.input(
    { prompt = target .. " at " .. paw.time.format(beat) .. ": ", text = string.format("%g", current) },
    function(text)
      if tonumber(text) then add(tonumber(text)) end
    end
  )
end, {
  desc = "Add an automation point at the cursor: `lane.add -6`, `lane.add by=1 target=pan`, `lane.add 800 target=cutoff device=synth`",
})
command("lane.clear", function(ctx)
  local lane = need_lane(ctx)
  if lane then lane:clear() end
end, { desc = "Remove every point of the part's volume automation, or of `target=...`" })
command("lane.toggle", function(ctx)
  local lane = need_lane(ctx)
  if not lane then return end
  lane.enabled = not lane.enabled
  paw.notify(lane.target .. " automation " .. (lane.enabled and "on" or "off"))
end, { desc = "Turn the part's volume automation, or `target=...`, off or on" })
command("lane.remove", function(ctx)
  local lane = need_lane(ctx)
  if lane then lane:remove() end
end, { desc = "Remove the part's volume automation, or `target=...`" })
