-- Where a part's sound goes, for a frontend to show and change: its
-- output, its sends, a device's output pairs and its sidechain.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local options = require("paw.options")
local util = require("paw.util")
local type types = require("paw.types")
local M = require("paw.frontend.core")
local host = require("paw.frontend.host")

local paw = host.paw
local opt = options.opt
local A = M.act
local part_text = host.part_text
local type Check = M.Check
local type PairMenu = M.PairMenu
local type Routing = M.Routing
local type SendState = M.SendState
local type Target = M.Target

-- Where a part's sound goes.

--- Where a part's sound goes, for a frontend to show and change:
---   output   the name of the part it plays into ("Master" without one)
---   targets  the parts it could play into or send to, `{ id, name }` each;
---            the master is first, with id 0
---   sends    `{ target, name, level, pre }` each, levels in dB
--- A part cannot play into itself or into a part that plays into it.
function M.routing(part: integer): Routing
  local t = api.part_get(part)
  local targets: {Target} = {{id = 0, name = "Master"}}
  -- Not a part whose sound reaches this one, by any route.
  local reaching = paw.routes.reaching(part)
  for _, id in ipairs(paw.routes.peers(part)) do
    if id ~= part and not reaching[id] then
      targets[#targets + 1] = {id = id, name = part_text(id, "name")}
    end
  end
  local sends: {SendState} = {}
  for i, send in ipairs(t.sends or {}) do
    local ok, to = pcall(api.part_get, send.target)
    sends[i] = {
      target = send.target, name = ok and (to as types.Part).name or "?", level = send.level, pre = send.pre or false
    }
  end
  local ok, to = pcall(api.part_get, t.output or 0)
  return {
    output = t.output and ok and (to as types.Part).name or "Master",
    output_id = t.output or 0,
    targets = targets,
    sends = sends,
    master = t.master or false,
  }
end

--- Play a part into another (`target` 0 or nil for the master).
function A.set_output(part: integer, target?: integer)
  if target and target ~= 0 then
    api.part_set(part, {output = target})
  else
    api.part_set(part, "output", nil)
  end
end

--- Send a part's sound to another as well, at `level` dB (`paw.opt.send_level` without).
function A.add_send(part: integer, target: integer, level?: number)
  local sends = api.part_get(part).sends
  for _, send in ipairs(sends) do
    if send.target == target then
      return
    end
  end
  sends[#sends + 1] = {target = target, level = level or opt.send_level}
  api.part_set(part, {sends = sends})
end

--- Change the send at `index` (from 1): `level` in dB, `pre` whether it is
--- taken ahead of the fader; nil leaves either as it is.
function A.set_send(part: integer, index: integer, level?: number, pre?: boolean)
  local sends = api.part_get(part).sends
  if not sends[index] then
    return
  end
  if level ~= nil then
    sends[index].level = util.fader_db(sends[index].level, level)
  end
  if pre ~= nil then
    sends[index].pre = pre and true or nil
  end
  api.part_set(part, {sends = sends})
end

function A.remove_send(part: integer, index: integer)
  local sends = api.part_get(part).sends
  if not sends[index] then
    return
  end
  table.remove(sends, index)
  api.part_set(part, {sends = sends})
end

--- The menu of the side-chain of a device: "None" first, then the parts
--- that it can listen to. The last item tells if it takes the sound before
--- their fader. Each is `{ label, checked }`.
--- `act.choose_sidechain` takes one by place.
function M.sidechain_menu(device: integer): {Check}
  local d = api.device_get(device)
  local out: {Check} = {{label = "None: its own input", checked = d.sidechain == nil}}
  for _, source in ipairs(paw.routes.sidechain_sources(device)) do
    out[#out + 1] = {label = source.name, checked = source.id == d.sidechain}
  end
  out[#out + 1] = {label = "Before the fader", checked = d.sidechain_pre or false}
  return out
end

--- The menu of the other output pairs of a device. For each pair, it gives
--- `{ label, choices }`. The label names the pair and where it plays. The
--- choices (`{ label, checked }`) are "Nowhere" and the parts that it can
--- play into. `act.route_pair` takes one. `act.spread_outputs` makes a
--- part for each pair that plays nowhere.
function M.outputs_menu(device: integer): {PairMenu}
  local out: {PairMenu} = {}
  local d = api.device_get(device)
  local reaching = paw.routes.reaching(d.part)
  for _, o in ipairs(paw.routes.outputs(device)) do
    if o.pair > 1 then
      local choices: {Check} = {{label = "Nowhere: not heard", checked = o.target == nil}}
      for _, id in ipairs(paw.routes.peers(d.part)) do
        if id ~= d.part and not reaching[id] then
          choices[#choices + 1] = {label = part_text(id, "name"), checked = id == o.target}
        end
      end
      out[#out + 1] = {
        label = string.format("%d %s → %s", o.pair, o.name, o.target_name or "not heard"), choices = choices
      }
    end
  end
  return out
end

--- Route a device's output pair `pair` (from 2) to the `index`th choice of
--- its menu (`M.outputs_menu`): 1 for nowhere, then the parts it lists.
function A.route_pair(device: integer, pair: integer, index: integer)
  if index == 1 then
    return paw.routes.set_output(device, pair, nil)
  end
  local d = api.device_get(device)
  local reaching = paw.routes.reaching(d.part)
  local n = 1
  for _, id in ipairs(paw.routes.peers(d.part)) do
    if id ~= d.part and not reaching[id] then
      n = n + 1
      if n == index then
        return paw.routes.set_output(device, pair, id)
      end
    end
  end
end

function A.spread_outputs(device: integer)
  paw.routes.spread(device)
end

--- Choose from a device's side-chain menu (`M.sidechain_menu`), by place
--- from 1: none, a part, or the last entry, which turns taking it before
--- the fader on or off.
function A.choose_sidechain(device: integer, index: integer)
  local d = api.device_get(device)
  local sources = paw.routes.sidechain_sources(device)
  if index == 1 then
    paw.routes.set_sidechain(device, nil)
  elseif sources[index - 1] then
    paw.routes.set_sidechain(device, sources[index - 1].id, d.sidechain_pre)
  elseif index == #sources + 2 and d.sidechain then
    api.device_set(device, {sidechain_pre = not d.sidechain_pre})
  end
end
