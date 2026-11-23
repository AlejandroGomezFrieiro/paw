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
  return tree,
    string.format(
      "%s → %s: %d change%s",
      versions.from_label,
      versions.to_label,
      tree.count,
      tree.count == 1 and "" or "s"
    )
end

local function versions_complete()
  local words = { "now", "HEAD", "HEAD~1" }
  for _, s in ipairs(projdiff.snapshots()) do
    words[#words + 1] = "snap:" .. s.name
  end
  return words
end

command("Pdiff", function(ctx)
  local tree, title = compare(ctx)
  if not tree then return end
  if tree.count == 0 then return paw.notify(title .. " (nothing differs)") end
  view.open(tree, title)
end, {
  desc = "What changed in the project: `Pdiff` since it was saved, `Pdiff HEAD~2` (git), `Pdiff #7` (undo state), `Pdiff snap:name`, `Pdiff other` (another project folder), `Pdiff a b`",
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
  paw.notify(
    "snapshot "
      .. name
      .. (file and " written beside the project" or " kept for this session")
      .. "; `:Pdiff snap:"
      .. name
      .. "` compares with it"
  )
end, { desc = "Keep the project as it is, to compare with later: `Psnapshot before the bridge`", raw = true })

command("Pmerge", function(ctx)
  local folder = ctx.args[1]
  -- Conflicts that the open project holds already: settle them.
  if not folder and #projdiff.merge.conflicts(projdiff.state(nil)) > 0 then return mergeview.open() end
  folder = folder or paw.api.project_get("path")
  if not folder then
    return paw.notify("the project has no folder: `:Pmerge song` merges the project folder song", "warn")
  end
  local n, err = projdiff.merge_git(folder)
  if not n then return paw.notify(err, "warn") end
  if n == 0 then
    return paw.notify("the merge has no conflict left: `:w` saves the project, then `git add` it to finish the merge")
  end
  mergeview.open()
end, {
  desc = "Merge a project folder that a git merge stopped on, and settle its conflicts (the open project, or `Pmerge song`)",
  complete = { "files" },
})

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
    paw.notify(
      #list .. " merge conflict" .. (#list == 1 and "" or "s") .. " left in this project: `:Pmerge` settles them",
      "warn"
    )
  end
end)
