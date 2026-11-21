-- The undo tree, named checkpoints and A/B listening. See README.md beside
-- this file.
local api = paw.api
local undotree = require("undotree")
local view = require("undotree.view")
require("undotree.paint")

paw.option.define("undotree_ab_key", "")   -- one more key that switches between A and B; "" for none

local command, map = paw.command, paw.keymap.set
-- On the core's `<leader>p` (project): the undo history is the project's.

command("undotree", function()
  if paw.ui.float and paw.ui.float.name == "undotree" then return paw.ui.close() end
  view.open()
end, { desc = "Show the undo tree" })

command("earlier", function(ctx)
  undotree.travel(-1, ctx.args[1], ctx.count)
end, { desc = "Go back in time across branches: `earlier 5`, `earlier 2m` (s, m, h, d)" })

command("later", function(ctx)
  undotree.travel(1, ctx.args[1], ctx.count)
end, { desc = "Go forward in time across branches: `later 5`, `later 30s`" })

command("undo.goto", function(ctx)
  local id = tonumber(ctx.args[1])
  if not id then return paw.notify("usage: undo.goto <state number>", "warn") end
  undotree.go(id)
end, { desc = "Go to a state of the undo tree by its number" })

command("undo.name", function(ctx)
  local name = table.concat(ctx.args, " ")
  local id = api.undo_name(name ~= "" and name or nil)
  paw.notify(name ~= "" and ("named #" .. id .. " " .. name) or ("#" .. id .. " has no name now"))
end, { desc = "Name the current state, in this session (`checkpoint` also writes it to disk)", raw = true })

command("undo.diff", function(ctx)
  local diff = api.undo_diff(tonumber(ctx.args[1]), tonumber(ctx.args[2]))
  local lines = { { text = undotree.summary(diff), style = "HelpSection" }, "" }
  for _, item in ipairs(diff.items) do lines[#lines + 1] = item end
  paw.ui.page(string.format("#%d → #%d", diff.from, diff.to), lines)
end, { desc = "What changed: `undo.diff` the last step, `undo.diff 3` from #3 to now, `undo.diff 3 7`" })

command("checkpoint", function(ctx)
  local function write(name)
    local ok, result, why = pcall(undotree.checkpoint, name)
    if not ok then return paw.notify(tostring(result), "error") end
    if not result then return paw.notify(why, "warn") end
    if result.pending then
      paw.notify("named #" .. result.state .. " " .. result.name .. "; it is written beside the project when the project is first saved")
    else
      paw.notify("checkpoint " .. result.name .. " written (#" .. result.state .. ")")
    end
  end
  local name = table.concat(ctx.args, " ")
  if name ~= "" then return write(name) end
  paw.ui.input({ prompt = "Checkpoint name: " }, write)
end, { desc = "Name the current state and write it beside the project: `checkpoint before the bridge`", raw = true })

command("checkpoints", function()
  undotree.choose()
end, { desc = "List the checkpoints, and restore one" })

command("checkpoint.restore", function(ctx)
  local item = undotree.find(ctx.args[1] or "")
  if not item then return paw.notify("no such checkpoint: `:checkpoints` lists them", "warn") end
  local ok, err = pcall(undotree.restore, item)
  if not ok then paw.notify(tostring(err), "error") end
end, { desc = "Restore a checkpoint by its number in `:checkpoints` or its name", raw = true })

command("checkpoint.delete", function(ctx)
  local item = undotree.find(ctx.args[1] or "")
  if not item or not item.file then return paw.notify("no such checkpoint on disk", "warn") end
  api.checkpoint_delete(item.file)
  paw.notify("deleted checkpoint " .. item.name)
end, { desc = "Delete a checkpoint from disk, by number or name", raw = true })

command("ab.mark", function(ctx)
  undotree.mark_a(tonumber(ctx.args[1]))
end, { desc = "Mark the current state (or the one given) as A, for comparing by ear" })

command("ab.toggle", function()
  local where, why = undotree.toggle()
  if where then paw.notify("playing " .. where) else paw.notify(why, "warn") end
end, { desc = "Switch between A and the state you came from, while the song plays on" })

command("ab.clear", function()
  undotree.clear_ab()
  paw.notify("A and B cleared")
end, { desc = "Forget the A/B marks" })

map("g-", function(ctx) undotree.travel(-1, nil, ctx.count) end, { desc = "Older state, across branches", repeatable = false })
map("g+", function(ctx) undotree.travel(1, nil, ctx.count) end, { desc = "Newer state, across branches", repeatable = false })
map("<leader>pu", "undotree", { desc = "Undo tree", repeatable = false })
map("<leader>vu", "undotree", { desc = "Undo tree", repeatable = false })
map("<leader>pa", "ab.mark", { desc = "Mark this state as A", repeatable = false })
map("<leader>pb", "ab.toggle", { desc = "Switch between A and B", repeatable = false })
map("<leader>pB", "ab.clear", { desc = "Forget A and B", repeatable = false })
map("<leader>pc", "checkpoint", { desc = "Write a checkpoint", repeatable = false })
map("<leader>pC", "checkpoints", { desc = "List checkpoints", repeatable = false })
map("<leader>pn", function()
  paw.ui.input({ prompt = "Name this state: " }, function(text) paw.cmd("undo.name", { text }) end)
end, { desc = "Name this state", repeatable = false })
map("<leader>p.", "undo.diff", { desc = "What the last step changed", repeatable = false })
if paw.opt.undotree_ab_key ~= "" then
  map(paw.opt.undotree_ab_key, "ab.toggle", { desc = "Switch between A and B", repeatable = false })
end
