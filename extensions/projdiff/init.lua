-- What changed between two versions of a project, and merging two that
-- changed apart. See README.md beside this file.
local projdiff = require("projdiff")
local view = require("projdiff.view")
local mergeview = require("projdiff.mergeview")

local command, map = paw.command, paw.keymap.set
paw.keymap.group("<leader>g", "versions")

local function compare(ctx)
  local versions, err = projdiff.compare(ctx.args)
  if not versions then
    paw.notify(err, "warn")
    return
  end
  local tree = projdiff.diff.diff(versions.from.project, versions.to.project)
  return tree, string.format("%s → %s: %d change%s", versions.from_label, versions.to_label, tree.count, tree.count == 1 and "" or "s")
end

local function versions_complete()
  local words = { "now", "HEAD", "HEAD~1" }
  for _, s in ipairs(projdiff.snapshots()) do words[#words + 1] = "snap:" .. s.name end
  return words
end

command("Pdiff", function(ctx)
  local tree, title = compare(ctx)
  if not tree then return end
  if tree.count == 0 then return paw.notify(title .. " (nothing differs)") end
  view.open(tree, title)
end, {
  desc = "What changed in the project: `Pdiff` since it was saved, `Pdiff HEAD~2` (git), `Pdiff #7` (undo state), `Pdiff snap:name`, `Pdiff other.json`, `Pdiff a b`",
  complete = versions_complete,
})

command("Pdiff.qf", function(ctx)
  local tree, title = compare(ctx)
  if not tree then return end
  local n = projdiff.to_quickfix(tree, title)
  paw.notify(title .. ": " .. n .. " in the quickfix list")
end, { desc = "The changes of `Pdiff` as a quickfix list, each a place to jump to", complete = versions_complete })

command("Psnapshot", function(ctx)
  local name, file = projdiff.snapshot(table.concat(ctx.args, " "))
  paw.notify("snapshot " .. name .. (file and " written beside the project" or " kept for this session") .. "; `:Pdiff snap:" .. name .. "` compares with it")
end, { desc = "Keep the project as it is, to compare with later: `Psnapshot before the bridge`", raw = true })

command("Pmerge", function(ctx)
  local path = ctx.args[1] or paw.api.project_get("path")
  if not path then return paw.notify("the project has no file: `:Pmerge file.json`", "warn") end
  mergeview.open(path)
end, { desc = "Settle the conflicts a git merge left in a project (the open one, or `Pmerge file.json`)", complete = { "files" } })

command("Pgit", function()
  local root = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "extensions/projdiff"
  paw.ui.page("Git for projects", {
    { text = "Add this to .gitattributes", style = "HelpSection" },
    "*.json diff=paw merge=paw   (or the names of your project files)",
    "",
    { text = "And this to the repository (git config) or ~/.gitconfig", style = "HelpSection" },
    "[diff \"paw\"]",
    "  textconv = paw --clean --no-plugins --no-listen --audio null -l " .. root .. "/git.lua textconv",
    "[merge \"paw\"]",
    "  name = paw project merge",
    "  driver = paw --clean --no-plugins --no-listen --audio null -l " .. root .. "/git.lua merge %O %A %B %L %P",
    "",
    "Conflicts are written into the merged project (meta.merge_conflicts); `:Pmerge` settles them.",
  })
end, { desc = "How to make git diff and merge projects with paw" })

map("<leader>gd", "Pdiff", { desc = "What changed since the project was saved", repeatable = false })
map("<leader>gm", "Pmerge", { desc = "Settle merge conflicts", repeatable = false })
map("<leader>gs", function()
  paw.ui.input({ prompt = "Snapshot name: " }, function(text) paw.cmd("Psnapshot", { text }) end)
end, { desc = "Keep a snapshot of the project", repeatable = false })

-- A project a merge left conflicts in says so whenever it is opened.
paw.on("project.loaded", function()
  local meta = paw.api.project_get().meta
  local list = meta and meta.merge_conflicts
  if type(list) == "table" and #list > 0 then
    paw.notify(#list .. " merge conflict" .. (#list == 1 and "" or "s") .. " left in this project: `:Pmerge` settles them", "warn")
  end
end)
