-- The default commands and keys: views. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local api = paw.api
local util = paw.util
local command = paw.command
local cursor = paw.cursor
local roll = paw.ui.views:get("pianoroll")

command("view.next", function() paw.ui.focus_next(1) end, { desc = "Focus the next view" })
command("view.prev", function() paw.ui.focus_next(-1) end, { desc = "Focus the previous view" })
command(
  "view.toggle",
  function(ctx) paw.ui.toggle(tostring(ctx.args[1])) end,
  { desc = "Show or hide a view: `view.toggle mixer`", complete = { "views" } }
)
command("roll.toggle", function()
  if paw.ui.visible("pianoroll") then return paw.ui.toggle("pianoroll") end
  if roll:clip() then return paw.ui.toggle("pianoroll") end
  -- Nothing was open: the clip under the cursor, or no pane that would
  -- only say there is none.
  local clip = cursor.clip()
  if not clip then return paw.notify("no clip under the cursor to open in the piano roll", "warn") end
  roll:edit(clip)
  if clip.kind == "midi" and not paw.ui.visible("pianoroll") then paw.ui.show("pianoroll") end
end, { desc = "Show or hide the piano roll; with no clip open, it opens on the clip under the cursor" })
command(
  "view.focus",
  function(ctx) paw.ui.focus(tostring(ctx.args[1])) end,
  { desc = "Focus a view by name", complete = { "views" } }
)
command("view.close", function()
  if paw.ui.float then return paw.ui.close() end
  paw.ui.hide(paw.ui.focused)
end, { desc = "Close the focused panel; the keyboard goes to the window before" })
command("view.window", function(ctx)
  local name = ctx.args[1] and tostring(ctx.args[1]) or (paw.ui.float and paw.ui.float.name) or paw.ui.focused
  if not paw.ui.views:get(name) then return paw.notify("no view `" .. name .. "`", "warn") end
  paw.canvas.open_view(name)
end, {
  desc = "Open a view in a window of its own, in the graphical frontend: `view.window undotree`; the focused one without a name",
  complete = { "views" },
})
command("view.dock", function(ctx)
  local name = ctx.args[1] and tostring(ctx.args[1]) or paw.ui.focused
  if not paw.canvas.open_views[name] then
    return paw.notify("`" .. tostring(name) .. "` is not in a window of its own", "warn")
  end
  paw.canvas.dock(name)
end, {
  desc = "Put a view in a window of its own back in the main window, as a pane: `view.dock notation`; the focused one without a name",
  complete = { "views" },
})
command("view.open", function(ctx)
  local name = tostring(ctx.args[1] or "")
  local view = paw.ui.views:get(name)
  if not view then return paw.notify("no view `" .. name .. "`", "warn") end
  -- Where it is already: in a window of its own, or in the layout.
  if paw.canvas.open_views[name] then return paw.canvas.focus(name) end
  if paw.layout.homes[name] or paw.layout.find(paw.ui.layout, name) then return paw.ui.focus(name) end
  local made, why = paw.layout.split({ view = name })
  if not made then paw.notify(why, "warn") end
end, {
  desc = "Show a view docked: where it docks, else in a window split from this one: `view.open undotree`",
  complete = { "views" },
})
command("view.only", function() paw.layout.only() end, { desc = "Close every window but this one, as `:only`" })
command("zoom", function(ctx)
  local name = paw.ui.focused == "pianoroll" and "note_zoom" or "zoom"
  local arrange = paw.ui.views:get("arrange")
  if ctx.args.by then
    paw.opt[name] = util.clamp(paw.opt[name] * ctx.args.by, 0.125, 64)
  elseif tonumber(ctx.args[1]) then
    paw.opt[name] = tonumber(ctx.args[1])
  elseif ctx.args[1] == "fit" and name == "zoom" and arrange.geometry then
    -- The whole song and a bar after it across the timeline.
    local length = api.project_get().length or 0
    paw.opt.zoom = util.clamp(arrange.geometry.layout.tw / (length + paw.time.bar()), 0.125, 64)
    arrange.scroll = 0
  end
end, { desc = "Set columns per beat, or scale them, or show the whole song: `zoom 4`, `zoom by=2`, `zoom fit`" })
command("grid", function(ctx)
  local note = paw.ui.focused == "pianoroll"
  local name = note and "note_grid" or "grid"
  local which = note and "note" or nil
  local text = ctx.args[1]
  if ctx.args.by then
    -- A note value stays one (`1/8t` by 2 is `1/4t`); else the step in beats.
    local d, t = tostring(paw.opt[name]):match("^1/(%d+)(t?)$")
    local den = d and tonumber(d) / ctx.args.by
    if den and den >= 1 and den % 1 == 0 then
      paw.opt[name] = "1/" .. den .. t
    else
      paw.opt[name] = util.clamp(paw.timegrid.step(which) * ctx.args.by, 1 / 32, 16)
    end
  elseif text then
    local value = tonumber(text) or text
    local ok, why = paw.option.check(name, value)
    if not ok then return paw.notify(why, "error") end
    paw.opt[name] = value
  end
  paw.notify("grid " .. paw.timegrid.label(which))
end, {
  desc = "Set the grid: beats, a note value, bar, auto, frame or a time, or scale it: `grid 1/8t`, `grid bar`, `grid by=2`",
})

-- The default workspaces (paw/workspace.tl): a layout for each task, which
-- `<Space>w` and a letter go to. `init.lua` can change them or add more
-- through `paw.layouts`, and `:workspace.save` keeps your own.
paw.layouts.record = { dir = "v", "arrange", "mixer" }
paw.layouts.edit = { dir = "v", "arrange", "roll" }
paw.layouts.mix = { dir = "v", "mixer", "devices" }
paw.layouts.score = "notation"
