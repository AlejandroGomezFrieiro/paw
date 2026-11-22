-- The default commands and keys: tracks. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local api = paw.api
local util = paw.util
local command = paw.command
local cursor = paw.cursor
local keymap = paw.keymap
local common = require("paw.defaults.common")
local need_track = common.need_track

command("track.add", function(ctx)
  local index = cursor.index()
  -- A kind of track an extension defines: `track.add vocal`, `kind=vocal`.
  local kind = ctx.args.kind or paw.track_kinds.kinds[ctx.args[1] or ""] and ctx.args[1]
  if kind then
    -- The kind's own words follow it (`track.add vocal Kitane`: a singer).
    local opts, words = {}, {}
    for k, v in pairs(ctx.args) do
      if type(k) ~= "number" and k ~= "kind" then opts[k] = v end
    end
    for i, word in ipairs(ctx.args) do
      if not (i == 1 and word == kind and not ctx.args.kind) then words[#words + 1] = word end
    end
    opts.words = words
    opts.index = index and (ctx.args.above and index or index + 1) or nil
    local track = paw.track_kinds.add(kind, opts)
    cursor.set_track(track)
    return track
  end
  local track = paw.add_track({
    name = ctx.args.name or ctx.args[1] and tostring(ctx.args[1]) or nil,
    index = index and (ctx.args.above and index or index + 1) or nil,
  })
  if ctx.args.device then
    -- Do not leave a track behind when its device cannot be added.
    local ok, err = pcall(track.add_device, track, ctx.args.device)
    if not ok then
      track:remove()
      error(err, 0)
    end
  end
  cursor.set_track(track)
  return track
end, {
  desc = "Add a track below the cursor, or above it: `track.add Bass device=synth`, `track.add above=true`; a kind an extension defines: `track.add vocal`",
  complete = function()
    local out = {}
    for _, spec in ipairs(paw.track_kinds.list()) do
      out[#out + 1] = { text = spec.name, desc = spec.title }
    end
    return out
  end,
})
command("track.new", function()
  local items = { { text = "Track            an ordinary track" } }
  for _, spec in ipairs(paw.track_kinds.list()) do
    items[#items + 1] = { text = string.format("%-16s %s", spec.title, spec.desc or ""), kind = spec.name }
  end
  paw.pick({
    title = "New track",
    items = items,
    format = function(item) return item.text end,
    on_choose = function(item) paw.cmd("track.add", item.kind and { kind = item.kind } or {}) end,
  })
end, {
  desc = "Add a track of a kind chosen from a list: an ordinary one, or one an extension defines (a vocal track, a drum track)",
})
command("track.remove", function(ctx)
  -- Never the cursor's track when another was meant.
  if ctx.args[1] ~= nil then
    error("track.remove removes the track at the cursor and takes no argument: `:t3 track.remove` removes track 3", 0)
  end
  local track = need_track()
  if not track then return end
  local index = cursor.index()
  track:remove()
  local list = paw.scope.tracks()
  if #list > 0 then cursor.set_track(list[math.min(index, #list)]) end
end, { desc = "Remove the track" })
command("track.rename", function(ctx)
  local track = need_track()
  if not track then return end
  if ctx.args[1] then
    track.name = tostring(ctx.args[1])
  else
    paw.ui.input({ prompt = "Track name: ", text = track.name }, function(name)
      if name ~= "" then track.name = name end
    end)
  end
end, { desc = "Rename the track" })
-- The theme's track colours by name, for `track.color`.
local colour_names = require("paw.theme").hue_names
command("track.color", function(ctx)
  local track = need_track()
  if not track then return end
  local want = ctx.args[1] and tostring(ctx.args[1]):lower()
  if not want then
    return paw.notify("track.color takes " .. table.concat(colour_names, ", ") .. ", a colour as #rrggbb, or none")
  end
  local hues = require("paw.theme").hues
  for i, name in ipairs(colour_names) do
    if name == want then want = hues[i] end
  end
  if want == "none" then
    track.color = nil
  elseif want:match("^#%x%x%x%x%x%x$") then
    track.color = want
  else
    paw.notify("no colour `" .. want .. "`: use " .. table.concat(colour_names, ", ") .. ", #rrggbb, or none", "warn")
  end
end, {
  desc = "Give the track a colour: `track.color teal`, `track.color #ff8800`, `track.color none`",
  complete = function()
    local words = { "none" }
    for _, name in ipairs(colour_names) do
      words[#words + 1] = name
    end
    return words
  end,
})
-- Where a track's sound goes: its output and its sends.

--- A track by a part of its name, or the master for "master".
local function track_named(name)
  if not name or name == "" then return nil end
  if name:lower() == "master" then return 0 end
  local found
  for _, id in ipairs(api.track_list()) do
    local known = api.track_get(id, "name")
    if known == name then return id end
    if known:lower():find(name:lower(), 1, true) then found = found or id end
  end
  return found
end

--- Choose among the tracks a track can play into or send to.
local function pick_target(track, title, with_master, on_choose)
  local items = {}
  for _, target in ipairs(paw.frontend.routing(track).targets) do
    if with_master or target.id ~= 0 then items[#items + 1] = target end
  end
  -- A send goes to a return first: a track with no instrument and no audio
  -- of its own, which is there to hold effects.
  if not with_master then
    local rank = {}
    for i, target in ipairs(items) do
      rank[target.id] = (paw.fx.preferred(target.id) == "instrument" and 0 or 1) * 1000 + i
    end
    table.sort(items, function(a, b) return rank[a.id] < rank[b.id] end)
  end
  paw.pick({
    title = title,
    items = items,
    format = function(t) return t.name end,
    on_choose = function(t) on_choose(t.id) end,
  })
end

command("track.output", function(ctx)
  local track = need_track()
  if not track then return end
  local function set(target)
    local ok, err = pcall(paw.frontend.act.set_output, track.id, target)
    if not ok then return paw.notify((tostring(err):gsub("^[^:]*:%d+: ", ""):match("^[^\n]*")), "warn") end
    paw.notify(track.name .. " → " .. paw.frontend.routing(track.id).output)
  end
  local name = ctx.args[1]
  if not name or name == "" then return pick_target(track.id, "Output of " .. track.name, true, set) end
  local target = track_named(name)
  if not target then return paw.notify("no track `" .. name .. "`", "warn") end
  set(target)
end, {
  desc = "Play the track into another: `track.output Drum bus`, `track.output master`; alone, choose from a list",
  raw = true,
  complete = "tracks",
})

--- The tracks a command for each track is about: those of a selection
--- of whole tracks in the arrange view or of strips in the mixer, else the
--- cursor track.
local function selected_tracks()
  local selection = keymap.selection()
  if selection and (selection.view == "arrange" or selection.view == "mixer") then
    local rows, out = paw.groups.rows(), {}
    for row = math.max(1, selection.r0), selection.r1 do
      if rows[row] then out[#out + 1] = rows[row] end
    end
    if #out > 0 then return out end
  end
  local id = cursor.track_id()
  return id and { id } or {}
end

command("send", function(ctx)
  local ids = selected_tracks()
  if #ids == 0 then return paw.notify("no track selected", "warn") end
  local asked = tonumber(ctx.args[2]) or tonumber(ctx.args.level)
  local level = asked or paw.opt.send_level
  local pre = ctx.args.pre ~= nil and ctx.args.pre ~= false and ctx.args.pre ~= 0 and ctx.args.pre ~= "0" or nil
  local function add(target)
    local to, said = api.track_get(target, "name"), {}
    for _, id in ipairs(ids) do
      local name = api.track_get(id, "name")
      local index
      for i, send in ipairs(api.track_get(id).sends) do
        if send.target == target then index = i end
      end
      if id == target or target == 0 then
        said[#said + 1] = name .. " cannot send to " .. (target == 0 and "the master" or "itself")
      elseif index then
        -- The send is there: a level or `pre` given sets it; else it is as it was.
        local send = api.track_get(id).sends[index]
        local was = send.level
        local changed = (asked and math.abs(asked - was) > 1e-9)
          or (ctx.args.pre ~= nil and (send.pre or false) ~= (pre or false))
        if changed then
          paw.frontend.act.set_send(id, index, asked, ctx.args.pre ~= nil and (pre or false) or nil)
          local now = api.track_get(id).sends[index].level
          said[#said + 1] =
            string.format("%s ↗ %s now at %g dB (was %g)%s", name, to, now, was, pre and ", ahead of the fader" or "")
        else
          said[#said + 1] = string.format("%s already sends to %s at %g dB: unchanged", name, to, was)
        end
      else
        paw.frontend.act.add_send(id, target, level)
        if pre then paw.frontend.act.set_send(id, #api.track_get(id).sends, nil, true) end
        said[#said + 1] = string.format("%s ↗ %s at %g dB%s", name, to, level, pre and ", ahead of the fader" or "")
      end
    end
    if keymap.mode == "x" then keymap.set_mode("n") end
    paw.notify(#said == 1 and said[1] or string.format("%d tracks: %s", #said, table.concat(said, "; ")))
  end
  local name = ctx.args[1]
  if not name then
    local first = api.track_get(ids[1], "name")
    return pick_target(ids[1], "Send " .. (#ids == 1 and first or #ids .. " tracks") .. " to", false, add)
  end
  local target = track_named(tostring(name))
  if not target or target == 0 then return paw.notify("no track `" .. tostring(name) .. "` to send to", "warn") end
  add(target)
end, {
  desc = "Send the track's sound (or the selected tracks') to another as well, at `send_level` dB unless told: `send Reverb -9`, `send Reverb -9 pre=1`; again with a level, set the send's level; alone, choose from a list",
  complete = { "tracks" },
})

command("send.remove", function(ctx)
  local track = need_track()
  if not track then return end
  local sends = track:get().sends
  local name = ctx.args[1]
  for index, send in ipairs(sends) do
    local to = api.track_get(send.target, "name")
    if not name or to:lower():find(tostring(name):lower(), 1, true) then
      paw.frontend.act.remove_send(track.id, index)
      return paw.notify(track.name .. " no longer sends to " .. to)
    end
  end
  paw.notify(#sends == 0 and "the track has no sends" or "no send to `" .. tostring(name) .. "`", "warn")
end, {
  desc = "Take a send away: `send.remove Reverb`; alone, the first",
  complete = function()
    local track, out = cursor.track(), {}
    for _, send in ipairs(track and track:get().sends or {}) do
      out[#out + 1] = api.track_get(send.target, "name")
    end
    return out
  end,
})

-- Groups of tracks (see paw.groups).

--- The tracks a group command is about: those of the selection, else the
--- cursor track.
local function chosen_tracks()
  local selection = keymap.selection()
  if selection and selection.view == "arrange" then
    local rows, out = paw.groups.rows(), {}
    for row = math.max(1, selection.r0), selection.r1 do
      if rows[row] then out[#out + 1] = rows[row] end
    end
    if #out > 0 then return out end
  end
  local id = cursor.track_id()
  return id and { id } or {}
end

command("track.group", function(ctx)
  local tracks = chosen_tracks()
  if #tracks == 0 then return paw.notify("no track to group", "warn") end
  -- Typed as a command alone, a raw command is given an empty text.
  local name = ctx.args[1] ~= "" and ctx.args[1] or nil
  local function make(text)
    if not text or text == "" then return end
    local group = paw.groups.make(tracks, text)
    if keymap.mode == "x" then keymap.set_mode("n") end
    cursor.set_track(group)
    paw.notify(
      string.format(
        "group “%s” holds %d track%s; its fader and devices act on all of them",
        text,
        #tracks,
        #tracks == 1 and "" or "s"
      )
    )
  end
  if name then return make(name) end
  paw.ui.input({ prompt = "Group name: ", text = "Group" }, make)
end, { desc = "Put the selected tracks (or the cursor track) in a new group: `track.group Strings`", raw = true })

command("track.ungroup", function()
  local track = need_track()
  if not track then return end
  if paw.groups.is_group(track.id) then
    paw.groups.dissolve(track.id)
    return paw.notify("the group is dissolved; its tracks stay")
  end
  for _, id in ipairs(chosen_tracks()) do
    paw.groups.remove(id)
  end
end, { desc = "Take the track out of its group; on a group, dissolve it" })

command("track.into", function(ctx)
  local tracks = chosen_tracks()
  local function into(group)
    for _, id in ipairs(tracks) do
      if id ~= group then
        local ok, err = pcall(paw.groups.add, id, group)
        if not ok then return paw.notify(tostring(err):gsub("^[^:]*:%d+: ", ""), "warn") end
      end
    end
  end
  local groups = {}
  for _, id in ipairs(api.track_list()) do
    if paw.groups.is_group(id) then groups[#groups + 1] = { id = id, name = api.track_get(id, "name") } end
  end
  local name = ctx.args[1]
  if name then
    for _, group in ipairs(groups) do
      if group.name:lower():find(name:lower(), 1, true) then return into(group.id) end
    end
    return paw.notify("no group `" .. name .. "`", "warn")
  end
  if #groups == 0 then return paw.notify("no groups yet: `:track.group` makes one", "warn") end
  paw.pick({
    title = "Move into group",
    items = groups,
    format = function(g) return g.name end,
    on_choose = function(g) into(g.id) end,
  })
end, {
  desc = "Move the track into a group: `track.into Strings`; alone, choose it from a list",
  raw = true,
  complete = function()
    local out = {}
    for _, id in ipairs(api.track_list()) do
      if paw.groups.is_group(id) then out[#out + 1] = api.track_get(id, "name") end
    end
    return out
  end,
})

command("track.fold", function(ctx)
  local track = need_track()
  if not track then return end
  local group = paw.groups.is_group(track.id) and track.id or paw.groups.of(track.id)
  if not group then return paw.notify("not in a group", "warn") end
  if ctx.args[1] == "all" or ctx.args[1] == "none" then
    for _, id in ipairs(api.track_list()) do
      paw.groups.fold(id, ctx.args[1] == "all")
    end
    return
  end
  paw.groups.fold(group)
end, { desc = "Fold the group away, or open it: `track.fold`; `track.fold all`, `track.fold none`" })

command("group.link", function()
  local track = need_track()
  if not track then return end
  local group = paw.groups.is_group(track.id) and track.id or paw.groups.of(track.id)
  if not group then return paw.notify("not in a group", "warn") end
  paw.groups.link(group)
  paw.notify(
    string.format(
      "faders of “%s” %s",
      api.track_get(group, "name"),
      paw.groups.linked(group) and "are linked: moving one member's fader moves the others" or "are free again"
    )
  )
end, { desc = "Link the faders of the group's members, or let them go: moving one moves the others by as many dB" })

-- VCAs: faders over tracks that do not route them (see paw.vca).

--- The VCA named, by part of its name, or nil.
local function vca_named(name)
  for _, id in ipairs(paw.vca.list()) do
    if api.track_get(id, "name"):lower():find(tostring(name):lower(), 1, true) then return id end
  end
end

local function vca_names()
  local out = {}
  for _, id in ipairs(paw.vca.list()) do
    out[#out + 1] = api.track_get(id, "name")
  end
  return out
end

--- Do something with a VCA: the one named, else one chosen from a list.
local function with_vca(name, title, from, act)
  if name == "" then name = nil end
  local vcas = {}
  for _, id in ipairs(from) do
    vcas[#vcas + 1] = { id = id, name = api.track_get(id, "name") }
  end
  if name then
    local id = vca_named(name)
    if id then return act(id) end
    return paw.notify("no VCA `" .. name .. "`", "warn")
  end
  if #vcas == 0 then return paw.notify("no VCAs here: `:vca.make` makes one", "warn") end
  paw.pick({
    title = title,
    items = vcas,
    format = function(v) return v.name end,
    on_choose = function(v) act(v.id) end,
  })
end

command("vca.make", function(ctx)
  local tracks = chosen_tracks()
  if #tracks == 0 then return paw.notify("no track to put under a VCA", "warn") end
  local function make(text)
    if not text or text == "" then return end
    local vca = paw.vca.make(tracks, text)
    if keymap.mode == "x" then keymap.set_mode("n") end
    cursor.set_track(vca)
    paw.notify(
      string.format(
        "VCA “%s” moves %d track%s; their routing is as it was",
        text,
        #tracks,
        #tracks == 1 and "" or "s"
      )
    )
  end
  if ctx.args[1] and ctx.args[1] ~= "" then return make(ctx.args[1]) end
  paw.ui.input({ prompt = "VCA name: ", text = "VCA" }, make)
end, { desc = "A new VCA over the selected tracks (or the cursor track): `vca.make Drums`", raw = true })

command("vca.assign", function(ctx)
  local tracks = chosen_tracks()
  if #tracks == 0 then return paw.notify("no track to put under a VCA", "warn") end
  with_vca(ctx.args[1], "Put under VCA", paw.vca.list(), function(vca)
    for _, id in ipairs(tracks) do
      local ok, err = pcall(paw.vca.assign, id, vca)
      if not ok then return paw.notify(tostring(err):gsub("^[^:]*:%d+: ", ""), "warn") end
    end
  end)
end, {
  desc = "Put the selected tracks under a VCA: `vca.assign Drums`; alone, choose it from a list",
  raw = true,
  complete = vca_names,
})

command("vca.release", function(ctx)
  local tracks = chosen_tracks()
  local name = ctx.args[1]
  if not name or name == "" then
    for _, id in ipairs(tracks) do
      paw.vca.unassign(id)
    end
    return
  end
  with_vca(name, "Take out of VCA", paw.vca.list(), function(vca)
    for _, id in ipairs(tracks) do
      paw.vca.unassign(id, vca)
    end
  end)
end, {
  desc = "Take the selected tracks out of a VCA (`vca.release Drums`), or out of all of them",
  raw = true,
  complete = vca_names,
})

command("vca.dissolve", function()
  local track = need_track()
  if not track then return end
  if not paw.vca.is_vca(track.id) then return paw.notify("not a VCA", "warn") end
  paw.vca.dissolve(track.id)
  paw.notify("the VCA is gone; its tracks stay, at their own faders")
end, { desc = "Take the VCA at the cursor away; its tracks stay" })

command("track.duplicate", function()
  local track = need_track()
  if track then cursor.set_track(track:duplicate()) end
end, { desc = "Duplicate the track" })

for _, flag in ipairs({ "mute", "solo", "armed", "monitor" }) do
  command("track." .. flag, function()
    local track = need_track()
    if track then track[flag] = not track[flag] end
  end, { desc = "Toggle " .. flag })
end

command("track.volume", function(ctx)
  local track = need_track()
  if not track then return end
  if ctx.args.by then
    track.volume = util.fader_db(track.volume, track.volume + ctx.args.by * (ctx.count or 1))
  elseif tonumber(ctx.args[1]) then
    track.volume = tonumber(ctx.args[1])
  end
end, { desc = "Set the volume in dB, or nudge it: `track.volume -6`, `track.volume by=1`" })
command("track.pan", function(ctx)
  local track = need_track()
  if not track then return end
  if ctx.args.by then
    track.pan = util.round(track.pan + ctx.args.by * (ctx.count or 1), 0.01)
  elseif tonumber(ctx.args[1]) then
    track.pan = tonumber(ctx.args[1])
  end
end, { desc = "Set the pan from -1 to 1, or nudge it: `track.pan by=0.1`" })
command("track.move", function(ctx)
  local track = need_track()
  if cursor.on_master() then return paw.notify("the master track stays after the last track", "warn") end
  if not track then return end
  -- A count moves it that many places: `3<A-j>`.
  local to = cursor.index() + (ctx.args.by or 1) * (ctx.count or 1)
  track:move(util.clamp(to, 1, #paw.routes.peers(track.id)))
end, { desc = "Move the track down or up, by the count: `track.move by=-1`" })
-- What each choice of input means, and the lists, are `paw.audio`'s; here
-- they are commands.
local function input_picker(track) paw.audio.pick(track) end
command("track.input", function(ctx)
  local track = need_track()
  if not track then return end
  local spec = ctx.args[1]
  if spec == nil then return input_picker(track) end
  track.input = tostring(spec)
  paw.notify(track.name .. " ← " .. (paw.audio.label(track:get()) or "no audio input"))
end, {
  desc = "Choose the track's input from a list; or set it: `track.input 1/2`, `track.input 3`, `track.input none`",
  complete = function()
    local words = {}
    for _, choice in ipairs(paw.audio.choices(cursor.track_id() or paw.tracks()[1] or 0)) do
      if choice.group == "audio" then words[#words + 1] = choice.value.input end
    end
    if #words == 0 then words = { "none", "1", "2", "1/2" } end
    return words
  end,
})
command("track.midi", function(ctx)
  local track = need_track()
  if not track then return end
  local port = ctx.args[1] and table.concat(ctx.args, " ")
  if port == nil and ctx.args.ch == nil then return input_picker(track) end
  local value = {}
  if port then
    -- A part of a port's name is enough.
    local found = port ~= "all" and port
    for _, p in ipairs(paw.midi.inputs()) do
      if found and p.name:lower():find(found:lower(), 1, true) then
        found = p.name
        break
      end
    end
    value.midi_port = found or false
  end
  if ctx.args.ch then
    local ch = tonumber(ctx.args.ch)
    value.midi_channel = ch and ch >= 1 and ch <= 16 and math.floor(ch) or false
  end
  paw.audio.choose(track, value)
  paw.notify(track.name .. " ← " .. (paw.audio.label(track:get()) or "MIDI from every port"))
end, {
  desc = "Take MIDI from one port and channel, or all: `track.midi Keystation ch=1`, `track.midi all`",
  complete = function()
    local words = { "all" }
    for _, p in ipairs(paw.midi.inputs()) do
      words[#words + 1] = p.name
    end
    return words
  end,
})
command("track.color.pick", function()
  local track = need_track()
  if not track then return end
  local hues = require("paw.theme").hues
  local items = {}
  for i, name in ipairs(colour_names) do
    items[#items + 1] = { name = name, value = hues[i] }
  end
  items[#items + 1] = { name = "none", value = nil }
  paw.pick({
    title = "Colour of " .. track.name,
    items = items,
    format = function(item)
      local now = (track.color or "") == (item.value or "") and "● " or "  "
      return now .. string.format("%-8s %s", item.name, item.value or "the theme's, in turn")
    end,
    on_choose = function(item)
      api.undo_label("color of " .. track.name)
      track.color = item.value
      paw.notify(track.name .. " is " .. item.name)
    end,
  })
end, { desc = "Choose the track's colour from the theme's hues" })
