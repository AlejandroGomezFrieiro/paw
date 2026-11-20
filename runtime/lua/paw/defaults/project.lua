-- The default commands and keys: project and program. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local api = paw.api
local command, map = paw.command, paw.keymap.set
local cursor, transport = paw.cursor, paw.transport
local keymap, edit = paw.keymap, paw.edit
local roll = paw.ui.views.pianoroll
local common = require("paw.defaults.common")
local need_track, plain_folder = common.need_track, common.plain_folder

--- What made the state the project is in now, as the undo tree names it.
local function step_name()
  local ok, tree = pcall(api.undo_tree)
  if not ok then return nil end
  local current = api.undo_current()
  for _, state in ipairs(tree.states or {}) do
    if state.id == current then return state.label or state.keys end
  end
end

command("undo", function(ctx)
  local undone = {}
  for _ = 1, ctx.count or 1 do
    local name = step_name()
    if not paw.undo() then
      if #undone == 0 then return paw.notify("nothing to undo") end
      break
    end
    undone[#undone + 1] = name or "a change"
  end
  paw.notify("undid " .. table.concat(undone, ", "))
end, { desc = "Undo, saying what was undone" })
command("redo", function(ctx)
  local redone = {}
  for _ = 1, ctx.count or 1 do
    if not paw.redo() then
      if #redone == 0 then return paw.notify("nothing to redo") end
      break
    end
    redone[#redone + 1] = step_name() or "a change"
  end
  paw.notify("redid " .. table.concat(redone, ", "))
end, { desc = "Redo, saying what was redone" })
--- The files of a project kept in a folder that the buffer of the current
--- window shows: a clip's file in the piano roll, a chain's files in the
--- device panel; nil for the whole project. With each, the files that it
--- needs to be found: its track's `track.json` and `project.toml`.
local function buffer_files()
  local win = paw.layout.current()
  local files = api.project_files()
  if #files == 0 or not win then return nil end
  local want
  if win.view == "pianoroll" and roll:clip() then
    local id = roll:clip().id
    want = function(f) return f.clip == id end
  elseif win.view == "devices" and cursor.track_id() then
    local id = cursor.track_id()
    want = function(f) return f.track == id and (f.what == "devices" or f.what == "state") end
  else
    return nil
  end
  local out, tracks = {}, {}
  for _, f in ipairs(files) do
    if want(f) then
      out[#out + 1] = f.path
      if f.track then tracks[f.track] = true end
    end
  end
  for _, f in ipairs(files) do
    if (f.what == "track" and tracks[f.track]) or f.what == "project" then out[#out + 1] = f.path end
  end
  return out
end

--- Paths as a short list for a message: the names of the files.
local function file_names(list)
  local names = {}
  for i, path in ipairs(list) do
    if i > 4 then
      names[#names + 1] = string.format("%d more", #list - 4)
      break
    end
    names[#names + 1] = path:match("([^/]+)$") or path
  end
  return table.concat(names, ", ")
end

command("write", function(ctx)
  local path = ctx.args[1] and tostring(ctx.args[1]) or nil
  -- In a project kept in a folder, `:w` writes the files of this window's
  -- buffer (and those that it needs to be found); `:wa` writes them all.
  if not path and not api.project_get("path") and paw.midifile.document then
    local ok, written = pcall(paw.midifile.write_clip)
    if not ok then return paw.notify(tostring(written):gsub("^[^:]*:%d+: ", ""), "error") end
    return paw.notify("wrote " .. written)
  end
  if not path and not api.project_get("path") and paw.chain_document then
    local doc = paw.chain_document
    local ok, err = pcall(api.chain_write, doc.track, doc.path)
    if not ok then return paw.notify(tostring(err):gsub("^[^:]*:%d+: ", ""), "error") end
    api.project_mark_saved()
    return paw.notify("wrote " .. doc.path)
  end
  local files = not path and buffer_files()
  if files then
    local ok, written = pcall(api.project_save_files, files)
    if not ok then return paw.notify(tostring(written):gsub("^[^:]*:%d+: ", ""), "error") end
    if #written == 0 then return paw.notify("nothing to write: " .. file_names(files) .. " are as on the disk") end
    return paw.notify(string.format("wrote %s", file_names(written)))
  end
  -- A relative name goes beside the project, or to the folder `:cd` set.
  if path then path = paw.files.project_path(path) end
  -- A project that has no file yet is asked where it goes, when there is
  -- somebody to ask.
  if not path and not api.project_get("path") and paw.fx.interactive() then return paw.frontend.save_as() end
  -- A file of another program: written in its format when it holds whole
  -- projects, else it is for `:export` (paw/formats.tl).
  local format = path and paw.formats.for_path(path, "export")
  if format and format.project then
    local args = {}
    for k, v in pairs(ctx.args) do
      if type(k) == "string" then args[k] = v end
    end
    return paw.formats.export(path, { args = args })
  elseif format then
    return paw.notify("a project is not saved as " .. (format.desc or format.name) .. ": `:export " .. path .. "` writes one", "warn")
  end
  -- A project is a folder: one that holds other files and no project is
  -- not taken over.
  local folder = (path or api.project_get("path") or ""):gsub("%.[jJ][sS][oO][nN]$", "")
  if folder ~= "" and paw.files.is_dir(folder) and not paw.project.is_folder(folder) and #api.read_dir(folder) > 0 then
    return paw.notify(folder .. " has files and is not a project: `:w " .. folder:gsub("/+$", "") .. "/song` makes a project folder in it", "warn")
  end
  local saved, note = paw.project.write(path)
  paw.notify(note and (note .. ": " .. saved) or ("saved " .. saved))
end, { desc = "Save the project as a folder: `write song`", complete = { "projects" } })
command("wall", function()
  local path = api.project_get("path")
  if not path and paw.fx.interactive() then return paw.frontend.save_as() end
  local saved, note = paw.project.write()
  paw.notify(note and (note .. ": " .. saved) or ("saved " .. saved))
end, { desc = "Save every file of the project" })
command.alias("wa", "wall")
command("saveas", function() paw.frontend.save_as() end, { desc = "Save the project under a name chosen from a list of directories" })
command("edit", function(ctx)
  -- Alone, as in Vim, it opens the project's own file again: `:e!` goes
  -- back to the saved project and throws away what changed since.
  if not ctx.args[1] then
    local path = api.project_get("path")
    if not path then return paw.notify("the project has no file yet: `:e song` opens one, `:w song` saves this one", "warn") end
    if not paw.project.guard("edit") then return end
    paw.open(path)
    return paw.notify("opened " .. path .. " again as it was saved")
  end
  local how = ctx.args[2] and tostring(ctx.args[2])
  if how and how ~= "offline" and how ~= "online" then return paw.notify("usage: edit <project> [offline|online]", "warn") end
  local path = tostring(ctx.args[1])
  -- A folder is listed as a buffer to edit (`paw.files`), unless it is a project.
  if plain_folder(path) then return paw.files.open(path, { here = true }) end
  -- A buffer's name, a view's or an address (`paw://tracks`) shows it here;
  -- only a file's path asks about the project.
  local view, buf, target = paw.layout.resolve(path)
  local win = view and not how and paw.layout.current()
  if win then return paw.layout.show_in(win, view, buf and not buf.single and buf.id or nil, target) end
  path = paw.files.path(path)
  if paw.formats.for_path(path, "import") or paw.midifile.is_clip_file(path) or paw.is_audio_file(path) or paw.is_chain_file(path) then
    local args = { path }
    for k, v in pairs(ctx.args) do
      if type(k) == "string" then args[k] = v end
    end
    return paw.commands.run("open", args)
  end
  if not paw.project.guard("edit") then return end
  paw.open(path, { plugins_offline = how == "offline", all_online = how == "online" })
end, { desc = "Open a project: `edit song`; alone, the project's file again (`edit!` goes back to it as saved); `edit song offline` with every plugin offline, `online` with none held back; a MIDI or sound file as `open` does", complete = { "openable", function() return { "offline", "online" } end } })
command("new", function()
  if paw.project.guard("new") then paw.project.new() end
end, { desc = "Start an empty project, unless there is unsaved work" })

--- The example and practice projects that come with paw, by name:
--- `{ name, path }` for each `.lua` file under `examples/` (not the
--- configuration) of the first source tree or package that has them.
local function examples()
  for _, root in ipairs(paw.help.roots()) do
    local out = {}
    local function walk(dir, prefix)
      for _, entry in ipairs(api.read_dir(dir)) do
        local name = entry.name
        if entry.is_dir and name ~= "config" then
          walk(dir .. "/" .. name, prefix .. name .. "/")
        elseif not entry.is_dir and name:match("%.lua$") then
          out[#out + 1] = { name = (prefix .. name:gsub("%.lua$", "")):gsub("^tutorials/", ""), path = dir .. "/" .. name }
        end
      end
    end
    walk(root .. "/examples", "")
    if #out > 0 then
      table.sort(out, function(a, b) return a.name < b.name end)
      return out
    end
  end
  return {}
end
command("example", function(ctx)
  local list = examples()
  if #list == 0 then
    return paw.notify("no examples found: start paw in its source tree, or set PAW_HOME to it", "warn")
  end
  local word = ctx.args[1] and tostring(ctx.args[1]) or ""
  local found
  for _, e in ipairs(list) do
    if e.name == word then found = e end
  end
  -- A part of the name is enough when only one example has it.
  if not found and word ~= "" then
    local some = {}
    for _, e in ipairs(list) do
      if e.name:find(word, 1, true) then some[#some + 1] = e end
    end
    if #some == 1 then found = some[1] end
  end
  if not found then
    local names = {}
    for i, e in ipairs(list) do names[i] = e.name end
    return paw.notify((word == "" and "which example? " or "no single example `" .. word .. "`: ") .. table.concat(names, ", "), "warn")
  end
  if not paw.project.guard("example") then return end
  paw.project.new()
  dofile(found.path)
  -- The example is where its history starts: `u` does not take it apart.
  api.undo_reset()
  paw.notify("opened the example " .. found.name .. ": `:w song` saves it as your own")
end, {
  desc = "Open an example or a practice project that comes with paw: `example demo-song`, `example make-music/2-midi-keyboard`",
  complete = function()
    local out = {}
    for _, e in ipairs(examples()) do out[#out + 1] = { text = e.name, desc = e.path } end
    return out
  end,
})
-- `:render`, `:render.cancel` and `:stems` are in paw/render.lua.
command("track.bounce", function()
  local track = need_track()
  if not track then return end
  -- What the track sounds like, devices and all, as one audio clip on a new
  -- track below it; the original is muted, not removed.
  local bounced = paw.bounce(track)
  if not bounced then return paw.notify("nothing on the track to bounce", "warn") end
  cursor.set_track(bounced)
end, { desc = "Render the track with its devices to audio on a new track, and mute the original" })
command("lane.write", function(ctx)
  local on = ctx.args[1]
  if on == nil then on = not transport.write else on = on == true or on == "on" end
  transport.write = on
  paw.notify(on and "moving a fader or a parameter while playing now writes automation" or "automation writing is off")
end, { desc = "Write automation by moving things while the song plays, on every track: `lane.write`, `lane.write off`" })
-- How a track treats its automation: see `paw.lanes.modes`.
command("automation", function(ctx)
  local track = need_track()
  if not track then return end
  local mode = ctx.args[1] and tostring(ctx.args[1]):lower()
  if not mode then
    -- Without a word: the next mode in turn.
    local modes = paw.lanes.modes
    for i, name in ipairs(modes) do
      if name == track.automation then mode = modes[i % #modes + 1] end
    end
  end
  if not paw.lanes.mode_text[mode] then
    return paw.notify("automation: " .. table.concat(paw.lanes.modes, ", "), "warn")
  end
  local ids = ctx.args[2] == "all" and api.track_list() or { track.id }
  for _, id in ipairs(ids) do api.track_set(id, "automation", mode) end
  paw.notify(string.format("%s: automation %s (%s)", ctx.args[2] == "all" and "every track" or track.name, mode, paw.lanes.mode_text[mode]))
end, {
  desc = "How the track treats automation: `automation touch`, `automation read all`; read, touch, latch, write or off",
  complete = function() return paw.lanes.modes end,
})
command("engine", function(ctx)
  local wanted = ctx.args.threads ~= nil and tonumber(ctx.args.threads) or nil
  if ctx.args.threads ~= nil and not wanted then return paw.notify("engine: threads=N, a number, or 0 for as many as the machine has", "warn") end
  local before = api.engine_get().threads
  if wanted then paw.opt.threads = wanted end
  if ctx.args[1] or ctx.args.rate or ctx.args.buffer then
    api.engine_restart({ backend = ctx.args[1] and tostring(ctx.args[1]), sample_rate = ctx.args.rate, buffer_size = ctx.args.buffer })
  end
  -- The audio thread takes the new threads at its next block: wait for it,
  -- so that the count said is the one that runs.
  if wanted and wanted ~= before then
    local deadline = api.now() + 500
    while api.engine_get().threads == before and api.now() < deadline do api.sleep(5) end
  end
  local e = api.engine_get()
  local asked = wanted and wanted > 0 and e.threads ~= wanted and string.format(" (%d asked)", wanted) or ""
  paw.notify(string.format("%s: %s, %d Hz, %d %s%s, %d xruns", e.backend, e.device, e.sample_rate, e.threads,
    e.threads == 1 and "thread" or "threads", asked, e.xruns))
end, { desc = "Show the audio engine, restart it, or set its threads: `engine pipewire rate=48000 buffer=256`, `engine threads=4`" })
command("engine.status", function()
  local e = api.engine_get()
  paw.notify(string.format("%s %s: cpu %d%%, %d xruns, %d late plugin blocks, %d MIDI events dropped, %d recorded frames lost, %d devices stopped",
    e.backend, e.device, math.floor((e.cpu or 0) * 100 + 0.5), e.xruns, e.late_blocks, e.midi_dropped, e.record_dropped, e.devices_stopped))
end, { desc = "What has gone wrong while playing: xruns, late plugin blocks, dropped MIDI, lost recorded frames, stopped devices" })
-- The audio devices: a picker, and a command for each.
local engine_groups = { info = "", output = "output", input = "input", block = "block", rate = "rate", backend = "system" }
command("audio", function()
  local choices = paw.audio.engine_choices()
  paw.pick({
    title = "Audio devices",
    items = choices,
    format = function(item)
      if item.group == "info" then return item.label end
      return string.format("%s %-7s %s", item.checked and "●" or " ", engine_groups[item.group], item.label)
    end,
    on_choose = function(item) paw.audio.choose_engine(item) end,
  })
end, { desc = "Choose the audio output, input, block size, sample rate and sound system from a list" })
local function device_names(which)
  return function()
    local ok, list = pcall(paw.audio.devices)
    local words = { "default" }
    for _, d in ipairs(ok and list[which] or {}) do words[#words + 1] = d.name end
    return words
  end
end
for _, which in ipairs({ "output", "input" }) do
  command("audio." .. which, function(ctx)
    if not ctx.args[1] then return paw.notify("audio." .. which .. ": " .. api.engine_get()[which == "output" and "device" or "input_device"]) end
    paw.audio.choose_engine({ [which] = table.concat(ctx.args, " ") })
  end, {
    desc = "Open the " .. which .. " device by name or part of it, or `default`: `audio." .. which .. " UR22`",
    complete = device_names(which .. "s"),
  })
end
command("audio.buffer", function(ctx)
  local frames = tonumber(ctx.args[1])
  if not frames then return paw.notify("audio.buffer: " .. paw.audio.timing()) end
  paw.audio.choose_engine({ buffer = math.floor(frames) })
end, { desc = "Frames per audio callback, or 0 for the device's own: `audio.buffer 128`" })
command("audio.rate", function(ctx)
  local rate = tonumber(ctx.args[1])
  if not rate then return paw.notify("audio.rate: " .. paw.audio.timing()) end
  paw.audio.choose_engine({ rate = math.floor(rate) })
end, { desc = "The sample rate in Hz, or 0 for the device's own: `audio.rate 48000`" })
command("audio.system", function(ctx)
  if not ctx.args[1] then return paw.notify("audio.system: " .. api.engine_get().backend) end
  paw.audio.choose_engine({ backend = tostring(ctx.args[1]) })
end, { desc = "The sound system, as `:audio` lists them: `audio.system pipewire`, `audio.system auto`",
  complete = function() return (paw.audio.devices().backends or {}) end })
-- Tracks that do not feed each other are processed side by side.
paw.on("option.changed", function(e)
  if e.name == "threads" then api.engine_set_threads(e.value) end
  if e.name == "device_sleep" then api.engine_set_sleep(e.value) end
end)
command("quit", function()
  if paw.project.unsaved() then
    return paw.notify("the project has unsaved work: `:w` saves it, `:q!` quits without it", "error")
  end
  api.quit(0)
end, { desc = "Quit, unless there are unsaved changes" })
command("quit!", function()
  paw.autosave.discard = true
  api.quit(0)
end, { desc = "Quit without saving" })
command("reload", function()
  api.reload()
  paw.defer(function() paw.notify("reloaded") end)
end, { desc = "Reload the Lua runtime, your configuration and extensions" })
command("lua", function(ctx)
  local code = ctx.args[1] or ""
  local chunk = loadstring("return " .. code, "=lua") or assert(loadstring(code, "=lua"))
  -- Asked for by hand: a minute, not the two seconds a callback gets.
  paw.limit.untrusted(chunk)
  paw.limit.extend(60000)
  local results = { chunk() }
  if #results > 0 then
    for i, v in ipairs(results) do results[i] = paw.inspect(v) end
    paw.notify(table.concat(results, ", "))
  end
end, { desc = "Run Lua: `lua paw.project.tempo = 90`, `lua paw.tracks()`", raw = true })
command("messages", function()
  local styles = { info = "Normal", warn = "Warn", error = "Error" }
  local lines = {}
  for _, m in ipairs(paw.ui.messages) do lines[#lines + 1] = { text = m.text, style = styles[m.level] } end
  if #lines == 0 then lines[1] = { text = "No messages yet.", style = "Dim" } end
  paw.ui.page("Messages", lines, { bottom = true })
end, { desc = "Show every message so far, the newest at the bottom" })
command("commands", function()
  local lines = {}
  for _, spec in ipairs(paw.commands.list()) do
    lines[#lines + 1] = string.format("%-22s %s", spec.name, spec.desc)
  end
  paw.ui.page("Commands", lines)
end, { desc = "List every command" })
command("ext.load", function(ctx)
  local name = tostring(ctx.args[1] or "")
  if name == "" then return paw.notify("which extension? `:ext.load notation`; `:extensions` lists the loaded ones", "warn") end
  if paw.ext.loaded[name] then return paw.notify(name .. " is loaded already") end
  local entry, err = paw.ext.load_bundled(name)
  if not entry then return paw.notify(err, "warn") end
  if entry.ok then paw.notify(name .. " loaded for this session: `paw.ext.load` in init.lua keeps it") end
end, {
  desc = "Load a bundled extension now: `ext.load notation`",
  complete = function()
    local out = {}
    for _, name in ipairs(paw.ext.bundled()) do
      if not paw.ext.loaded[name] then out[#out + 1] = name end
    end
    return out
  end,
})
local function loaded_names()
  local out = {}
  for _, e in ipairs(paw.ext.list()) do out[#out + 1] = e.name end
  return out
end
local function unload(ctx, force)
  local name = tostring(ctx.args[1] or "")
  local ok, err = paw.ext.unload(name, { force = force })
  if not ok then return paw.notify(err, "warn") end
  paw.notify(name .. " unloaded: what it registered is gone" .. (type(ok) == "string" and "; " .. ok or ""))
end
command("ext.unload", function(ctx) unload(ctx, false) end, {
  desc = "Take a loaded extension away, with everything it registered: `ext.unload notation`; refused while its devices are on tracks",
  complete = loaded_names,
})
command("ext.unload!", function(ctx) unload(ctx, true) end, {
  desc = "Take a loaded extension away even while its devices are on tracks, where they stay until removed",
  complete = loaded_names,
})
command("extensions", function()
  local lines = {}
  for _, e in ipairs(paw.ext.list()) do
    local head = e.name .. (e.version and " " .. e.version or "")
    lines[#lines + 1] = { text = string.format("%-24s %s", head, e.ok and e.path or "FAILED: " .. tostring(e.error)), style = e.ok and "Title" or "Error" }
    if e.manifest and e.manifest.description then lines[#lines + 1] = "  " .. e.manifest.description end
    for _, group in ipairs(paw.ext.provides(e.name)) do
      -- Wrapped, the title only on the first line.
      local line = string.format("  %-22s ", group.title)
      for i, item in ipairs(group.items) do
        if i > 1 and #line + #item > 100 then
          lines[#lines + 1] = { text = line, style = "Dim" }
          line = string.rep(" ", 25)
        end
        line = line .. item .. "  "
      end
      lines[#lines + 1] = { text = line, style = "Dim" }
    end
  end
  if #lines == 0 then lines[1] = "No extensions loaded. They live in " .. api.env().config_dir .. "/extensions" end
  paw.ui.page("Extensions", lines)
end, { desc = "List loaded extensions, each with what it registered" })

for _, name in ipairs({ "open", "edit", "new", "example" }) do paw.project.allow_discard(name) end

for alias, target in pairs({ w = "write", e = "edit", q = "quit", ["q!"] = "quit!", u = "undo" }) do
  command.alias(alias, target)
end

command("cmdline", function(ctx)
  -- From a selection, the command is for it, as `:` in Vim's visual mode.
  local from_visual = ctx.mode == "x" and keymap.selection() ~= nil
  if from_visual then keymap.set_mode("n") end
  paw.ui.input({
    prompt = ":",
    text = from_visual and "'<,'>" or nil,
    history = "cmdline",
    -- Command names, then what each command says its arguments are.
    complete = function(text) return paw.commands.complete(text) end,
    -- What the line would act on, shown as it is typed: paw/ex.tl.
    preview = function(text) return paw.ex.preview(text) end,
  }, function(line)
    -- A number alone is a bar to go to, as it is a line in an editor.
    if line:match("^%s*%d+%s*$") then return paw.commands.run("cursor.bar", { tonumber(line) }) end
    if line:match("%S") then paw.state.last_cmdline = line paw.commands.used(line:match("^%s*:?(%S+)")) end
    -- What the line changes is one undo step, named by the line, not by
    -- the `:` that opened it.
    api.undo_label(nil)
    api.undo_label(":" .. line:match("^%s*:?(.-)%s*$"))
    paw.commands.exec(line)
  end)
end, { desc = "Type a command" })
