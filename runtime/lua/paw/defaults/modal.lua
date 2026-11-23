-- The default commands and keys: modal editing. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local api = paw.api
local command = paw.command
local cursor = paw.cursor
local keymap = paw.keymap
local common = require("paw.defaults.common")
local need_track = common.need_track

command(
  "visual",
  function(ctx) keymap.visual_start(ctx.args[1] == "line" and "V" or ctx.args[1] == "block" and "b" or "v") end,
  { desc = "Start or stop selecting: `visual`, `visual line`, `visual block`" }
)
-- `normal` is an Ex command, with a range or without: paw/ex.tl.
command("search", function(ctx)
  local function go(text)
    if text == "" then return end
    keymap.push_jump()
    keymap.search(text, 1)
  end
  if ctx.args[1] then return go(table.concat(ctx.args, " ")) end
  paw.ui.input({ prompt = "/", history = "search" }, go)
end, { desc = "Find a clip or track by name: `search chorus`; `n` and `N` go on to the next and previous" })
command("registers", function()
  local lines = {}
  local names = {}
  for name in pairs(keymap.registers) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local value, what = keymap.registers[name]
    if value.kind == "keys" then
      what = "macro   " .. value.keys
    elseif value.kind == "tracks" then
      local list = {}
      for i, t in ipairs(value.tracks) do
        list[i] = t.name
      end
      what = "tracks  " .. table.concat(list, ", ")
    elseif value.kind == "range" then
      local clips = 0
      for _, row in ipairs(value.rows) do
        clips = clips + #row
      end
      what = string.format(
        "time    %g beats on %d track%s, %d clip%s",
        value.length,
        #value.rows,
        #value.rows == 1 and "" or "s",
        clips,
        clips == 1 and "" or "s"
      )
    elseif value.kind == "notes" then
      what = string.format("notes   %d over %g beats", #value.notes, value.length)
    elseif value.kind == "device" then
      what = "device  " .. value.device.kind
    else
      what = value.kind
    end
    lines[#lines + 1] = string.format('"%s  %s', name, what)
  end
  if #lines == 0 then lines[1] = "Nothing yanked or recorded yet." end
  paw.ui.page("Registers", lines)
end, { desc = "Show what the registers hold" })
command("marks", function()
  local lines = {}
  for view, list in pairs({ arrange = keymap.marks("arrange"), pianoroll = keymap.marks("pianoroll") }) do
    local names = {}
    for name in pairs(list) do
      names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
      local pos = list[name]
      local where = view == "arrange"
          and paw.time.format(pos.beat) .. "  " .. (pcall(api.track_get, pos.track) and api.track_get(pos.track, "name") or "(track gone)")
        or paw.music.name(pos[1]) .. "  beat " .. pos[2] + 1
      lines[#lines + 1] = string.format("%s  %-10s %s", name, view, where)
    end
  end
  if #lines == 0 then lines[1] = "No marks. `ma` sets mark a at the cursor, `'a` goes back to it." end
  paw.ui.page("Marks", lines)
end, { desc = "List the marks" })
command("changes", function()
  local lines = {}
  local list = keymap.changes()
  for i = #list, 1, -1 do
    local pos = list[i]
    local where = pos.beat
        and paw.time.format(pos.beat) .. "  " .. (pcall(api.track_get, pos.track) and api.track_get(pos.track, "name") or "(track gone)")
      or string.format("row %d  beat %g", pos[1], (pos[2] or 0) + 1)
    lines[#lines + 1] = string.format("%3d  %s", #list - i + 1, where)
  end
  if #lines == 0 then lines[1] = "No changes yet in this view. `g;` goes to where the last edit was." end
  paw.ui.page("Changes · " .. tostring(paw.ui.focused), lines)
end, { desc = "List where the focused view's project edits happened, newest first; `g;` and `g,` walk them" })
local function remove_marks(spec, all)
  local removed, err = keymap.delmarks(spec, all)
  if not removed then return paw.notify(err, "warn") end
  if removed == 0 then return paw.notify("no such mark is set", "warn") end
  paw.notify(removed == 1 and "removed 1 mark" or "removed " .. removed .. " marks")
end
command("delmarks", function(ctx)
  if not ctx.args[1] then
    return paw.notify("usage: delmarks a b c-e; delmarks! removes every lowercase mark", "warn")
  end
  remove_marks(table.concat(ctx.args, " "))
end, {
  desc = "Remove marks: `delmarks a`, `delmarks a-d x`",
  complete = function()
    local seen, out = {}, {}
    for _, view in ipairs({ "arrange", "pianoroll" }) do
      for name in pairs(keymap.marks(view)) do
        seen[name] = true
      end
    end
    for name in pairs(seen) do
      out[#out + 1] = name
    end
    table.sort(out)
    return out
  end,
})
command("delmarks!", function() remove_marks("", true) end, { desc = "Remove every lowercase mark" })
command.alias("delm", "delmarks")
command.alias("delm!", "delmarks!")
command("info", function()
  -- A view says what is under its own cursor first (`view:describe()`);
  -- with `only` set, that is all there is to say.
  local view = paw.ui.views:get(paw.ui.focused)
  local first = view and view.describe and view:describe() or nil
  if first and first.only then return paw.ui.page(first.title or "Under the cursor", first) end
  local track = need_track()
  if not track then return end
  local t, lines = track:get(), first or {}
  local clip = cursor.clip()
  if clip then
    local c = clip:get()
    lines[#lines + 1] = { text = "Clip  " .. c.name, style = "Title" }
    lines[#lines + 1] = string.format(
      "  %s to %s, %g beats%s",
      paw.time.format(c.start),
      paw.time.format(c.start + c.length),
      c.length,
      c.muted and ", muted" or ""
    )
    if c.kind == "nest" then
      -- A block of a subproject.
      lines[#lines + 1] = "  " .. paw.nest.describe(c)
    elseif c.kind == "midi" then
      lines[#lines + 1] = string.format("  %d notes", c.note_count)
      if c.link then lines[#lines + 1] = string.format("  linked: %s, %d clips", c.link, c.link_count) end
      local overrides = common.overrides_text(c)
      if overrides then lines[#lines + 1] = "  plays with " .. overrides end
      -- A clip from a file outside the project, or a copy of one.
      if c.source then
        lines[#lines + 1] = string.format("  refers to %s%s", c.source, c.offline and " (missing)" or "")
      end
      if c.origin then lines[#lines + 1] = string.format("  copied from %s", c.origin) end
    else
      lines[#lines + 1] = string.format("  %s", c.file)
      lines[#lines + 1] = string.format("  from %.3f s into the file, gain %+.1f dB", c.offset, c.gain)
    end
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = { text = "Track  " .. t.name, style = "Title" }
  -- A track or a chain from outside the project, or a copy of one.
  if t.source then lines[#lines + 1] = "  refers to " .. t.source end
  if t.origin then lines[#lines + 1] = "  copied from " .. t.origin end
  if t.chain_source then lines[#lines + 1] = "  devices from " .. t.chain_source end
  if t.chain_origin then lines[#lines + 1] = "  devices copied from " .. t.chain_origin end
  local kind = paw.track_kinds.describe(track.id)
  if kind then lines[#lines + 1] = "  kind    " .. kind end
  -- A frozen track: whether its file is up to date (paw/freeze.lua).
  local frozen = paw.freeze.describe(track.id)
  if frozen then lines[#lines + 1] = "  " .. frozen end
  -- What the parts of the track column say of it (paw/trackcolumn.tl).
  for _, line in ipairs(paw.trackcolumn.describe(track.id)) do
    lines[#lines + 1] = "  " .. line
  end
  lines[#lines + 1] = string.format(
    "  volume %+.1f dB, pan %+.2f%s%s%s",
    t.volume,
    t.pan,
    t.mute and ", muted" or "",
    t.solo and ", solo" or "",
    t.armed and ", armed" or ""
  )
  lines[#lines + 1] = "  output  " .. (t.output and api.track_get(t.output, "name") or "Master")
  if t.input then lines[#lines + 1] = "  input   " .. t.input end
  for _, send in ipairs(t.sends) do
    lines[#lines + 1] = string.format("  send    %s at %+.1f dB", api.track_get(send.target, "name"), send.level)
  end
  for i, device in ipairs(track:devices()) do
    local d = device:get()
    lines[#lines + 1] = string.format("  %d. %s%s", i, d.name, d.bypass and "  (bypassed)" or "")
  end
  -- MIDI with nothing to play it is silent: say so, and how to fix it.
  local midi = false
  for _, c in ipairs(track.id ~= 0 and api.clip_list(track.id) or {}) do
    midi = midi or c.kind == "midi"
  end
  if
    midi
    and not kind
    and not (t.midi_output and t.midi_output.port)
    and paw.fx.preferred(track.id) == "instrument"
  then
    lines[#lines + 1] =
      { text = "  no instrument: its MIDI makes no sound. Press `a` and choose one (synth, a plugin)", style = "Warn" }
  end
  for _, lane in ipairs(api.lane_list(track.id)) do
    lines[#lines + 1] = string.format(
      "  automation  %s, %d points%s",
      lane.param or lane.target,
      lane.point_count,
      lane.enabled and "" or ", off"
    )
  end
  paw.ui.page("Under the cursor", lines)
end, { desc = "Describe what is under the cursor: a fold or the scope, the clip, the track" })
command("wq", function(ctx)
  paw.commands.run("write", ctx.args)
  api.quit(0)
end, { desc = "Save the project and quit" })
command.alias("x", "wq")
command.alias("reg", "registers")
