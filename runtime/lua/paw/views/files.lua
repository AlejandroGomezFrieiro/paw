-- The file manager, edited as text after oil.nvim and fyler.nvim
-- (paw/textbuf.lua says how text buffers work):
--
--   :e some/folder         paw://files/home/me/music    a folder a line, in this window
--   :Files                 paw://tree/home/me/music     the folder as a tree, in a split
--
-- A line is a file or a folder (`name/`): its name, then what is known of
-- it (length, rate and channels of a sound file, its size). Rename by
-- changing the name, move by giving a path (`../old/kick.wav`), make a
-- file or folder by typing a line (`name/` for a folder), copy a file with
-- `yyp` and another name, delete with `dd`; `:w` shows what will be done
-- and `y` does it. A file that is deleted goes to the trash (the
-- freedesktop trash), never away; nothing is overwritten.
--
-- Enter opens a folder, a project (asking about unsaved work first), and
-- places a sound or MIDI file at the cursor's track and time; `go` brings
-- it in on a new track; `gh` hears it. The tree opens and closes folders
-- with Enter and `za`.
local api = paw.api
local util = paw.util
local tb = paw.textbuf
local quote, unquote, cells = tb.quote, tb.unquote, tb.cells

local M = {}

local options = require("paw.options")
options.define("files_hidden", false) -- list files whose names start with a dot
options.define("files_hear", false)   -- hear the sound file under the cursor in a files buffer, once it rests there

-- Paths ----------------------------------------------------------------------------

local function home() return os.getenv("HOME") or "/" end
local function cwd() return os.getenv("PWD") or home() end

--- A path without `.`, `..` and doubled or trailing slashes; `/` for the root.
local function normalize(path)
  local parts = {}
  for part in tostring(path):gmatch("[^/]+") do
    if part == ".." then
      parts[#parts] = nil
    elseif part ~= "." then
      parts[#parts + 1] = part
    end
  end
  return "/" .. table.concat(parts, "/")
end

--- The path a name stands for in `base`: `~` is the home directory, a name
--- with a slash first is from the root, any other from `base`.
local function resolve(path, base)
  path = tostring(path)
  if path == "~" or path:sub(1, 2) == "~/" then path = home() .. path:sub(2) end
  if path:sub(1, 1) ~= "/" then path = (base or cwd()) .. "/" .. path end
  return normalize(path)
end

local function join(dir, name) return dir == "/" and "/" .. name or dir .. "/" .. name end
local function dirname(path) return normalize(path:match("^(.*)/[^/]+$") or "/") end
local function basename(path) return path:match("([^/]+)$") or path end

-- The folder that `:cd` set, and the one before it for `:cd -`.
local chosen, previous

--- The folder that `:cd` set, or nil when there is none.
function M.cwd() return chosen end

--- The folder that a relative name in a command goes to: the folder that
--- `:cd` set; else the folder of the project's file; else the folder that
--- paw started in.
function M.here()
  if chosen then return chosen end
  local path = api.project_get("path")
  if path and path ~= "" then return dirname(resolve(path)) end
  return cwd()
end

--- The full path of a name that the user typed: `~` is the home folder, and
--- a relative name is in `paw.files.here()`.
---   paw.files.path("mix.wav")  -- "/home/me/songs/mix.wav" in the folder of the project
function M.path(name)
  return resolve(name, M.here())
end

--- The full path of a project's name that the user typed, as `:w` takes
--- it: as `path`, but a relative name goes beside a project folder, not
--- into it.
---   paw.files.project_path("take2")  -- "/home/me/songs/take2" beside songs/song
function M.project_path(name)
  local path = api.project_get("path")
  if not chosen and path and path:match("/project%.toml$") then
    return resolve(name, dirname(dirname(resolve(path))))
  end
  return M.path(name)
end

--- Set the folder for relative names, as `:cd` does: `dir` is relative to
--- the folder now; `-` is the folder before; nil is the home folder;
--- false returns to the default (beside the project).
--- Returns the folder, or nil and why not.
function M.cd(dir)
  if dir == false then
    chosen, previous = nil, nil
    return M.here()
  end
  local target
  if dir == "-" then
    if not previous then return nil, "no folder before this one" end
    target = previous
  else
    target = resolve(dir or home(), M.here())
  end
  local stat = api.fs_stat(target)
  if not (stat and stat.dir) then return nil, target .. " is not a folder" end
  previous, chosen = M.here(), target
  return target
end

--- The name of the buffer that lists a folder, as a tree or not.
function M.buffer_name(dir, tree)
  return (tree and "paw://tree" or "paw://files") .. normalize(dir)
end

--- True if a path is a folder.
function M.is_dir(path)
  local stat = api.fs_stat(resolve(path, M.here()))
  return stat ~= nil and stat.dir
end

--- A path as a person writes it, from `base` when it is below it.
local function shown(path, base)
  if base ~= "/" and path:sub(1, #base + 1) == base .. "/" then return path:sub(#base + 2) end
  local h = home()
  if path == h then return "~" end
  if path:sub(1, #h + 1) == h .. "/" then return "~" .. path:sub(#h + 1) end
  return path
end

-- What a file is --------------------------------------------------------------------

local function human(size)
  if size < 1024 then return string.format("%dB", size) end
  if size < 1024 * 1024 then return string.format("%.0fK", size / 1024) end
  if size < 1024 * 1024 * 1024 then return string.format("%.1fM", size / 1024 / 1024) end
  return string.format("%.1fG", size / 1024 / 1024 / 1024)
end

local function length_text(seconds)
  if seconds < 60 then return string.format("%.1fs", seconds) end
  return string.format("%d:%04.1f", math.floor(seconds / 60), seconds % 60)
end

-- Sound files' headers, kept while the file is as it was.
local sounds = {}

--- What a sound file's header says: `{ rate, channels, seconds }`, or nil
--- for a file that is not one that can be read.
function M.sound_info(path, stat)
  stat = stat or api.fs_stat(path)
  if not stat then return nil end
  local key = path .. "\0" .. (stat.mtime or 0) .. "\0" .. stat.size
  local hit = sounds[path]
  if hit and hit.key == key then return hit.info or nil end
  local ok, info = pcall(api.fs_sound, path)
  sounds[path] = { key = key, info = ok and info or false }
  return ok and info or nil
end

local function is_sound(path) return paw.is_audio_file(path) end
local function is_midi(path) return paw.midifile.is_midi_file(path) end

-- Reading ------------------------------------------------------------------------------

--- The files the project plays, as a set of paths.
local function used_media()
  local used = {}
  for _, f in ipairs(api.media_list()) do used[normalize(f.path)] = true end
  return used
end

local function listing(dir, st, tree, depth, out, used)
  local hidden = st.hidden
  if hidden == nil then hidden = paw.opt.files_hidden end
  local entries = api.read_dir(dir)
  table.sort(entries, function(a, b)
    if a.is_dir ~= b.is_dir then return a.is_dir end
    local x, y = a.name:lower(), b.name:lower()
    if x ~= y then return x < y end
    return a.name < b.name
  end)
  for _, e in ipairs(entries) do
    if hidden or e.name:sub(1, 1) ~= "." then
      local path = join(dir, e.name)
      local stat = api.fs_stat(path)
      local item = { id = path, name = e.name, dir = e.is_dir, depth = depth, stat = stat }
      if used and not e.is_dir and is_sound(path) then item.unused = not used[path] end
      if not (st.filter == "unused" and (e.is_dir or not item.unused)) then out[#out + 1] = item end
      if tree and e.is_dir and st.expanded[path] and depth < 16 then listing(path, st, tree, depth + 1, out, used) end
    end
  end
end

local function root_of(ctx) return normalize(ctx.args[1]) end

local watching

local function read(ctx)
  local st = ctx.buf.state
  st.expanded = st.expanded or {}
  local dir = root_of(ctx)
  local stat = api.fs_stat(dir)
  if not (stat and stat.dir) then return nil, dir .. " is not a folder" end
  M.watch()
  -- In the project's media folder, what no clip plays is marked.
  local media = api.media_dir()
  local used = (st.filter == "unused" or normalize(media) == dir) and used_media() or nil
  local out = {}
  listing(dir, st, ctx.kind.tree, 0, out, used)
  return out
end

local function format(item, ctx)
  local name = string.rep("  ", ctx.kind.tree and item.depth or 0) .. quote(item.name) .. (item.dir and "/" or "")
  local row = { name, "", "", "", "", "" }
  local stat = item.stat
  if not item.dir and stat then
    if is_sound(item.id) then
      local info = M.sound_info(item.id, stat)
      if info then
        row[2] = info.seconds and length_text(info.seconds) or ""
        row[3] = string.format("%gk", info.rate / 1000)
        row[4] = info.channels .. "ch"
      end
    end
    row[5] = human(stat.size)
    if item.unused then row[6] = "unused" end
  end
  return row
end

local function parse(text, ctx)
  local list = cells(text)
  if #list == 0 then return nil, "an empty line" end
  local raw = list[1].text
  local dir = false
  local body = raw:match("^(.-)/$")
  if body and body ~= "" then raw, dir = body, true end
  local name = unquote(raw)
  if name == "" or name == "." or name == ".." or name == "~" then return nil, "a file needs a name, not `" .. raw .. "`" end
  local depth = ctx.kind.tree and math.floor(list[1].col / 2 + 0.5) or 0
  return { name = name, dir = dir, depth = depth }
end

-- Writing ------------------------------------------------------------------------------

local exists = api.fs_exists

--- Make a folder and the ones above it that are missing, noting each for undoing.
local function make_dirs(path, state)
  local missing = {}
  local at = path
  while at ~= "/" and not exists(at) do
    table.insert(missing, 1, at)
    at = dirname(at)
  end
  for _, dir in ipairs(missing) do
    api.fs_mkdir(dir)
    table.insert(state.undo, function() os.remove(dir) end)
  end
end

local function info_of(trashed) return (trashed:gsub("/files/([^/]+)$", "/info/%1.trashinfo")) end

local function plan(ch, ctx)
  local root = root_of(ctx)
  local tree = ctx.kind.tree
  local steps = {}
  local function row_error(e, text) error(string.format("line %d: %s", e.row, text), 0) end

  -- Where each line puts its file: in the folder the line's place says
  -- (the one it is in, or the nearest folder above it with less indent).
  local stack = {}
  for _, e in ipairs(ch.lines) do
    local f = e.fields
    local parent = root
    if tree then
      while #stack > 0 and stack[#stack].depth >= f.depth do stack[#stack] = nil end
      if #stack > 0 then parent = stack[#stack].final end
    end
    e.final = resolve(f.name, parent)
    if f.dir then stack[#stack + 1] = { depth = f.depth, final = e.final } end
  end

  -- Moves run in the order of the lines; a folder renamed first takes what
  -- is in it, which later lines find under its new name.
  local renames = {}
  local function phys(path)
    for _, r in ipairs(renames) do
      if path == r[1] then
        path = r[2]
      elseif path:sub(1, #r[1] + 1) == r[1] .. "/" then
        path = r[2] .. path:sub(#r[1] + 1)
      end
    end
    return path
  end
  local moves, copies, makes, folders = {}, {}, {}, {}
  local made = {}
  for _, e in ipairs(ch.lines) do
    local f = e.fields
    if e.base and not e.copy_of then
      if f.dir ~= e.base.dir then row_error(e, "a file cannot become a folder, or a folder a file: delete the line and type the other") end
      local from = phys(e.id)
      if from ~= e.final then
        moves[#moves + 1] = { from = from, to = e.final, row = e, dir = f.dir }
        renames[#renames + 1] = { from, e.final }
      end
    elseif e.copy_of then
      if e.base.dir then row_error(e, "a folder is not copied here: only files are") end
      local from = phys(e.copy_of)
      if e.final == from then row_error(e, "a copy needs a name of its own") end
      copies[#copies + 1] = { from = from, to = e.final, row = e }
    else
      if f.dir then
        folders[#folders + 1] = { to = e.final, row = e }
      else
        makes[#makes + 1] = { to = e.final, row = e }
      end
    end
  end

  -- What would be written over, or made twice, is refused here.
  local sources = {}
  for _, m in ipairs(moves) do sources[m.from] = true end
  local seen = {}
  local function claim(item, what)
    if seen[item.to] then row_error(item.row, "two lines make " .. shown(item.to, root)) end
    seen[item.to] = true
    if exists(item.to) and not sources[item.to] then
      row_error(item.row, shown(item.to, root) .. " is there already: nothing is written over")
    end
    if what == "move" and item.to:sub(1, #item.from + 1) == item.from .. "/" then
      row_error(item.row, shown(item.from, root) .. " cannot go inside itself")
    end
  end
  for _, m in ipairs(moves) do claim(m, "move") end
  for _, c in ipairs(copies) do claim(c) end
  for _, m in ipairs(makes) do claim(m) end
  for _, d in ipairs(folders) do claim(d) end

  -- A name that another line gives up (a swap, a shift along) is reached
  -- by way of a temporary name.
  local chained = false
  for _, m in ipairs(moves) do
    if sources[m.to] then chained = true end
  end
  if chained and tree then
    error("a name is taken by another line that moves: rename them one at a time in a tree", 0)
  end

  for _, d in ipairs(folders) do
    steps[#steps + 1] = { text = "new folder " .. shown(d.to, root) .. "/", run = function(state)
      make_dirs(d.to, state)
    end }
  end
  local function text_of(m)
    local verb = dirname(m.from) == dirname(m.to) and "rename " or "move "
    return verb .. shown(m.from, root) .. (m.dir and "/" or "") .. " → " .. shown(m.to, root) .. (m.dir and "/" or "")
  end
  local function move_now(from, to, state)
    make_dirs(dirname(to), state)
    api.fs_move(from, to)
    table.insert(state.undo, function() api.fs_move(to, from) end)
  end
  if chained then
    local temps = {}
    for i, m in ipairs(moves) do
      temps[i] = join(dirname(m.from), ".move-" .. i .. "-" .. basename(m.from))
      steps[#steps + 1] = { text = "move " .. shown(m.from, root) .. " aside", quiet = true, run = function(state)
        move_now(m.from, temps[i], state)
      end }
    end
    for i, m in ipairs(moves) do
      steps[#steps + 1] = { text = text_of(m), run = function(state) move_now(temps[i], m.to, state) end }
    end
  else
    for _, m in ipairs(moves) do
      steps[#steps + 1] = { text = text_of(m), run = function(state) move_now(m.from, m.to, state) end }
    end
  end
  for _, c in ipairs(copies) do
    steps[#steps + 1] = { text = "copy " .. shown(c.from, root) .. " → " .. shown(c.to, root), run = function(state)
      local from = api.fs_stat(c.from)
      if from and from.dir then error(c.from .. " is a directory: only files are copied", 0) end
      make_dirs(dirname(c.to), state)
      api.fs_copy(c.from, c.to)
      table.insert(state.undo, function() os.remove(c.to) end)
    end }
  end
  for _, m in ipairs(makes) do
    steps[#steps + 1] = { text = "new file " .. shown(m.to, root), run = function(state)
      make_dirs(dirname(m.to), state)
      api.fs_create(m.to)
      table.insert(state.undo, function() os.remove(m.to) end)
    end }
  end
  -- What is deleted goes to the trash, deepest first.
  local gone = {}
  for _, d in ipairs(ch.deleted) do gone[#gone + 1] = { path = phys(d.id), dir = d.base.dir } end
  table.sort(gone, function(a, b) return #a.path > #b.path end)
  for _, g in ipairs(gone) do
    steps[#steps + 1] = { text = "delete " .. shown(g.path, root) .. (g.dir and "/" or "") .. " (to the trash)", run = function(state)
      if not exists(g.path) then return end
      local trashed = api.fs_trash(g.path)
      table.insert(state.undo, function()
        api.fs_move(trashed, g.path)
        os.remove(info_of(trashed))
      end)
    end }
  end
  return steps
end

-- Opening ------------------------------------------------------------------------------

--- Place a sound or MIDI file at the cursor's track and time, or on a new
--- track (`fresh`); open a project; anything else is said not to open.
local function place(path, fresh)
  local stat = api.fs_stat(path)
  if not stat then return paw.notify(path .. " is not there any more: `:e!` reads the folder again", "warn") end
  local name = basename(path)
  if is_sound(path) then
    local track = not fresh and paw.cursor.track() or nil
    local ok, clip = pcall(paw.import_audio, path, { track = track and track.id, start = paw.cursor.beat })
    if not ok then return paw.notify("could not place " .. name .. ": " .. tostring(clip), "error") end
    return paw.notify(string.format("%s: %.1f beats on “%s” at %s", name, clip.length, clip:track().name, paw.time.format(clip.start)))
  end
  if is_midi(path) then
    local track = not fresh and paw.cursor.track() or nil
    local ok, done = pcall(paw.midifile.import, path, { track = track })
    if not ok then return paw.notify("could not place " .. name .. ": " .. tostring(done):gsub("^[^:]*:%d+: ", ""), "error") end
    return paw.notify(string.format("%s: %d notes on %d track%s", name, done.notes, #done.tracks, #done.tracks == 1 and "" or "s"))
  end
  if path:lower():match("%.json$") then return paw.commands.run("open", { path }) end
  paw.notify(name .. " is not a project, a sound or a MIDI file", "warn")
end

local function toggle(buf, path)
  local st = buf.state
  if st.text:modified() then return paw.notify("the buffer has changes: `:w` applies them, `:e!` throws them away", "warn") end
  st.expanded = st.expanded or {}
  st.expanded[path] = not st.expanded[path] or nil
  tb.reload(buf)
end

local function enter(ctx, line)
  if not (line and line.id) then return paw.notify("a new line opens once `:w` has made it", "warn") end
  local stat = api.fs_stat(line.id)
  if stat and stat.dir then
    if ctx.kind.tree then return toggle(ctx.buf, line.id) end
    return tb.open(M.buffer_name(line.id, false), { here = true })
  end
  place(line.id, false)
end

-- Hearing ------------------------------------------------------------------------------

local function hearable(path) return is_sound(path) or is_midi(path) end

local function hear(path)
  local ok, err = pcall(paw.pick.hear_file, path)
  if not ok then paw.notify(tostring(err):match("^[^\n]*"):gsub("^[^:]*:%d+: ", ""), "warn") end
  return ok
end

local heard = { path = nil, since = 0, playing = nil }

--- With `paw.opt.files_hear` on, the file the cursor has rested on for
--- `paw.opt.audition_delay` ms is heard, and stops when the cursor moves on.
local function follow()
  local _, buf, t, s = tb.here()
  local kind = buf and buf.state.kind
  local path
  if paw.opt.files_hear and kind and kind.files then
    local line = t.lines[s.row]
    path = line and line.id
  end
  if path ~= heard.path then heard.path, heard.since = path, api.now() end
  if not (path and hearable(path)) then
    if heard.playing then
      heard.playing = nil
      paw.audition.stop()
    end
    return
  end
  if heard.playing ~= path and api.now() - heard.since >= (tonumber(paw.opt.audition_delay) or 150) then
    heard.playing = path
    hear(path)
  end
end

--- Start to watch the cursor, when a files buffer exists.
function M.watch()
  if watching then return end
  watching = paw.every(100, follow)
end

-- The kinds ----------------------------------------------------------------------------

local function parent_of(tree)
  return function(ctx)
    local dir = root_of(ctx)
    if dir == "/" then return nil end
    return M.buffer_name(dirname(dir), tree)
  end
end

local function kind(name, tree)
  tb.kind(name, {
    pattern = "^paw://" .. name .. "(/.*)$",
    example = "paw://" .. name .. "/home",
    tree = tree,
    files = true,
    static = true,
    title = function(ctx)
      local st = ctx.buf.state
      local text = (tree and "Tree " or "Files ") .. shown(root_of(ctx), "/")
      if st.filter == "unused" then text = text .. " · media nothing plays" end
      return text
    end,
    keywords = {},
    first_style = "TrackName",
    keys = {
      { "<CR>", tree and "open, place" or "open, place a sound" }, { "d", "trash", "dd" }, { "o", "new" }, { "y", "copy", "yyp" },
      { "go", "new track" }, { "gh", "hear" }, { "-", "up" }, { ":", "does it", ":w" }, { "?", "keys" },
    },
    hint = tree
      and "edit names and `:w` · Enter or `za` opens a folder · `dd` trash, `o` new (`name/` a folder), `yyp` copy · Enter places a sound · `go` new track · `gh` hear · `-` up"
      or "edit names and `:w` · Enter opens, places a sound at the cursor · `dd` trash, `o` new (`name/` a folder), `yyp` copy · `go` new track · `gh` hear · `-` up",
    style = function(cell, i)
      if i == 1 then return cell:match("/$") and "Accent" or "TrackName" end
      if cell == "unused" then return "Warn" end
      return "Faint"
    end,
    read = read,
    format = format,
    parse = parse,
    plan = plan,
    parent = parent_of(tree),
    open = enter,
  })
end
kind("files", false)
kind("tree", true)

-- Opening a buffer -------------------------------------------------------------------

--- Show a folder: in this window (`opts.here`), or split beside (a tree by
--- default). `opts.tree`, `opts.filter` ("unused") and `opts.hidden`.
function M.open(dir, opts)
  opts = opts or {}
  dir = resolve(dir or M.here(), M.here())
  local stat = api.fs_stat(dir)
  if not (stat and stat.dir) then return nil, dir .. " is not a folder" end
  local name = M.buffer_name(dir, opts.tree)
  local win, err = tb.open(name, { here = opts.here, vertical = opts.tree and not opts.here })
  if not win then return nil, err end
  local buf = tb.buf()
  if buf and buf.name == name then
    local st = buf.state
    if st.filter ~= opts.filter or (opts.hidden ~= nil and st.hidden ~= opts.hidden) then
      st.filter = opts.filter
      if opts.hidden ~= nil then st.hidden = opts.hidden end
      tb.reload(buf)
    end
  end
  return win
end

-- The folder a bare `:files` shows: where the current files buffer is, else
-- beside the project, else where the program started.
local function default_dir()
  local buf = tb.buf()
  if buf and buf.state.kind and buf.state.kind.files then return root_of({ args = buf.state.args }) end
  return M.here()
end

local function dir_arg(ctx)
  local arg = ctx.args[1] and tostring(ctx.args[1]) or ""
  if arg == "" then return default_dir() end
  if arg == "media" then return api.media_dir() end
  return resolve(arg, M.here())
end

local function show(tree)
  return function(ctx)
    local win, err = M.open(dir_arg(ctx), { tree = tree, here = not tree })
    if not win then paw.notify(err, "warn") end
  end
end

paw.command("cd", function(ctx)
  local arg = ctx.args[1] and tostring(ctx.args[1]) or nil
  local dir, why = M.cd(arg)
  if not dir then return paw.notify(why, "warn") end
  paw.notify("relative names go to " .. dir)
end, { desc = "Set the folder that relative names go to, as in Vim: `cd ~/songs`, `cd -` the one before; alone, the home folder", raw = false, complete = { "dirs" } })
paw.command("pwd", function()
  local how = chosen and "set with `:cd`" or api.project_get("path") and "the project's folder" or "where paw started"
  paw.notify(M.here() .. " (" .. how .. ")")
end, { desc = "Show the folder that relative names (`:render mix.wav`, `:import loop.wav`) go to" })

paw.command("files", show(false), {
  desc = "The files of a folder as a buffer to edit, in this window: `files`, `files ~/music`, `files media` (the project's own folder)",
  complete = { "files" },
})
paw.command("files.tree", show(true), {
  desc = "The files of a folder as a tree in a split, folders opened with Enter: `files.tree`, `files.tree ~/music`",
  complete = { "files" },
})
paw.command("Files", show(true), { desc = "The files as a tree in a split (`files.tree`)", complete = { "files" } })

paw.command("media.unused", function()
  local dir = api.media_dir()
  if not exists(dir) then return paw.notify("the project has no media folder yet: " .. dir, "warn") end
  local win, err = M.open(dir, { here = true, filter = "unused" })
  if not win then return paw.notify(err, "warn") end
  paw.notify("sound files in the media folder that no clip plays: `dd` the ones to go and `:w` (to the trash)")
end, { desc = "The files in the project's media folder that no clip plays, to delete (to the trash) or keep" })

-- Keys ---------------------------------------------------------------------------------

local function files_buffer()
  local _, buf, t, s = tb.here()
  if buf and buf.state.kind and buf.state.kind.files then return buf, t, s end
end

local function ctx_of(buf)
  return { buf = buf, args = buf.state.args, kind = buf.state.kind, target = buf.target }
end

local function files_key(lhs, fn, desc, modes)
  paw.keymap.set(lhs, function(ctx)
    local buf, t, s = files_buffer()
    if not buf then return paw.notify("`" .. lhs .. "` works in a files buffer: `:e` a folder, or `:files`", "warn") end
    fn(buf, t, s, ctx)
  end, { view = "textbuf", mode = modes or "n", desc = desc, repeatable = false })
end

files_key("za", function(buf, t, s)
  if not buf.state.kind.tree then return paw.notify("folders open in a tree: `:Files`", "warn") end
  local line = t.lines[s.row]
  local stat = line and line.id and api.fs_stat(line.id)
  if stat and stat.dir then toggle(buf, line.id) end
end, "Files: open or close the folder")

local function fold_all(open)
  return function(buf)
    local st = buf.state
    if not st.kind.tree then return paw.notify("folders open in a tree: `:Files`", "warn") end
    if st.text:modified() then return paw.notify("the buffer has changes: `:w` applies them, `:e!` throws them away", "warn") end
    st.expanded = {}
    if open then
      local function walk(dir, depth)
        if depth > 8 then return end
        for _, e in ipairs(api.read_dir(dir)) do
          if e.is_dir and e.name:sub(1, 1) ~= "." then
            st.expanded[join(dir, e.name)] = true
            walk(join(dir, e.name), depth + 1)
          end
        end
      end
      walk(root_of(ctx_of(buf)), 0)
    end
    tb.reload(buf)
  end
end
files_key("zR", fold_all(true), "Files: open every folder")
files_key("zM", fold_all(false), "Files: close every folder")

files_key("g.", function(buf)
  local st = buf.state
  local now = st.hidden
  if now == nil then now = paw.opt.files_hidden end
  st.hidden = not now
  tb.reload(buf)
  paw.notify(st.hidden and "hidden files shown" or "hidden files left out")
end, "Files: show or hide the files whose names start with a dot")

files_key("gh", function(buf, t, s)
  local line = t.lines[s.row]
  if not (line and line.id) then return paw.notify("no file on this line to hear", "warn") end
  if not hearable(line.id) then return paw.notify(basename(line.id) .. " is not a sound or MIDI file", "warn") end
  if hear(line.id) then paw.notify("hearing " .. basename(line.id)) end
end, "Files: hear the file")

files_key("gH", function()
  paw.opt.files_hear = not paw.opt.files_hear
  if not paw.opt.files_hear then paw.audition.stop() end
  paw.notify(paw.opt.files_hear and "hearing the file under the cursor" or "not hearing files as the cursor moves")
end, "Files: hear each sound file as the cursor rests on it, or stop doing so")

-- A new track for the file, or one each for the lines selected.
files_key("go", function(buf, t, s)
  local line = t.lines[s.row]
  if line and line.id then place(line.id, true) end
end, "Files: bring the file in on a new track")
files_key("go", function(buf, t, s)
  local region = paw.keymap.selection()
  paw.keymap.set_mode("n")
  if not region then return end
  for row = region.r0, region.r1 do
    local line = t.lines[row]
    if line and line.id and not (api.fs_stat(line.id) or {}).dir then place(line.id, true) end
  end
end, "Files: bring each file selected in on a track of its own", "x")

return M
