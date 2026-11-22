-- Commands, keys and menu entries for templates.
local templates = require("templates")
local command = paw.command

local function clean(err) return (tostring(err):gsub("^[^:]*:%d+: ", ""):match("^[^\n]*")) end

--- A path as it is said: under the home directory, from `~`.
local function shown(path)
  local home = os.getenv("HOME")
  if home and home ~= "" and home ~= "/" and path:sub(1, #home + 1) == home .. "/" then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

--- Ask for a name, starting from one, and call `done` with it.
local function named(given, start, done)
  if given and given ~= "" then return done(given) end
  paw.ui.input({ prompt = "Template name: ", text = start }, function(text)
    if text and text:match("%S") then return done(text) end
    paw.notify("no name given: nothing saved", "warn")
  end)
end

--- Save a template of `kind` named `name` with `save(name)`, which returns
--- the file's path; asks first when there is one of that name already, and
--- says so when the name had to change to be a file's.
local function saving(kind, name, save, said)
  local ok, kept = pcall(templates.file_name, name)
  if not ok then return paw.notify(clean(kept), "warn") end
  local function go()
    local done, path = pcall(save, name)
    if not done then return paw.notify(clean(path), "error") end
    paw.notify(said(kept, shown(path)) .. (kept ~= name and " (a file name cannot hold some of the characters)" or ""))
  end
  local file = io.open(templates.path(kind, name), "r")
  if not file then return go() end
  file:close()
  paw.ui.input({ prompt = string.format("there is a template “%s”: replace it? (y/n) ", kept) }, function(answer)
    if answer and answer:lower():match("^%s*y") then return go() end
    paw.notify("nothing saved: the template “" .. kept .. "” stays as it was")
  end)
end

command(
  "template.save",
  function(ctx)
    local track = paw.cursor.track()
    if not track then return paw.notify("no track to save", "warn") end
    local group = paw.groups.is_group(track.id)
    named(ctx.args[1], track.name, function(name)
      saving(
        group and "group" or "track",
        name,
        function(n) return (group and templates.save_group or templates.save_track)(track, n) end,
        function(kept, path)
          return string.format("%s “%s” saved as a template (%s)", group and "group" or "track", kept, path)
        end
      )
    end)
  end,
  { desc = "Save the track as a template, or the group with every track in it: `template.save Lead vocal`", raw = true }
)

command("template.fx", function(ctx)
  local track = paw.cursor.track()
  if not track then return paw.notify("no track", "warn") end
  named(ctx.args[1], track.name .. " chain", function(name)
    saving(
      "fx",
      name,
      function(n) return templates.save_fx(track, n) end,
      function(kept, path)
        return string.format("the devices of “%s” saved as the chain “%s” (%s)", track.name, kept, path)
      end
    )
  end)
end, { desc = "Save the track's devices as a chain to add elsewhere: `template.fx Vocal chain`", raw = true })

--- Make a template again and say what was made.
local function load(name, kind)
  local ok, made, was = pcall(templates.load, name, { kind = kind })
  if not ok then return paw.notify(clean(made), "error") end
  if was == "fx" then
    paw.notify(#made .. (#made == 1 and " device" or " devices") .. " added from “" .. name .. "”")
  else
    paw.notify((was == "group" and "group “" or "track “") .. made.name .. "” made from a template")
  end
end

--- Choose among the templates of one kind, or of all.
local function pick(kind, on_choose)
  local items = templates.list(kind)
  if #items == 0 then
    return paw.notify("no templates yet: `:template.save` saves the track, `:template.fx` its devices", "warn")
  end
  paw.pick({
    title = "Templates",
    items = items,
    format = function(item) return string.format("%-16s %s", item.title, item.name) end,
    on_choose = on_choose,
  })
end

command("template.load", function(ctx)
  local name = ctx.args[1]
  if name and name ~= "" then return load(name) end
  pick(nil, function(item) load(item.name, item.kind) end)
end, {
  desc = "Make a template again: a track or group below the cursor track, a chain on it. `template.load Lead vocal`; alone, choose from a list",
  raw = true,
  complete = function()
    local names = {}
    for i, item in ipairs(templates.list()) do
      names[i] = item.name
    end
    return names
  end,
})

command("template.delete", function(ctx)
  local name = ctx.args[1]
  if name and name ~= "" then
    return paw.notify(
      templates.delete(name) and ("template “" .. name .. "” deleted") or ("no template `" .. name .. "`")
    )
  end
  pick(nil, function(item)
    templates.delete(item.name, item.kind)
    paw.notify("template “" .. item.name .. "” deleted")
  end)
end, {
  desc = "Delete a template: `template.delete Lead vocal`; alone, choose from a list",
  raw = true,
  complete = function()
    local names = {}
    for i, item in ipairs(templates.list()) do
      names[i] = item.name
    end
    return names
  end,
})

command("templates", function()
  local items = templates.list()
  if #items == 0 then return paw.notify("no templates yet, in " .. shown(templates.dir())) end
  local lines = {}
  for i, item in ipairs(items) do
    lines[i] = string.format("%-16s %s", item.title, item.name)
  end
  paw.notify(table.concat(lines, "\n"))
end, { desc = "List the templates" })

paw.keymap.group("<localleader>T", "templates", { view = "arrange" })
paw.keymap.set(
  "<localleader>Tl",
  "template.load",
  { view = "arrange", desc = "Make a track, group or chain from a template" }
)
paw.keymap.set("<localleader>Ts", "template.save", { view = "arrange", desc = "Save the track or group as a template" })
paw.keymap.set("<localleader>Tf", "template.fx", { view = "arrange", desc = "Save the track's devices as a chain" })

-- In the window's menus.
table.insert(paw.frontend.menus.timeline, { label = "From a template…", command = "template.load" })
table.insert(paw.frontend.menus.track, { label = "Save as a template…", command = "template.save" })
table.insert(paw.frontend.menus.track, { label = "Save its devices as a chain…", command = "template.fx" })
table.insert(paw.frontend.menus.track, {
  label = "Add devices from a template…",
  run = function()
    pick("fx", function(item) load(item.name, "fx") end)
  end,
})
