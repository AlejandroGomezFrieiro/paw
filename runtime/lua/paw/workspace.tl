-- Workspaces: a named screen for each task, as Blender's workspaces. One
-- key goes from the edit screen to the mix screen and back:
--
--   paw.workspace.go("mix")        -- `:workspace mix`, `<Space>wm`
--   paw.workspace.save("tracking") -- `:workspace.save tracking`
--   paw.workspace.current()        -- "mix", or nil before the first switch
--
-- A workspace is a layout (paw/layout.tl, "Saved layouts"): the defaults
-- name four in `paw.layouts` (record, edit, mix, score), `:workspace.save`
-- writes one to the layouts folder, and `:workspace.save!` keeps one in
-- the project's screen (`workspaces`, and `workspace`, the one the
-- project opens with). When you leave a workspace, its tabs and windows
-- stay in memory, so that you come back to them as you left them. Each
-- seat has its own current workspace and its own kept screens.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local commands = require("paw.commands")
local seats = require("paw.seats")
local layout = require("paw.layout")
local cursor = require("paw.cursor")
local statusline = require("paw.statusline")
local pick = require("paw.pick")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type UiModule = require("paw.ui")

local type SpecNode = layout.SpecNode
local type Saved = types.SavedLayout

local record Paw is partial.Paw
  ui: UiModule
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

--- The workspace state of a seat. `current` is the workspace on the
--- screen, nil until the seat goes to one. `kept` holds the tabs and
--- windows of each workspace that the seat left, by name; it never holds
--- the current one. A project that opens empties both: the kept windows
--- show the last project's clips and scopes.
local record State
  current: string
  kept: {string: Saved}
end

local state: State = {kept = {}}
seats.keep(
  "workspace",
  function(): State return state end,
  function(s: State) state = s end,
  function(): State return {kept = {}} end
)

--- An entry of the picker of workspaces.
local record Item
  name: string
end

local record M
  source: contracts.PickSource<Item>
  --- What going to a workspace does after its windows show, by the name
  --- of the workspace: a function that gives a text for the message, or
  --- nil. `paw.workspace.on_enter.record` puts the cursor on the first
  --- armed track.
  on_enter: {string: function(): string}
end

--- The name of the workspace on the screen, or nil.
function M.current(): string
  return state.current
end

--- The workspaces that the project keeps (`:workspace.save!`), by name.
local function in_project(): {string: Saved}
  local screen = api.project_screen()
  return screen and screen.workspaces or {}
end

--- The names of the workspaces there are: the defaults, the
--- configuration's, those saved, the project's and those kept in memory.
function M.names(): {string}
  local seen: {string: boolean} = {}
  local out: {string} = {}
  local function add(name: string)
    if not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  for _, name in ipairs(layout.layout_names()) do
    add(name)
  end
  for name in pairs(in_project()) do
    add(name)
  end
  for name in pairs(state.kept) do
    add(name)
  end
  table.sort(out)
  return out
end

--- What workspace `name` shows when you go to it: its windows as you left
--- them, else the project's, else the layout of that name. Nil and the
--- reason when there is none.
local function spec_of(name: string): SpecNode, string
  local kept = state.kept[name] or in_project()[name]
  if kept then
    return kept as SpecNode
  end
  local spec = layout.layout_spec(name)
  if not spec then
    return nil, "no workspace `" .. name .. "`: `<Space>ww` lists them"
  end
  return spec
end

--- Go to workspace `name`. The tabs and windows of the workspace that you
--- leave stay in memory. Then `on_enter` of the workspace runs. Returns
--- true and the text of `on_enter`, or false and the reason when `name`
--- names no workspace or none of its windows can show.
function M.go(name: string): boolean, string
  -- In the workspace already: its windows stay, and its `on_enter` runs
  -- again (`<Space>wr` finds the armed track again).
  if name ~= state.current then
    local spec, why = spec_of(name)
    if not spec then
      return false, why
    end
    -- Capture before the restore replaces the windows.
    local leaving = state.current and layout.capture(true)
    if not layout.restore(spec) then
      return false, "workspace `" .. name .. "` has no window that paw can show: is the extension of its view loaded?"
    end
    if leaving then
      state.kept[state.current] = leaving
    end
    state.kept[name] = nil
    state.current = name
  end
  local enter = M.on_enter[name]
  return true, enter and enter()
end

-- The record workspace: the cursor on the first armed track of the song,
-- so that `R` records there.
M.on_enter = {
  record = function(): string
    for _, id in ipairs(api.track_list()) do
      local track = api.track_get(id)
      if track.armed then
        cursor.set_track(id)
        return "the cursor on " .. track.name .. ", the first armed track"
      end
    end
    return "no track is armed: the cursor stays, and `r` arms the track at the cursor"
  end,
}

--- Keep the tabs and windows as workspace `name` in the layouts folder.
--- When `project` is true, keep them in the project's screen instead, so
--- that the project opens in that workspace. The screen is now that
--- workspace.
function M.save(name: string, project?: boolean): boolean, string
  if project then
    local screen = api.project_screen() or {seats = {}}
    screen.workspaces = screen.workspaces or {}
    screen.workspaces[name] = layout.capture(true)
    screen.workspace = name
    api.project_screen_set(screen)
    -- The next save writes it: the project asks to be saved.
    api.project_mark_changed()
  else
    local ok, where = layout.save(name)
    if not ok then
      return false, where
    end
  end
  state.kept[name] = nil
  state.current = name
  api.ui_redraw()
  return true
end

-- The picker: `<Space>ww`, `:workspace` ------------------------------------------------

local function choose(item: Item)
  local ok, text = M.go(item.name)
  if not ok then
    paw.notify(text, "warn")
    return
  end
  paw.notify("workspace " .. item.name .. (text and ", " .. text or ""))
end

M.source = {
  desc = "Go to a workspace: a screen for a task",
  title = "Workspaces",
  empty = "No workspace: `<Space>ws` keeps the screen as one.",
  items = function(): {Item}
    local out: {Item} = {}
    for i, name in ipairs(M.names()) do
      out[i] = {name = name}
    end
    return out
  end,
  format = function(item: Item): string return item.name == state.current and item.name .. "  (now)" or item.name end,
  primary = function(item: Item): string return item.name end,
  search = function(item: Item): string return item.name end,
  on_choose = choose,
}
pick.sources:put("workspaces", M.source)

-- Commands -------------------------------------------------------------------------

local function complete_names(_: string, info: commands.Info): {string | commands.Candidate}
  if info.index > 1 then
    return {}
  end
  return M.names() as {string | commands.Candidate}
end

commands.define(
  "workspace",
  function(ctx: contracts.CommandContext): contracts.CommandResult
    local name = ctx.args[1]
    if name == nil then
      commands.run("pick", {"workspaces"})
      return
    end
    choose({name = tostring(name)})
  end,
  {desc = "Go to a workspace: `workspace mix`; alone, choose one in a picker", complete = complete_names}
)

--- `:workspace.save` and `:workspace.save!`: with no name, they ask for one.
local function save_command(project: boolean): function(ctx: contracts.CommandContext): contracts.CommandResult
  local function save(name: string)
    local ok, why = M.save(name, project)
    if not ok then
      paw.notify(why, "error")
    elseif project then
      paw.notify("workspace " .. name .. " kept in the project: it opens in it from the next save")
    else
      paw.notify("workspace " .. name .. " saved")
    end
  end
  return function(ctx: contracts.CommandContext): contracts.CommandResult
    local name = table.concat(ctx.args as {string}, " "):match("^%s*(.-)%s*$")
    if name ~= "" then
      save(name)
      return
    end
    paw.ui.input(
      {prompt = "Workspace name: ", label = "Save the screen as a workspace"},
      function(text: string)
        if text and text ~= "" then
          save(text)
        end
      end
    )
  end
end
commands.define(
  "workspace.save",
  save_command(false),
  {
    desc = "Keep the tabs and windows as a workspace: `workspace.save tracking`; alone, it asks",
    complete = complete_names,
  }
)
commands.define(
  "workspace.save!",
  save_command(true),
  {desc = "Keep the tabs and windows as a workspace of the project, which opens in it", complete = complete_names}
)

-- The status line: the name of the workspace -------------------------------------------

statusline.component(
  "workspace",
  {
    rank = 4,
    still = true,
    key = function(): string return state.current or "" end,
    fn = function(): contracts.StatusText return state.current and {{state.current, "StatusOn"}} or nil end,
  }
)

-- A project that opens --------------------------------------------------------------

-- The kept windows show the last project's clips and scopes: forget them.
-- A project that keeps a workspace to open in (`:workspace.save!`) opens
-- in it, after paw/layout.tl put back the project's screen.
local function opened()
  state.current, state.kept = nil, {}
  local screen = api.project_screen()
  local name = opt.project_screen and screen and screen.workspace
  if name and screen.workspaces and screen.workspaces[name] then
    M.go(name)
  end
end
events.on(
  kernel.project_loaded,
  function()
    for _, id in ipairs(seats.list()) do
      if id == seats.current then
        opened()
      else
        seats.within(id, opened)
      end
    end
  end
)

return M
