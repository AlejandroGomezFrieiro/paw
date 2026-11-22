-- The default commands and keys: keys. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local api = paw.api
local util = paw.util
local command, map = paw.command, paw.keymap.set
local cursor, transport = paw.cursor, paw.transport
local keymap, edit = paw.keymap, paw.edit
local roll = paw.ui.views.pianoroll
local common = require("paw.defaults.common")
local motion, need_track, amap = common.motion, common.need_track, common.amap

--
-- Neovim's grammar on a timeline. Beats are the columns and tracks the lines
-- of the arrange view; a clip is a word. In the piano roll pitches are the
-- lines and a note is a word. So `dw` deletes up to the next clip, `yy` yanks
-- a track, `3>ic` nudges a clip three steps later, `.` does it again.

-- The names the key hints give to prefixes that only lead to more keys.
-- The leader keys are a noun, then a verb or an object: `<leader>f` finds,
-- `<leader>fc` finds a clip, `<leader>dd` shows the devices, `<leader>ts`
-- sends the track (docs/reference/keys.md, "The leader keys"). The
-- extensions name their own: `g` versions, `h` tutor, `n` notation, `u` utau.
keymap.group("<leader>a", "automation")
keymap.group("<leader>c", "clip", { view = "arrange" })
keymap.group("<leader>d", "devices")
keymap.group("<leader>f", "find")
keymap.group("<leader>l", "language servers")
keymap.group("<leader>m", "mix")
keymap.group("<leader>p", "project")
keymap.group("<leader>r", "markers and regions")
keymap.group("<leader>t", "tracks", { view = "arrange" })
keymap.group("<leader>T", "tempo and transport")
keymap.group("<leader>v", "views")
keymap.group("<leader>z", "scopes")
keymap.group("gr", "set a value")

local nx = { "n", "x" }
local linewise = { motion = true, linewise = true }
local far = { motion = true, jump = true }
local far_lines = { motion = true, linewise = true, jump = true }

-- Space is the leader: Space Space plays and stops, at once (no other key
-- starts with it, so it never waits).
map("<leader><Space>", "transport.toggle", { mode = nx, role = "play", desc = "Play or stop" })
map(
  "<S-CR>",
  "transport.play_other",
  { mode = nx, desc = "Play from the playhead (the other start than <Space><Space>)" }
)
map("gs", "transport.start", { mode = nx, desc = "Playhead to the start" })
map("g0", "transport.start", { mode = nx, desc = "Playhead to the start, in every view" })
map("gp", "transport.to_cursor", { mode = nx, desc = "Playhead to the cursor" })
map("gL", "transport.loop", { mode = nx, desc = "Toggle looping" })
map("gm", "transport.metronome", { mode = nx, desc = "Toggle the metronome" })
-- The metronome's: `gC` opens curves in every view.
map("gM", "countin", { mode = nx, desc = "Count a bar in before recording, or not" })
keymap.classic("gC", "countin", { mode = nx, desc = "Count a bar in before recording, or not" })
-- `K` describes what is under the cursor in every view: `:info` asks the
-- view first (`view:describe()`).
map("K", "info", { desc = "Describe what is under the cursor", role = "describe" })
map("gI", "punch", { desc = "Punch in and out: record only between two points, or not" })
map("gI", "punch selection", { mode = "x", desc = "Punch in and out over the selection" })
map("ge", "device.editor", { desc = "Show or hide the plugin's window" })
map("R", "transport.record", { desc = "Record from the cursor, or stop recording" })
map(":", "cmdline", { mode = nx, desc = "Type a command" })
map("?", "pick.keys", { mode = nx, desc = "Show key mappings" })
map("u", "undo", { desc = "Undo", repeatable = false })
map("<C-r>", "redo", { desc = "Redo", repeatable = false })
map(".", function(ctx) keymap.repeat_last(ctx.count) end, { desc = "Repeat the last change", repeatable = false })
map(
  "q",
  function(ctx) keymap.record(ctx.char) end,
  { mode = nx, char = true, record = true, desc = "Record keys into a register; `q` again stops" }
)
--- `@19|`: bar 19 of the song, whatever bar a scope (`paw.scope`) shows
--- there. The digits after `@` are read until `|`.
local function song_bar(digits)
  require("paw.views.cmdline").ask_key("@" .. digits, function(key)
    if key:match("^%d$") then return song_bar(digits .. key) end
    if key ~= "|" then return paw.notify("`@" .. digits .. "` goes to a bar of the song with `|`: `@19|`", "warn") end
    keymap.push_jump()
    cursor.set_beat(paw.time.bar_start(tonumber(digits)))
  end)
end
map("@", function(ctx)
  if ctx.char:match("^%d$") then
    song_bar(ctx.char)
  elseif ctx.char == ":" then
    for _ = 1, ctx.count or 1 do
      paw.commands.exec(paw.state.last_cmdline or "")
    end
  else
    keymap.play(ctx.char, ctx.count)
  end
end, {
  mode = nx,
  char = true,
  repeatable = false,
  desc = "Play the keys in a register; `@@` the last one, `@:` the last command; `@19|` bar 19 of the song",
})
map("m", function(ctx) keymap.mark(ctx.char) end, { char = true, desc = "Set a mark at the cursor" })
map(
  "'",
  function(ctx) keymap.goto_mark(ctx.char) end,
  { motion = true, char = true, desc = "Go to a mark; `''` goes back, `'.` to the last edit" }
)
map(
  "`",
  function(ctx) keymap.goto_mark(ctx.char) end,
  { motion = true, char = true, desc = "Go to a mark; `` `. `` goes to the last edit" }
)
map("g;", function(ctx) keymap.change(ctx.count or 1) end, { desc = "Back to where the project was edited before" })
map("g,", function(ctx) keymap.change(-(ctx.count or 1)) end, { desc = "Forward again through the edits" })
map("<C-o>", function(ctx) keymap.jump(ctx.count or 1) end, { desc = "Back to where the cursor jumped from" })
map("<C-i>", function(ctx) keymap.jump(-(ctx.count or 1)) end, { desc = "Forward again" })
map("v", function() keymap.visual_start("v") end, { mode = nx, desc = "Select a stretch of time" })
map("V", function() keymap.visual_start("V") end, { mode = nx, desc = "Select whole rows" })
map("<C-v>", function() keymap.visual_start("b") end, { mode = nx, desc = "Select a block" })
map("gv", keymap.visual_restore, { desc = "Select what was selected last" })
map("o", keymap.visual_swap, { mode = "x", desc = "Go to the other end of the selection" })
map("/", "search", { mode = nx, desc = "Find by name" })
map("n", function(ctx) keymap.search_next(1, ctx.count) end, util.merge(far, { desc = "Next match" }))
map("N", function(ctx) keymap.search_next(-1, ctx.count) end, util.merge(far, { desc = "Previous match" }))
map("<Tab>", "view.next", { mode = nx, desc = "Focus the next view" })
map("<S-Tab>", "view.prev", { mode = nx, desc = "Focus the previous view" })
-- Windows and tabs (`Ctrl-w`, `gt`) are mapped in paw/layout.tl.
map("<leader>mm", "view.toggle mixer", { desc = "Show or hide the mixer" })
map("<leader>dd", "view.toggle devices", { desc = "Show or hide the device panel" })
map("<leader>vm", "view.toggle mixer", { desc = "Show or hide the mixer" })
map("<leader>vd", "view.toggle devices", { desc = "Show or hide the device panel" })
map("<leader>vp", "roll.toggle", { desc = "Show or hide the piano roll, on the clip under the cursor" })
-- Tempo and transport. `gm` and `gM` do the same without the leader.
map("<leader>Tm", "transport.metronome", { desc = "Turn the metronome on or off" })
map("<leader>Tc", "countin", { desc = "Count a bar in before recording, or not" })
-- Markers and regions. `g'`, `gx` and `gX` do some of the same in the arrange view.
map("<leader>rm", "marker.new", { desc = "Put a marker at the cursor: type its name" })
map("<leader>rn", "region.new", { mode = nx, desc = "Make a region over the selection or the loop: type its name" })
map("<leader>rx", "marker.remove", { desc = "Remove the marker at the cursor" })
map("<leader>rX", "region.remove", { desc = "Remove the region the cursor is in; its clips stay" })
map("<leader>rl", "region.loop", { desc = "Loop the region the cursor is in" })
map("<leader>rR", "render.regions", { desc = "Render every region to a file of its own: type the folder" })
-- `.` repeats the last change; `<leader>.` adjusts it: a panel shows its parameters (paw/views/adjust.tl).
-- With no command to adjust, the command line says why.
map("<leader>.", function()
  if not require("paw.views.adjust").open() then
    paw.commands.run("cmdline", { text = paw.commands.adjusting() or "adjust " })
  end
end, { desc = "Adjust the last command: change its parameters in place of its undo step", repeatable = false })
-- What other programs have taught the fingers.
map("<Del>", function() keymap.normal("x") end, { desc = "Delete what is under the cursor" })
-- On a selection it is the operator: what the Delete key does anywhere else.
map("<Del>", function() keymap.normal("d") end, { mode = "x", desc = "Delete the selection" })
map("<C-z>", "undo", { mode = nx, desc = "Undo", repeatable = false })
map("<C-y>", "redo", { mode = nx, desc = "Redo", repeatable = false })
map("<C-s>", "write", { mode = nx, desc = "Save the project" })
map("ZZ", "wq", { desc = "Save and quit" })
map("ZQ", "quit!", { desc = "Quit without saving" })
map("zi", "zoom by=2", { mode = nx, desc = "Zoom in" })
map("zo", "zoom by=0.5", { mode = nx, desc = "Zoom out" })
map("]g", "grid by=2", { mode = nx, desc = "Coarser grid" })
map("[g", "grid by=0.5", { mode = nx, desc = "Finer grid" })

--- Whole tracks from a row down, as a region.
local function rows(first, n)
  return { view = "arrange", kind = "line", r0 = first, r1 = first + (n or 1) - 1, c0 = 0, c1 = 0 }
end

--- Put the cursor on the track now at a row, after tracks came or went.
local function settle(row)
  local list = paw.scope.tracks()
  if #list > 0 then cursor.set_track(list[util.clamp(row, 1, #list)]) end
end

-- Tracks can be driven from the arrange view and the mixer alike. The
-- mixer's motions, values and operators are in paw/mixer_rows.lua: its
-- strips are a grid of rows.
for _, name in ipairs({ "arrange", "mixer" }) do
  local function vmap(lhs, rhs, desc, opts) map(lhs, rhs, util.merge({ view = name, desc = desc }, opts)) end
  vmap("o", "track.add", "Add a track below")
  vmap("O", "track.add above=true", "Add a track above")
  vmap("grn", "track.rename", "Rename the track")
  vmap("M", "track.mute", "Mute the track")
  vmap("s", "track.solo", "Solo")
  vmap("r", "track.armed", "Arm for recording")
  vmap("I", "track.input", "Choose the input")
  vmap("<A-i>", "track.monitor", "Hear the input without arming")
  vmap("<A-j>", "track.move by=1", "Move the track down")
  vmap("<A-k>", "track.move by=-1", "Move the track up")
  vmap("a", "device.add", "Add a device")
end
local function tmap(lhs, rhs, desc, opts) map(lhs, rhs, util.merge({ view = "arrange", desc = desc }, opts)) end
tmap("j", "cursor.down", "Next track", linewise)
tmap("k", "cursor.up", "Previous track", linewise)
tmap("<Down>", "cursor.down", "Next track", linewise)
tmap("<Up>", "cursor.up", "Previous track", linewise)
tmap("gg", "cursor.first_track", "First track, or track N", far_lines)
tmap("G", "cursor.last_track", "Last track, or track N", far_lines)
-- A track's main value is its volume and its second its pan, as in the mixer.
tmap("+", "track.volume by=1", "Volume up 1 dB", { role = "main+" })
tmap("-", "track.volume by=-1", "Volume down 1 dB", { role = "main-" })
tmap("<C-a>", "track.volume by=1", "Volume up, a dB for each of the count", { role = "main+" })
tmap("<C-x>", "track.volume by=-1", "Volume down, a dB for each of the count", { role = "main-" })
tmap("]", "track.pan by=0.1", "Pan right", { role = "second+" })
tmap("[", "track.pan by=-0.1", "Pan left", { role = "second-" })
keymap.classic(")", "track.pan by=0.1", { view = "arrange", desc = "Pan right" })
keymap.classic("(", "track.pan by=-0.1", { view = "arrange", desc = "Pan left" })
keymap.classic("]", false, { view = "arrange" })
keymap.classic("[", false, { view = "arrange" })
keymap.classic("<C-a>", "clip.transpose by=1", { view = "arrange", desc = "Transpose the clip up a semitone" })
keymap.classic("<C-x>", "clip.transpose by=-1", { view = "arrange", desc = "Transpose the clip down a semitone" })
paw.mixer_rows = require("paw.mixer_rows")

-- Arrange: motions.
amap("l", "cursor.right", "Right one grid step", motion)
amap("h", "cursor.left", "Left one grid step", motion)
amap("<Right>", "cursor.right", "Right one grid step", motion)
amap("<Left>", "cursor.left", "Left one grid step", motion)
amap("w", "cursor.next_clip", "Start of the next clip", motion)
amap("b", "cursor.prev_clip", "Start of this clip, or the one before", motion)
amap("e", "cursor.clip_end", "End of this clip, or the next", motion)
amap("W", "cursor.next_bar", "Next bar", motion)
amap("B", "cursor.prev_bar", "Previous bar", motion)
amap("0", "cursor.start", "Start of the project", motion)
amap("^", "cursor.first_clip", "Start of the track's first clip", motion)
amap("$", "cursor.end", "End of the track's last clip", motion)
amap("|", "cursor.bar", "Bar N", far)
amap("gP", "cursor.to_playhead", "Cursor to the playhead", far)
amap("<C-d>", function(ctx) cursor.move_track(4 * (ctx.count or 1)) end, "Four tracks down", linewise)
amap("<C-u>", function(ctx) cursor.move_track(-4 * (ctx.count or 1)) end, "Four tracks up", linewise)
amap("*", function()
  local clip = cursor.clip()
  if clip then keymap.search(clip.name, 1) end
end, "Next clip with this one's name", far)
amap("zz", function() paw.ui.views.arrange:center() end, "Scroll the cursor to the middle")
-- Groups of tracks.
map("<leader>tg", "track.group", { view = "arrange", mode = nx, desc = "Group the selected tracks" })
amap("<leader>tG", "track.ungroup", "Take the track out of its group; dissolve a group")
-- Folds (paw/folds.tl): view state of this window, as Vim's. `zo` stays
-- zoom out; `za` opens.
amap("za", "fold.toggle", "Fold the group or fold at the cursor, or open it")
amap("zc", "fold.close", "Fold the group or fold at the cursor")
amap("zd", "fold.delete", "Delete the fold at the cursor (its tracks stay)")
amap("zE", "fold.clear", "Delete every fold of this window")
keymap.operator("zf", function(region)
  local f, why = paw.folds.make(paw.scope.of_region(region))
  if not f then return paw.notify(why, "warn") end
  paw.notify(
    string.format("folded %s (%s) · `za` opens it, `zd` deletes it", paw.folds.name(f), paw.folds.describe(f))
  )
end, {
  view = "arrange",
  repeatable = false,
  desc = "Fold a region (zfar) into a column, a group (zfag) or tracks (Vjjzf) into one line",
})
amap("zm", "fold.more", "Fold one more level of regions")
amap("zr", "fold.less", "Open one more level of regions")
-- Scopes (paw/scope.tl): `zn` enters what a motion covers in this window,
-- `znn` the innermost scope at the cursor; `zw` goes up, `zW` to the song,
-- `]z` `[z` to the scopes beside. The `<leader>z` keys open and name them.
keymap.operator("zn", function(region, ctx)
  local spec
  if ctx.keys == "znn" then
    spec = paw.scope.at_cursor()
    if not spec then return paw.notify("nothing smaller to enter at the cursor: `zw` goes up", "warn") end
  else
    spec = paw.scope.of_region(region)
    if not spec then return paw.notify("that is all that the window shows: nothing to enter", "warn") end
  end
  local ok, err = pcall(paw.scope.enter, spec)
  if not ok then return paw.notify(tostring(err), "warn") end
  paw.notify(paw.scope.describe() .. " · `zw` goes back")
end, {
  view = "arrange",
  repeatable = false,
  desc = "Enter a scope in this window: znar the region, znag the group, znit the track, znn the innermost at the cursor",
})
amap("zw", "widen", "Up one level of scope")
amap("zW", "widen!", "Up to the whole song")
-- The scope at the cursor, or the selection's, in a new window.
for _, how in ipairs({ { "s", "split", "split" }, { "v", "vsplit", "vertical split" }, { "t", "tab", "tab" } }) do
  map("<leader>z" .. how[1], function()
    local spec
    if keymap.mode == "x" then
      local reg = keymap.selection()
      keymap.set_mode("n")
      spec = reg and paw.scope.of_region(reg)
    end
    local ok, err = pcall(paw.scope.open, how[2], spec)
    if not ok then return paw.notify(tostring(err), "warn") end
    paw.notify(paw.scope.describe())
  end, { mode = nx, desc = "The scope at the cursor, or the selection, in a new " .. how[3] })
end
map("<leader>zn", "scope.name", { desc = "Name this window's scope: type its name" })
map("<leader>zz", "scope.list", { desc = "Enter a scope, or go up to a level, from a list" })
amap("]z", "scope.next", "The next scope beside this one: region, group, track", { motion = true, mode = "n" })
amap("[z", "scope.prev", "The scope before this one, beside it", { motion = true, mode = "n" })
-- VCAs, and the faders of a group moving together.
map("<leader>tv", "vca.make", { view = "arrange", mode = nx, desc = "A new VCA over the selected tracks" })
map("<leader>ta", "vca.assign", { view = "arrange", mode = nx, desc = "Put the selected tracks under a VCA" })
map("<leader>tr", "vca.release", { view = "arrange", mode = nx, desc = "Take the selected tracks out of their VCAs" })
amap("<leader>tx", "vca.dissolve", "Take the VCA at the cursor away")
amap("<leader>tl", "group.link", "Link the faders of the group's members")
amap("<leader>ts", "send", "Send the track's sound to another as well")
amap("<leader>to", "track.output", "Choose where the track's sound goes")
amap("zM", "fold.closeall", "Fold every group and fold of this window")
amap("zR", "fold.openall", "Open every group and fold of this window")
amap("zl", function(ctx) paw.ui.views.arrange:scroll_by(ctx.count or 1) end, "Scroll a bar later")
amap("zh", function(ctx) paw.ui.views.arrange:scroll_by(-(ctx.count or 1)) end, "Scroll a bar earlier")

-- Arrange: text objects.
local function aobject(lhs, fn, desc) keymap.textobject(lhs, fn, { view = "arrange", desc = desc }) end
local function on_row(c0, c1)
  local row = cursor.index() or 1
  return { view = "arrange", kind = "char", r0 = row, r1 = row, c0 = c0, c1 = c1 }
end
aobject("ic", function()
  local clip = cursor.clip()
  if clip then return on_row(clip.start, clip.start + clip.length) end
end, "The clip under the cursor")
aobject("ac", function()
  local clip = cursor.clip()
  if not clip then return end
  -- With the silence after it, up to the next clip.
  local c1 = clip.start + clip.length
  local finish = c1
  for _, other in ipairs(clip:track():clips()) do
    if other.start >= c1 - 1e-9 and (finish == c1 or other.start < finish) then finish = other.start end
  end
  return on_row(clip.start, finish)
end, "The clip and the gap after it")
for _, lhs in ipairs({ "ib", "ab" }) do
  aobject(lhs, function(ctx)
    local n = paw.time.bar_of(cursor.beat)
    return on_row(paw.time.bar_start(n), paw.time.bar_start(n + (ctx.count or 1)))
  end, "This bar, or N bars from it")
end
for _, lhs in ipairs({ "il", "al" }) do
  aobject(lhs, function() return on_row(transport.loop_start, transport.loop_end) end, "The loop")
end
-- A region: its time on this track (`ir`), or on every track (`ar`), so
-- `dar` empties the region in the whole song and keeps the region itself.
-- The innermost region at the cursor; with a count, the region around it
-- (`2ar`), as Vim's `2a(`.
--- A stretch of time cut at the edges of the window's scope (`paw.scope`)
--- when it has time: a text object takes only what the scope shows.
local function in_scope(c0, c1)
  local from, to = paw.scope.span()
  if from then return math.max(c0, from), math.min(c1, to) end
  return c0, c1
end
local function region_here(ctx)
  local r = paw.markers.around(cursor.beat, ctx.count)
  if not r then paw.notify("the cursor is in no region", "warn") end
  return r
end
aobject("ir", function(ctx)
  local r = region_here(ctx)
  if r then return on_row(in_scope(r.beat, r.beat + r.length)) end
end, "The region the cursor is in, on this track (2ir: the region around it)")
aobject("ar", function(ctx)
  local r = region_here(ctx)
  local n = #paw.groups.rows()
  if r and n > 0 then
    local c0, c1 = in_scope(r.beat, r.beat + r.length)
    return {
      view = "arrange",
      kind = "block",
      r0 = 1,
      r1 = n,
      c0 = c0,
      c1 = c1,
      scope = { kind = "region", id = r.id },
    }
  end
end, "The region the cursor is in, on every track of the scope (2ar: the region around it)")
for _, lhs in ipairs({ "it", "at" }) do
  aobject(lhs, function()
    local row = cursor.index() or 1
    local c0, c1 = in_scope(edit.arrange.span(rows(row)))
    if c1 > c0 then
      local reg = on_row(c0, c1)
      local id = cursor.track_id()
      reg.scope = id and id ~= 0 and { kind = "track", id = id } or nil
      return reg
    end
  end, "Everything on the track")
end
for _, lhs in ipairs({ "ie", "ae" }) do
  aobject(lhs, function()
    local n = #paw.groups.rows()
    local c0, c1 = paw.scope.span()
    if not c0 then
      c0, c1 = 0, paw.project.length
    end
    if n == 0 or c1 <= c0 then return end
    return { view = "arrange", kind = "block", r0 = 1, r1 = n, c0 = c0, c1 = c1, entire = true }
  end, "The entire project, or the entire scope in a narrowed window")
end

-- Arrange: operators.
-- An operator acts on tracks and clips: on the master, which has no clips
-- and no place in the list of tracks, it says so.
local function aop(lhs, fn, desc)
  keymap.operator(lhs, function(region, ctx)
    local n = #paw.groups.rows()
    if cursor.on_master() or (n > 0 and region.r0 > n) then
      return paw.notify("the master track has no clips and stays: move to a track with `k`", "warn")
    end
    return fn(region, ctx)
  end, { view = "arrange", desc = desc })
end
aop("d", function(region, ctx)
  keymap.setreg(edit.arrange.delete(region), ctx.register)
  if region.kind == "line" then settle(region.r0) end
end, "Delete")
aop("y", function(region, ctx)
  local value = edit.arrange.yank(region)
  keymap.setreg(value, ctx.register, true)
  if value.kind == "tracks" then
    paw.notify(
      #value.tracks == 1 and "yanked track " .. value.tracks[1].name or "yanked " .. #value.tracks .. " tracks"
    )
  else
    paw.notify(string.format("yanked %g beats", value.length))
  end
end, "Yank")
aop("c", function(region, ctx)
  -- Empty the stretch and start a fresh clip there, open for typing notes.
  local c0, c1 = edit.arrange.span(region)
  if c1 - c0 < 1e-9 then
    c0, c1 = cursor.beat, cursor.beat + paw.opt.clip_length
  end
  local removed = edit.arrange.delete(util.merge(region, { kind = "char", c0 = c0, c1 = c1 }))
  keymap.setreg(removed, ctx.register)
  local track = need_track()
  if not track then return end
  cursor.set_beat(c0)
  -- The new clip takes the name of the one it replaces.
  local first = removed.rows[1] and removed.rows[1][1]
  roll:edit(track:add_clip({ start = c0, length = c1 - c0, name = first and first.name or nil }))
  keymap.set_mode("i")
end, "Change: empty it and enter notes")
--- Move a region's clips by grid steps, and the cursor with them so that
--- `.` finds them again.
local function shift(region, steps)
  local by = math.max(steps * paw.opt.grid, -region.c0)
  edit.arrange.shift(region, by)
  if region.kind ~= "line" then cursor.set_beat(cursor.beat + by) end
end
aop(">", function(region, ctx) shift(region, region.visual and ctx.count or 1) end, "Move clips later")
aop("<lt>", function(region, ctx) shift(region, -(region.visual and ctx.count or 1)) end, "Move clips earlier")
aop("=", edit.arrange.quantize, "Snap clips and their notes to the grid")
keymap.operator("gc", edit.arrange.mute, { view = "arrange", desc = "Mute or unmute", role = "mute" })
aop("gl", function(region)
  local c0, c1 = edit.arrange.span(region)
  if c1 <= c0 then return end
  transport.loop_start, transport.loop_end, transport.loop_enabled = c0, c1, true
end, "Loop")

-- Arrange: what is done so often that it has a key of its own.
amap("x", function() keymap.normal("dic") end, "Delete the clip")
amap("D", function() keymap.normal("d$") end, "Delete to the end of the track")
amap("C", function() keymap.normal("c$") end, "Change to the end of the track")
amap("Y", function() keymap.normal("y$") end, "Yank to the end of the track")
amap(
  "p",
  function(ctx) edit.arrange.paste(keymap.getreg(ctx.register), false, ctx.count) end,
  "Paste after the clip, or tracks below"
)
amap(
  "P",
  function(ctx) edit.arrange.paste(keymap.getreg(ctx.register), true, ctx.count) end,
  "Paste at the cursor, or tracks above"
)
amap("&", "clip.duplicate", "Repeat the clip after itself")
amap("~", "clip.mute", "Mute or unmute the clip")
amap("S", "clip.split", "Split the clip at the cursor")
amap("J", "clip.join", "Join the clip with those over it, or with the next one")
amap("<CR>", "clip.edit", "Edit the clip's notes")
amap(
  "i",
  function() paw.insert.start() end,
  "Insert mode: m a MIDI clip, a an automation point, r a region, ' a marker; Enter enters notes"
)
amap("grc", "clip.rename", "Rename the clip")
amap("gw", "clip.warp", "Put a warp marker on the audio clip at the cursor")
amap("gW", "clip.warp remove", "Take off the clip's warp marker nearest the cursor")
amap("L", "clip.move by=1", "Move the clip right")
amap("H", "clip.move by=-1", "Move the clip left")
amap("<A-l>", "clip.resize by=1", "Lengthen the clip")
amap("<A-h>", "clip.resize by=-1", "Shorten the clip")
amap("A", "lane.add", "Add a volume automation point at the cursor")
amap("<leader>at", "lane.toggle", "Turn volume automation off or on")
amap("<leader>aw", "lane.write", "Write automation by moving things while playing, or stop")
amap("<leader>am", "automation", "The track's automation mode: read, touch, latch, write, off in turn")
amap("]t", "take next", "The clip's next take")
amap("[t", "take prev", "The clip's take before")
amap("zT", "tempo.lane", "Show or hide the tempo curve under the ruler")
amap("zt", "take.lanes", "Show the track's takes as lanes under its clips, or hide them")
amap("]'", "marker.next", "The next marker or region", { motion = true })
amap("['", "marker.prev", "The marker or region before", { motion = true })
amap("]r", "region.next", "The next region at the level of the one the cursor is in", { motion = true })
amap("[r", "region.prev", "The region before, at the level of the one the cursor is in", { motion = true })
amap("g'", "marker.new", "Put a marker at the cursor: type its name")
amap('g"', "marker.list", "Go to a marker or region from a list")
amap("gx", "marker.remove", "Remove the marker at the cursor")
amap("gX", "region.remove", "Remove the region the cursor is in; its clips stay")
amap("<leader>ax", "lane.clear", "Clear the volume automation")

-- Arrange: on a selection.
-- `role` as in normal mode: `]` `[` run at once, as they do there, though `]g` waits for its `g`.
local function ax(lhs, fn, desc, role)
  map(lhs, nil, { view = "arrange", mode = "x", operator = fn, desc = desc, role = role })
end
ax("x", function(region, ctx) keymap.setreg(edit.arrange.delete(region), ctx.register) end, "Delete")
ax("p", function(region, ctx)
  local value = keymap.getreg(ctx.register)
  if not value then return paw.notify("nothing to paste yet", "warn") end
  local replaced = edit.arrange.delete(region)
  if region.kind == "line" then settle(region.r0) end
  edit.arrange.paste(value, true, ctx.count)
  keymap.setreg(replaced)
end, "Replace with the register")
ax("J", function(region)
  for _, id in ipairs(edit.arrange.tracks(region)) do
    local c0, c1 = edit.arrange.span(region)
    edit.arrange.join(id, c0, c1, region.clips)
  end
end, "Join the clips")
map("S", "clip.split", { view = "arrange", mode = "x", desc = "Split the chosen clips at the cursor" })
ax("~", edit.arrange.mute, "Mute or unmute")
ax("M", edit.arrange.mute, "Mute or unmute")
ax("<CR>", function(region)
  local ids = {}
  for _, track in ipairs(edit.arrange.tracks(region)) do
    for _, c in ipairs(api.clip_list(track)) do
      local inside
      if region.clips then
        inside = region.clips[c.id]
      else
        inside = region.kind == "line" or (c.start < region.c1 - 1e-9 and c.start + c.length > region.c0 + 1e-9)
      end
      if inside and c.kind == "midi" then ids[#ids + 1] = c.id end
    end
  end
  local under = paw.cursor.clip()
  paw.roll_clips.open(ids, under and under.id)
end, "Edit the notes of the selected MIDI clips together")
-- The main value of what is selected: whole tracks (`V`) their volume, a
-- stretch of clips the pitch of their notes; the second the tracks' pan.
local function main_value(sign)
  return function(region, ctx)
    local n = sign * (ctx.count or 1)
    if region.kind ~= "line" then return edit.arrange.transpose(region, n) end
    for _, id in ipairs(edit.arrange.tracks(region)) do
      local track = paw.track(id)
      track.volume = util.fader_db(track.volume, track.volume + n)
    end
  end
end
local function pan_value(sign)
  return function(region, ctx)
    for _, id in ipairs(edit.arrange.tracks(region)) do
      local track = paw.track(id)
      track.pan = util.clamp(util.round(track.pan + 0.1 * sign * (ctx.count or 1), 0.01), -1, 1)
    end
  end
end
ax("<C-a>", main_value(1), "Tracks louder, or the clips' notes up")
ax("<C-x>", main_value(-1), "Tracks softer, or the clips' notes down")
ax("+", main_value(1), "Tracks louder, or the clips' notes up")
ax("-", main_value(-1), "Tracks softer, or the clips' notes down")
ax("]", pan_value(1), "Pan the tracks right", "second+")
ax("[", pan_value(-1), "Pan the tracks left", "second-")
ax("L", function(region, ctx) shift(region, ctx.count or 1) end, "Move the clips right")
ax("H", function(region, ctx) shift(region, -(ctx.count or 1)) end, "Move the clips left")

-- Device panel: its rows are devices and parameters (paw/device_rows.lua).
paw.device_rows = require("paw.device_rows")

-- Piano roll: motions.
local function pmap(lhs, rhs, desc, opts) map(lhs, rhs, util.merge({ view = "pianoroll", desc = desc }, opts)) end
local noteobj = require("paw.note_objects")
--- The notes of the roll, and the one under the cursor among them.
local function here()
  if not roll:clip() then return end
  local notes = roll:ordered()
  local _, place, part = roll:note_at(roll.pitch, roll.beat)
  if place then
    for _, n in ipairs(notes) do
      if n.clip == part.id and n.place == place then return notes, n end
    end
  end
  return notes
end
local function move(dbeat, dpitch)
  return function(ctx)
    local n = ctx.count or 1
    roll:move(dbeat * n * paw.opt.note_grid, dpitch * n)
  end
end
pmap("h", move(-1, 0), "Left one step", motion)
pmap("l", move(1, 0), "Right one step", motion)
pmap("j", move(0, -1), "Down a semitone", linewise)
pmap("k", move(0, 1), "Up a semitone", linewise)
pmap("<Left>", move(-1, 0), "Left one step", motion)
pmap("<Right>", move(1, 0), "Right one step", motion)
pmap("<Down>", move(0, -1), "Down a semitone", linewise)
pmap("<Up>", move(0, 1), "Up a semitone", linewise)
-- An octave is half a page of pitches: `Ctrl-d` `Ctrl-u`, as in Vim. `K`
-- describes, as in every view.
pmap("<C-d>", move(0, -12), "Down an octave", linewise)
pmap("<C-u>", move(0, 12), "Up an octave", linewise)
keymap.classic("J", move(0, -12), { view = "pianoroll", desc = "Down an octave", motion = true, linewise = true })
keymap.classic("K", move(0, 12), { view = "pianoroll", desc = "Up an octave", motion = true, linewise = true })
pmap("w", function(ctx) roll:to_note(1, ctx.count) end, "Next note", motion)
pmap("b", function(ctx) roll:to_note(-1, ctx.count) end, "Previous note", motion)
pmap("e", function(ctx) roll:to_note_end(ctx.count) end, "End of this note, or the next", motion)
pmap("W", function(ctx) roll:to_bar(ctx.count or 1) end, "Next bar", motion)
pmap("B", function(ctx) roll:to_bar(-(ctx.count or 1)) end, "Previous bar", motion)
pmap("0", function() roll:set(nil, (roll:span())) end, "Start of the clip", motion)
pmap("^", function() roll:to_edge(1) end, "The first note", motion)
pmap("$", function() roll:to_edge(-1) end, "End of the clip", motion)
pmap("gg", function() roll:to_extreme(1) end, "The highest note", far_lines)
pmap("G", function() roll:to_extreme(-1) end, "The lowest note", far_lines)
pmap("*", function() keymap.search(paw.music.name(roll.pitch), 1) end, "Next note of this pitch", far)
-- The phrases, as Vim's sentences: `)` the next, `(` the start of this
-- one or the one before.
local function to_phrase(dir, count)
  local notes = here()
  if not notes then return end
  local list = noteobj.phrases(notes, paw.opt.phrase_rest)
  local pitch, beat = roll.pitch, roll.beat
  for _ = 1, count or 1 do
    local found
    if dir > 0 then
      for _, p in ipairs(list) do
        if p.start > beat + 1e-9 then
          found = p
          break
        end
      end
    else
      for i = #list, 1, -1 do
        if list[i].start < beat - 1e-9 then
          found = list[i]
          break
        end
      end
    end
    if not found then
      if dir > 0 then
        beat = select(2, roll:span())
      else
        beat = (roll:span())
      end
      break
    end
    pitch, beat = found.notes[1].pitch, found.start
  end
  roll:set(pitch, beat)
end
-- The chords: `]c` the start of the next place where two or more notes
-- start together, `[c` of the one before (`ic` is the chord).
local function to_chord(dir, count)
  local notes = here()
  if not notes then return end
  local starts = {}
  -- The lowest note of each chord: the first of the notes of one start.
  for i, n in ipairs(notes) do
    local before, after = notes[i - 1], notes[i + 1]
    local first = not before or math.abs(before.start - n.start) > 1e-9
    if first and after and math.abs(after.start - n.start) < 1e-9 then starts[#starts + 1] = n end
  end
  local at = roll.beat
  local found
  for _ = 1, count or 1 do
    local step
    if dir > 0 then
      for _, n in ipairs(starts) do
        if n.start > at + 1e-9 then
          step = n
          break
        end
      end
    else
      for i = #starts, 1, -1 do
        if starts[i].start < at - 1e-9 then
          step = starts[i]
          break
        end
      end
    end
    if not step then break end
    found, at = step, step.start
  end
  if found then roll:set(found.pitch, found.start) end
end
pmap("]c", function(ctx) to_chord(1, ctx.count) end, "Next chord", far)
pmap("[c", function(ctx) to_chord(-1, ctx.count) end, "Previous chord", far)
pmap(")", function(ctx) to_phrase(1, ctx.count) end, "Next phrase", far)
pmap("(", function(ctx) to_phrase(-1, ctx.count) end, "Start of this phrase, or the one before", far)
pmap("gp", "transport.to_cursor", "Playhead to the cursor")

-- Piano roll: text objects. The musical objects of the notes
-- (paw/note_objects.tl): `in` the note, `ic` the chord, `ip` the phrase,
-- `iv` the voice, `i=` the pitch, then `ib` the bar, `ir` the region and
-- `ie` everything. `a` takes in what surrounds the object. A count takes
-- more of them, and the same object again in visual mode takes one more.
local function pobject(lhs, fn, desc) keymap.textobject(lhs, fn, { view = "pianoroll", desc = desc }) end
--- The region of `picked`: a plain block when the block holds no other
--- note, else one that names its notes.
local function region_of(notes, picked, to)
  local reg = noteobj.region(picked, to)
  if not reg then return end
  local count = 0
  for _, n in ipairs(notes) do
    if n.pitch >= reg.r0 and n.pitch <= reg.r1 and n.start >= reg.c0 - 1e-9 and n.start < reg.c1 - 1e-9 then
      count = count + 1
    end
  end
  if count == #picked then reg.notes = nil end
  return reg
end
--- A stretch of the roll's time at every pitch.
local function stretch(c0, c1)
  return { view = "pianoroll", kind = "char", r0 = roll.pitch, r1 = roll.pitch, c0 = c0, c1 = c1 }
end

for _, lhs in ipairs({ "in", "an" }) do
  pobject(
    lhs,
    function(ctx)
      local notes, at = here()
      if not at then return end
      -- The note, and with a count the next notes of its voice.
      local voice = noteobj.voice(notes, at)
      local first = 1
      for i, n in ipairs(voice) do
        if n == at then first = i end
      end
      local last = math.min(#voice, first + (ctx.count or 1) - 1)
      local picked = {}
      for i = first, last do
        picked[#picked + 1] = voice[i]
      end
      -- `an`: up to where the next note of the voice starts.
      local after = lhs == "an" and voice[last + 1]
      return region_of(notes, picked, after and after.start)
    end,
    lhs == "in" and "The note under the cursor (2in: and the next of its voice)"
      or "The note and the rest after it, up to the next of its voice"
  )
end
for _, lhs in ipairs({ "ic", "ac" }) do
  pobject(
    lhs,
    function(ctx)
      local notes, at = here()
      if not notes then return end
      local chord = noteobj.chords(notes, at, roll.beat, ctx.count or 1)
      if #chord == 0 then return end
      if lhs == "ic" then return region_of(notes, chord) end
      -- `ac`: the chord as the harmony reads it (a broken chord too): every
      -- note that starts while it holds, in the phrase of the chord. Where
      -- no chord is read, the notes that sound with these.
      local s0, s1, e1 = math.huge, -math.huge, -math.huge
      for _, n in ipairs(chord) do
        s0, s1, e1 = math.min(s0, n.start), math.max(s1, n.start), math.max(e1, n.start + n.length)
      end
      local base = roll:clip().start
      local h0, h1 = paw.harmony.at(base + s0), paw.harmony.at(base + s1)
      local from, to, starting = s0, e1, false
      if h0 and h1 then
        local phrases = noteobj.phrases(notes, paw.opt.phrase_rest)
        local p0, p1 = phrases[noteobj.phrase_at(phrases, s0)], phrases[noteobj.phrase_at(phrases, s1)]
        from, to, starting = math.max(h0.at - base, p0.start), math.min(h1.at + h1.length - base, p1.finish), true
      end
      local inside = {}
      for _, n in ipairs(chord) do
        inside[n] = true
      end
      local picked = {}
      for _, n in ipairs(notes) do
        local yes = inside[n]
        if starting then
          yes = yes or (n.start >= from - 1e-9 and n.start < to - 1e-9)
        else
          yes = yes or (n.start < to - 1e-9 and n.start + n.length > from + 1e-9)
        end
        if yes then picked[#picked + 1] = n end
      end
      return region_of(notes, picked)
    end,
    lhs == "ic" and "The chord: the notes that start with the one under the cursor (2ic: and the next chord)"
      or "The chord as the harmony reads it: every note that starts while it holds"
  )
end
for _, lhs in ipairs({ "ip", "ap" }) do
  pobject(
    lhs,
    function(ctx)
      local notes = here()
      if not notes then return end
      local list = noteobj.phrases(notes, paw.opt.phrase_rest)
      local first = noteobj.phrase_at(list, roll.beat)
      if not first then return end
      local last = math.min(#list, first + (ctx.count or 1) - 1)
      local c0, c1 = list[first].start, list[last].finish
      if lhs == "ap" then c1 = list[last + 1] and list[last + 1].start or math.max(c1, select(2, roll:span())) end
      return stretch(c0, c1)
    end,
    lhs == "ip" and "The phrase: notes with no long rest between them (from a rest, the next)"
      or "The phrase and the rest after it"
  )
end
for _, lhs in ipairs({ "iv", "av" }) do
  pobject(
    lhs,
    function()
      local notes, at = here()
      if not at then return end
      local voice = noteobj.voice(notes, at)
      if lhs == "av" then voice = noteobj.doublings(notes, voice) end
      return region_of(notes, voice)
    end,
    lhs == "iv" and "The voice of the note under the cursor: the top line, the bass, or the line between"
      or "The voice and the notes that double it in other octaves"
  )
end
for _, lhs in ipairs({ "i=", "a=" }) do
  pobject(
    lhs,
    function()
      local notes, at = here()
      if not notes then return end
      return region_of(notes, noteobj.pitch(notes, at and at.pitch or roll.pitch, lhs == "a="))
    end,
    lhs == "i=" and "Every note of the pitch under the cursor"
      or "Every note of the pitch class under the cursor, in every octave"
  )
end
for _, lhs in ipairs({ "ib", "ab" }) do
  pobject(lhs, function(ctx)
    local clip = roll:clip()
    if not clip then return end
    local n = paw.time.bar_of(clip.start + roll.beat)
    return stretch(paw.time.bar_start(n) - clip.start, paw.time.bar_start(n + (ctx.count or 1)) - clip.start)
  end, "This bar, or N bars from it")
end
-- A region of the song: the innermost one at the cursor, and with a count
-- the one around it.
for _, lhs in ipairs({ "ir", "ar" }) do
  pobject(lhs, function(ctx)
    local clip = roll:clip()
    if not clip then return end
    local r = paw.markers.around(clip.start + roll.beat, ctx.count)
    if not r then return paw.notify("the cursor is in no region", "warn") end
    local c0, c1 = in_scope(r.beat, r.beat + r.length)
    return stretch(c0 - clip.start, c1 - clip.start)
  end, "The region of the song the cursor is in (2ir: the region around it)")
end
for _, lhs in ipairs({ "ie", "ae" }) do
  pobject(lhs, function()
    if not roll:clip() then return end
    return stretch(roll:span())
  end, "Every note of the clip, or of the clips edited")
end

-- Piano roll: operators. They act on every clip the roll edits.
local function editing()
  local parts = roll:parts()
  return #parts > 1 and parts or roll:clip()
end
local function pop(lhs, fn, desc)
  keymap.operator(lhs, function(region, ctx)
    if roll:clip() then return fn(editing(), region, ctx) end
  end, { view = "pianoroll", desc = desc })
end
pop("d", function(clip, region, ctx) keymap.setreg(edit.roll.delete(clip, region), ctx.register) end, "Delete")
pop("y", function(clip, region, ctx)
  local value = edit.roll.yank(clip, region)
  keymap.setreg(value, ctx.register, true)
  paw.notify(#value.notes == 1 and "yanked 1 note" or "yanked " .. #value.notes .. " notes")
end, "Yank")
pop("c", function(clip, region, ctx)
  keymap.setreg(edit.roll.delete(clip, region), ctx.register)
  if region.kind ~= "line" then roll:set(nil, region.c0) end
  keymap.set_mode("i")
end, "Change: delete and enter notes")
local function shift_notes(clip, region, steps)
  local by = math.max(steps * paw.opt.note_grid, region.kind == "line" and -math.huge or -region.c0)
  edit.roll.each(clip, region, function(n) n.start = math.max(0, n.start + by) end)
  if region.kind ~= "line" then roll:set(nil, roll.beat + by) end
end
pop(
  ">",
  function(clip, region, ctx) shift_notes(clip, region, region.visual and ctx.count or 1) end,
  "Move notes later"
)
pop(
  "<lt>",
  function(clip, region, ctx) shift_notes(clip, region, -(region.visual and ctx.count or 1)) end,
  "Move notes earlier"
)
pop("=", function(clip, region)
  local grid = paw.opt.note_grid
  edit.roll.each(clip, region, function(n)
    n.start, n.length = util.round(n.start, grid), math.max(grid, util.round(n.length, grid))
  end)
end, "Snap notes to the grid")
pop("gl", function(_, region)
  local clip = roll:clip()
  local c0, c1 = region.c0, region.c1
  if region.kind == "line" then
    c0, c1 = roll:span()
  end
  transport.loop_start, transport.loop_end, transport.loop_enabled = clip.start + c0, clip.start + c1, true
end, "Loop")

-- Piano roll: single keys.
pmap("<CR>", function() roll:toggle_note() end, "Add or remove a note")
pmap("i", function() keymap.set_mode("i") end, "Draw: the note under the cursor at its start, or a new one")
pmap("a", function()
  -- The pencil takes the note at its end, or starts a step on: past the
  -- end of the clip if need be, which grows to hold what is drawn.
  paw.roll_draw.append()
  keymap.set_mode("i")
end, "Draw: the note under the cursor at its end, or a new one a step on")
pmap("I", function()
  paw.roll_draw.step_next()
  keymap.set_mode("i")
end, "Step input: notes played on a MIDI keyboard go in at the cursor")
-- Notes chosen with the pointer (a click, a box) come first for the keys
-- that would otherwise act on the note under the cursor.
-- The first of them: its clip's id and its place there.
local function chosen()
  for _, part in ipairs(roll:parts()) do
    local places = paw.frontend.chosen_notes(part.id)
    if #places > 0 then return part.id, places[1] end
  end
end
pmap("x", function()
  local clip = roll:clip()
  -- Controller moves chosen in the strip go with the chosen notes.
  local moves = clip and paw.controls.remove(clip.id) or 0
  local first = chosen()
  if first then return paw.frontend.act.remove_chosen_notes(first) end
  if moves == 0 then keymap.normal("din") end
end, "Delete the note, or the notes and controller moves chosen with the pointer")
pmap("gA", function()
  local clip = roll:clip()
  if clip then paw.frontend.act.select_all_notes(clip.id) end
end, "Choose every note")
command("notes.quantize", function(ctx)
  local clip = roll:clip()
  if not clip then return paw.notify("open a clip in the piano roll first", "warn") end
  local n = paw.frontend.act.quantize_notes(clip.id, tonumber(ctx.args[1]) and tonumber(ctx.args[1]) / 100 or 1)
  paw.notify(string.format("%d note%s on the %g-beat grid", n, n == 1 and "" or "s", paw.opt.note_grid))
end, { desc = "Quantize the piano roll's chosen notes, or all, to its grid: `notes.quantize [strength%]`" })
pmap("E", "notes.list", "The clip's notes and controller moves as a list, to change in place")
command("notes.list", function()
  local clip = roll:clip()
  if not clip then return paw.notify("open a clip in the piano roll first", "warn") end
  paw.ui.open("eventlist", { title = "Events · " .. clip.name, width = 60, height = 24 })
end, {
  desc = "List the piano roll's notes and controller moves, each cell changed in place (Enter), `x` deletes, `a` adds a move",
})
command("controls.line", function(ctx)
  local clip = roll:clip()
  if not clip then return paw.notify("open a clip in the piano roll first", "warn") end
  local args = ctx.args
  local kind, at = args[1], 2
  local number
  if kind == "cc" then
    number, at = tonumber(args[2]), 3
  end
  local from, to = tonumber(args[at]), tonumber(args[at + 1])
  if not (kind == "cc" and number or kind == "bend" or kind == "pressure") or not from or not to then
    return paw.notify("controls.line cc 74 0 127, controls.line bend -8192 8191, controls.line pressure 0 127", "warn")
  end
  -- From and to in the units the event list shows: seven-bit steps, or the wheel's -8192 to 8191.
  local function height(v) return kind == "bend" and (v / 8192 + 1) / 2 or v / 127 end
  local selection = keymap.selection()
  local b0, b1 = 0, clip.length
  if selection and paw.ui.focused == "pianoroll" and selection.kind ~= "line" then
    b0, b1 = selection.c0, selection.c1
  end
  -- The last step of the stretch reaches `to`.
  b1 = math.max(b0, b1 - paw.opt.note_grid)
  local made = paw.frontend.act.line_controls(clip.id, kind, number, b0, height(from), b1, height(to), false)
  keymap.set_mode("n")
  paw.notify(string.format("%d %s moves in a line", made, kind == "cc" and "CC " .. number or kind))
end, {
  desc = "Draw a straight line of controller moves over the piano roll's selection, or its whole clip: "
    .. "`controls.line cc 74 0 127`, `controls.line bend 0 8191`, `controls.line pressure 127 0`",
})
pmap("D", function() keymap.normal("d$") end, "Delete to the end of the clip")
pmap("C", function() keymap.normal("c$") end, "Change to the end of the clip")
pmap("Y", function() keymap.normal("y$") end, "Yank to the end of the clip")
pmap("p", function(ctx) roll:paste(keymap.getreg(ctx.register), false, ctx.count) end, "Paste after the note")
pmap("P", function(ctx) roll:paste(keymap.getreg(ctx.register), true, ctx.count) end, "Paste at the cursor")
-- A note's length is `Alt-h` `Alt-l`, as a clip's is in the arrange view;
-- `+` `-` are its pitch, its main value.
local function lengthen()
  roll:change(function(n) n.length = n.length + paw.opt.note_grid end)
end
local function shorten()
  roll:change(function(n) n.length = math.max(paw.opt.note_grid, n.length - paw.opt.note_grid) end)
end
pmap("<A-l>", lengthen, "Lengthen the note")
pmap("<A-h>", shorten, "Shorten the note")
keymap.classic("+", lengthen, { view = "pianoroll", desc = "Lengthen the note" })
keymap.classic("-", shorten, { view = "pianoroll", desc = "Shorten the note" })
pmap("L", function()
  if roll:change(function(n) n.start = n.start + paw.opt.note_grid end) then roll:move(paw.opt.note_grid, 0) end
end, "Move the note right")
pmap("H", function()
  local step = math.min(paw.opt.note_grid, roll.beat)
  if roll:change(function(n) n.start = math.max(0, n.start - step) end) then roll:move(-step, 0) end
end, "Move the note left")
local function transpose(sign)
  return function(ctx)
    local by = sign * (ctx.count or 1)
    local clip, place = chosen()
    if clip then return paw.frontend.act.drag_notes(clip, place, 0, by, false, true) end
    if roll:change(function(n) n.pitch = util.clamp(n.pitch + by, 0, 127) end) then roll:move(0, by) end
  end
end
pmap("+", transpose(1), "Move the note up a semitone", { role = "main+" })
pmap("-", transpose(-1), "Move the note down a semitone", { role = "main-" })
pmap("<C-a>", transpose(1), "Move the note up a semitone for each of the count", { role = "main+" })
pmap("<C-x>", transpose(-1), "Move the note down a semitone for each of the count", { role = "main-" })
pmap("]", function(ctx)
  roll:change(function(n) n.velocity = math.min(127, n.velocity + 10 * (ctx.count or 1)) end)
end, "Louder", { role = "second+" })
pmap("[", function(ctx)
  roll:change(function(n) n.velocity = math.max(1, n.velocity - 10 * (ctx.count or 1)) end)
end, "Softer", { role = "second-" })
pmap("gh", function() roll:audition() end, "Hear the pitch under the cursor")
-- The clips the roll edits (`paw.roll_clips`). The tracks it shows are
-- REAPER's editable and visible: `]t` `[t` make the next or previous one
-- active (its notes the ones edited, the old ones behind), and `Tab`
-- `Shift-Tab` go round them; with no other track shown, `Tab` is the next
-- view as everywhere.
pmap("]t", function(ctx) paw.roll_clips.step_track(ctx.count or 1) end, "The next track shown becomes the one edited")
pmap(
  "[t",
  function(ctx) paw.roll_clips.step_track(-(ctx.count or 1)) end,
  "The track shown before becomes the one edited"
)
pmap("<Tab>", function(ctx)
  if not paw.roll_clips.step_track(ctx.count or 1, true) then paw.cmd("view.next") end
end, "The next track shown becomes the one edited, round; else the next view")
pmap("<S-Tab>", function(ctx)
  if not paw.roll_clips.step_track(-(ctx.count or 1), true) then paw.cmd("view.prev") end
end, "The track shown before becomes the one edited, round; else the view before")
local function clip_here()
  -- The clip of the note under the cursor: one edited, or one shown behind.
  local _, _, part = roll:note_at(roll.pitch, roll.beat)
  if part then return part.id end
  local note = paw.roll_clips.context_at(roll.pitch, roll.beat)
  if note then return note.clip end
  paw.notify("no note under the cursor", "warn")
end
pmap("ga", function()
  local id = clip_here()
  if id then paw.roll_clips.activate(id) end
end, "Edit the clip of the note under the cursor: new notes go there")
pmap("gE", function()
  local id = clip_here()
  if id then paw.roll_clips.toggle(id) end
end, "Edit the clip of the note under the cursor too, or no longer")
pmap("gn", function(ctx) paw.roll_clips.cycle(ctx.count or 1) end, "The next clip edited becomes the active one")
pmap("gN", function(ctx) paw.roll_clips.cycle(-(ctx.count or 1)) end, "The clip edited before becomes the active one")
command(
  "roll.tracks",
  function() paw.roll_clips.pick() end,
  { desc = "Choose whose notes the piano roll shows behind its own, and which clips it edits together" }
)
command("roll.only", function() paw.roll_clips.only() end, { desc = "Edit the piano roll's active clip alone" })
-- Escape cancels and stays, as in every view: `<C-w>p` goes back to the
-- window before, `<leader>vp` hides the roll.
pmap("<Esc>", function()
  if chosen() then return paw.frontend.act.clear_note_selection() end
  keymap.escape_hint()
end, "Let go of the chosen notes", { repeatable = false })
keymap.classic("<Esc>", function()
  if chosen() then return paw.frontend.act.clear_note_selection() end
  paw.layout.back()
end, { view = "pianoroll", desc = "Let go of the chosen notes; back to the window before" })

-- Diagnostics and language servers (paw.diagnostic, paw.lsp), on whatever
-- is under the cursor in each view: a note, a clip, a track, a strip, a
-- device or parameter. `K` means other things in these views, so asking
-- what is known about it is `gK`.
for _, v in ipairs({ "pianoroll", "arrange", "mixer", "devices" }) do
  map(
    "]d",
    function(ctx) paw.diagnostic.jump(1, ctx.count) end,
    { view = v, desc = "Next diagnostic here", jump = true }
  )
  map(
    "[d",
    function(ctx) paw.diagnostic.jump(-1, ctx.count) end,
    { view = v, desc = "Previous diagnostic here", jump = true }
  )
  map(
    "gK",
    function() paw.lsp.show_hover() end,
    { view = v, desc = "What the diagnostics and language servers say about what is under the cursor" }
  )
  map(
    "<leader>la",
    function() paw.lsp.code_actions() end,
    { view = v, desc = "Fixes and actions for what is under the cursor" }
  )
  map(
    "<leader>ll",
    function() paw.lsp.show_hover() end,
    { view = v, desc = "The problems and what the language servers say about what is under the cursor" }
  )
end
map("<leader>li", "lsp info", { desc = "The language servers and what they can do" })
command(
  "diagnostics",
  function(ctx) paw.diagnostic.list(ctx.args[1] == "clip" and paw.ui.views.pianoroll.clip_id or nil) end,
  {
    desc = "List the diagnostics, grouped by what they are about, or (`diagnostics clip`) the piano roll's; Enter goes to one",
    complete = { "clip" },
  }
)
command("lsp", function(ctx) paw.lsp.command(ctx) end, {
  desc = "Language servers: `lsp info`, `lsp start|stop|restart [name]`, `lsp log`",
  complete = function() return paw.lsp.command_complete() end,
})

-- Piano roll: on a selection.
local function px(lhs, fn, desc, role)
  map(lhs, nil, {
    view = "pianoroll",
    mode = "x",
    desc = desc,
    role = role,
    operator = function(region, ctx)
      if roll:clip() then fn(editing(), region, ctx) end
    end,
  })
end
px("x", function(clip, region, ctx) keymap.setreg(edit.roll.delete(clip, region), ctx.register) end, "Delete")
px("p", function(clip, region, ctx)
  local value = keymap.getreg(ctx.register)
  if not value then return end
  local replaced = edit.roll.delete(clip, region)
  roll:paste(value, true, ctx.count)
  keymap.setreg(replaced)
end, "Replace with the register")
px("<C-a>", function(clip, region, ctx)
  local by = ctx.count or 1
  edit.roll.each(clip, region, function(n) n.pitch = math.min(127, n.pitch + by) end)
end, "Up a semitone")
px("<C-x>", function(clip, region, ctx)
  local by = ctx.count or 1
  edit.roll.each(clip, region, function(n) n.pitch = math.max(0, n.pitch - by) end)
end, "Down a semitone")
px("]", function(clip, region)
  edit.roll.each(clip, region, function(n) n.velocity = math.min(127, n.velocity + 10) end)
end, "Louder", "second+")
px("[", function(clip, region)
  edit.roll.each(clip, region, function(n) n.velocity = math.max(1, n.velocity - 10) end)
end, "Softer", "second-")
local function lengthen_region(clip, region)
  edit.roll.each(clip, region, function(n) n.length = n.length + paw.opt.note_grid end)
end
local function shorten_region(clip, region)
  edit.roll.each(clip, region, function(n) n.length = math.max(paw.opt.note_grid, n.length - paw.opt.note_grid) end)
end
px("<A-l>", lengthen_region, "Lengthen")
px("<A-h>", shorten_region, "Shorten")
px("+", function(clip, region, ctx)
  local by = ctx.count or 1
  edit.roll.each(clip, region, function(n) n.pitch = math.min(127, n.pitch + by) end)
end, "Up a semitone")
px("-", function(clip, region, ctx)
  local by = ctx.count or 1
  edit.roll.each(clip, region, function(n) n.pitch = math.max(0, n.pitch - by) end)
end, "Down a semitone")
for lhs, fn in pairs({ ["+"] = lengthen_region, ["-"] = shorten_region }) do
  keymap.classic(lhs, nil, {
    view = "pianoroll",
    mode = "x",
    desc = lhs == "+" and "Lengthen" or "Shorten",
    operator = function(region)
      if roll:clip() then fn(editing(), region) end
    end,
  })
end

-- Piano roll: insert mode is a pencil (`paw.roll_draw`). It draws a note
-- from the cursor, or takes up the note under it; `h` `l` move the edge
-- of the note that the cursor is on. What is drawn is written when insert
-- mode ends, as one undo step.
local function drawmap(lhs, fn, desc, extra)
  map(lhs, fn, util.merge({ view = "pianoroll", mode = "i", desc = desc }, extra or {}))
end
local drawing = paw.roll_draw
for digit = 0, 9 do
  drawmap(
    tostring(digit),
    function() drawing.digit(digit) end,
    digit == 0 and "The start of the note (or a count)" or "A count for the next key"
  )
end
for _, lhs in ipairs({ "l", "<Right>" }) do
  drawmap(lhs, function() drawing.grow(1) end, "The edge a step right: longer at the end, shorter at the start")
end
for _, lhs in ipairs({ "h", "<Left>" }) do
  drawmap(lhs, function() drawing.grow(-1) end, "The edge a step left: shorter at the end, longer at the start")
end
for _, lhs in ipairs({ "k", "<Up>" }) do
  drawmap(lhs, function() drawing.bend(1) end, "Bend the note up at its end")
end
for _, lhs in ipairs({ "j", "<Down>" }) do
  drawmap(lhs, function() drawing.bend(-1) end, "Bend the note down at its end")
end
drawmap("o", function() drawing.edge() end, "The other edge of the note")
drawmap("^", function() drawing.edge("start") end, "The start of the note")
drawmap("$", function() drawing.edge("end") end, "The end of the note")
for _, lhs in ipairs({ "+", "<C-a>" }) do
  drawmap(lhs, function() drawing.pitch(1) end, "The note up a semitone")
end
for _, lhs in ipairs({ "-", "<C-x>" }) do
  drawmap(lhs, function() drawing.pitch(-1) end, "The note down a semitone")
end
drawmap("K", function() drawing.pitch(12) end, "The note up an octave")
drawmap("J", function() drawing.pitch(-12) end, "The note down an octave")
drawmap("r", function(ctx) drawing.name(ctx.char) end, "The pitch by its name: r c, r f then #", { char = true })
drawmap("#", function() drawing.accidental(1) end, "After r and a name: sharp")
drawmap("b", function() drawing.accidental(-1) end, "After r and a name: flat")
drawmap(">", function() drawing.nudge(1) end, "The note a step later")
drawmap("<lt>", function() drawing.nudge(-1) end, "The note a step earlier")
drawmap("=", function() drawing.length_key() end, "The length in note values: =4 a beat, =8. dotted, =8t triplet")
drawmap(".", function()
  if not drawing.length_key(".") then drawing.again() end
end, "The note or chord again, after this one")
drawmap("t", function() drawing.length_key("t") end, "After = and a value: a triplet")
drawmap("<CR>", function() drawing.next("legato") end, "Keep the note, and draw the next where it ends")
drawmap("<Space>", function() drawing.next("rest") end, "Keep the note, and draw the next after a step's rest")
drawmap("c", function() drawing.pick_chord() end, "A chord here: choose or type its symbol (V7, ii, Cmaj7, F#m9/C#)")
drawmap(
  "m",
  function(ctx) drawing.mark(ctx.char) end,
  "A mark of the song here: mk a key, mt a tempo, ms a time signature, m' a marker",
  { char = true }
)
drawmap(
  "C",
  function() drawing.pick_chord(true) end,
  "A strummed chord here: its notes one after the other (strum, strum_dir)"
)
drawmap("~", function() drawing.tie() end, "Tie the note to the next note: it ends where the next one starts")
drawmap(
  "<C-r>",
  function(ctx) drawing.put_register(ctx.char) end,
  "Put the notes of a register at the note: <C-r> and its name",
  { char = true }
)
drawmap("<Tab>", function() drawing.snippet() end, "Expand a snippet here: choose one")
drawmap("a", function() drawing.articulate() end, "An articulation on the note (from the articulations extension)")
drawmap(
  "e",
  function(ctx) drawing.expression(ctx.char) end,
  "A controller here: em modulation, ee expression, eb breath, es sustain, e and a number",
  { char = true }
)
drawmap("<C-n>", function() drawing.suggest(1) end, "Suggest what comes next here: the next suggestion")
drawmap("<C-p>", function() drawing.suggest(-1) end, "Suggest what comes next here: the suggestion before")
drawmap("<C-e>", function() drawing.unsuggest() end, "Put back what was there before the suggestions")
drawmap("x", function() drawing.erase() end, "Erase the note: a note of the clip goes when insert mode ends")
drawmap("<BS>", function() drawing.back() end, "Take back the note kept last, to draw it again")
drawmap("<C-w>", function() drawing.back() end, "Take back the note kept last, to draw it again")
drawmap("<C-u>", function() drawing.back_all() end, "Take back all that this insert drew")
drawmap("]", function() drawing.velocity(1) end, "Louder notes")
drawmap("[", function() drawing.velocity(-1) end, "Softer notes")
drawmap("I", function() drawing.toggle_step() end, "Step input on or off: notes played on a MIDI keyboard go in")
drawmap("<C-o>", function()
  -- One command of normal mode: what is drawn is written, and insert mode
  -- (step input if it was on) starts again after it.
  local stepping = drawing.stepping()
  keymap.set_mode("n")
  keymap.after_next(function()
    if paw.ui.focused == "pianoroll" and keymap.mode == "n" then
      if stepping then drawing.step_next() end
      keymap.set_mode("i")
    end
  end)
end, "One command of normal mode, then draw again")

-- Piano roll: snippets (runtime/lua/paw/snippet.tl). While one is active its
-- keys come first; otherwise each key does what it does everywhere else.
roll.layer("snippet", 40, function(p) paw.snippet.paint(p) end)
command("snippet", function(ctx)
  local name = ctx.args[1]
  local region = paw.snippet.take_cmdline_selection()
  if name == nil then return paw.snippet.pick({ count = ctx.count, selection = region }) end
  local _, why = paw.snippet.expand(tostring(name), { count = ctx.count, selection = region })
  if why then paw.notify(why, "warn") end
end, {
  desc = "Expand a snippet at the piano roll's cursor: `snippet dominant`, `3snippet arp`; alone, choose one",
  complete = function()
    local out = {}
    for _, s in ipairs(paw.snippet.offered("pianoroll")) do
      out[#out + 1] = { text = s.name, desc = s.desc }
    end
    return out
  end,
})
-- While a snippet is active its keys come first, before a suggestion's and
-- before Escape leaves insert mode.
roll:key_scope("pianoroll.snippet", 40, function() return paw.snippet.active() ~= nil end)
local function smap(lhs, fn, desc)
  map(lhs, fn, { view = "pianoroll.snippet", mode = { "n", "i" }, desc = desc, repeatable = false })
end
smap("<Tab>", function() paw.snippet.jump(1) end, "The snippet's next choice")
smap("<S-Tab>", function() paw.snippet.jump(-1) end, "The snippet's choice before")
smap("<C-n>", function() paw.snippet.step(1) end, "The snippet's choice: its next value")
smap("<C-p>", function() paw.snippet.step(-1) end, "The snippet's choice: its value before")
smap("<C-y>", function() paw.snippet.finish() end, "End the snippet, keeping its notes")
smap("<Esc>", function() paw.snippet.finish() end, "End the snippet, keeping its notes")
map(
  "<C-s>",
  function(ctx) paw.snippet.pick({ count = ctx.count }) end,
  { view = "pianoroll", mode = { "n", "i", "x" }, desc = "Choose a snippet to expand here", repeatable = false }
)

-- Piano roll: suggestions (`paw.complete`). Ctrl-Space asks the sources;
-- while a suggestion shows, its keys come first, in normal and insert mode.
local ni = { "n", "i" }
map(
  "<C-Space>",
  function() paw.complete.request("manual") end,
  { view = "pianoroll", mode = ni, desc = "Suggest what comes next", repeatable = false }
)
local function cmap(lhs, fn, desc, modes)
  map(lhs, fn, { view = "pianoroll.complete", mode = modes or ni, desc = desc, repeatable = false })
end
cmap("<Tab>", function() paw.complete.accept() end, "Accept the suggestion")
cmap("<C-l>", function() paw.complete.accept(true) end, "Accept the suggestion's next note or chord")
cmap("<C-n>", function() paw.complete.select(1) end, "The next alternative")
cmap("<C-p>", function() paw.complete.select(-1) end, "The previous alternative")
for n = 1, 9 do
  cmap("<A-" .. n .. ">", function() paw.complete.select(n, true) end, "Alternative " .. n)
end
cmap("<C-e>", function() paw.complete.dismiss() end, "Dismiss the suggestion")
cmap("<Esc>", function() paw.complete.dismiss() end, "Dismiss the suggestion")
cmap("gh", function() paw.complete.audition() end, "Hear the suggestion, from a bar before", { "n" })

command(
  "complete",
  function() paw.complete.request("manual") end,
  { desc = "Suggest what comes next in the piano roll" }
)
command(
  "complete.accept",
  function(args) paw.complete.accept(args[1] == "next") end,
  { desc = "Accept the suggestion: `:complete.accept next` takes its next note or chord only" }
)
command("complete.dismiss", function() paw.complete.dismiss() end, { desc = "Dismiss the suggestion" })
command(
  "complete.audition",
  function() paw.complete.audition() end,
  { desc = "Hear the suggestion through the track, from a bar before" }
)
command("complete.sources", function()
  local lines = {}
  for _, s in ipairs(paw.complete.list()) do
    lines[#lines + 1] = string.format(
      "%-16s priority %-4d %s%s",
      s.name,
      s.priority,
      table.concat(s.views, ","),
      s.auto and "  auto" or ""
    )
  end
  paw.notify(#lines > 0 and table.concat(lines, "\n") or "no completion sources: an extension adds them")
end, { desc = "List the completion sources" })
