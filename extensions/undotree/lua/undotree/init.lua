-- The undo tree, named checkpoints and A/B comparison, over `paw.api.undo_*`
-- and `paw.api.checkpoint_*`. See README.md beside the extension.
local api = paw.api

local M = {
  a = nil,        -- the state marked A
  b = nil,        -- where A/B came from: the state toggled away from
  pending = {},   -- checkpoints named before the project had a file: { name, id }
}

-- Reading ------------------------------------------------------------------------

--- The tree as `paw.api.undo_tree()` gives it, with `by_id` added.
function M.tree()
  local tree = api.undo_tree()
  tree.by_id = {}
  for _, s in ipairs(tree.states) do tree.by_id[s.id] = s end
  return tree
end

--- When a state was made, as a clock time, with the date when not today.
function M.when(time)
  if os.date("%Y-%m-%d", time) == os.date("%Y-%m-%d") then return os.date("%H:%M:%S", time) end
  return os.date("%Y-%m-%d %H:%M", time)
end

--- How long ago, briefly: "12 s", "5 min", "3 h", "2 d".
function M.ago(time)
  local s = math.max(0, os.time() - time)
  if s < 60 then return string.format("%d s", s) end
  if s < 3600 then return string.format("%d min", s / 60) end
  if s < 86400 then return string.format("%d h", s / 3600) end
  return string.format("%d d", s / 86400)
end

--- What made a state, as text: the command and the keys typed for it.
function M.what(state)
  if state.parent == nil then return "opened" end
  local keys, label = state.keys, state.label
  if keys and label then return label .. "  " .. keys end
  return label or keys or "a change"
end

--- The tree as rows to draw, newest first, each with the branch graph to its
--- left: `{ id, graph, state, col, lanes }` (`col` is the state's lane, from
--- 1, among `lanes` that row's graph is wide). `*` is a state, `@` the current one; `│`
--- carries a branch down to its parent, and `─┘` joins a branch to the
--- state it grew from.
function M.rows(tree)
  local rows, lanes = {}, {}   -- lanes[i] = the id that lane is heading for, or false
  local states = tree.states
  for i = #states, 1, -1 do
    local s = states[i]
    local col, merging = nil, {}
    for l, want in ipairs(lanes) do
      if want == s.id then
        if col then merging[l] = true else col = l end
      end
    end
    if not col then
      for l, want in ipairs(lanes) do
        if not want then col = l break end
      end
      col = col or #lanes + 1
    end
    local last_merge = 0
    for l in pairs(merging) do last_merge = math.max(last_merge, l) end
    local width = math.max(#lanes, col)
    local parts = {}
    for l = 1, width do
      local cell
      if l == col then
        cell = s.current and "@" or "*"
      elseif merging[l] then
        cell = l == last_merge and "┘" or "┴"
      elseif l > col and l < last_merge then
        cell = lanes[l] and "┼" or "─"
      else
        cell = lanes[l] and "│" or " "
      end
      parts[#parts + 1] = cell
      if l < width then parts[#parts + 1] = (l >= col and l < last_merge) and "─" or " " end
    end
    rows[#rows + 1] = { id = s.id, graph = table.concat(parts), state = s, col = col, lanes = width }
    for l in pairs(merging) do lanes[l] = false end
    lanes[col] = s.parent or false
    while #lanes > 0 and not lanes[#lanes] do lanes[#lanes] = nil end
  end
  return rows
end

--- One line describing a state.
function M.describe(state)
  local tags = {}
  if state.name then tags[#tags + 1] = '"' .. state.name .. '"' end
  if state.id == M.a then tags[#tags + 1] = "[A]" end
  if state.id == M.b then tags[#tags + 1] = "[B]" end
  if state.saved then tags[#tags + 1] = "(saved)" end
  local tag = #tags > 0 and (table.concat(tags, " ") .. "  ") or ""
  return string.format("#%d  %s  %s%s", state.id, M.when(state.time), tag, M.what(state))
end

--- What a diff from `paw.api.undo_diff` adds up to, in one line:
--- "2 clips changed, 5 notes added".
function M.summary(diff)
  if diff.same then return "no change" end
  local parts = {}
  for _, kind in ipairs({ "tracks", "devices", "clips", "notes", "lanes" }) do
    local c = diff[kind]
    for _, what in ipairs({ "added", "removed", "changed" }) do
      if c[what] > 0 then
        local noun = kind == "lanes" and "automation lanes" or kind
        if c[what] == 1 then noun = noun:gsub("s$", "") end
        parts[#parts + 1] = string.format("%d %s %s", c[what], noun, what)
      end
    end
  end
  if #diff.project > 0 then parts[#parts + 1] = "project " .. table.concat(diff.project, ", ") end
  return table.concat(parts, ", ")
end

-- Moving --------------------------------------------------------------------------

local function moved(id)
  if not id then return false end
  local s = M.tree().by_id[id]
  if s then paw.notify(M.describe(s)) end
  return true
end

--- Go to a state by id.
function M.go(id)
  if not api.undo_goto(id) then
    paw.notify("no state #" .. tostring(id) .. " in the undo tree", "warn")
    return false
  end
  return moved(id)
end

--- Read an amount for `earlier` and `later`: a count (`5`) or a time (`30s`,
--- `2m`, `1h`, `1d`). Returns `{ steps = n }` or `{ seconds = n }`, or nil.
function M.parse_amount(text, count)
  if text == nil or text == "" then return { steps = count or 1 } end
  local n, unit = tostring(text):match("^%s*(%d+%.?%d*)%s*(%a*)%s*$")
  n = tonumber(n)
  if not n then return nil end
  if unit == "" then return { steps = n } end
  local scale = ({ s = 1, sec = 1, m = 60, min = 60, h = 3600, d = 86400 })[unit]
  return scale and { seconds = n * scale } or nil
end

--- Go `amount` earlier (`dir` -1) or later (1) in time, across branches.
--- Returns the state gone to, or nil.
function M.travel(dir, text, count)
  local amount = M.parse_amount(text, count)
  if not amount then
    paw.notify("give a count or a time such as 30s, 2m, 1h", "warn")
    return nil
  end
  local id
  if amount.steps then
    id = api.undo_step(dir * math.floor(amount.steps))
  else
    id = api.undo_travel(dir * amount.seconds)
  end
  if not id then
    paw.notify(dir < 0 and "already at the oldest state" or "already at the newest state")
    return nil
  end
  moved(id)
  return id
end

-- A/B ---------------------------------------------------------------------------

--- Mark a state (the current one by default) as A.
function M.mark_a(id)
  api.undo_checkpoint()
  id = id or api.undo_current()
  if M.a and M.a ~= id and M.a ~= M.b then pcall(api.undo_keep, M.a, false) end
  M.a = id
  api.undo_keep(id, true)
  paw.notify("A is #" .. id)
  api.ui_redraw()
  return id
end

--- Switch between A and the state you were at. The transport carries on: the
--- switch is an ordinary sync of one snapshot to the other. Returns "A" or
--- "B" for where it went, or nil and why not.
function M.toggle()
  if not M.a then return nil, "no A yet: mark one with <leader>pa or :ab.mark" end
  api.undo_checkpoint()
  local at = api.undo_current()
  if at == M.a then
    if not M.b then return nil, "this is A, and there is no B to go back to yet" end
    if not api.undo_goto(M.b) then
      M.b = nil
      return nil, "B is no longer in the undo tree"
    end
    return "B"
  end
  if M.b and M.b ~= at and M.b ~= M.a then pcall(api.undo_keep, M.b, false) end
  M.b = at
  api.undo_keep(at, true)
  if not api.undo_goto(M.a) then
    M.a = nil
    return nil, "A is no longer in the undo tree"
  end
  return "A"
end

function M.clear_ab()
  for _, id in ipairs({ M.a, M.b }) do pcall(api.undo_keep, id, false) end
  M.a, M.b = nil, nil
end

-- Checkpoints --------------------------------------------------------------------

--- Name the current state and write it beside the project. With no project
--- file yet the name is kept, and the checkpoint is written at the first save.
function M.checkpoint(name)
  name = name and tostring(name):match("^%s*(.-)%s*$") or ""
  if name == "" then return nil, "a checkpoint needs a name" end
  if not api.checkpoint_dir() then
    local id = api.undo_name(name)
    M.pending[#M.pending + 1] = { name = name, id = id }
    return { name = name, state = id, pending = true }
  end
  return api.checkpoint_write(name)
end

--- Write the checkpoints that were waiting for a project file.
function M.write_pending()
  local wrote = 0
  for _, p in ipairs(M.pending) do
    if pcall(api.checkpoint_write, p.name, p.id) then wrote = wrote + 1 end
  end
  M.pending = {}
  return wrote
end

--- Every checkpoint to choose from, newest first: those on disk, then names
--- given in this session that are not on disk. Each is
--- `{ text, id, name, time, file }` or `{ text, id, name, time, state }`.
function M.items()
  local items, on_disk = {}, {}
  local list = api.checkpoint_list()
  for i = #list, 1, -1 do
    local c = list[i]
    on_disk[c.name] = true
    items[#items + 1] = { name = c.name, time = c.time, file = c.file, text = c.name .. "  " .. M.when(c.time) }
  end
  local tree = M.tree()
  for i = #tree.states, 1, -1 do
    local s = tree.states[i]
    if s.name and not on_disk[s.name] then
      items[#items + 1] = { name = s.name, time = s.time, state = s.id,
        text = s.name .. "  " .. M.when(s.time) .. "  (this session only)" }
    end
  end
  for i, item in ipairs(items) do item.id = i end
  return items
end

--- Restore a checkpoint item: one on disk becomes a new state (so undo comes
--- back from it); one of this session is gone to.
function M.restore(item)
  if item.file then
    local id = api.checkpoint_restore(item.file)
    paw.notify("restored " .. item.name .. " as #" .. id)
    return id
  end
  return M.go(item.state) and item.state
end

--- An item by its number in `items()` or by its name.
function M.find(which)
  local items = M.items()
  local n = tonumber(which)
  if n and items[n] then return items[n] end
  for _, item in ipairs(items) do
    if item.name == tostring(which) then return item end
  end
end

--- List the checkpoints, in the picker when there is one.
function M.choose()
  local items = M.items()
  if #items == 0 then
    paw.notify("no checkpoints yet: `:checkpoint <name>` makes one")
    return
  end
  if paw.pick then
    paw.pick({ title = "Checkpoints", items = items, on_choose = function(item) M.restore(item) end })
    return
  end
  local lines = {}
  for i, item in ipairs(items) do lines[#lines + 1] = string.format("%3d  %s", i, item.text) end
  lines[#lines + 1] = ""
  lines[#lines + 1] = { text = ":checkpoint.restore <number or name> restores one", style = "Dim" }
  paw.ui.page("Checkpoints", lines)
end

paw.on("project.loaded", function()
  M.a, M.b, M.pending = nil, nil, {}
end)

paw.on("project.saved", function()
  if #M.pending == 0 then return end
  local n = M.write_pending()
  if n > 0 then paw.notify(string.format("wrote %d checkpoint%s beside the project", n, n == 1 and "" or "s")) end
end)

return M
