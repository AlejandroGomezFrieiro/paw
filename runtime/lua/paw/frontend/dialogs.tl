-- What the window asks for its dialogs and menus: save as, the renderer
-- it draws with, the files to open and save, the render dialog, the
-- inputs and the engine, and the layout that it keeps.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local options = require("paw.options")
local commands = require("paw.commands")
local M = require("paw.frontend.core")
local host = require("paw.frontend.host")

local paw = host.paw
local opt = options.opt
local render_module = host.render_module
local part_flag = host.part_flag
local type Check = M.Check
local type Choice = host.Choice
local type Closing = M.Closing
local type DialogInfo = M.DialogInfo
local type EngineMenu = M.EngineMenu
local type InputMenu = M.InputMenu
local type RangeChoice = host.RangeChoice
local type RenderDialog = M.RenderDialog
local type Renderer = M.Renderer
local type WindowLayout = M.WindowLayout

--- Save the project under a new name: type it at a prompt that starts with
--- the name of the project. A relative name goes where `:w name` puts it
--- (`paw.files.here()`), `..` and `~` go elsewhere, and Tab completes.
--- `after` runs once it is saved.
function M.save_as(after?: function())
  local p = api.project_get()
  -- A project is a folder: its name is the folder's.
  local name = p.path and (p.path:gsub("/project%.toml$", ""):gsub("%.json$", ""):match("([^/]+)$"))
    or (p.name ~= "" and p.name or "song")
  local home = os.getenv("HOME") or ""
  local dir = paw.files.here()
  if home ~= "" and (dir == home or dir:sub(1, #home + 1) == home .. "/") then
    dir = "~" .. dir:sub(#home + 1)
  end
  paw.ui.input(
    {
      prompt = "Save as (" .. dir .. "): ",
      text = name,
      complete = function(text: string): {{string: string}}
        return commands.completers:get("projects")(text) as {{string: string}}
      end,
    },
    function(typed: string)
      if typed == "" then
        return
      end
      local saved, note = paw.project.write(paw.files.project_path(typed))
      paw.notify(note and (note .. ": " .. saved) or ("saved " .. saved))
      if after then
        after()
      end
    end
  )
end

options.define("native_dialogs", true) -- the window opens the desktop's file dialogs, not the kernel's list
-- Frames a second the window draws while the song plays (the playhead, the
-- meters): "auto" is 30 on a graphics card and 15 on the processor. Keys,
-- the pointer and edits are drawn at once all the same.
options.define("window_fps", "auto", {type = {"number", "string"}, min = 1, max = 60, values = {"auto"}})
-- The window keeps what does not move in a pane as textures, and paints a
-- part again only when it changes: true, false, or "auto" (on).
options.define("window_cache", "auto", {type = {"boolean", "string"}, values = {"auto", true, false}})

--- What the graphical window said of the OpenGL that draws it when it
--- started: `{ renderer, version, software, cause }`, or nil before a
--- window started. `cause` tells why a window draws on the processor:
--- "asked", "libgl", "no-card" or "driver".
M.window_renderer = nil

--- What to do about a window that draws on the processor, by cause, the
--- likely cause first. `:checkhealth window` gives all of them.
M.software_advice = {
  asked = "PAW_GUI_RENDERER=software or --renderer software asks for the processor: unset the variable and leave out the option",
  libgl = "LIBGL_ALWAYS_SOFTWARE is set: unset it",
  driver = "the OpenGL driver of the graphics card is missing (on NixOS, set hardware.graphics.enable = true; elsewhere install Mesa's drivers), "
    .. "or the X server gives no DRI3 (over SSH, VNC or Xvfb): start the window on the computer's own screen",
  ["no-card"] = "no graphics card was found (/dev/dri has no render node): on this computer the window can only draw on the processor; "
    .. "a lower paw.opt.window_fps costs less",
}

--- The window tells which OpenGL renderer draws it (see
--- `paw.frontend.window_renderer`). One that draws on the processor is
--- told once, in a line that says what to do.
function M.window_renderer_set(info: Renderer)
  M.window_renderer = info
  if type(info) == "table" and info.software then
    local advice = M.software_advice[info.cause] or M.software_advice.driver
    paw.notify(
      "The window draws on the processor ("
        .. tostring(info.renderer):match("^%S+")
        .. "), which costs CPU while a song plays: "
        .. advice
        .. ". See :checkhealth window.",
      "warn"
    )
  end
end

--- The data that the window needs to open the file dialog of the desktop.
--- `native` tells if it must use that dialog (the option). When it is off,
--- the dialogs are those of the kernel. `dir` is the folder to start in:
--- `paw.files.here()`, as in the list picker. `name` is the file name of the project, for
--- "Save as". `render` is the file endings that a render can write.
function M.dialog_info(): DialogInfo
  local p = api.project_get()
  local dir = paw.files.here()
  local name = p.path and p.path:match("([^/]+)$") or ((p.name ~= "" and p.name or "song") .. ".json")
  -- What a render can write: wav and flac, and the lossy formats ffmpeg can make.
  local render: {string} = {"wav", "flac"}
  for ext, available in pairs(M.render_dialog().formats) do
    if available then
      render[#render + 1] = ext
    end
  end
  table.sort(render)
  return {native = opt.native_dialogs and true or false, dir = dir, name = name, render = render}
end

--- Tells if paw would lose data if it closes now: { modified, name, path }.
function M.closing(): Closing
  local p = api.project_get()
  return {modified = paw.project.unsaved(), name = p.name, path = p.path}
end

--- The start values of the render dialog. These are the file that a render
--- would write, and the ranges that paw can render (`{ name, label }`: the
--- song, the loop, the selection, each region). They are also the sample
--- rate of the engine, and the lossy formats that ffmpeg can make here
--- (`formats`: `{ mp3 = true, ogg = false, ... }`).
function M.render_dialog(): RenderDialog
  local t = api.transport_get()
  local ranges: {RangeChoice} = {{name = "song", label = "The whole song"}}
  if t.loop_end > t.loop_start then
    ranges[#ranges + 1] = {
      name = "loop",
      label = string.format(
        "The loop (%s – %s)",
        paw.time.format(paw.time.local_beat(t.loop_start)),
        paw.time.format(paw.time.local_beat(t.loop_end))
      ),
    }
  end
  local sel = paw.keymap.selection()
  if sel and sel.c0 and sel.c1 and sel.c1 > sel.c0 then
    ranges[#ranges + 1] = {name = "selection", label = "The selection"}
  end
  for _, r in ipairs(paw.markers.regions()) do
    ranges[#ranges + 1] = {name = "region:" .. r.id, label = "Region “" .. paw.markers.pathname(r) .. "”"}
  end
  -- A project with no file yet renders in the folder for relative names.
  local path = render_module().default_path()
  if not path:find("/", 1, true) then
    path = paw.files.here() .. "/" .. path
  end
  local formats: {string: boolean} = {}
  for _, f in ipairs(api.render_formats(opt.ffmpeg)) do
    if f.lossy then
      formats[f.extensions[1]] = f.available
    end
  end
  return {
    path = path,
    ranges = ranges,
    sample_rate = api.engine_get().sample_rate,
    formats = formats,
    tags = render_module().tags(),
  }
end

--- The menu of the input of a part: the choices of `paw.audio.choices`
--- under their headings, `audio`, `midi` and `channel`. It also gives the
--- MIDI output of the part: `midi_out`, `midi_out_channel` and
--- `midi_out_form`. Each is a list of `{ label, checked }`.
--- `act.choose_input` takes one by heading and place.
function M.input_menu(part: integer): InputMenu
  local out: InputMenu = {
    audio = {},
    midi = {},
    channel = {},
    midi_out = {},
    midi_out_channel = {},
    midi_out_form = {},
    monitor = part_flag(part, "monitor"),
  }
  local lists = out as {string: {Check}}
  for _, choice in ipairs(paw.audio.choices(part)) do
    local list = lists[choice.group]
    list[#list + 1] = {label = choice.label, checked = choice.checked}
  end
  return out
end

--- The recent projects the File menu lists: `{ label, path }` each.
function M.recent_menu(): {RangeChoice}
  return paw.recent.menu()
end

local function layout_file(): string
  return M.layout_path or api.env().state_dir .. "/window.json"
end

--- How the window was left (its size, the zoom, the heights of rows and of
--- the piano roll, if the mixer shows): a table, empty when nothing
--- was kept. It belongs to the machine, so it is kept here, where a window
--- attached to this kernel finds it too. (`M.layout_path` names another
--- file, for tests.)
function M.layout_get(): WindowLayout
  local handle = io.open(layout_file(), "rb")
  if not handle then
    return {}
  end
  local text = handle:read("*a")
  handle:close()
  local ok, data = pcall(api.json_decode, text)
  return ok and type(data) == "table" and data as WindowLayout or {}
end

--- Keep the window's layout (see `layout_get`).
function M.layout_set(layout: WindowLayout)
  local file = layout_file()
  pcall(api.fs_mkdir, (file:match("^(.*)/[^/]*$") or "."))
  local handle = io.open(file .. ".tmp", "wb")
  if not handle then
    return
  end
  handle:write(api.json_encode(layout, true))
  handle:close()
  os.rename(file .. ".tmp", file)
end

--- The menu where the audio devices are chosen: `info` (lines to show),
--- `output`, `input`, `block`, `rate` and `backend`, each a list of
--- `{ label, checked }`.
--- `act.choose_engine` takes one by heading and place.
function M.engine_menu(): EngineMenu
  local out: EngineMenu = {info = {}, output = {}, input = {}, block = {}, rate = {}, backend = {}}
  local ok, got = pcall(paw.audio.engine_choices)
  if not ok then
    out.info[1] = {label = tostring(got):match("[^\n]*"), checked = false}
    return out
  end
  local lists = out as {string: {Check}}
  for _, choice in ipairs(got as {Choice}) do
    local list = lists[choice.group]
    list[#list + 1] = {label = choice.label, checked = choice.checked}
  end
  return out
end
