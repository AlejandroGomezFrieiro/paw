-- The default commands and keys: parts. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local api = paw.api
local util = paw.util
local command = paw.command
local cursor = paw.cursor
local keymap = paw.keymap
local common = require("paw.defaults.common")
local need_part = common.need_part

--- Put a new part into the group that `o` or `O` next to part `beside`
--- puts it in (`paw.groups.home`): it then plays into that group.
local function join_group(part, beside, above)
  local group = beside and paw.groups.home(beside, above)
  if group then paw.groups.add(part, group) end
end

command("part.add", function(ctx)
  local index = cursor.index()
  local beside = index and cursor.part_id()
  -- A kind of part an extension defines: `part.add vocal`, `kind=vocal`.
  local kind = ctx.args.kind or paw.part_kinds.kinds:get(ctx.args[1] or "") and ctx.args[1]
  if kind then
    -- The kind's own words follow it (`part.add vocal Kitane`: a singer).
    local opts, words = {}, {}
    for k, v in pairs(ctx.args) do
      if type(k) ~= "number" and k ~= "kind" then opts[k] = v end
    end
    for i, word in ipairs(ctx.args) do
      if not (i == 1 and word == kind and not ctx.args.kind) then words[#words + 1] = word end
    end
    opts.words = words
    opts.index = index and (ctx.args.above and index or index + 1) or nil
    local part = paw.part_kinds.add(kind, opts)
    join_group(part, beside, ctx.args.above)
    cursor.set_part(part)
    return part
  end
  local part = paw.add_part({
    name = ctx.args.name or ctx.args[1] and tostring(ctx.args[1]) or nil,
    index = index and (ctx.args.above and index or index + 1) or nil,
  })
  if ctx.args.device then
    -- Do not leave a part behind when its device cannot be added.
    local ok, err = pcall(part.add_device, part, ctx.args.device)
    if not ok then
      part:remove()
      error(err, 0)
    end
  end
  join_group(part.id, beside, ctx.args.above)
  cursor.set_part(part)
  return part
end, {
  desc = "Add a part below the cursor, or above it: `part.add Bass device=synth`, `part.add above=true`; a kind an extension defines: `part.add vocal`",
  complete = function()
    local out = {}
    for _, spec in ipairs(paw.part_kinds.list()) do
      out[#out + 1] = { text = spec.name, desc = spec.title }
    end
    return out
  end,
})
command("part.new", function()
  local items = { { text = "Part            an ordinary part" } }
  for _, spec in ipairs(paw.part_kinds.list()) do
    items[#items + 1] = { text = string.format("%-16s %s", spec.title, spec.desc or ""), kind = spec.name }
  end
  paw.pick({
    title = "New part",
    items = items,
    format = function(item) return item.text end,
    on_choose = function(item) paw.cmd("part.add", item.kind and { kind = item.kind } or {}) end,
  })
end, {
  desc = "Add a part of a kind chosen from a list: an ordinary one, or one an extension defines (a vocal part, a drum part)",
})
command("part.remove", function(ctx)
  -- Never the cursor's part when another was meant.
  if ctx.args[1] ~= nil then
    error("part.remove removes the part at the cursor and takes no argument: `:t3 part.remove` removes part 3", 0)
  end
  local part = need_part()
  if not part then return end
  local index = cursor.index()
  part:remove()
  local list = paw.scope.parts()
  if #list > 0 then cursor.set_part(list[math.min(index, #list)]) end
end, { desc = "Remove the part" })
command("part.rename", function(ctx)
  local part = need_part()
  if not part then return end
  if ctx.args[1] then
    part.name = tostring(ctx.args[1])
  else
    paw.ui.input({ prompt = "Part name: ", text = part.name }, function(name)
      if name ~= "" then part.name = name end
    end)
  end
end, { desc = "Rename the part" })
-- The theme's part colours by name, for `part.color`.
local colour_names = require("paw.theme").hue_names
command("part.color", function(ctx)
  local part = need_part()
  if not part then return end
  local want = ctx.args[1] and tostring(ctx.args[1]):lower()
  if not want then
    return paw.notify("part.color takes " .. table.concat(colour_names, ", ") .. ", a colour as #rrggbb, or none")
  end
  local hues = require("paw.theme").hues
  for i, name in ipairs(colour_names) do
    if name == want then want = hues[i] end
  end
  if want == "none" then
    part.color = nil
  elseif want:match("^#%x%x%x%x%x%x$") then
    part.color = want
  else
    paw.notify("no colour `" .. want .. "`: use " .. table.concat(colour_names, ", ") .. ", #rrggbb, or none", "warn")
  end
end, {
  desc = "Give the part a colour: `part.color teal`, `part.color #ff8800`, `part.color none`",
  complete = function()
    local words = { "none" }
    for _, name in ipairs(colour_names) do
      words[#words + 1] = name
    end
    return words
  end,
})
-- Where a part's sound goes: its output and its sends.

--- A part by some of its name, or the master for "master".
local function part_named(name)
  if not name or name == "" then return nil end
  if name:lower() == "master" then return 0 end
  local found
  for _, id in ipairs(api.part_list()) do
    local known = api.part_get(id, "name")
    if known == name then return id end
    if known:lower():find(name:lower(), 1, true) then found = found or id end
  end
  return found
end

--- Choose among the parts a part can play into or send to.
local function pick_target(part, title, with_master, on_choose)
  local items = {}
  for _, target in ipairs(paw.frontend.routing(part).targets) do
    if with_master or target.id ~= 0 then items[#items + 1] = target end
  end
  -- A send goes to a return first: a part with no instrument and no audio
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

command("part.output", function(ctx)
  local part = need_part()
  if not part then return end
  local function set(target)
    local ok, err = pcall(paw.frontend.act.set_output, part.id, target)
    if not ok then return paw.notify((tostring(err):gsub("^[^:]*:%d+: ", ""):match("^[^\n]*")), "warn") end
    paw.notify(part.name .. " → " .. paw.frontend.routing(part.id).output)
  end
  local name = ctx.args[1]
  if not name or name == "" then return pick_target(part.id, "Output of " .. part.name, true, set) end
  local target = part_named(name)
  if not target then return paw.notify("no part `" .. name .. "`", "warn") end
  set(target)
end, {
  desc = "Play the part into another: `part.output Drum bus`, `part.output master`; alone, choose from a list",
  raw = true,
  complete = "parts",
})

--- The parts a command for each part is about: those of a selection
--- of whole parts in the arrange view or of strips in the mixer, else the
--- cursor part.
local function selected_parts()
  local selection = keymap.selection()
  if selection and (selection.view == "arrange" or selection.view == "mixer") then
    local rows, out = paw.groups.rows(), {}
    for row = math.max(1, selection.r0), selection.r1 do
      if rows[row] then out[#out + 1] = rows[row] end
    end
    if #out > 0 then return out end
  end
  local id = cursor.part_id()
  return id and { id } or {}
end

command("send", function(ctx)
  local ids = selected_parts()
  if #ids == 0 then return paw.notify("no part selected", "warn") end
  local asked = tonumber(ctx.args[2]) or tonumber(ctx.args.level)
  local level = asked or paw.opt.send_level
  local pre = ctx.args.pre ~= nil and ctx.args.pre ~= false and ctx.args.pre ~= 0 and ctx.args.pre ~= "0" or nil
  local function add(target)
    local to, said = api.part_get(target, "name"), {}
    for _, id in ipairs(ids) do
      local name = api.part_get(id, "name")
      local index
      for i, send in ipairs(api.part_get(id).sends) do
        if send.target == target then index = i end
      end
      if id == target or target == 0 then
        said[#said + 1] = name .. " cannot send to " .. (target == 0 and "the master" or "itself")
      elseif index then
        -- The send is there: a level or `pre` given sets it; else it is as it was.
        local send = api.part_get(id).sends[index]
        local was = send.level
        local changed = (asked and math.abs(asked - was) > 1e-9)
          or (ctx.args.pre ~= nil and (send.pre or false) ~= (pre or false))
        if changed then
          paw.frontend.act.set_send(id, index, asked, ctx.args.pre ~= nil and (pre or false) or nil)
          local now = api.part_get(id).sends[index].level
          said[#said + 1] =
            string.format("%s ↗ %s now at %g dB (was %g)%s", name, to, now, was, pre and ", ahead of the fader" or "")
        else
          said[#said + 1] = string.format("%s already sends to %s at %g dB: unchanged", name, to, was)
        end
      else
        paw.frontend.act.add_send(id, target, level)
        if pre then paw.frontend.act.set_send(id, #api.part_get(id).sends, nil, true) end
        said[#said + 1] = string.format("%s ↗ %s at %g dB%s", name, to, level, pre and ", ahead of the fader" or "")
      end
    end
    if keymap.mode == "x" then keymap.set_mode("n") end
    paw.notify(#said == 1 and said[1] or string.format("%d parts: %s", #said, table.concat(said, "; ")))
  end
  local name = ctx.args[1]
  if not name then
    local first = api.part_get(ids[1], "name")
    return pick_target(ids[1], "Send " .. (#ids == 1 and first or #ids .. " parts") .. " to", false, add)
  end
  local target = part_named(tostring(name))
  if not target or target == 0 then return paw.notify("no part `" .. tostring(name) .. "` to send to", "warn") end
  add(target)
end, {
  desc = "Send the part's sound (or the selected parts') to another as well, at `send_level` dB unless told: `send Reverb -9`, `send Reverb -9 pre=1`; again with a level, set the send's level; alone, choose from a list",
  complete = { "parts" },
})

command("send.remove", function(ctx)
  local part = need_part()
  if not part then return end
  local sends = part:get().sends
  local name = ctx.args[1]
  for index, send in ipairs(sends) do
    local to = api.part_get(send.target, "name")
    if not name or to:lower():find(tostring(name):lower(), 1, true) then
      paw.frontend.act.remove_send(part.id, index)
      return paw.notify(part.name .. " no longer sends to " .. to)
    end
  end
  paw.notify(#sends == 0 and "the part has no sends" or "no send to `" .. tostring(name) .. "`", "warn")
end, {
  desc = "Take a send away: `send.remove Reverb`; alone, the first",
  complete = function()
    local part, out = cursor.part(), {}
    for _, send in ipairs(part and part:get().sends or {}) do
      out[#out + 1] = api.part_get(send.target, "name")
    end
    return out
  end,
})

-- Groups of parts (see paw.groups).

--- The parts a group command is about: those of the selection, else the
--- cursor part.
local chosen_parts = common.chosen_parts

command("part.group", function(ctx)
  local parts = chosen_parts()
  if #parts == 0 then return paw.notify("no part to group", "warn") end
  -- Typed as a command alone, a raw command is given an empty text.
  local name = ctx.args[1] ~= "" and ctx.args[1] or nil
  local function make(text)
    if not text or text == "" then return end
    local group = paw.groups.make(parts, text)
    if keymap.mode == "x" then keymap.set_mode("n") end
    cursor.set_part(group)
    paw.notify(
      string.format(
        "group “%s” holds %d part%s; its fader and devices act on all of them",
        text,
        #parts,
        #parts == 1 and "" or "s"
      )
    )
  end
  if name then return make(name) end
  paw.ui.input({ prompt = "Group name: ", text = "Group" }, make)
end, { desc = "Put the selected parts (or the cursor part) in a new group: `part.group Strings`", raw = true })

command("part.ungroup", function()
  local part = need_part()
  if not part then return end
  if paw.groups.is_group(part.id) then
    paw.groups.dissolve(part.id)
    return paw.notify("the group is dissolved; its parts stay")
  end
  for _, id in ipairs(chosen_parts()) do
    paw.groups.remove(id)
  end
end, { desc = "Take the part out of its group; on a group, dissolve it" })

command("part.into", function(ctx)
  local parts = chosen_parts()
  local function into(group)
    for _, id in ipairs(parts) do
      if id ~= group then
        local ok, err = pcall(paw.groups.add, id, group)
        if not ok then return paw.notify(tostring(err):gsub("^[^:]*:%d+: ", ""), "warn") end
      end
    end
  end
  local groups = {}
  for _, id in ipairs(api.part_list()) do
    if paw.groups.is_group(id) then groups[#groups + 1] = { id = id, name = api.part_get(id, "name") } end
  end
  local name = ctx.args[1]
  if name then
    for _, group in ipairs(groups) do
      if group.name:lower():find(name:lower(), 1, true) then return into(group.id) end
    end
    return paw.notify("no group `" .. name .. "`", "warn")
  end
  if #groups == 0 then return paw.notify("no groups yet: `:part.group` makes one", "warn") end
  paw.pick({
    title = "Move into group",
    items = groups,
    format = function(g) return g.name end,
    on_choose = function(g) into(g.id) end,
  })
end, {
  desc = "Move the part into a group: `part.into Strings`; alone, choose it from a list",
  raw = true,
  complete = function()
    local out = {}
    for _, id in ipairs(api.part_list()) do
      if paw.groups.is_group(id) then out[#out + 1] = api.part_get(id, "name") end
    end
    return out
  end,
})

-- Folds (paw/folds.tl): view state of the window, never an undo step.
local function fold_words(f) return string.format("%s (%s)", paw.folds.name(f), paw.folds.describe(f)) end
local function fold_command(name, fn, verb, desc)
  command(name, function()
    local f, why = fn()
    if not f then return paw.notify(why, "warn") end
    paw.notify(verb(f) .. " " .. fold_words(f))
  end, { desc = desc })
end
-- `za`: on a subproject's return row (or a part it shows in place), its
-- parts under the row (paw/nest.tl); else the fold at the cursor.
command("fold.toggle", function()
  local id = cursor.part_id()
  if id and id ~= 0 and not paw.groups.is_group(id) and paw.nest.toggle(id) then return end
  local f, why = paw.folds.toggle()
  if not f then return paw.notify(why, "warn") end
  paw.notify((f.closed and "folded " or "opened ") .. fold_words(f))
end, {
  desc = "Fold the fold at the cursor (a group, a fold of parts, a region), or open it; on a return row, its parts",
})
fold_command("fold.close", paw.folds.close, function() return "folded" end, "Fold the fold at the cursor")
fold_command("fold.open", paw.folds.open, function() return "opened" end, "Open the fold at the cursor")
fold_command(
  "fold.delete",
  paw.folds.delete,
  function() return "deleted the fold" end,
  "Delete the fold at the cursor: its parts stay"
)
command("fold.clear", function()
  local n = paw.folds.clear()
  paw.notify(string.format("deleted %d fold%s of this window", n, n == 1 and "" or "s"))
end, { desc = "Delete every fold of this window: the parts stay" })
command("fold.more", function(ctx)
  local level = paw.folds.level(-(ctx.count or 1))
  paw.notify(level == 0 and "every region folded: `zr` opens a level" or ("regions open to level " .. level))
end, { desc = "Fold one more level of regions, the deepest first (as Vim's zm)" })
command("fold.less", function(ctx)
  local level = paw.folds.level(ctx.count or 1)
  paw.notify("regions open to level " .. level)
end, { desc = "Open one more level of regions (as Vim's zr)" })
command("fold.closeall", function()
  paw.folds.all(true)
  paw.notify("folded everything in this window: `zR` opens it all")
end, { desc = "Fold every group and every fold of this window" })
command("fold.openall", function()
  paw.folds.all(false)
  paw.notify("opened every fold of this window")
end, { desc = "Open every group and every fold of this window" })

command("group.link", function()
  local part = need_part()
  if not part then return end
  local group = paw.groups.is_group(part.id) and part.id or paw.groups.of(part.id)
  if not group then return paw.notify("not in a group", "warn") end
  paw.groups.link(group)
  paw.notify(
    string.format(
      "faders of “%s” %s",
      api.part_get(group, "name"),
      paw.groups.linked(group) and "are linked: moving one member's fader moves the others" or "are free again"
    )
  )
end, { desc = "Link the faders of the group's members, or let them go: moving one moves the others by as many dB" })

-- VCAs: faders over parts that do not route them (see paw.vca).

--- The VCA named, by part of its name, or nil.
local function vca_named(name)
  for _, id in ipairs(paw.vca.list()) do
    if api.part_get(id, "name"):lower():find(tostring(name):lower(), 1, true) then return id end
  end
end

local function vca_names()
  local out = {}
  for _, id in ipairs(paw.vca.list()) do
    out[#out + 1] = api.part_get(id, "name")
  end
  return out
end

--- Do something with a VCA: the one named, else one chosen from a list.
local function with_vca(name, title, from, act)
  if name == "" then name = nil end
  local vcas = {}
  for _, id in ipairs(from) do
    vcas[#vcas + 1] = { id = id, name = api.part_get(id, "name") }
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
  local parts = chosen_parts()
  if #parts == 0 then return paw.notify("no part to put under a VCA", "warn") end
  local function make(text)
    if not text or text == "" then return end
    local vca = paw.vca.make(parts, text)
    if keymap.mode == "x" then keymap.set_mode("n") end
    cursor.set_part(vca)
    paw.notify(
      string.format("VCA “%s” moves %d part%s; their routing is as it was", text, #parts, #parts == 1 and "" or "s")
    )
  end
  if ctx.args[1] and ctx.args[1] ~= "" then return make(ctx.args[1]) end
  paw.ui.input({ prompt = "VCA name: ", text = "VCA" }, make)
end, { desc = "A new VCA over the selected parts (or the cursor part): `vca.make Drums`", raw = true })

command("vca.assign", function(ctx)
  local parts = chosen_parts()
  if #parts == 0 then return paw.notify("no part to put under a VCA", "warn") end
  with_vca(ctx.args[1], "Put under VCA", paw.vca.list(), function(vca)
    for _, id in ipairs(parts) do
      local ok, err = pcall(paw.vca.assign, id, vca)
      if not ok then return paw.notify(tostring(err):gsub("^[^:]*:%d+: ", ""), "warn") end
    end
  end)
end, {
  desc = "Put the selected parts under a VCA: `vca.assign Drums`; alone, choose it from a list",
  raw = true,
  complete = vca_names,
})

command("vca.release", function(ctx)
  local parts = chosen_parts()
  local name = ctx.args[1]
  if not name or name == "" then
    for _, id in ipairs(parts) do
      paw.vca.unassign(id)
    end
    return
  end
  with_vca(name, "Take out of VCA", paw.vca.list(), function(vca)
    for _, id in ipairs(parts) do
      paw.vca.unassign(id, vca)
    end
  end)
end, {
  desc = "Take the selected parts out of a VCA (`vca.release Drums`), or out of all of them",
  raw = true,
  complete = vca_names,
})

command("vca.dissolve", function()
  local part = need_part()
  if not part then return end
  if not paw.vca.is_vca(part.id) then return paw.notify("not a VCA", "warn") end
  paw.vca.dissolve(part.id)
  paw.notify("the VCA is gone; its parts stay, at their own faders")
end, { desc = "Take the VCA at the cursor away; its parts stay" })

command("part.duplicate", function()
  local part = need_part()
  if part then cursor.set_part(part:duplicate()) end
end, { desc = "Duplicate the part" })

for _, flag in ipairs({ "mute", "solo", "armed", "monitor" }) do
  command("part." .. flag, function()
    local part = need_part()
    if part then part[flag] = not part[flag] end
  end, { desc = "Toggle " .. flag })
end

command("part.volume", function(ctx)
  local part = need_part()
  if not part then return end
  if ctx.args.by then
    part.volume = util.fader_db(part.volume, part.volume + ctx.args.by * (ctx.count or 1))
  elseif tonumber(ctx.args[1]) then
    part.volume = tonumber(ctx.args[1])
  end
end, { desc = "Set the volume in dB, or nudge it: `part.volume -6`, `part.volume by=1`" })
command("part.pan", function(ctx)
  local part = need_part()
  if not part then return end
  if ctx.args.by then
    part.pan = util.round(part.pan + ctx.args.by * (ctx.count or 1), 0.01)
  elseif tonumber(ctx.args[1]) then
    part.pan = tonumber(ctx.args[1])
  end
end, { desc = "Set the pan from -1 to 1, or nudge it: `part.pan by=0.1`" })
command("part.move", function(ctx)
  local part = need_part()
  if cursor.on_master() then return paw.notify("the master part stays after the last part", "warn") end
  if not part then return end
  -- A count moves it that many places: `3<A-j>`.
  local to = cursor.index() + (ctx.args.by or 1) * (ctx.count or 1)
  part:move(util.clamp(to, 1, #paw.routes.peers(part.id)))
end, { desc = "Move the part down or up, by the count: `part.move by=-1`" })
-- What each choice of input means, and the lists, are `paw.audio`'s; here
-- they are commands.
local function input_picker(part) paw.audio.pick(part) end
command("part.input", function(ctx)
  local part = need_part()
  if not part then return end
  local spec = ctx.args[1]
  if spec == nil then return input_picker(part) end
  part.input = tostring(spec)
  paw.notify(part.name .. " ← " .. (paw.audio.label(part:get()) or "no audio input"))
end, {
  desc = "Choose the part's input from a list; or set it: `part.input 1/2`, `part.input 3`, `part.input none`",
  complete = function()
    local words = {}
    for _, choice in ipairs(paw.audio.choices(cursor.part_id() or paw.parts()[1] or 0)) do
      if choice.group == "audio" then words[#words + 1] = choice.value.input end
    end
    if #words == 0 then words = { "none", "1", "2", "1/2" } end
    return words
  end,
})
command("part.midi", function(ctx)
  local part = need_part()
  if not part then return end
  local port = ctx.args[1] and table.concat(ctx.args, " ")
  if port == nil and ctx.args.ch == nil then return input_picker(part) end
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
  paw.audio.choose(part, value)
  paw.notify(part.name .. " ← " .. (paw.audio.label(part:get()) or "MIDI from every port"))
end, {
  desc = "Take MIDI from one port and channel, or all: `part.midi Keystation ch=1`, `part.midi all`",
  complete = function()
    local words = { "all" }
    for _, p in ipairs(paw.midi.inputs()) do
      words[#words + 1] = p.name
    end
    return words
  end,
})
command("part.color.pick", function()
  local part = need_part()
  if not part then return end
  local hues = require("paw.theme").hues
  local items = {}
  for i, name in ipairs(colour_names) do
    items[#items + 1] = { name = name, value = hues[i] }
  end
  items[#items + 1] = { name = "none", value = nil }
  paw.pick({
    title = "Colour of " .. part.name,
    items = items,
    format = function(item)
      local now = (part.color or "") == (item.value or "") and "● " or "  "
      return now .. string.format("%-8s %s", item.name, item.value or "the theme's, in turn")
    end,
    on_choose = function(item)
      api.undo_label("color of " .. part.name)
      part.color = item.value
      paw.notify(part.name .. " is " .. item.name)
    end,
  })
end, { desc = "Choose the part's colour from the theme's hues" })
