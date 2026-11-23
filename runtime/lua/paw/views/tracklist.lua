-- The listings of the project that are edited as text (paw/textbuf.tl):
--
--   paw://tracks             a track a line: name, volume, pan, flags, output, group, colour, devices
--   paw://sends              a send a line: from, to, level, before or after the fader
--   paw://track/N/devices    the device chain of track N (or `master`): name, on, wet, preset
--   paw://markers            a marker or region a line: where, name, where it ends
--
-- Each kind reads the project into lines of fields two spaces apart, reads
-- a line back into fields, and turns what changed into the steps of a
-- plan. A line reads back as the same fields it was written from, so a
-- line left alone is no change, whatever the project rounds.
local api = paw.api
local tb = paw.textbuf
local quote, unquote, cells = tb.quote, tb.unquote, tb.cells

local function arrow() return paw.opt.ascii and "->" or "→" end
local function chain() return paw.opt.ascii and ">" or "▸" end

local function fmt(v)
  local text = string.format("%.1f", v)
  if text == "-0.0" then text = "0.0" end
  return text
end

local function db_text(v) return v <= -119.95 and "-inf" or fmt(v) end

local function parse_db(text, what)
  text = text:gsub("%s*[dD][bB]$", "")
  if text == "-inf" or text == "-∞" then return -120 end
  local v = tonumber(text)
  if not v then error(what .. " is in dB, like " .. what .. " -6", 0) end
  if v < -120 or v > 24 then error(what .. " is from -inf to +24 dB", 0) end
  return v
end

local function pan_text(p)
  local n = math.floor(math.abs(p) * 100 + 0.5)
  if n == 0 then return "C" end
  return (p < 0 and "L" or "R") .. n
end

local function parse_pan(text)
  local up = text:upper()
  if up == "C" or up == "CENTRE" or up == "CENTER" or up == "0" then return 0 end
  local side, n = up:match("^([LR])%s*(%d+%.?%d*)$")
  local v
  if side then
    v = tonumber(n) * (side == "L" and -1 or 1)
  else
    v = tonumber(text)
  end
  if not v then error("pan is C, L and a percentage or R and one: pan L30", 0) end
  if math.abs(v) > 100 then error("pan goes as far as L100 and R100", 0) end
  return v / 100
end

--- A track's name, or nil for one that is gone.
local function track_name(id)
  if id == nil then return nil end
  local ok, t = pcall(api.track_get, id)
  return ok and t.name or nil
end

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

-- paw://tracks -------------------------------------------------------------------------

local TRACK_FIELDS = "the name first, then vol, pan, flags (M S R), out, group, in, color and " .. chain() .. " devices"

local function parse_track(text)
  local list = cells(text)
  if #list == 0 then return nil, "an empty line" end
  local f = {
    name = unquote(list[1].text),
    vol = 0,
    pan = 0,
    mute = false,
    solo = false,
    armed = false,
    head = false,
    devices = {},
  }
  if f.name == "" then return nil, "a track needs a name" end
  for i = 2, #list do
    local cell = list[i].text
    local key, value = cell:match("^(%S+)%s+(.+)$")
    -- `▸` is three bytes: it cannot go in a set of characters.
    local rest = cell:match("^▸%s*(.*)$") or cell:match("^>%s*(.*)$")
    if rest then
      for part in (rest .. ","):gmatch("%s*(.-)%s*,") do
        if part ~= "" then f.devices[#f.devices + 1] = part end
      end
    elseif key == "vol" then
      f.vol = parse_db(value, "vol")
    elseif key == "pan" then
      f.pan = parse_pan(value)
    elseif key == "out" then
      f.out = unquote(value)
      if f.out:lower() == "master" then f.out = nil end
    elseif key == "in" then
      f.group = unquote(value)
    elseif key == "color" or key == "colour" then
      if value:lower() ~= "none" then
        if not value:match("^#%x%x%x%x%x%x$") then return nil, "a colour is #rrggbb, like color #ff9e64" end
        f.color = value:lower()
      end
    elseif cell == "group" then
      f.head = true
    elseif cell:match("^[MSRmsr%-]+$") and #cell <= 3 then
      local up = cell:upper()
      f.mute, f.solo, f.armed = up:find("M") ~= nil, up:find("S") ~= nil, up:find("R") ~= nil
    else
      return nil, "`" .. cell .. "` is not a field: " .. TRACK_FIELDS
    end
  end
  return f
end

local function device_names(t)
  local out = {}
  for i, id in ipairs(t.devices) do
    local ok, d = pcall(api.device_get, id)
    out[i] = ok and d.name or "?"
  end
  return out
end

--- What a device's name or kind names, of the devices there are: its kind.
local function device_kind(name)
  local lower = name:lower()
  local types = paw.device_types()
  for _, info in ipairs(types) do
    if info.kind:lower() == lower then return info.kind end
  end
  for _, info in ipairs(types) do
    if (info.name or ""):lower() == lower then return info.kind end
  end
end

--- The tracks of a plan's lines by name, to resolve `out` and `in`.
local function resolver(lines, what)
  local by_name = {}
  for _, e in ipairs(lines) do
    local key = e.fields.name
    by_name[key] = by_name[key] or {}
    table.insert(by_name[key], e)
  end
  return function(name, row)
    local list = by_name[name]
    -- A narrowed window lists its scope's tracks: the others are named as they are.
    if not list and paw.scope.limits_tracks() then
      for _, id in ipairs(api.track_list()) do
        if api.track_get(id, "name") == name and not paw.scope.contains(id) then
          list = list or {}
          list[#list + 1] = { id = id, fields = { name = name, head = paw.groups.is_group(id) or nil } }
        end
      end
    end
    if not list then error(string.format("line %d: no track `%s` in the list for %s", row, name, what), 0) end
    if #list > 1 then
      error(string.format("line %d: %d tracks are called `%s`: name them apart first", row, #list, name), 0)
    end
    return list[1]
  end
end

tb.kind("tracks", {
  title = function() return "Tracks" end,
  keywords = { vol = true, pan = true, out = true, ["in"] = true, color = true, group = true },
  hint = "edit the tracks and `:w` · `dd` deletes, `yyp` copies one with its devices, `cw` renames, Ctrl-a on a number, Enter its devices",
  style = function(cell, i)
    if i == 1 then return "TrackName" end
    if cell:match("^[MSR%-]+$") and #cell <= 3 then
      return cell:find("M") and "Mute" or cell:find("S") and "Solo" or cell:find("R") and "Armed" or "Faint"
    end
    if cell:match("^▸") or cell:match("^>") then return "DeviceName" end
  end,
  read = function()
    local out = {}
    -- In a narrowed window, the tracks of its scope: the others are left as they are.
    for i, id in ipairs(paw.scope.tracks()) do
      out[i] = { id = id, track = api.track_get(id) }
    end
    return out
  end,
  format = function(item)
    local t = item.track
    local group = paw.groups.of(t.id)
    -- A member sounding through its group says so with `in` alone.
    local out = t.output and t.output ~= group and track_name(t.output)
    local names = device_names(t)
    return {
      quote(t.name),
      "vol " .. db_text(t.volume),
      "pan " .. pan_text(t.pan),
      (t.mute and "M" or "-") .. (t.solo and "S" or "-") .. (t.armed and "R" or "-"),
      out and "out " .. quote(out) or "",
      paw.groups.is_group(t.id) and "group" or "",
      group and "in " .. quote(track_name(group)) or "",
      t.color and "color " .. t.color or "",
      #names > 0 and chain() .. " " .. table.concat(names, ", ") or "",
    }
  end,
  parse = parse_track,
  open = function(_, line)
    local index
    for i, id in ipairs(api.track_list({ all = true })) do
      if id == line.id then index = i end
    end
    if not index then return paw.notify("a new track has no devices yet: `:w` makes it first", "warn") end
    tb.open("paw://track/" .. index .. "/devices", { here = true })
  end,
  plan = function(ch)
    local steps = {}
    local resolve = resolver(ch.lines, "`out` or `in`")
    local function step(text, run, quiet) steps[#steps + 1] = { text = text, run = run, quiet = quiet } end
    local function id_of(e, state) return e.id or state.made[e.row] end

    -- What the lines name must be there when the plan is applied.
    for _, e in ipairs(ch.lines) do
      local f = e.fields
      if f.out then resolve(f.out, e.row) end
      if f.group then
        local g = resolve(f.group, e.row)
        if not g.fields.head then
          error(string.format("line %d: `%s` is not a group: give its line `group`", e.row, f.group), 0)
        end
        if g == e then error(string.format("line %d: a group cannot be inside itself", e.row), 0) end
      end
      if e.base and not tb.same(f.devices, e.base.devices) then
        error(
          string.format("line %d: a track's devices are edited in paw://track/N/devices (Enter on its line)", e.row),
          0
        )
      end
      if not e.base then
        for _, name in ipairs(f.devices) do
          if not device_kind(name) then error(string.format("line %d: no device `%s`", e.row, name), 0) end
        end
      end
    end
    for _, e in ipairs(ch.lines) do
      if e.base and e.base.head and not e.fields.head then
        for _, m in ipairs(ch.lines) do
          if m.fields.group == e.fields.name then
            error(string.format("line %d: `%s` still has tracks in it (line %d)", e.row, e.fields.name, m.row), 0)
          end
        end
      end
    end

    for _, d in ipairs(ch.deleted) do
      local t = api.track_get(d.id)
      step(
        string.format("delete %s (%s, %s)", quote(t.name), plural(#t.devices, "device"), plural(#t.clips, "clip")),
        function() api.track_remove(d.id) end
      )
    end

    -- What is set on a track from its line, but `out` and `in`, which wait
    -- until every track is made.
    local function set_fields(e, keys)
      local f = e.fields
      local texts = {}
      local function run_set(key, value)
        return function(st) api.track_set(id_of(e, st), key, value) end
      end
      for _, key in ipairs(keys) do
        if key == "name" then
          texts[#texts + 1] =
            { string.format("rename %s → %s", quote(e.base.name), quote(f.name)), run_set("name", f.name) }
        elseif key == "vol" then
          texts[#texts + 1] = {
            string.format(
              "%s: volume %s → %s dB",
              quote(f.name),
              e.base and db_text(e.base.vol) or "0.0",
              db_text(f.vol)
            ),
            run_set("volume", f.vol),
          }
        elseif key == "pan" then
          texts[#texts + 1] = {
            string.format("%s: pan %s → %s", quote(f.name), e.base and pan_text(e.base.pan) or "C", pan_text(f.pan)),
            run_set("pan", f.pan),
          }
        elseif key == "mute" or key == "solo" or key == "armed" then
          local word = key == "armed" and "armed" or key
          texts[#texts + 1] =
            { string.format("%s: %s %s", quote(f.name), word, f[key] and "on" or "off"), run_set(key, f[key]) }
        elseif key == "color" then
          texts[#texts + 1] =
            { string.format("%s: colour %s", quote(f.name), f.color or "none"), run_set("color", f.color) }
        elseif key == "head" then
          texts[#texts + 1] = {
            string.format("%s: %s", quote(f.name), f.head and "becomes a group" or "is a group no more"),
            function(st)
              local id = id_of(e, st)
              local meta = api.track_get(id, "meta") or {}
              meta.group_head = f.head or nil
              api.track_set(id, "meta", meta)
            end,
          }
        end
      end
      for _, pair in ipairs(texts) do
        step(pair[1], pair[2])
      end
    end

    for _, e in ipairs(ch.changed) do
      set_fields(e, e.keys)
    end

    -- Copies and new tracks, where their lines are.
    local made = {}
    for _, e in ipairs(ch.lines) do
      if e.copy_of then
        local t = api.track_get(e.copy_of)
        made[#made + 1] = e
        step(
          string.format(
            "copy %s as %s (%s, %s)",
            quote(t.name),
            quote(e.fields.name),
            plural(#t.devices, "device"),
            plural(#t.clips, "clip")
          ),
          function(st)
            local snap = paw.track(e.copy_of):snapshot()
            -- The tracks the original's further output pairs play into stay the original's.
            for _, device in ipairs(snap.devices) do
              device.outputs = nil
            end
            -- The copy is what its line says: where it plays and which group
            -- it is in are set with the others' below.
            snap.name, snap.volume, snap.pan, snap.color = e.fields.name, e.fields.vol, e.fields.pan, e.fields.color
            snap.mute, snap.output = e.fields.mute, nil
            local track = paw.restore_track(snap)
            st.made[e.row] = track.id
            if e.fields.solo then api.track_set(track.id, "solo", true) end
            if e.fields.armed then api.track_set(track.id, "armed", true) end
            local meta = api.track_get(track.id, "meta") or {}
            meta.group_head, meta.group = e.fields.head or nil, nil
            api.track_set(track.id, "meta", meta)
          end
        )
      elseif not e.id then
        local f = e.fields
        local kinds = {}
        for _, name in ipairs(f.devices) do
          kinds[#kinds + 1] = device_kind(name)
        end
        step(
          string.format("add %s%s", quote(f.name), #kinds > 0 and " with " .. table.concat(kinds, ", ") or ""),
          function(st)
            local track = paw.add_track({ name = f.name, volume = f.vol, pan = f.pan, color = f.color })
            st.made[e.row] = track.id
            for key, value in pairs({ mute = f.mute, solo = f.solo, armed = f.armed }) do
              if value then api.track_set(track.id, key, true) end
            end
            if f.head then
              local meta = api.track_get(track.id, "meta") or {}
              meta.group_head = true
              api.track_set(track.id, "meta", meta)
            end
            for _, kind in ipairs(kinds) do
              track:add_device(kind)
            end
          end
        )
      end
    end

    -- Outputs and groups, now that every track is there.
    for _, e in ipairs(ch.lines) do
      local f, base = e.fields, e.base
      local new = not base or e.copy_of
      if new and f.group or (base and not e.copy_of and f.group ~= base.group) then
        local g = f.group and resolve(f.group, e.row)
        step(
          f.group and string.format("%s: into the group %s", quote(f.name), quote(f.group))
            or string.format("%s: out of the group %s", quote(f.name), quote(base.group)),
          function(st)
            local id = id_of(e, st)
            if g then
              paw.groups.add(id, id_of(g, st))
            else
              paw.groups.remove(id, true)
            end
          end
        )
      end
      if new and f.out or (base and not e.copy_of and f.out ~= base.out) then
        local o = f.out and resolve(f.out, e.row)
        step(string.format("%s: output → %s", quote(f.name), f.out and quote(f.out) or "master"), function(st)
          local id = id_of(e, st)
          local to = o and id_of(o, st)
          if not to and f.group then to = id_of(resolve(f.group, e.row), st) end
          api.track_set(id, "output", to)
        end)
      end
    end

    -- The order of the lines, if it is not the order the tracks are in.
    if ch.moved or #made > 0 or #ch.added > 0 then
      for _, e in ipairs(ch.moves) do
        step(string.format("move %s from %d to %d", quote(e.fields.name), e.from, e.place))
      end
      step("order the tracks as the lines are", function(st)
        -- In a narrowed window, its tracks keep the place in the list they had.
        local i = 0
        local first = paw.scope.limits_tracks() and paw.scope.tracks()[1]
        for k, id in ipairs(first and api.track_list() or {}) do
          if id == first then i = k - 1 end
        end
        for _, e in ipairs(ch.lines) do
          local id = id_of(e, st)
          if id then
            i = i + 1
            api.track_move(id, i)
          end
        end
      end, true)
    end
    return steps
  end,
})

-- paw://sends --------------------------------------------------------------------------------

local function parse_send(text)
  local list = cells(text)
  if #list == 0 then return nil, "an empty line" end
  local f = { from = unquote(list[1].text), level = 0, pre = false }
  for i = 2, #list do
    local cell = list[i].text
    local to = cell:match("^→%s*(.+)$") or cell:match("^%->%s*(.+)$") or cell:match("^to%s+(.+)$")
    if to then
      f.to = unquote(to)
    elseif cell == "pre" or cell == "post" then
      f.pre = cell == "pre"
    elseif cell:match("^[%-%+%d%.]") then
      f.level = parse_db(cell, "a send's level")
    else
      return nil,
        "`"
          .. cell
          .. "` is not a field: the track it is from, "
          .. arrow()
          .. " the track it goes to, the level in dB, pre or post"
    end
  end
  if not f.to then return nil, "a send goes somewhere: " .. arrow() .. " and a track's name" end
  return f
end

--- A track of the project by its name, or an error that says what is wrong.
local function project_track(name, row)
  if name:lower() == "master" then error(string.format("line %d: a send goes to a track, not the master", row), 0) end
  local found = {}
  for _, id in ipairs(api.track_list()) do
    if api.track_get(id, "name") == name then found[#found + 1] = id end
  end
  if #found == 0 then error(string.format("line %d: no track `%s`", row, name), 0) end
  if #found > 1 then
    error(string.format("line %d: %d tracks are called `%s`: name them apart first", row, #found, name), 0)
  end
  return found[1]
end

local function send_text(f) return quote(f.from) .. " " .. arrow() .. " " .. quote(f.to) end

tb.kind("sends", {
  title = function() return "Sends" end,
  keywords = {},
  hint = "edit the sends and `:w` · `yyp` and change the target to add one, `dd` removes, Ctrl-a and Ctrl-x on the level",
  style = function(cell, i)
    if i == 1 then return "TrackName" end
    if cell:match("^→") or cell:match("^%->") then return "TrackRoute" end
    if cell == "pre" then return "Accent" end
    if cell == "post" then return "Faint" end
  end,
  read = function()
    local out = {}
    for _, id in ipairs(api.track_list()) do
      local t = api.track_get(id)
      local seen = {}
      for _, s in ipairs(t.sends or {}) do
        local key = id .. ">" .. s.target
        seen[key] = (seen[key] or 0) + 1
        out[#out + 1] = { id = key .. (seen[key] > 1 and "#" .. seen[key] or ""), from = t, send = s }
      end
    end
    return out
  end,
  format = function(item)
    local s = item.send
    return {
      quote(item.from.name),
      arrow() .. " " .. quote(track_name(s.target) or "?"),
      db_text(s.level) .. " dB",
      s.pre and "pre" or "post",
    }
  end,
  parse = parse_send,
  plan = function(ch)
    local steps = {}
    -- The sends each track the plan touches ends with, from the lines.
    local touched, order = {}, {}
    local function touch(id)
      if not touched[id] then
        touched[id] = {}
        order[#order + 1] = id
      end
    end
    for _, d in ipairs(ch.deleted) do
      touch(project_track(d.base.from, d.row or 0))
      steps[#steps + 1] = { text = "remove the send " .. send_text(d.base) }
    end
    for _, e in ipairs(ch.changed) do
      touch(project_track(e.base.from, e.row))
      touch(project_track(e.fields.from, e.row))
      local f, b = e.fields, e.base
      if f.from ~= b.from or f.to ~= b.to then
        steps[#steps + 1] = { text = "move the send " .. send_text(b) .. " to " .. send_text(f) }
      end
      if f.level ~= b.level then
        steps[#steps + 1] =
          { text = string.format("%s: %s → %s dB", send_text(f), db_text(b.level), db_text(f.level)) }
      end
      if f.pre ~= b.pre then
        steps[#steps + 1] = { text = send_text(f) .. ": " .. (f.pre and "before the fader" or "after the fader") }
      end
    end
    for _, e in ipairs(ch.lines) do
      local from = project_track(e.fields.from, e.row)
      project_track(e.fields.to, e.row)
      if not e.base or e.copy_of then
        touch(from)
        steps[#steps + 1] = {
          text = string.format(
            "add a send %s at %s dB%s",
            send_text(e.fields),
            db_text(e.fields.level),
            e.fields.pre and ", before the fader" or ""
          ),
        }
      end
    end
    for _, e in ipairs(ch.lines) do
      local from = project_track(e.fields.from, e.row)
      if touched[from] then
        table.insert(
          touched[from],
          { target = project_track(e.fields.to, e.row), level = e.fields.level, pre = e.fields.pre or nil }
        )
      end
    end
    for _, id in ipairs(order) do
      local sends = touched[id]
      for _, s in ipairs(sends) do
        if s.target == id then error("a track cannot send to itself: " .. track_name(id), 0) end
      end
      steps[#steps + 1] = {
        text = "the sends of " .. quote(track_name(id)),
        quiet = true,
        run = function()
          -- The list the project gives is marked as one, so that it stays a
          -- list when it is empty.
          local list = api.track_get(id).sends
          for i = #list, 1, -1 do
            list[i] = nil
          end
          for i, send in ipairs(sends) do
            list[i] = send
          end
          api.track_set(id, "sends", list)
        end,
      }
    end
    return steps
  end,
})

-- paw://track/N/devices ------------------------------------------------------------------------

--- The track a devices buffer is of: N its place in the list, or `master`.
local function chain_track(ctx)
  local which = ctx.args[1]
  if which == "master" then return paw.master.id end
  local n = tonumber(which)
  local id = n and api.track_list({ all = true })[n]
  if not id then
    error("no track " .. tostring(which) .. ": paw://track/N/devices takes the track's place in the list, or master", 0)
  end
  return id
end

local function parse_device(text)
  local list = cells(text)
  if #list == 0 then return nil, "an empty line" end
  local f = { name = unquote(list[1].text), on = true }
  for i = 2, #list do
    local cell = list[i].text
    local key, value = cell:match("^(%S+)%s+(.+)$")
    if cell == "on" or cell == "off" or cell == "bypass" or cell == "bypassed" then
      f.on = cell == "on"
    elseif key == "wet" then
      local v = tonumber((value:gsub("%s*%%$", "")))
      if not v or v < 0 or v > 100 then return nil, "wet is a percentage from 0 to 100, like wet 50%" end
      f.wet = v
    elseif key == "preset" then
      f.preset = unquote(value)
    else
      return nil,
        "`" .. cell .. "` is not a field: the device first, then on or off, wet and a percentage, preset and a name"
    end
  end
  return f
end

local function wet_text(v)
  local text = string.format("%.1f", v):gsub("%.0$", "")
  return text
end

--- A preset of a device by name, the way `paw.fx.load` finds one; nil without.
local function find_preset(device, name)
  local list = paw.fx.presets(device)
  for _, p in ipairs(list) do
    if p.name == name then return p end
  end
  for _, p in ipairs(list) do
    if p.name:lower():find(name:lower(), 1, true) then return p end
  end
end

tb.kind("devices", {
  pattern = "^paw://track/([%w]+)/devices$",
  example = "paw://track/1/devices",
  title = function(ctx)
    local ok, id = pcall(chain_track, ctx)
    return ok and "Devices of " .. (id == paw.master.id and "the master" or track_name(id)) or "Devices"
  end,
  keywords = { wet = true, preset = true },
  hint = "edit the chain and `:w` · `o` and a device's name adds one, `dd` removes, `yyp` copies, `ddp` moves one down · `-` the tracks",
  style = function(cell, i)
    if i == 1 then return "DeviceName" end
    if cell == "off" or cell == "bypassed" then return "DeviceOff" end
    if cell == "on" then return "Faint" end
  end,
  read = function(ctx)
    local id = chain_track(ctx)
    local out = {}
    for i, d in ipairs(api.track_get(id).devices) do
      out[i] = { id = d, device = api.device_get(d) }
    end
    return out
  end,
  format = function(item)
    local d = item.device
    local preset = type(d.meta) == "table" and d.meta.preset or nil
    return {
      quote(d.name),
      d.bypass and "off" or "on",
      d.params.fx_wet and "wet " .. wet_text(d.params.fx_wet) .. "%" or "",
      preset and "preset " .. quote(preset) or "",
    }
  end,
  parse = parse_device,
  parent = function() return "paw://tracks" end,
  open = function(ctx, line)
    if not line.id then return paw.notify("a new device opens once `:w` has made it", "warn") end
    -- The device panel, on the device's own row.
    local track = chain_track(ctx)
    if track ~= paw.master.id then paw.cursor.set_track(track) end
    paw.ui.show("devices")
    local panel = paw.ui.views.devices
    for i, row in ipairs(panel:rows()) do
      if row.device and row.device.id == line.id and not row.param then
        panel.row = i
        break
      end
    end
    paw.ui.focus("devices")
  end,
  plan = function(ch, ctx)
    local track = chain_track(ctx)
    local steps = {}
    local function step(text, run, quiet) steps[#steps + 1] = { text = text, run = run, quiet = quiet } end
    local function id_of(e, st) return e.id or st.made[e.row] end
    for _, e in ipairs(ch.lines) do
      if e.base and not e.copy_of and e.fields.name ~= e.base.name then
        error(
          string.format(
            "line %d: a device is called what it is: delete the line and add `%s` on one of its own",
            e.row,
            e.fields.name
          ),
          0
        )
      end
      if not e.base and not device_kind(e.fields.name) then
        error(string.format("line %d: no device `%s`: `:devices` lists them", e.row, e.fields.name), 0)
      end
      if e.fields.preset and e.base and not e.copy_of and e.fields.preset ~= e.base.preset then
        if not find_preset(e.id, e.fields.preset) then
          error(string.format("line %d: %s has no preset `%s`", e.row, e.fields.name, e.fields.preset), 0)
        end
      end
    end
    for _, d in ipairs(ch.deleted) do
      step("remove " .. quote(d.base.name), function() api.device_remove(d.id) end)
    end
    --- The line's settings on the device, those that differ from `base`.
    local function settle(e, base)
      local f = e.fields
      if f.on ~= (base and base.on) then
        step(
          string.format("%s: %s", quote(f.name), f.on and "on" or "off (bypassed)"),
          function(st) api.device_set(id_of(e, st), "bypass", not f.on) end
        )
      end
      if f.wet and f.wet ~= (base and base.wet) then
        step(
          string.format("%s: wet %s%%", quote(f.name), wet_text(f.wet)),
          function(st) api.device_set_param(id_of(e, st), "fx_wet", f.wet) end
        )
      end
      if f.preset ~= (base and base.preset) then
        if f.preset then
          step(
            string.format("%s: preset %s", quote(f.name), quote(f.preset)),
            function(st) paw.fx.load(id_of(e, st), f.preset) end
          )
        else
          step(string.format("%s: forget the preset's name", quote(f.name)), function(st)
            local id = id_of(e, st)
            local meta = api.device_get(id).meta or {}
            meta.preset = nil
            api.device_set(id, "meta", meta)
          end)
        end
      end
    end
    for _, e in ipairs(ch.changed) do
      settle(e, e.base)
    end
    for _, e in ipairs(ch.lines) do
      if e.copy_of then
        step(
          "copy " .. quote(e.base.name),
          function(st) st.made[e.row] = paw.restore_device(paw.device(e.copy_of):snapshot(), track).id end
        )
        settle(e, e.base)
      elseif not e.id then
        local kind = device_kind(e.fields.name)
        step("add " .. kind, function(st) st.made[e.row] = paw.track(track):add_device(kind).id end)
        settle(e, { on = true, wet = 100 })
      end
    end
    if ch.moved or #ch.copied > 0 or #ch.added > 0 then
      if ch.moved then step("put the chain in the order of the lines", nil) end
      step("order the devices", function(st)
        local i = 0
        for _, e in ipairs(ch.lines) do
          local id = id_of(e, st)
          if id then
            i = i + 1
            api.device_move(id, track, i)
          end
        end
      end, true)
    end
    return steps
  end,
})

-- paw://markers -------------------------------------------------------------------------------

--- `bar.beat`, with hundredths of a beat when it is not on one.
local function position_text(beat)
  local bar, b, frac = api.tempo_bbt(beat)
  local part = math.floor(frac * 100 + 0.5)
  if part >= 100 then part = 99 end
  if part == 0 then return string.format("%d.%d", bar + 1, b + 1) end
  return string.format("%d.%d.%02d", bar + 1, b + 1, part)
end

local function parse_position(text)
  local bar, beat, part = text:match("^(%d+)%.?(%d*)%.?(%d*)$")
  if not bar or tonumber(bar) < 1 then error("a position is bar.beat, like 5.1, or bar.beat.hundredths", 0) end
  local at = paw.time.bar_start(tonumber(bar))
  local _, den = api.tempo_signature(at)
  local unit = 4 / (den or 4)
  return at + ((tonumber(beat) or 1) - 1 + (tonumber(part) or 0) / 100) * unit
end

local function parse_marker(text)
  local list = cells(text)
  if #list == 0 then return nil, "an empty line" end
  local ok, beat = pcall(parse_position, list[1].text)
  if not ok then return nil, beat end
  local f = { beat = beat, name = "" }
  local named = false
  for i = 2, #list do
    local cell = list[i].text
    local to = cell:match("^to%s+(.+)$")
    local colour = cell:match("^colou?r%s+(.+)$")
    if to then
      local fine, finish = pcall(parse_position, to)
      if not fine then return nil, finish end
      f.finish = finish
    elseif colour then
      if not colour:match("^#%x%x%x%x%x%x$") and colour:lower() ~= "none" then return nil, "a colour is #rrggbb" end
      f.color = colour:lower() ~= "none" and colour:lower() or nil
    elseif not named then
      f.name, named = unquote(cell), true
    else
      return nil, "`" .. cell .. "` is not a field: where it is, the name, to and where a region ends, color"
    end
  end
  if f.finish and f.finish <= f.beat + 1e-9 then return nil, "a region ends after it starts" end
  return f
end

local function marker_text(f)
  return (f.finish and "region " or "marker ")
    .. (f.name ~= "" and quote(f.name) .. " " or "")
    .. "at "
    .. position_text(f.beat)
end

tb.kind("markers", {
  title = function() return "Markers and regions" end,
  keywords = { to = true, color = true },
  first_style = "Marker",
  hint = "edit the markers and `:w` · `o` and `5.1  Chorus` adds one, `to 9.1` makes it a region · Enter goes there",
  style = function(cell, i)
    if i == 1 then return "Marker" end
    if i == 2 and not cell:match("^to ") and not cell:match("^colou?r ") then return "RegionName" end
  end,
  read = function()
    local out = {}
    for i, m in ipairs(paw.markers.list()) do
      out[i] = { id = m.id, marker = m }
    end
    return out
  end,
  format = function(item)
    local m = item.marker
    return {
      position_text(m.beat),
      m.name ~= "" and quote(m.name) or "",
      m.length and "to " .. position_text(m.beat + m.length) or "",
      m.color and "color " .. m.color or "",
    }
  end,
  parse = parse_marker,
  open = function(_, line, text)
    local f = parse_marker(text)
    if not f then return end
    paw.cursor.set_beat(f.beat)
    paw.notify(marker_text(f))
  end,
  plan = function(ch)
    local steps = {}
    for _, d in ipairs(ch.deleted) do
      steps[#steps + 1] = { text = "delete the " .. marker_text(d.base), run = function() paw.markers.remove(d.id) end }
    end
    for _, e in ipairs(ch.changed) do
      local f = e.fields
      steps[#steps + 1] = {
        text = "change the " .. marker_text(e.base) .. " to " .. marker_text(f),
        run = function()
          paw.markers.set(
            e.id,
            { beat = f.beat, name = f.name, length = f.finish and f.finish - f.beat or false, color = f.color or false }
          )
        end,
      }
    end
    for _, e in ipairs(ch.lines) do
      if not e.base or e.copy_of then
        local f = e.fields
        steps[#steps + 1] = {
          text = "add the " .. marker_text(f),
          run = function()
            paw.markers.add(f.beat, f.name, { length = f.finish and f.finish - f.beat or nil, color = f.color })
          end,
        }
      end
    end
    return steps
  end,
})
