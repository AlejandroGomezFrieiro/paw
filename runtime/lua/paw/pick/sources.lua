-- The pickers that come with the runtime. Each is a table of the fields
-- `paw.pick` takes, with a `desc`, or a function that returns one; add your
-- own to `paw.pick.sources` the same way.
return function(pick)
  local api = paw.api
  local S = {}

  local function need_track()
    local track = paw.cursor.track()
    if not track then paw.notify("no track selected", "warn") end
    return track
  end

  local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

  -- Pickers ------------------------------------------------------------------------

  S.pickers = {
    desc = "Every picker",
    title = "Pickers",
    items = function()
      local out = {}
      for name, source in pairs(pick.sources) do
        if name ~= "pickers" and not name:match("^_") then
          local desc = type(source) == "table" and (source.desc or source.title) or ""
          out[#out + 1] = { name = name, desc = desc }
        end
      end
      table.sort(out, function(a, b) return a.name < b.name end)
      return out
    end,
    format = function(s) return string.format("%-14s %s", s.name, s.desc) end,
    on_choose = function(s) pick(s.name) end,
  }

  -- Commands -----------------------------------------------------------------------

  --- Every key that runs a command, by the command's name: lists of
  --- `lhs` strings, with the view in brackets for a view's own.
  local function key_index()
    local index = {}
    for _, mode in ipairs({ "n", "x" }) do
      for _, scope in ipairs({ paw.ui.focused, "arrange", "pianoroll", "devices", "mixer" }) do
        for _, map in ipairs(paw.keymap.list(mode, scope)) do
          if type(map.rhs) == "string" then
            local name = map.rhs:match("^(%S+)")
            local key = map.lhs .. (map.scope ~= "global" and " (" .. map.scope .. ")" or "")
            local list = index[name] or {}
            index[name] = list
            if not list[key] then
              list[key] = true
              list[#list + 1] = key
            end
          end
        end
      end
    end
    -- The shortest key first: `u` before `Ctrl-z`.
    for _, list in pairs(index) do
      for i, key in ipairs(list) do list[i] = { key = key, n = i } end
      table.sort(list, function(a, b)
        local la, lb = #paw.keymap.human((a.key:gsub(" %(.*%)$", ""))), #paw.keymap.human((b.key:gsub(" %(.*%)$", "")))
        if la ~= lb then return la < lb end
        return a.n < b.n
      end)
      for i, entry in ipairs(list) do list[i] = entry.key end
    end
    return index
  end

  local keys_now = {}

  --- Keys that run a command, as `lhs` strings.
  local function keys_for(name)
    return keys_now[name] or {}
  end

  --- The commands the focused view has keys of its own for, by name.
  local function view_commands()
    local out = {}
    local view = paw.ui.focused
    for _, mode in ipairs({ "n", "x" }) do
      for _, map in ipairs(paw.keymap.list(mode, view)) do
        if map.scope == view and type(map.rhs) == "string" then out[map.rhs:match("^(%S+)")] = true end
      end
    end
    return out
  end

  local view_set = {}

  local function edit_command(spec)
    paw.ui.input({ prompt = ":", history = "cmdline", text = spec.name .. " " }, function(line)
      if line:match("%S") then paw.state.last_cmdline = line paw.commands.used(line:match("^%s*:?(%S+)")) end
      paw.commands.exec(line)
    end)
  end

  S.commands = {
    desc = "Run a command",
    title = "Commands",
    items = function()
      keys_now = key_index()
      view_set = view_commands()
      return paw.commands.list()
    end,
    format = function(spec)
      local keys = keys_for(spec.alias_of or spec.name)
      local key = keys[1] and paw.keymap.human((keys[1]:gsub(" %(.*%)$", ""))) or ""
      return string.format("%-24s %-10s %s", spec.name, key, spec.alias_of and "→ " .. spec.alias_of or spec.desc)
    end,
    primary = function(spec) return spec.name end,
    -- Commands used before come first, and those the focused view has keys for.
    boost = function(spec)
      local name = spec.alias_of or spec.name
      return math.min(paw.commands.uses(name), 10) * 8 + (view_set[name] and 40 or 0)
    end,
    on_choose = function(spec)
      paw.state.last_cmdline = spec.name
      paw.commands.used(spec.name)
      paw.commands.run(spec.name)
    end,
    actions = {
      ["<C-e>"] = { fn = function(spec) if spec then edit_command(spec) end end, desc = "edit arguments" },
      ["<C-]>"] = { fn = function(spec) if spec then paw.help.for_command(spec.alias_of or spec.name) end end, desc = "help" },
    },
    preview = function(spec)
      local lines = { { text = spec.name, style = "Title" }, "" }
      for line in (spec.desc ~= "" and spec.desc or "(no description)"):gmatch("[^\n]+") do lines[#lines + 1] = line end
      if spec.alias_of then lines[#lines + 1] = "Another name for " .. spec.alias_of end
      local keys = keys_for(spec.alias_of or spec.name)
      if #keys > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = { text = "Keys", style = "HelpSection" }
        for _, key in ipairs(keys) do
          local lhs, where = key:match("^(.-)( %(.*%))$")
          lines[#lines + 1] = "  " .. paw.keymap.human(lhs or key) .. (where or "")
        end
      end
      lines[#lines + 1] = ""
      lines[#lines + 1] = { text = "C-e types it on the command line, for arguments", style = "Dim" }
      return lines
    end,
  }

  -- Key mappings -------------------------------------------------------------------

  -- What a key is for, in a few letters: where it works and what kind it is.
  local kind_tags = { motion = "motion", operator = "operator", object = "object", visual = "visual", insert = "insert" }

  local function key_tag(entry)
    if entry.other then return entry.other .. " view" end
    local where = entry.map.scope == "global" and "global" or entry.map.scope:gsub("^%a+%.", "")
    local kind = kind_tags[entry.kind]
    return kind and where .. " " .. kind or where
  end

  --- Run a mapping chosen in the keys picker, as if its keys were typed.
  local function run_key(entry)
    local map = entry.map
    if entry.other then
      paw.ui.focus(entry.other)
      return paw.notify(paw.keymap.human(map.lhs) .. " is a key of the " .. entry.other .. " view, which has the keys now")
    end
    if entry.kind == "object" then
      return paw.notify(paw.keymap.human(map.lhs) .. " names a region: type it after an operator such as `d` or `y`, or in a selection")
    end
    if entry.kind == "insert" then
      return paw.notify(paw.keymap.human(map.lhs) .. " works in insert mode: `i` first")
    end
    if entry.kind == "visual" and paw.keymap.mode ~= "x" then
      return paw.notify(paw.keymap.human(map.lhs) .. " acts on a selection: `v` or `V` first")
    end
    paw.keymap.normal(map.lhs)
  end

  S.keys = function()
    local view = paw.ui.focused
    -- The picker is as wide as the screen allows, the list on the left
    -- and, beside it, the help of the key chosen.
    -- (A window's main area is wider than the screen the kernel keeps for it.)
    local cells = paw.panes.cells()
    local total = math.min(150, math.max((api.ui_size()), cells and cells.w or 0) - 4)
    local list_w = math.floor(total * 0.6)
    local preview_w = total - list_w - 3
    local cols = { key = 8, tag = 4, desc = 10 }
    return {
      desc = "Every key that works in the focused view",
      title = "Keys · " .. tostring(view),
      empty = "No keys are mapped here.",
      width = total,
      choose = "run",
      -- The view's own keys before the global ones, and those before the keys of other views.
      boost = function(entry) return entry.other and 0 or entry.map.scope == "global" and 20 or 40 end,
      items = function()
        -- Ranked rather than alphabetical: what the view itself adds, then
        -- what works everywhere; plain keys before motions, operators and
        -- the rest; short keys before long ones.
        local rank = { key = 1, operator = 2, motion = 3, object = 4, visual = 5, insert = 6 }
        local out, seen = {}, {}
        for _, entry in ipairs(paw.keymap.all(view)) do
          local map = entry.map
          entry.human = paw.keymap.human(map.lhs)
          entry.desc = map.desc or (type(map.rhs) == "string" and map.rhs) or "(no description)"
          entry.tag = key_tag(entry)
          -- Keys that do the same thing in the same place are one line.
          local same = entry.tag .. "\t" .. entry.desc .. "\t" .. tostring(map.rhs)
          local first = seen[same]
          if first then
            if not first.humans[entry.human] then
              first.humans[entry.human] = true
              first.human = first.human .. ", " .. entry.human
            end
          else
            entry.humans = { [entry.human] = true }
            seen[same] = entry
            out[#out + 1] = entry
          end
        end
        table.sort(out, function(a, b)
          local ga, gb = a.map.scope == "global" and 1 or 0, b.map.scope == "global" and 1 or 0
          if ga ~= gb then return ga < gb end
          if rank[a.kind] ~= rank[b.kind] then return (rank[a.kind] or 9) < (rank[b.kind] or 9) end
          if #a.map.keys ~= #b.map.keys then return #a.map.keys < #b.map.keys end
          local la, lb = a.map.lhs:match("^%a") and 0 or 1, b.map.lhs:match("^%a") and 0 or 1
          if la ~= lb then return la < lb end
          return a.map.lhs:lower() .. a.map.lhs < b.map.lhs:lower() .. b.map.lhs
        end)
        -- After them, the keys of the other views, so that a search for what
        -- a key does finds it wherever it works: `send` in the mixer finds
        -- the arrange view's `<leader>s`.
        local names = {}
        for name, v in pairs(paw.ui.views) do
          if name ~= view and v.focusable ~= false and not v.modal then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do
          for _, map in ipairs(paw.keymap.list("n", name)) do
            if map.scope == name and not map.motion and map.desc then
              out[#out + 1] = { map = map, kind = "key", other = name, human = paw.keymap.human(map.lhs), desc = map.desc }
              out[#out].tag = key_tag(out[#out])
            end
          end
        end
        -- The columns are as wide as what they hold, the description
        -- keeping what the others leave.
        local longest = 0
        cols.key, cols.tag = 8, 4
        for _, e in ipairs(out) do
          cols.key = math.max(cols.key, math.min(14, api.str_width(e.human)))
          cols.tag = math.max(cols.tag, api.str_width(e.tag))
          longest = math.max(longest, api.str_width(e.desc))
        end
        cols.desc = math.max(10, math.min(longest, list_w - 3 - cols.key - cols.tag - 2))
        return out
      end,
      format = function(e)
        return paw.util.fit(e.human, cols.key) .. " " .. paw.util.fit(e.desc, cols.desc) .. " " .. e.tag
      end,
      -- What the manual says of the key, or what it is for.
      preview = function(e)
        local lines = paw.help.excerpt_for_map(e.map, preview_w, 24)
        if lines then return lines end
        return { { text = e.human, style = "HelpKey" }, "", e.desc, "", { text = "the manual has nothing on it yet", style = "Dim" } }
      end,
      primary = function(e) return e.human end,
      -- The whole description, not the part that the width leaves.
      search = function(e) return e.human .. " " .. e.desc .. " " .. e.tag end,
      on_choose = run_key,
      actions = { ["<C-]>"] = { fn = function(e) if e then paw.help.for_map(e.map) end end, desc = "help" } },
    }
  end

  -- Tracks and clips ---------------------------------------------------------------

  local function track_name(id)
    local ok, t = pcall(api.track_get, id)
    return ok and t.name or "?"
  end

  S.tracks = {
    desc = "Go to a track",
    title = "Tracks",
    items = function()
      local out = {}
      for i, id in ipairs(paw.scope.tracks()) do out[#out + 1] = { id = id, index = i, name = track_name(id) } end
      return out
    end,
    format = function(t) return string.format("%2d  %s", t.index, t.name) end,
    location = function(t) return paw.address.track(t.id) end,
    on_choose = function(t)
      paw.keymap.push_jump()
      paw.cursor.set_track(t.id)
      if paw.ui.views.arrange.center then paw.ui.views.arrange:center() end
    end,
    delete = function(list)
      api.undo_label(#list == 1 and "Remove the track" or "Remove tracks")
      for _, t in ipairs(list) do
        if pcall(api.track_get, t.id) then api.track_remove(t.id) end
      end
    end,
    -- What the track plays around the cursor, heard when asked for.
    audition_key = "tracks",
    audition_default = false,
    audition = function(t) return t.name .. " · " .. paw.audition.through(t.id) end,
    preview = function(t)
      local info = api.track_get(t.id)
      local lines = { { text = info.name, style = "Title" }, "" }
      lines[#lines + 1] = string.format("volume %+.1f dB, pan %+.2f%s%s", info.volume, info.pan, info.mute and ", muted" or "", info.solo and ", solo" or "")
      lines[#lines + 1] = "output  " .. (info.output and track_name(info.output) or "Master")
      for i, id in ipairs(info.devices) do lines[#lines + 1] = string.format("%d. %s", i, api.device_get(id).name) end
      local clips = api.clip_list(t.id)
      lines[#lines + 1] = ""
      lines[#lines + 1] = plural(#clips, "clip")
      for _, c in ipairs(clips) do lines[#lines + 1] = string.format("  %-10s %s", paw.time.format(c.start), c.name) end
      return lines
    end,
  }

  S.clips = {
    desc = "Go to a clip",
    title = "Clips",
    items = function()
      local out = {}
      for _, id in ipairs(paw.scope.tracks()) do
        local name = track_name(id)
        for _, c in ipairs(api.clip_list(id)) do
          out[#out + 1] = { id = c.id, track = id, track_name = name, name = c.name, start = c.start, length = c.length, kind = c.kind }
        end
      end
      return out
    end,
    format = function(c) return string.format("%-20s %-14s %s", c.name, c.track_name, paw.time.format(c.start)) end,
    location = function(c) return paw.address.clip(c.id) end,
    on_choose = function(c)
      paw.keymap.push_jump()
      paw.ui.focus("arrange")
      paw.cursor.set_track(c.track)
      paw.cursor.set_beat(c.start)
      paw.ui.views.arrange:center()
    end,
    delete = function(list)
      api.undo_label(#list == 1 and "Remove the clip" or "Remove clips")
      for _, c in ipairs(list) do
        if pcall(api.clip_get, c.id) then api.clip_remove(c.id) end
      end
    end,
    -- A MIDI clip's notes drawn as a small piano roll, an audio clip's sound.
    preview = function(c, width, height)
      local info = api.clip_get(c.id)
      local lines = {
        { text = info.name, style = "Title" },
        "track   " .. c.track_name,
        string.format("from    %s to %s, %g beats%s", paw.time.format(info.start), paw.time.format(info.start + info.length), info.length, info.muted and ", muted" or ""),
        info.kind == "midi" and plural(info.note_count, "note") or "audio   " .. tostring(info.file),
        "",
      }
      local drawn = require("paw.pick.preview").clip(c.id, width or 40, math.max(4, (height or 20) - #lines - 3))
      for _, line in ipairs(drawn) do lines[#lines + 1] = line end
      return lines
    end,
    -- Heard: an audio clip's file; a MIDI clip's first bars through its track.
    audition_key = "clips",
    audition = function(c)
      local info = api.clip_get(c.id)
      if info.kind == "audio" then
        paw.audition.file(info.file)
        return info.name
      end
      local length = math.min(info.length, paw.time.bar(info.start) * 2)
      local notes = {}
      for _, n in ipairs(api.clip_notes(c.id)) do
        if n.start >= 0 and n.start < length then
          notes[#notes + 1] = { pitch = n.pitch, start = n.start, length = n.length, velocity = n.velocity }
        end
      end
      paw.audition.phrase(c.track, notes, { length = length, label = info.name, key = "clip" .. c.id })
      return string.format("%s · %g beats on %s", info.name, length, c.track_name)
    end,
  }

  -- Devices ------------------------------------------------------------------------

  local typed -- what was typed in the device picker, remembered with the choice
  local wanted -- the kind of device the track most likely needs, listed first
  S.devices = {
    desc = "Add a device or plugin to the track",
    title = "Add a device",
    -- Favourites first, then the ones used last; `@instrument`, `@clap`,
    -- `@fav` or `@<vendor>` typed filter (see `paw.fx.rank`).
    items = function()
      wanted = paw.fx.preferred(paw.cursor.track_id())
      return paw.fx.device_list(wanted)
    end,
    format = function(info) return paw.fx.device_line(info) end,
    rank = function(info, query, line)
      typed = query
      return paw.fx.rank(info, query, line, wanted)
    end,
    on_choose = function(info)
      local track = need_track()
      if not track then return end
      paw.fx.add(track, info.kind, { query = typed })
      paw.notify("added " .. info.name .. " to " .. track.name)
    end,
    -- Heard on the track, with what it plays around the cursor: added as a
    -- trial, taken away again unless chosen. A plugin is made apart, so
    -- the selection rests on it longer first.
    audition = function(info)
      local track = paw.cursor.track()
      if not track then return "no track to try it on" end
      local device = paw.audition.try(function() return paw.fx.place(track, info.kind) end)
      return {
        label = info.name .. " · " .. paw.audition.through(track.id),
        loading = function()
          local ok, d = pcall(api.device_get, device.id)
          return ok and d.status == "loading"
        end,
        keep = function()
          paw.fx.added(device, info.kind, { query = typed })
          paw.notify("added " .. info.name .. " to " .. track.name)
        end,
      }
    end,
    audition_delay = function(info, ms) return info.format ~= "builtin" and math.max(ms, 600) or ms end,
    actions = {
      ["<C-f>"] = { desc = "favourite", fn = function(info, query)
        if info then paw.fx.toggle_favourite(info.kind) end
        paw.pick("devices", { query = query })
      end },
      ["<C-t>"] = { desc = "instruments/effects", fn = function(_, query)
        -- Step the filter: none, instruments, effects.
        local q = query:gsub("%s*@instrument", ""):gsub("%s*@effect", "")
        local was = query:find("@instrument") and 1 or query:find("@effect") and 2 or 0
        local tag = ({ [0] = " @instrument", [1] = " @effect", [2] = "" })[was]
        paw.pick("devices", { query = (q .. tag):gsub("^%s+", "") })
      end },
    },
    preview = function(info)
      local lines = {
        { text = info.name, style = "Title" }, "",
        "kind     " .. info.kind,
        "format   " .. info.format .. (info.category and info.category ~= "" and ", " .. info.category or ""),
      }
      if info.favourite then lines[#lines + 1] = "a favourite (Ctrl-f)" end
      if info.vendor and info.vendor ~= "" then lines[#lines + 1] = "vendor   " .. info.vendor end
      local params = info.params or {}
      if #params > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = { text = plural(#params, "parameter"), style = "HelpSection" }
        for i, p in ipairs(params) do
          if i > 30 then break end
          lines[#lines + 1] = "  " .. p.name
        end
      end
      return lines
    end,
  }

  S.track_devices = {
    desc = "Devices on the track: show one in the device panel",
    title = "Devices on the track",
    empty = "No devices on this track. `<leader>fa` adds one.",
    items = function()
      local track, out = paw.cursor.track(), {}
      for i, device in ipairs(track and track:devices() or {}) do
        local d = device:get()
        out[#out + 1] = { id = d.id, index = i, name = d.name, kind = d.kind, bypass = d.bypass }
      end
      return out
    end,
    format = function(d) return string.format("%d. %s%s", d.index, d.name, d.bypass and "  (bypassed)" or "") end,
    on_choose = function(d)
      local panel = paw.ui.views.devices
      paw.ui.focus("devices")
      for i, row in ipairs(panel:rows()) do
        if row.device.id == d.id and not row.param and not row.picture then panel.row = i end
      end
      api.ui_redraw()
    end,
    actions = {
      ["<C-e>"] = { fn = function(d) if d then api.device_editor(d.id) end end, desc = "plugin window" },
    },
    preview = function(d)
      local info = api.device_get(d.id)
      local lines = { { text = info.name, style = "Title" }, "", "kind   " .. info.kind, "" }
      for i, p in ipairs(info.param_info) do
        if i > 40 then break end
        lines[#lines + 1] = string.format("%-18s %s", p.name, paw.frontend.format_value(p, info.params[p.key]))
      end
      return lines
    end,
  }

  -- Marks and registers ------------------------------------------------------------

  S.marks = {
    desc = "Go to a mark",
    title = "Marks",
    empty = "No marks. `ma` sets mark a at the cursor.",
    items = function()
      local out = {}
      for _, view in ipairs({ "arrange", "pianoroll" }) do
        local list = paw.keymap.marks(view)
        local names = {}
        for name in pairs(list) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
          local pos = list[name]
          local where
          if view == "arrange" then
            local ok, t = pcall(api.track_get, pos.track)
            where = paw.time.format(pos.beat) .. "  " .. (ok and t.name or "(track gone)")
          else
            where = paw.music.name(pos[1]) .. "  beat " .. pos[2] + 1
          end
          out[#out + 1] = { name = name, view = view, where = where }
        end
      end
      return out
    end,
    format = function(m) return string.format("%s  %-10s %s", m.name, m.view, m.where) end,
    on_choose = function(m)
      if paw.ui.focused ~= m.view then paw.ui.focus(m.view) end
      paw.keymap.goto_mark(m.name)
    end,
  }

  --- What a register holds, in a line.
  local function describe(value)
    if value.kind == "keys" then return "macro   " .. value.keys end
    if value.kind == "tracks" then
      local list = {}
      for i, t in ipairs(value.tracks) do list[i] = t.name end
      return "tracks  " .. table.concat(list, ", ")
    end
    if value.kind == "range" then
      local clips = 0
      for _, row in ipairs(value.rows) do clips = clips + #row end
      return string.format("time    %g beats on %s, %s", value.length, plural(#value.rows, "track"), plural(clips, "clip"))
    end
    if value.kind == "notes" then return string.format("notes   %d over %g beats", #value.notes, value.length) end
    if value.kind == "device" then return "device  " .. tostring(value.device.kind) end
    return tostring(value.kind)
  end

  S.registers = {
    desc = "Paste a register, or play a macro",
    title = "Registers",
    empty = "Nothing yanked or recorded yet.",
    items = function()
      local out = {}
      for name, value in pairs(paw.keymap.registers) do out[#out + 1] = { name = name, value = value } end
      table.sort(out, function(a, b) return a.name < b.name end)
      return out
    end,
    format = function(r) return string.format('"%s  %s', r.name, describe(r.value)) end,
    on_choose = function(r)
      if r.value.kind == "keys" then return paw.keymap.play(r.name) end
      paw.keymap.normal('"' .. r.name .. "P")
    end,
  }

  -- Messages -----------------------------------------------------------------------

  local levels = { info = "Normal", warn = "Warn", error = "Error" }

  S.messages = {
    desc = "Earlier messages, newest first",
    title = "Messages",
    empty = "No messages yet.",
    items = function()
      local out, list = {}, paw.ui.messages
      for i = #list, 1, -1 do out[#out + 1] = list[i] end
      return out
    end,
    format = function(m) return string.format("%-5s %s", m.level, m.text:match("^[^\n]*")) end,
    on_choose = function(m) paw.ui.page("Message", { { text = m.text, style = levels[m.level] } }) end,
    preview = function(m) return { { text = m.text, style = levels[m.level] } } end,
  }

  -- Files --------------------------------------------------------------------------

  local audio_ext = { wav = true, wave = true, aif = true, aiff = true, flac = true, mp3 = true, ogg = true }
  local skip_dir = { target = true, node_modules = true, result = true }

  local function is_project(path)
    local file = io.open(path, "rb")
    if not file then return false end
    local head = file:read(200) or ""
    file:close()
    return head:find('"version"', 1, true) ~= nil and head:find('"project"', 1, true) ~= nil
  end

  --- Project and audio files under `root`, walking at most `limit` entries.
  local function walk(root, limit)
    local out, seen = {}, 0
    local function visit(dir, prefix, depth)
      for _, entry in ipairs(api.read_dir(dir)) do
        seen = seen + 1
        if seen > limit then return end
        local name = entry.name
        local path = prefix .. name
        if entry.is_dir then
          if depth < 8 and name:sub(1, 1) ~= "." and not skip_dir[name] then visit(dir .. "/" .. name, path .. "/", depth + 1) end
        else
          local ext = (name:match("%.([^.]+)$") or ""):lower()
          if audio_ext[ext] then
            out[#out + 1] = { path = path, kind = "audio" }
          elseif paw.midifile.is_midi_file(name) then
            out[#out + 1] = { path = path, kind = "midi" }
          elseif ext == "json" and is_project(dir .. "/" .. name) then
            out[#out + 1] = { path = path, kind = "project" }
          end
        end
      end
    end
    visit(root, root == "." and "" or root .. "/", 0)
    return out
  end
  S._walk = walk

  S.files = {
    desc = "Open a project, or import audio or MIDI at the cursor",
    title = "Files",
    empty = "No project, audio or MIDI files under this directory.",
    items = function() return walk(".", 50000) end,
    format = function(f) return f.path end,
    on_choose = function(f)
      if f.kind == "project" then
        if not paw.project.guard("open") then return end
        paw.open(f.path)
        return paw.notify("opened " .. f.path)
      end
      if f.kind == "midi" then return paw.commands.run("import", { f.path }) end
      local track = need_track()
      if not track then return end
      track:add_clip({ start = paw.cursor.beat, file = f.path })
    end,
    audition_key = "files",
    audition = function(f) return pick.hear_file(f.path) end,
    preview = function(f)
      if f.kind == "project" then
        return { { text = f.path, style = "Title" }, "", "A project.", "Enter opens it in place of this one." }
      end
      if f.kind == "midi" then
        return {
          { text = f.path, style = "Title" }, "", "A MIDI file.",
          "Enter brings its tracks in at " .. paw.time.format(paw.cursor.beat) .. "; `:open` opens it as a project.",
        }
      end
      local track = paw.cursor.track()
      return {
        { text = f.path, style = "Title" }, "", "Audio.",
        "Enter adds it at " .. paw.time.format(paw.cursor.beat) .. (track and " on " .. track.name or ""),
      }
    end,
  }

  -- Options ------------------------------------------------------------------------

  S.options = {
    desc = "Set an option",
    title = "Options",
    items = function() return paw.option.list() end,
    format = function(o) return string.format("%-14s %s", o.name, tostring(paw.opt[o.name])) end,
    on_choose = function(o)
      local value = paw.opt[o.name]
      if type(value) == "boolean" then
        paw.opt[o.name] = not value
        return paw.notify(o.name .. " = " .. tostring(not value))
      end
      paw.ui.input({ prompt = o.name .. " = ", text = tostring(value) }, function(text)
        if text == "" then return end
        local value, err = paw.option.read(o.name, text)
        if value == nil then return paw.notify(err, "error") end
        paw.opt[o.name] = value
        paw.notify(o.name .. " = " .. tostring(paw.opt[o.name]))
      end)
    end,
    preview = function(o)
      return {
        { text = o.name, style = "Title" }, "",
        "now       " .. tostring(paw.opt[o.name]),
        "default   " .. tostring(o.default),
        "",
        { text = type(o.default) == "boolean" and "Enter switches it" or "Enter asks for a new value", style = "Dim" },
      }
    end,
  }

  require("paw.pick.project")(pick, S)
  return S
end
