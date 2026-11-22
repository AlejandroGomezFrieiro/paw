-- The panel of `<leader>.`: the parameters of the last command that can be
-- adjusted (`paw.command`'s `adjust`), in a float. A key changes the value
-- of one, and the command runs again through `:adjust` (paw/commands.tl):
-- the result takes the place of the command's undo step. Changes that come
-- quickly settle: only the last one runs, after SETTLE ms.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua. The panel is
-- drawn in cells, so the terminal and the window show the same scene.
local api = require("paw.api")
local commands = require("paw.commands")
local util = require("paw.util")
local type contracts = require("paw.contracts")

local type Arg = contracts.CommandArg
local type Data = util.Data

--- How long a change waits for the next one, in ms.
local SETTLE = 50

local record Panel is contracts.View
  selected: integer
  count: integer
  pending: {string: Arg}
end

local record M
  open: function(): boolean
  flush: function()
  SETTLE: integer
end

local view: Panel = {modal = true, focusable = true, window = false, selected = 1, pending = {}}
paw.seats.fields(
  "adjust", view as {string: Data}, {"selected", "count", "pending"}, {selected = 1, pending = {}} as {string: Data}
)
M.SETTLE = SETTLE

local timer: integer

local function cancel_timer()
  if timer then
    paw.cancel(timer)
    timer = nil
  end
end

--- Run the command again with the values changed since the last run.
function M.flush()
  cancel_timer()
  if next(view.pending) == nil then
    return
  end
  local changes = view.pending
  view.pending = {}
  local ok, err = pcall(commands.adjust, changes as contracts.CommandArgs) as (boolean, string)
  if not ok then
    paw.notify(err, "warn")
  end
  api.ui_redraw()
end

local function shown(value: Arg): string
  if value == nil then
    return "-"
  end
  return tostring(value)
end

--- What a parameter has now: the change that waits, else the command's value.
local function value_of(panel: contracts.AdjustPanel, p: contracts.AdjustParam): Arg
  local waiting = view.pending[p.name]
  if waiting ~= nil then
    return waiting
  end
  return panel.values[p.name]
end

--- The value `n` steps from `now`: a number moves by its `step` inside its
--- limits, a choice moves along its `values`.
local function stepped(p: contracts.AdjustParam, now: Arg, n: integer): Arg
  local current = now
  if p.step or current is number then
    local base: number = 0
    if current is number then
      base = current
    else
      local default = p.default
      if default is number then
        base = default
      end
    end
    local to = base + (p.step or 1) * n
    to = math.floor(to * 1e6 + 0.5) / 1e6
    if p.min and to < p.min then
      to = p.min
    end
    if p.max and to > p.max then
      to = p.max
    end
    return to
  end
  local list = p.values or {}
  if #list == 0 then
    return now
  end
  local at = 0
  for i, v in ipairs(list) do
    if v == tostring(now) then
      at = i
    end
  end
  return list[math.tointeger(util.clamp(at + n, 1, #list))]
end

--- Change the selected parameter by `n` steps, and run the command after
--- the settle time.
local function change(n: integer)
  local panel = commands.panel()
  if not panel then
    return
  end
  local p = panel.params[view.selected]
  if not p then
    return
  end
  view.pending[p.name] = stepped(p, value_of(panel, p), n)
  cancel_timer()
  timer = paw.defer(function() timer = nil; M.flush() end, SETTLE)
end

local function limits(p: contracts.AdjustParam): string
  local parts: {string} = {}
  if p.min and p.max then
    parts[#parts + 1] = string.format("%g to %g", p.min, p.max)
  end
  if p.step then
    parts[#parts + 1] = string.format("step %g", p.step)
  end
  return table.concat(parts, ", ")
end

function view:render(buf: contracts.Buf, _: contracts.RenderContext)
  local panel = commands.panel()
  if not panel then
    buf:text(1, 0, "no change to adjust", "Dim")
    return
  end
  local width = 0
  for _, p in ipairs(panel.params) do
    width = math.max(width, #p.name)
  end
  for i, p in ipairs(panel.params) do
    local on = i == self.selected
    local style = on and "Visual" or "Normal"
    buf:fill(0, i - 1, buf.width, 1, " ", style)
    buf:text(1, i - 1, (on and "> " or "  ") .. p.name, style)
    buf:text(width + 5, i - 1, shown(value_of(panel, p)), on and "Visual" or "Title")
    local extra = limits(p)
    if extra ~= "" then
      buf:text(width + 16, i - 1, extra, on and "Visual" or "Dim")
    end
  end
  local row = buf.height - 1
  buf:fill(0, row, buf.width, 1, " ", "FloatFooter")
  buf:text(1, row, "j k choose  + - change  <CR> type  : line  Esc close", "FloatFooter")
end

local function close()
  M.flush()
  view.count = nil
  paw.ui.close()
end

local function line(name: string)
  commands.run("cmdline", {text = "adjust " .. name .. "="} as contracts.CommandArgs)
end

function view:on_key(key: string): boolean
  local panel = commands.panel()
  if key:match("^%d$") and (self.count or key ~= "0") then
    self.count = (self.count or 0) * 10 + math.tointeger(tonumber(key))
    return true
  end
  local n = self.count or 1
  self.count = nil
  if key == "<Esc>" or key == "q" or key == "<C-c>" then
    close()
    return true
  elseif not panel then
    close()
    return true
  elseif key == "j" or key == "<Down>" then
    self.selected = math.min(#panel.params, self.selected + n)
  elseif key == "k" or key == "<Up>" then
    self.selected = math.max(1, self.selected - n)
  elseif key == "+" or key == "<C-a>" then
    change(n)
  elseif key == "-" or key == "<C-x>" then
    change(-n)
  elseif key == "<CR>" then
    M.flush()
    local p = panel.params[self.selected]
    if p then
      line(p.name)
    end
  elseif key == ":" then
    M.flush()
    commands.run("cmdline", {text = commands.adjusting() or "adjust "} as contracts.CommandArgs)
  end
  api.ui_redraw()
  return true
end

paw.ui.view("adjust", view)

--- Open the panel on the last command that can be adjusted. False when
--- there is none.
function M.open(): boolean
  local panel = commands.panel()
  if not panel then
    return false
  end
  view.selected, view.count, view.pending = 1, nil, {}
  paw.ui.open("adjust", {title = panel.title, width = 56, height = math.min(#panel.params, 10) + 2})
  return true
end

return M
