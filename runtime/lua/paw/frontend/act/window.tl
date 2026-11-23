-- The window's own gestures: the focus, keys, the floating window,
-- extensions' menus and bands, leaving the project, files chosen or
-- dropped, and the render dialog.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local util = require("paw.util")
local commands = require("paw.commands")
local type objects = require("paw.objects")
local type MidifileModule = require("paw.midifile")
local type RenderModule = require("paw.render")
local M = require("paw.frontend.core")
local host = require("paw.frontend.host")
local band_entries = require("paw.frontend.state").band_entries

local paw = host.paw
local A = M.act
local project_text = host.project_text
local render_module = host.render_module
local snap = host.snap
local to_arrange = host.to_arrange
local type Dropped = M.Dropped
local type RenderRequest = M.RenderRequest

--- An entry an extension added to a menu (`paw.frontend.menus`), by its
--- place in the list: `target` is the clip or the part that was clicked.
--- The timeline's entries are also offered by the buttons that make a
--- part, which have no place to give: no part, or a beat below 0, leaves
--- the cursor where it is.
function A.menu(kind: string, index: integer, target?: integer, beat?: number)
  local entry = (M.menus[kind] or {})[index]
  if not entry then
    return
  end
  if beat and beat < 0 then
    beat = nil
  end
  if kind == "clip" then
    A.menu_target(target, beat)
  elseif target and target > 0 then
    A.select(target, beat)
  else
    to_arrange()
  end
  if entry.run then
    entry.run(target, beat)
  elseif entry.command then
    commands.exec(entry.command)
  end
end

--- A click on an entry of an extension's band under the ruler
--- (`paw.frontend.bands`), by the band's place in the list and the entry's
--- in what it returns: its command runs, in the arrange view.
function A.band(band: integer, index: integer)
  local entry = band_entries(band)[index]
  if not entry then
    return
  end
  to_arrange()
  if entry.run then
    entry.run(entry)
  elseif entry.command then
    commands.exec(entry.command)
  end
end

--- The pointer on the floating window, drawn as the lines of `M.float`:
--- `kind` is "down" for a click, "scroll_up" or "scroll_down" for the
--- wheel; `line` and `col` count from 1. It goes where a click in the
--- terminal goes: in a picker a click on a row selects it, and a click on
--- the selected row (the second of a double click) chooses it.
function A.float_pointer(kind: string, line: integer, col?: integer)
  local float = paw.ui.float
  if not float then
    return
  end
  for _, r in ipairs(paw.ui.rects) do
    if r.name == float.name then
      return paw.ui.mouse(
        {kind = kind, button = "left", x = r.x + math.max(0, (col or 1) - 1), y = r.y + math.max(0, line - 1)}
      )
    end
  end
end

--- The payload of `ui.focus`.
local record Focus
  focused: boolean
end
local ui_focus: events.Event<Focus> = events.event("ui.focus")

--- Type keys as if at the keyboard: what a menu entry for an operator does
--- to a selection.
--- The window got the focus of the desktop (true), or lost it.
function A.focus(on: boolean)
  paw.ui.has_focus = on
  events.emit(ui_focus, {focused = on})
end

function A.keys(keys: string)
  -- Keys typed in the main window are not for a view in a window of its
  -- own, which sends its own (`paw.canvas.key`): they go to the window
  -- that had the keyboard before.
  if paw.canvas.open_views[paw.ui.focused] and not paw.ui.float and not paw.ui.grabber then
    paw.canvas.back(paw.ui.focused)
  end
  paw.keymap.feed(keys)
end

--- Leave the project: `what` is "quit", "new" (an empty project),
--- "open" (another, chosen from a list) or "open:<path>" (that one, already
--- chosen: from the recent list, by the desktop's dialog, or dropped on the
--- window). `how` is "save" to save its
--- changes first (asking where, for a project with no file yet),
--- "discard" to throw them away, or "go" when there are none.
function A.leave(how: string, what: string)
  local function go()
    if what == "quit" then
      if how == "discard" then
        paw.autosave.discard = true
      end
      api.quit(0)
    elseif what == "new" then
      paw.project.new()
    elseif what:match("^open:") then
      paw.recent.open(what:sub(6))
    else
      commands.exec("open")
    end
  end
  if how ~= "save" then
    return go()
  end
  if project_text("path") then
    paw.project.write()
    return go()
  end
  M.save_as(go)
end

--- A file chosen in the desktop's dialog, for what `kind` says: "import"
--- (a sound file on a new part, a MIDI file's parts at the cursor) or
--- "saveas" (the project's new file).
function A.chosen(kind: string, path: string)
  if kind == "saveas" then
    local saved, note = paw.project.write(path)
    paw.notify(note and (note .. ": " .. saved) or ("saved " .. saved))
  else
    commands.run("import", {path})
  end
end

--- Files dropped on the window: sound files, MIDI files and projects. A
--- project (the first of them, when there are several) is not opened here,
--- for the window asks about unsaved changes first: its path is returned as
--- `open`. A MIDI file's parts come in below the cursor's at `beat`, or
--- the edit cursor. Sound files go on the part at `row` (a place in the list of
--- drawn parts, from 1) at `beat`, snapped, one after another; with no
--- part there (below the last, or where the window cannot tell) each gets
--- a part of its own, at `beat` or the edit cursor. Anything else is said
--- to be refused. Returns `{ open, clips, refused }`.
function A.drop(paths: {string}, row?: integer, beat?: number): Dropped
  local out: Dropped = {clips = {}, refused = 0}
  local sounds, midis: {string}, {string} = {}, {}
  for _, path in ipairs(paths) do
    if paw.is_audio_file(path) then
      sounds[#sounds + 1] = path
    elseif paw.midifile.is_midi_file(path) then
      midis[#midis + 1] = path
    elseif path:lower():match("%.json$") or paw.project.is_folder(path) then
      out.open = out.open or path
    else
      out.refused = out.refused + 1
      paw.notify(
        "cannot take " .. (path:match("([^/]+)$") or path) .. ": it is not a sound file, a MIDI file or a project",
        "warn"
      )
    end
  end
  if out.open then
    return out
  end
  local rows = paw.groups.rows()
  local part = row and rows[row]
  local start = beat and snap(beat)
  for _, path in ipairs(midis) do
    local ok, got = pcall(paw.midifile.import, path, {start = start})
    if ok then
      local done = got as MidifileModule.Imported
      for _, clip in ipairs(done.clips) do
        out.clips[#out.clips + 1] = (clip as objects.Clip).id
      end
      paw.notify(
        string.format("dropped %s: %d notes on %d parts", path:match("([^/]+)$") or path, done.notes, #done.parts)
      )
    else
      out.refused = out.refused + 1
      paw.notify("could not import " .. path .. ": " .. tostring(got), "error")
    end
  end
  for _, path in ipairs(sounds) do
    local ok, got = pcall(paw.import_audio, path, {part = part, start = start})
    if ok then
      local clip = got as objects.Clip
      out.clips[#out.clips + 1] = clip.id
      if part then
        start = clip.start + clip.length
      end
      paw.notify(
        string.format(
          "dropped %s: %.1f beats on part “%s”", path:match("([^/]+)$") or path, clip.length, clip:part().name
        )
      )
    else
      out.refused = out.refused + 1
      paw.notify("could not import " .. path .. ": " .. tostring(got), "error")
    end
  end
  return out
end

local lossy_formats: {string: string} = {flac = "flac", mp3 = "mp3", ogg = "ogg", opus = "opus"}

--- Render as the window's dialog says: `o.path`, `o.range` (a name from
--- `render_dialog`), `o.format` ("wav", "flac", "mp3", "ogg" or "opus"), `o.quality` (for those
--- three: "low" to "best"), `o.bits`, `o.tail`
--- seconds, `o.normalize` dB or nil, `o.dither`, `o.mono`, and `o.stems`
--- for a file per part in a directory named after the path. `o.tags`
--- (`title`, `artist`, ... as `paw.render.tags` has them, an empty one
--- taking it out) becomes the project's tags, which the files carry. It
--- runs in the background: the state's `modal.render` says how far it is.
function A.render(o: RenderRequest)
  local render = render_module()
  if o.tags then
    render.tags(o.tags)
  end
  local opts: RenderModule.Options = {
    tail = tonumber(o.tail),
    bits = tonumber(o.bits) as integer,
    dither = o.dither and true or nil,
    normalize = tonumber(o.normalize),
    channels = o.mono and "mono" or nil,
    background = true,
  }
  local format = lossy_formats[o.format] or "wav"
  if format == "flac" and opts.bits == 32 then
    opts.bits = 24
  end
  if format ~= "wav" and format ~= "flac" then
    opts.bits, opts.dither, opts.quality = nil, nil, o.quality
  end
  local range = o.range or "song"
  local region = range:match("^region:(%d+)$")
  if region then
    local r = paw.markers.find({id = tonumber(region) as integer})
    if not r then
      error("that region is gone", 0)
    end
    opts.start, opts["end"] = r.beat, r.beat + r.length
  elseif range ~= "song" then
    opts.range = range
  end
  local path = util.expand_path(tostring(o.path or ""))
  if path == "" then
    error("render: name a file to write", 0)
  end
  local stem = path:gsub("%.[Ww][Aa][Vv]$", ""):gsub("%.[Ff][Ll][Aa][Cc]$", ""):gsub("%.[Mm][Pp]3$", ""):gsub(
    "%.[Oo][Gg][Gg]$", ""
  ):gsub("%.[Oo][Pp][Uu][Ss]$", "")
  if o.stems then
    -- One file for each part, through the master, as `:export` writes them.
    local export = require("paw.export")
    local args: commands.Args = {stem .. " stems/"}
    args.each, args["in"], args.format = "part", opts.range, format
    args.tail, args.bits, args.dither, args.normalize = opts.tail, opts.bits, opts.dither, opts.normalize
    args.quality, args.channels = opts.quality, o.mono and "mono" or "stereo"
    local plan = export.plan_args(args)
    -- A region of the dialog is its time, which no word of `:export` names.
    if opts.start then
      for _, r in ipairs(plan.renders) do
        r.from, r.to = opts.start, opts["end"]
      end
    end
    export.run(plan)
    return paw.notify(string.format("exporting %d files into %s · Esc cancels", #plan.renders, stem .. " stems"))
  end
  render.render(stem .. "." .. format, opts)
  paw.notify("rendering " .. (stem:match("([^/]+)$") or stem) .. "." .. format .. " · Esc cancels")
end
