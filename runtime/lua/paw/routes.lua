-- Routes between tracks besides outputs and sends: side-chains, which a
-- device on one track takes from another, and the further output pairs of
-- a device with several (a drum plugin with a pair per drum).
--
--   comp:set_sidechain(kick)                -- the bass's compressor listens to the kick
--   comp:set_sidechain(kick, { pre = true }) -- before the kick's fader, pan and mute
--   kit:set_output(2, kick_track)           -- the kit's second pair plays there
--   paw.routes.spread(kit)                  -- a track for each pair
--   paw.routes.feeds(a, b)                  -- whether a's sound reaches b
--   :device.sidechain Kick                  -- the device panel's device
--   :device.output 2 Kick   :device.spread
local api = paw.api
local M = {}

--- Where each track's sound goes next, by id: its output (the master, 0,
--- without one), its sends, where its devices' further output pairs play,
--- and the tracks of the devices that listen to it.
local function edges()
  local out = {}
  for _, id in ipairs(api.track_list({ all = true })) do
    out[id] = out[id] or {}
  end
  for _, id in ipairs(api.track_list({ all = true })) do
    local t = api.track_get(id)
    table.insert(out[id], t.output or 0)
    for _, send in ipairs(t.sends or {}) do
      table.insert(out[id], send.target)
    end
    for _, to in ipairs(t.pairs_into or {}) do
      table.insert(out[id], to)
    end
    for _, source in ipairs(t.listens or {}) do
      if out[source] then table.insert(out[source], id) end
    end
  end
  return out
end

--- Every track reachable from `start` along `next`, as a set of ids.
local function walk(next, start)
  local seen, stack = {}, { start }
  while #stack > 0 do
    for _, id in ipairs(next[table.remove(stack)] or {}) do
      if not seen[id] then
        seen[id] = true
        stack[#stack + 1] = id
      end
    end
  end
  return seen
end

--- The tracks a track's sound reaches, directly or through others, as a set
--- of ids: by outputs, sends and side-chains.
function M.reached(from) return walk(edges(), from) end

--- The tracks a track may route to: those of its place, the song or its
--- subproject (the tracks of a subproject route only to each other).
function M.peers(track)
  local ok, nest = pcall(api.track_get, track, "nest")
  return api.track_list({ nest = ok and nest or nil })
end

--- The tracks whose sound reaches a track, as a set of ids.
function M.reaching(into)
  local back = {}
  for from, list in pairs(edges()) do
    for _, to in ipairs(list) do
      back[to] = back[to] or {}
      table.insert(back[to], from)
    end
  end
  return walk(back, into)
end

--- True if the sound of `from` goes to `into`.
function M.feeds(from, into) return M.reached(from)[into] == true end

--- The tracks that a device can listen to, `{ id, name }` each, in the
--- order of the track list. Its own track, the master and the tracks that
--- its track feeds are not in the list.
function M.sidechain_sources(device)
  local track = api.device_get(device).track
  local reached = M.reached(track)
  local out = {}
  for _, id in ipairs(api.track_list({ all = true })) do
    if id ~= track and not reached[id] then out[#out + 1] = { id = id, name = api.track_get(id, "name") } end
  end
  return out
end

--- What a device listens to, as text: the name of the track, with `pre`
--- when it takes the sound before the fader. Nil if it listens to nothing.
function M.sidechain_text(d)
  if not d.sidechain then return nil end
  local ok, t = pcall(api.track_get, d.sidechain)
  return (ok and t.name or "?") .. (d.sidechain_pre and " pre" or "")
end

--- A track by itself, its id, or its name (the first whose name holds it);
--- nil for "none", "" or nil. Errors when there is no such track.
local function track_of(track)
  if type(track) ~= "string" then return track end
  if track == "" or track:lower() == "none" then return nil end
  local found = paw.track(track)
  if not found then
    for _, id in ipairs(api.track_list({ all = true })) do
      if api.track_get(id, "name"):lower():find(track:lower(), 1, true) then return paw.track(id) end
    end
    error("no track `" .. track .. "`", 0)
  end
  return found
end

--- Set a device's side-chain by a track, a track's id or name ("none" or
--- nil for none), and `pre`. Errors say why it cannot be.
function M.set_sidechain(device, track, pre) paw.device(device):set_sidechain(track_of(track), { pre = pre }) end

--- The output pairs of a device: `{ pair, name, target, target_name }`
--- each, the main pair (pair 1, on its own track) first. Empty for a
--- device with one pair.
function M.outputs(device)
  local d = api.device_get(device)
  local out = {}
  for pair, name in ipairs(d.ports and d.ports.outputs or {}) do
    local target = pair > 1 and (d.outputs or {})[tostring(pair)] or nil
    local ok, t = pcall(api.track_get, target or d.track)
    out[pair] = { pair = pair, name = name, target = target, target_name = target and ok and t.name or nil }
  end
  return out
end

--- Play a device's output pair `pair` (2 and on) into a track (a track, its
--- id or name; nil or "none" for nowhere). Errors say why it cannot be.
function M.set_output(device, pair, track)
  pair = math.floor(tonumber(pair) or 0)
  if pair < 2 then error("output pairs from 2 on can be routed; the first plays on the device's track", 0) end
  local outputs = {}
  for key, to in pairs(api.device_get(device).outputs or {}) do
    outputs[tostring(key)] = to
  end
  track = track_of(track)
  outputs[tostring(pair)] = track and (type(track) == "table" and track.id or track) or nil
  if next(outputs) == nil then outputs = nil end
  api.device_set(device, "outputs", outputs)
end

--- Make a track for each output pair of a device that plays nowhere yet,
--- with the name of the pair, and send the pair there. paw puts the new
--- tracks and the track of the device in a group (or in the group of the
--- track of the device). The track of the device cannot be the group,
--- because its pairs feed the new tracks, which would then feed it again.
--- Returns the new tracks.
function M.spread(device)
  local d = api.device_get(device)
  local made = {}
  local track = paw.track(d.track)
  local at = track.index
  for _, out in ipairs(M.outputs(device)) do
    if out.pair > 1 and not out.target then
      at = at + 1
      local t = paw.add_track({ name = out.name, index = at })
      M.set_output(device, out.pair, t)
      made[#made + 1] = t
    end
  end
  if #made == 0 then return made end
  local group = paw.groups.of(track)
  if group then
    for _, t in ipairs(made) do
      paw.groups.add(t, group)
    end
  else
    local members = { track }
    for _, t in ipairs(made) do
      members[#members + 1] = t
    end
    paw.groups.make(members, track.name .. " outputs")
  end
  return made
end

--- Define the commands for sends and sidechains. The runtime calls this once at start.
function M.setup()
  local command = paw.command

  command("device.sidechain", function(ctx)
    local device = paw.fx.target()
    if not device then return end
    local pre = ctx.args.pre ~= nil and ctx.args.pre ~= "0" and ctx.args.pre ~= "false"
    local function set(track)
      local ok, err = pcall(M.set_sidechain, device.id, track, pre)
      if not ok then return paw.notify((tostring(err):gsub("^[^:]*:%d+: ", ""):match("^[^\n]*")), "warn") end
      local text = M.sidechain_text(device:get())
      paw.notify(text and device.name .. " listens to " .. text or device.name .. " listens to its own input")
    end
    local name = table.concat(ctx.args, " ")
    if name ~= "" then return set(name) end
    local items = { { id = false, name = "None: its own input" } }
    for _, source in ipairs(M.sidechain_sources(device.id)) do
      items[#items + 1] = source
    end
    paw.pick({
      title = "Side-chain of " .. device.name,
      items = items,
      format = function(t) return t.name end,
      on_choose = function(t) set(t.id or nil) end,
    })
  end, {
    desc = "Let the device listen to another track as its side-chain: `device.sidechain Kick`, "
      .. "`device.sidechain Kick pre=1` (before its fader), `device.sidechain none`; alone, choose from a list",
    complete = { "tracks" },
  })

  -- Its key, `gS`, is in paw/device_rows.lua with the panel's others.

  local function warn(err) paw.notify((tostring(err):gsub("^[^:]*:%d+: ", ""):match("^[^\n]*")), "warn") end

  command("device.output", function(ctx)
    local device = paw.fx.target()
    if not device then return end
    local outputs = M.outputs(device.id)
    if #outputs < 2 then return paw.notify(device.name .. " has one output pair", "warn") end
    local function set(pair, track)
      local ok, err = pcall(M.set_output, device.id, pair, track)
      if not ok then return warn(err) end
      local out = M.outputs(device.id)[pair]
      paw.notify(string.format("%s %s → %s", device.name, out.name, out.target_name or "not heard"))
    end
    local function choose_track(pair)
      local items = { { id = false, name = "Nowhere: not heard" } }
      local reaching = M.reaching(device:get().track)
      for _, id in ipairs(M.peers(device:get().track)) do
        if id ~= device:get().track and not reaching[id] then
          items[#items + 1] = { id = id, name = api.track_get(id, "name") }
        end
      end
      paw.pick({
        title = outputs[pair].name .. " of " .. device.name .. " into",
        items = items,
        format = function(t) return t.name end,
        on_choose = function(t) set(pair, t.id or nil) end,
      })
    end
    local pair = tonumber(ctx.args[1])
    if pair then
      local name = table.concat(ctx.args, " ", 2)
      if name == "" then return choose_track(pair) end
      return set(pair, name)
    end
    local items = {}
    for i = 2, #outputs do
      items[#items + 1] = outputs[i]
    end
    paw.pick({
      title = "Outputs of " .. device.name,
      items = items,
      format = function(o) return string.format("%-3d %-24s → %s", o.pair, o.name, o.target_name or "not heard") end,
      on_choose = function(o) choose_track(o.pair) end,
    })
  end, {
    desc = "Play one of the device's further output pairs into a track: `device.output 2 Kick`, "
      .. "`device.output 2 none`; alone, choose from a list",
  })

  command("device.spread", function()
    local device = paw.fx.target()
    if not device then return end
    local ok, made = pcall(M.spread, device.id)
    if not ok then return warn(made) end
    paw.notify(
      #made == 0 and "every output pair of " .. device.name .. " already plays somewhere"
        or string.format("%d output pairs of %s on tracks of their own", #made, device.name)
    )
  end, { desc = "Spread the device's output pairs over new tracks, named after them and grouped with its track" })

  paw.keymap.set("O", "device.output", { view = "devices", desc = "Route the device's further output pairs" })

  command("track.midi_out", function(ctx)
    local track = paw.cursor.track()
    if not track then return paw.notify("no track here", "warn") end
    local words = {}
    for _, word in ipairs(ctx.args) do
      words[#words + 1] = tostring(word)
    end
    -- A form and a channel last, after the port's name, in either order.
    local form, channel
    for _ = 1, 2 do
      local last = words[#words]
      if #words > 1 and M.midi_out_forms[last] then
        form = table.remove(words)
      elseif #words > 1 and tonumber(last) then
        channel = tonumber(table.remove(words))
      end
    end
    local name = table.concat(words, " ")
    if name == "" then return paw.commands.exec("track.input") end
    local ok, err = pcall(M.set_midi_out, track.id, name, channel, form, tonumber(ctx.args.members))
    if not ok then return warn(err) end
    paw.notify(track.name .. " → " .. M.midi_out_text(track:get()))
  end, {
    desc = "Send what the track plays to a MIDI port: `track.midi_out Synth 2` (channel 2), "
      .. "`track.midi_out Synth` (each message's own channel), `track.midi_out Synth mpe` (a channel to each note, "
      .. "where the port takes no MIDI 2.0; or `plain`, `cc14`, `auto`), `track.midi_out none`; alone, the input list",
    complete = function()
      local words = { "none" }
      for _, port in ipairs(paw.midi.outputs()) do
        words[#words + 1] = port.name
      end
      return words
    end,
  })
end

--- What a MIDI output sends where the port takes no MIDI 2.0, by the name
--- `track.midi_output.form` has for it, in words.
M.midi_out_forms = {
  auto = "MIDI 2.0 where the port takes it, else plain MIDI 1.0",
  plain = "plain MIDI 1.0",
  mpe = "MPE: a channel to each note, with its own bend",
  cc14 = "MIDI 1.0 with 14-bit controllers",
}
M.midi_out_form_order = { "auto", "plain", "mpe", "cc14" }

--- Where a track sends MIDI, as text: `Synth · channel 2 · MPE`, or "no MIDI output".
function M.midi_out_text(t)
  local out = t.midi_output
  if not out then return "no MIDI output" end
  local form = out.form and out.form ~= "auto" and (out.form == "cc14" and "14-bit" or out.form:upper()) or nil
  return out.port .. (out.channel and " · channel " .. out.channel or "") .. (form and " · " .. form or "")
end

--- Send the MIDI of a track to the port named `name` (or a part of its
--- name, "none" for none). `channel` is 1 to 16, or nil for the channel of
--- each message. `form` applies where the port does not accept MIDI 2.0
--- (a key of `M.midi_out_forms`, nil keeps the current form). MPE uses
--- `members` channels (nil for 15).
function M.set_midi_out(track, name, channel, form, members)
  if name == "none" or name == "" then return api.track_set(track, "midi_output", nil) end
  local was = api.track_get(track, "midi_output") or {}
  form = form or was.form
  if form ~= nil and not M.midi_out_forms[form] then error("a MIDI output's form is auto, plain, mpe or cc14", 0) end
  members = members or (form == "mpe" and was.members or nil)
  local port = name
  for _, p in ipairs(paw.midi.outputs()) do
    if p.name == name then
      port = p.name
      break
    end
    if p.name:lower():find(name:lower(), 1, true) and port == name then port = p.name end
  end
  api.track_set(track, "midi_output", { port = port, channel = channel, form = form, members = members })
end

return M
